#!/bin/bash
set -euo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
CLEAR='\033[0m'

log_ok()      { echo -e "${GREEN}✓${CLEAR} $1"; }
log_warn()    { echo -e "${YELLOW}!${CLEAR} $1"; }
log_info()    { echo -e "${BLUE}›${CLEAR} $1"; }
log_section() { echo -e "\n${BOLD}=> $1${CLEAR}"; }

# Rewrite the previous line with a colored answer
confirm_line() { printf "\033[1A\033[2K"; echo -e "$1"; }

XCODE_VERSION=""
SUDO_KEEPALIVE_PID=""

cleanup() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup EXIT

sudo_keepalive() {
  sudo -v
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
}

check_dependencies() {
  if ! command -v xcodes &>/dev/null; then
    if ! command -v brew &>/dev/null; then
      log_warn "xcodes not installed and Homebrew not found."
      echo "Run ./install.sh to set up required tools."
      exit 1
    fi
    log_info "Installing xcodes..."
    brew install xcodes
    log_ok "xcodes installed"
  fi
}

check_disk_space() {
  local required_gb=60 available_gb
  available_gb=$(df -g / | awk 'NR==2 {print $4}')
  if (( available_gb < required_gb )); then
    log_warn "${available_gb}GB available — ~${required_gb}GB recommended for Xcode + SDKs + simulators"
    read -r -p "Continue anyway? [Y/n] " confirm || true
    if [[ "${confirm:-}" =~ ^[Nn]$ ]]; then
      confirm_line "Continue anyway? ${YELLOW}No${CLEAR}"
      exit 0
    fi
    confirm_line "Continue anyway? ${GREEN}Yes${CLEAR}"
  fi
}


prompt_version() {
  log_info "Fetching available Xcode versions..."

  local latest
  latest=$(xcodes list 2>/dev/null | python3 -c "
import sys, re
stable = [v.strip() for v in sys.stdin
          if v.strip() and not re.search(r'beta|release candidate|\brc\b', v, re.IGNORECASE)]
print(stable[-1] if stable else '')
" || true)

  if [[ -z "$latest" ]]; then
    log_warn "Could not fetch version list — enter version manually"
    read -r -p "Version to install: " XCODE_VERSION || true
    confirm_line "Version to install: ${GREEN}${XCODE_VERSION}${CLEAR}"
  else
    read -r -p "Version to install [${latest}]: " XCODE_VERSION || true
    XCODE_VERSION="${XCODE_VERSION:-$latest}"
    confirm_line "Version to install: ${GREEN}${XCODE_VERSION}${CLEAR}"
  fi

  if [[ -z "${XCODE_VERSION:-}" ]]; then
    echo "No version specified."
    exit 1
  fi
}

check_if_current() {
  local version="$1"
  local version_number current
  version_number=$(echo "$version" | awk '{print $1}')
  current=$(xcodebuild -version 2>/dev/null | awk 'NR==1{print $2}' || true)
  if [[ "$current" == "$version_number" ]]; then
    log_ok "Xcode ${version_number} is already installed and active"
    return 0
  fi
  return 1
}

preflight_summary() {
  local version="$1"

  echo ""
  echo -e "${BOLD}Version:${CLEAR}     ${version}"
  echo -e "${BOLD}Disk:${CLEAR}        ~60GB recommended"
  echo -e "${BOLD}Simulators:${CLEAR}  iPhone 17 (iOS), Apple TV (tvOS)"
  echo ""
  read -r -p "Proceed? [Y/n] " confirm || true
  if [[ "${confirm:-}" =~ ^[Nn]$ ]]; then
    confirm_line "Proceed? ${YELLOW}No${CLEAR}"
    exit 0
  fi
  confirm_line "Proceed? ${GREEN}Yes${CLEAR}"
}

cleanup_runtimes() {
  local keep_version
  keep_version=$(echo "$1" | awk '{print $1}')

  log_info "Scanning simulator runtimes..."

  local to_remove
  to_remove=$(xcrun simctl runtime list 2>/dev/null | python3 -c "
import sys, re
keep = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    m = re.match(r'(.+?)\s+-\s+([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})', line)
    if not m:
        continue
    name, uuid = m.group(1).strip(), m.group(2)
    if keep not in name:
        print(f'{uuid}\t{name}')
" "$keep_version" || true)

  if [[ -z "$to_remove" ]]; then
    log_ok "No stale runtimes found"
    return
  fi

  echo ""
  while IFS=$'\t' read -r uuid name; do
    echo "  ${name}"
  done <<< "$to_remove"
  echo ""

  read -r -p "Remove all stale runtimes? [Y/n] " confirm || true
  if [[ "${confirm:-}" =~ ^[Nn]$ ]]; then
    confirm_line "Remove all stale runtimes? ${YELLOW}No${CLEAR}"
    return
  fi
  confirm_line "Remove all stale runtimes? ${GREEN}Yes${CLEAR}"

  while IFS=$'\t' read -r uuid name; do
    log_info "Removing ${name}..."
    sudo xcrun simctl runtime delete "$uuid"
    log_ok "Removed ${name}"
  done <<< "$to_remove"
}

remove_old_versions() {
  local target="$1"
  local target_version
  target_version=$(echo "$target" | awk '{print $1}')

  for app in /Applications/Xcode*.app; do
    [[ -d "$app" ]] || continue
    local version
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
      "$app/Contents/Info.plist" 2>/dev/null || true)
    [[ -z "$version" || "$version" == "$target_version" ]] && continue
    read -r -p "Remove Xcode ${version}? [Y/n] " confirm || true
    if [[ "${confirm:-}" =~ ^[Nn]$ ]]; then
      confirm_line "Remove Xcode ${version}? ${YELLOW}No${CLEAR}"
    else
      confirm_line "Remove Xcode ${version}? ${GREEN}Yes${CLEAR}"
      log_info "Removing Xcode ${version}..."
      sudo rm -rf "$app"
      log_ok "Removed Xcode ${version}"
    fi
  done
}

install_xcode() {
  local version="$1"
  log_info "Downloading and installing Xcode ${version} (this will take a while)..."
  xcodes install "$version" --experimental-unxip
  log_ok "Xcode ${version} installed"
}

configure_xcode() {
  log_info "Accepting license..."
  sudo xcodebuild -license accept
  log_ok "License accepted"

  log_info "Running first launch..."
  sudo xcodebuild -runFirstLaunch
  log_ok "First launch complete"
}

install_platforms() {
  log_info "Downloading iOS platform..."
  sudo xcodebuild -downloadPlatform iOS
  log_ok "iOS platform installed"

  log_info "Downloading tvOS platform..."
  sudo xcodebuild -downloadPlatform tvOS
  log_ok "tvOS platform installed"
}

setup_simulators() {
  log_info "Removing unavailable simulators..."
  xcrun simctl delete unavailable
  log_ok "Unavailable simulators removed"

  local ios_runtime tvos_runtime iphone_device appletv_device

  ios_runtime=$(xcrun simctl list runtimes --json | python3 -c "
import json, sys
rts = [r for r in json.load(sys.stdin)['runtimes']
       if 'iOS' in r['name'] and r.get('isAvailable', False)]
print(rts[-1]['identifier'] if rts else '')
")

  tvos_runtime=$(xcrun simctl list runtimes --json | python3 -c "
import json, sys
rts = [r for r in json.load(sys.stdin)['runtimes']
       if 'tvOS' in r['name'] and r.get('isAvailable', False)]
print(rts[-1]['identifier'] if rts else '')
")

  iphone_device=$(xcrun simctl list devicetypes --json | python3 -c "
import json, sys
dts = [d for d in json.load(sys.stdin)['devicetypes']
       if 'iPhone 17' in d['name']]
print(dts[-1]['identifier'] if dts else '')
")

  appletv_device=$(xcrun simctl list devicetypes --json | python3 -c "
import json, sys
dts = [d for d in json.load(sys.stdin)['devicetypes']
       if 'Apple TV' in d['name'] and '4K' in d['name']]
print(dts[-1]['identifier'] if dts else '')
")

  ensure_simulator() {
    local name="$1" device="$2" runtime="$3"
    local udids
    udids=$(xcrun simctl list devices --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for rt, devices in data['devices'].items():
    for d in devices:
        if d['name'] == sys.argv[1]:
            print(d['udid'])
" "$name" || true)

    local count
    count=$(echo "$udids" | grep -c . || true)

    if [[ "$count" -eq 0 ]]; then
      xcrun simctl create "$name" "$device" "$runtime" > /dev/null
      log_ok "${name} simulator created"
    elif [[ "$count" -gt 1 ]]; then
      # Keep the first, delete the rest
      local keep
      keep=$(echo "$udids" | head -1)
      echo "$udids" | tail -n +2 | xargs xcrun simctl delete 2>/dev/null || true
      log_ok "${name} simulator deduplicated (kept 1 of ${count})"
    else
      log_ok "${name} simulator exists"
    fi
  }

  if [[ -n "$ios_runtime" && -n "$iphone_device" ]]; then
    ensure_simulator "iPhone 17" "$iphone_device" "$ios_runtime"
  else
    log_warn "iPhone 17 device type or iOS runtime not found — skipping"
  fi

  if [[ -n "$tvos_runtime" && -n "$appletv_device" ]]; then
    ensure_simulator "Apple TV" "$appletv_device" "$tvos_runtime"
  else
    log_warn "Apple TV device type or tvOS runtime not found — skipping"
  fi
}

run_cleanup() {
  local version="$1"
  log_info "Requesting sudo (required throughout)..."
  sudo_keepalive

  log_section "Cleanup"
  remove_old_versions "$version"
  cleanup_runtimes "$version"
  log_info "Removing unavailable simulators..."
  sudo xcrun simctl delete unavailable 2>/dev/null || true
  log_ok "Unavailable simulators removed"
}

main() {
  check_dependencies

  log_section "Xcode Installer"
  prompt_version
  check_disk_space
  preflight_summary "$XCODE_VERSION"

  run_cleanup "$XCODE_VERSION"

  if check_if_current "$XCODE_VERSION"; then
    log_section "Simulators"
    cleanup_runtimes "$XCODE_VERSION"
    setup_simulators
  else
    log_section "Download & Install"
    install_xcode "$XCODE_VERSION"

    log_section "Configure"
    configure_xcode

    log_section "Platforms & SDKs"
    install_platforms

    log_section "Simulators"
    cleanup_runtimes "$XCODE_VERSION"
    setup_simulators
  fi

  log_section "Done"
  xcodebuild -version
  log_ok "Xcode setup complete"
}

main "$@"
