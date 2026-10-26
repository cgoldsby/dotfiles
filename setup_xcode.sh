#!/bin/bash
set -euo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
DIM='\033[2m'
CLEAR='\033[0m'

SUDO_KEEPALIVE_PID=""

log_ok()      { echo -e "${GREEN}✓${CLEAR} $1"; }
log_warn()    { echo -e "${YELLOW}!${CLEAR} $1"; }
log_info()    { echo -e "${BLUE}›${CLEAR} $1"; }
log_section() { echo -e "\n${BOLD}=> $1${CLEAR}"; }

# Rewrite the previous line with a colored answer
confirm_line() { printf "\033[1A\033[2K"; echo -e "$1"; }

cleanup() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup EXIT

sudo_keepalive() {
  sudo -v
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
}

# Wait until a runtime identifier disappears from the list
wait_for_runtime_delete() {
  local id="$1"
  while xcrun simctl runtime list -j 2>/dev/null | jq -e --arg id "$id" 'has($id)' >/dev/null 2>&1; do
    sleep 1
  done
}

check_dependencies() {
  if ! command -v xcodes &>/dev/null; then
    log_warn "xcodes is required but not installed"
    log_info "Install it with: brew install xcodes"
    exit 1
  fi
}

# --- Cleanup Phase ---

cleanup_simulators() {
  log_section "Cleanup: Simulators"

  if ! xcode-select -p >/dev/null 2>&1; then
    log_info "No developer tools installed; skipping"
    return 0
  fi

  local devices_json
  devices_json=$(xcrun simctl list devices -j 2>/dev/null || true)

  if [[ -z "$devices_json" ]]; then
    log_info "No simulators found"
    return 0
  fi

  # Collect all devices (name, udid, runtime) into parallel arrays
  local names=() udids=() runtimes=()
  while IFS=$'\t' read -r name udid runtime; do
    names+=("$name")
    udids+=("$udid")
    runtimes+=("$runtime")
  done < <(echo "$devices_json" | jq -r '
    [.devices | to_entries[] | .key as $rt |
    ($rt | sub("com\\.apple\\.CoreSimulator\\.SimRuntime\\."; "")
         | sub("-"; " ")
         | sub("-"; ".")) as $label |
    .value[] | select(.isAvailable) |
    {name: .name, udid: .udid, label: $label}]
    | sort_by(.label, .name)[]
    | "\(.name)\t\(.udid)\t\(.label)"
  ')

  if [[ ${#names[@]} -eq 0 ]]; then
    log_info "No simulators found"
    return 0
  fi

  log_info "${#names[@]} simulator(s) found"
  for i in "${!names[@]}"; do
    echo -e "  ${names[$i]} (${runtimes[$i]})"
  done

  read -r -p "Delete all simulators? [y/N] " confirm || true
  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    confirm_line "Delete all simulators? ${GREEN}Yes${CLEAR}"
    xcrun simctl delete all
    log_ok "All simulators deleted"
    return 0
  fi
  confirm_line "Delete all simulators? ${YELLOW}No${CLEAR}"

  # Prompt for each simulator individually
  for i in "${!names[@]}"; do
    local display="${names[$i]} (${runtimes[$i]}) ${DIM}${udids[$i]}${CLEAR}"
    printf "Delete %b? [y/N] " "$display"
    read -r confirm || true
    if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
      confirm_line "Delete ${display}? ${GREEN}Yes${CLEAR}"
      xcrun simctl delete "${udids[$i]}"
      log_ok "Deleted ${names[$i]}"
    else
      confirm_line "Delete ${display}? ${YELLOW}No${CLEAR}"
    fi
  done
}

cleanup_runtimes() {
  log_section "Cleanup: Runtimes"

  if ! xcode-select -p >/dev/null 2>&1; then
    log_info "No developer tools installed; skipping"
    return 0
  fi

  local runtimes_json
  runtimes_json=$(xcrun simctl runtime list -j 2>/dev/null || true)

  if [[ -z "$runtimes_json" ]]; then
    log_info "No iOS/tvOS runtimes found"
    return 0
  fi

  # Collect iOS and tvOS runtimes
  local platforms=() versions=() identifiers=() sizes=()
  while IFS=$'\t' read -r platform version identifier size; do
    platforms+=("$platform")
    versions+=("$version")
    identifiers+=("$identifier")
    sizes+=("$size")
  done < <(echo "$runtimes_json" | jq -r '
    [to_entries[].value |
    select(.platformIdentifier == "com.apple.platform.iphonesimulator" or
           .platformIdentifier == "com.apple.platform.appletvsimulator") |
    (if .platformIdentifier == "com.apple.platform.iphonesimulator" then "iOS"
     else "tvOS" end) as $platform |
    (.sizeBytes / 1073741824 * 10 | floor / 10 | tostring + " GB") as $size |
    {platform: $platform, version: .version, identifier: .identifier, size: $size}]
    | sort_by(.platform, .version)[]
    | "\(.platform)\t\(.version)\t\(.identifier)\t\(.size)"
  ')

  if [[ ${#platforms[@]} -eq 0 ]]; then
    log_info "No iOS/tvOS runtimes found"
    return 0
  fi

  log_info "${#platforms[@]} runtime(s) found"
  for i in "${!platforms[@]}"; do
    echo -e "  ${platforms[$i]} ${versions[$i]} (${sizes[$i]})"
  done

  read -r -p "Delete all runtimes? [y/N] " confirm || true
  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    confirm_line "Delete all runtimes? ${GREEN}Yes${CLEAR}"
    for i in "${!identifiers[@]}"; do
      xcrun simctl runtime delete "${identifiers[$i]}"
      wait_for_runtime_delete "${identifiers[$i]}"
      log_ok "Deleted ${platforms[$i]} ${versions[$i]}"
    done
    return 0
  fi
  confirm_line "Delete all runtimes? ${YELLOW}No${CLEAR}"

  for i in "${!platforms[@]}"; do
    local display="${platforms[$i]} ${versions[$i]} (${sizes[$i]}) ${DIM}${identifiers[$i]}${CLEAR}"
    printf "Delete %b? [y/N] " "$display"
    read -r confirm || true
    if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
      confirm_line "Delete ${display}? ${GREEN}Yes${CLEAR}"
      xcrun simctl runtime delete "${identifiers[$i]}"
      wait_for_runtime_delete "${identifiers[$i]}"
      log_ok "Deleted ${platforms[$i]} ${versions[$i]}"
    else
      confirm_line "Delete ${display}? ${YELLOW}No${CLEAR}"
    fi
  done
}

cleanup_xcode() {
  log_section "Cleanup: Xcode"

  # Parse "xcodes installed" output: "VERSION (BUILD) [ARCH] (Selected)\tPATH"
  local installed_output
  installed_output=$(xcodes installed 2>/dev/null || true)

  local versions=() paths=() selected=()
  if [[ -n "$installed_output" ]]; then
    while IFS=$'\t' read -r info path; do
      local version
      version=$(echo "$info" | sed 's/ (.*//')
      local is_selected=""
      [[ "$info" == *"(Selected)"* ]] && is_selected="yes"
      versions+=("$version")
      paths+=("${path## }")
      selected+=("$is_selected")
    done <<< "$installed_output"
  fi

  if [[ ${#versions[@]} -eq 0 ]]; then
    log_info "No Xcode installations found"
  else
    log_info "${#versions[@]} Xcode(s) found"
    for i in "${!versions[@]}"; do
      local label="${versions[$i]}"
      [[ -n "${selected[$i]}" ]] && label="${label} (Selected)"
      echo -e "  ${label}"
    done

    read -r -p "Delete all Xcode installations? [y/N] " confirm || true
    if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
      confirm_line "Delete all Xcode installations? ${GREEN}Yes${CLEAR}"
      sudo_keepalive
      for i in "${!versions[@]}"; do
        sudo xcodes uninstall "${versions[$i]}"
        log_ok "Deleted Xcode ${versions[$i]}"
      done
    else
      confirm_line "Delete all Xcode installations? ${YELLOW}No${CLEAR}"

      for i in "${!versions[@]}"; do
        local label="${versions[$i]}"
        [[ -n "${selected[$i]}" ]] && label="${label} (Selected)"
        local display="${label} ${DIM}${paths[$i]}${CLEAR}"
        printf "Delete Xcode %b? [y/N] " "$display"
        read -r confirm || true
        if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
          confirm_line "Delete Xcode ${display}? ${GREEN}Yes${CLEAR}"
          [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
          sudo xcodes uninstall "${versions[$i]}"
          log_ok "Deleted Xcode ${versions[$i]}"
        else
          confirm_line "Delete Xcode ${display}? ${YELLOW}No${CLEAR}"
        fi
      done
    fi
  fi

  # Always clean shared caches and derived data
  local always_clean=(
    "$HOME/Library/Developer/Xcode/DerivedData"
    "$HOME/Library/Caches/com.apple.dt.Xcode"
  )
  for dir in "${always_clean[@]}"; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      log_ok "Removed ${dir/#$HOME/~}"
    fi
  done

  # Check if any Xcode installations remain
  local remaining
  remaining=$( (xcodes installed 2>/dev/null || true) | grep -c '.' 2>/dev/null) || remaining=0

  if [[ "$remaining" -eq 0 ]]; then
    # Clean preferences and saved state when no Xcode remains
    local final_clean=(
      "$HOME/Library/Preferences/com.apple.dt.Xcode.plist"
      "$HOME/Library/Saved Application State/com.apple.dt.Xcode.savedState"
    )
    for path in "${final_clean[@]}"; do
      if [[ -e "$path" ]]; then
        rm -rf "$path"
        log_ok "Removed ${path/#$HOME/~}"
      fi
    done

  fi
}

cleanup_clt() {
  log_section "Cleanup: Command Line Tools"

  # Only offer CLT removal when no Xcode remains
  local remaining
  remaining=$( (xcodes installed 2>/dev/null || true) | grep -c '.' 2>/dev/null) || remaining=0

  if [[ "$remaining" -gt 0 ]]; then
    log_info "Xcode still installed; skipping"
    return 0
  fi

  if [[ ! -d "/Library/Developer/CommandLineTools" ]]; then
    log_info "No Command Line Tools found"
    return 0
  fi

  read -r -p "Delete Command Line Tools? [y/N] " confirm || true
  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    confirm_line "Delete Command Line Tools? ${GREEN}Yes${CLEAR}"
    [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
    sudo rm -rf /Library/Developer/CommandLineTools
    log_ok "Removed Command Line Tools"
  else
    confirm_line "Delete Command Line Tools? ${YELLOW}No${CLEAR}"
  fi
}

install_xcode() {
  log_section "Install: Xcode"

  read -r -p "Install Xcode? [y/N] " confirm || true
  if [[ ! "${confirm:-}" =~ ^[Yy]$ ]]; then
    confirm_line "Install Xcode? ${YELLOW}No${CLEAR}"
    return 0
  fi
  confirm_line "Install Xcode? ${GREEN}Yes${CLEAR}"

  # Ensure CLT exists so xcodes can fetch the version list
  if ! xcode-select -p >/dev/null 2>&1; then
    log_info "Installing Command Line Tools (required for xcodes)..."
    [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
    sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    local clt_pkg
    clt_pkg=$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools.*' | head -1 || true)
    if [[ -n "$clt_pkg" ]]; then
      sudo softwareupdate -i "$clt_pkg"
    else
      log_warn "Could not find Command Line Tools package"
      sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      return 1
    fi
    sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    local clt_version
    clt_version=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null \
      | awk '/version:/ {split($2,v,"."); print v[1]"."v[2]}' || true)
    log_ok "Command Line Tools ${clt_version:-} installed"
  fi

  # Fetch latest stable version
  log_info "Fetching available Xcode versions..."
  local latest
  latest=$(xcodes list 2>/dev/null \
    | grep -viE 'beta|release candidate|\brc\b|showing' \
    | grep -v '^$' \
    | sed 's/ (.*//' \
    | tail -1 \
    | tr -d '[:space:]' || true)

  local xcode_version
  if [[ -n "$latest" ]]; then
    read -r -p "Version to install [${latest}]: " xcode_version || true
    xcode_version="${xcode_version:-$latest}"
    confirm_line "Version to install: ${GREEN}${xcode_version}${CLEAR}"
  else
    log_warn "Could not fetch version list"
    read -r -p "Version to install: " xcode_version || true
    confirm_line "Version to install: ${GREEN}${xcode_version}${CLEAR}"
  fi

  if [[ -z "${xcode_version:-}" ]]; then
    log_warn "No version specified"
    return 1
  fi

  # Install
  [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
  log_info "Installing Xcode ${xcode_version}..."
  if ! xcodes install "$xcode_version"; then
    log_warn "Xcode ${xcode_version} installation failed"
    return 1
  fi
  log_ok "Xcode ${xcode_version} installed"

  # Select and accept license
  local app_path
  app_path=$(xcodes installed 2>/dev/null | grep "^${xcode_version}" | awk -F'\t' '{print $2}' | tr -d ' ')
  if [[ -n "$app_path" ]]; then
    sudo xcode-select -s "$app_path"
    log_ok "Selected ${app_path}"
  fi

  if sudo xcodebuild -license accept 2>/dev/null; then
    log_ok "License accepted"
  else
    log_warn "Could not accept license automatically"
  fi
}

install_runtimes() {
  log_section "Install: Runtimes"

  if ! xcode-select -p >/dev/null 2>&1; then
    log_info "No Xcode installed; skipping"
    return 0
  fi

  # Get SDK versions from the selected Xcode
  local ios_version tvos_version
  ios_version=$(xcodebuild -showsdks 2>/dev/null \
    | awk '/Simulator - iOS/ {print $NF}' \
    | sed 's/iphonesimulator//' || true)
  tvos_version=$(xcodebuild -showsdks 2>/dev/null \
    | awk '/Simulator - tvOS/ {print $NF}' \
    | sed 's/appletvsimulator//' || true)

  # Check which runtimes are already installed
  local installed_runtimes
  installed_runtimes=$(xcrun simctl runtime list -j 2>/dev/null || true)

  local ios_installed tvos_installed
  ios_installed=$(echo "$installed_runtimes" | jq -r \
    --arg v "$ios_version" \
    'to_entries[].value | select(.platformIdentifier == "com.apple.platform.iphonesimulator" and .version == $v) | .version' 2>/dev/null || true)
  tvos_installed=$(echo "$installed_runtimes" | jq -r \
    --arg v "$tvos_version" \
    'to_entries[].value | select(.platformIdentifier == "com.apple.platform.appletvsimulator" and .version == $v) | .version' 2>/dev/null || true)

  # iOS runtime
  if [[ -n "$ios_version" ]]; then
    if [[ -n "$ios_installed" ]]; then
      log_ok "iOS ${ios_version} runtime already installed"
    else
      read -r -p "Install iOS ${ios_version} runtime? [y/N] " confirm || true
      if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
        confirm_line "Install iOS ${ios_version} runtime? ${GREEN}Yes${CLEAR}"
        [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
        log_info "Downloading iOS ${ios_version} runtime..."
        xcodebuild -downloadPlatform iOS
        log_ok "iOS ${ios_version} runtime installed"
      else
        confirm_line "Install iOS ${ios_version} runtime? ${YELLOW}No${CLEAR}"
      fi
    fi
  fi

  # tvOS runtime
  if [[ -n "$tvos_version" ]]; then
    if [[ -n "$tvos_installed" ]]; then
      log_ok "tvOS ${tvos_version} runtime already installed"
    else
      read -r -p "Install tvOS ${tvos_version} runtime? [y/N] " confirm || true
      if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
        confirm_line "Install tvOS ${tvos_version} runtime? ${GREEN}Yes${CLEAR}"
        [[ -z "$SUDO_KEEPALIVE_PID" ]] && sudo_keepalive
        log_info "Downloading tvOS ${tvos_version} runtime..."
        xcodebuild -downloadPlatform tvOS
        log_ok "tvOS ${tvos_version} runtime installed"
      else
        confirm_line "Install tvOS ${tvos_version} runtime? ${YELLOW}No${CLEAR}"
      fi
    fi
  fi
}

install_simulators() {
  log_section "Install: Simulators"

  if ! xcode-select -p >/dev/null 2>&1; then
    log_info "No Xcode installed; skipping"
    return 0
  fi

  local devices_json
  devices_json=$(xcrun simctl list devices -j 2>/dev/null || true)
  local runtimes_json
  runtimes_json=$(xcrun simctl list runtimes --json 2>/dev/null || true)

  # Get the SDK versions from the selected Xcode
  local ios_version tvos_version
  ios_version=$(xcodebuild -showsdks 2>/dev/null \
    | awk '/Simulator - iOS/ {print $NF}' \
    | sed 's/iphonesimulator//' || true)
  tvos_version=$(xcodebuild -showsdks 2>/dev/null \
    | awk '/Simulator - tvOS/ {print $NF}' \
    | sed 's/appletvsimulator//' || true)

  # iOS simulator
  if [[ -n "$ios_version" ]]; then
    local ios_runtime_id
    ios_runtime_id=$(echo "$runtimes_json" | jq -r \
      --arg v "$ios_version" \
      '.runtimes[] | select(.name == "iOS \($v)") | .identifier' 2>/dev/null || true)

    if [[ -z "$ios_runtime_id" ]]; then
      log_info "iOS ${ios_version} runtime not installed; skipping simulator"
    else
      # Get supported iPhone devices from this runtime
      local ios_devices
      ios_devices=$(echo "$runtimes_json" | jq -r \
        --arg v "$ios_version" \
        '.runtimes[] | select(.name == "iOS \($v)") | .supportedDeviceTypes[] | select(.name | test("^iPhone")) | "\(.name)\t\(.identifier)"' 2>/dev/null || true)

      # First iPhone (e.g. iPhone 17)
      local iphone_name iphone_id
      iphone_name=$(echo "$ios_devices" | grep -E '^iPhone [0-9]+\t' | head -1 | cut -f1 || true)
      iphone_id=$(echo "$ios_devices" | grep -E '^iPhone [0-9]+\t' | head -1 | cut -f2 || true)

      if [[ -n "$iphone_id" ]]; then
        local existing
        existing=$(echo "$devices_json" | jq -r \
          --arg rt "$ios_runtime_id" --arg name "$iphone_name" \
          '.devices[$rt] // [] | map(select(.isAvailable and .name == $name)) | length' 2>/dev/null || echo "0")
        if [[ "$existing" -gt 0 ]]; then
          log_ok "${iphone_name} (iOS ${ios_version}) already exists"
        else
          read -r -p "Create ${iphone_name} (iOS ${ios_version})? [y/N] " confirm || true
          if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
            confirm_line "Create ${iphone_name} (iOS ${ios_version})? ${GREEN}Yes${CLEAR}"
            xcrun simctl create "$iphone_name" "$iphone_id" "$ios_runtime_id" >/dev/null
            log_ok "Created ${iphone_name} (iOS ${ios_version})"
          else
            confirm_line "Create ${iphone_name} (iOS ${ios_version})? ${YELLOW}No${CLEAR}"
          fi
        fi
      fi

      # iPhone Duo (if supported by this runtime)
      local duo_name duo_id
      duo_name=$(echo "$ios_devices" | grep -E '^iPhone Duo\t' | head -1 | cut -f1 || true)
      duo_id=$(echo "$ios_devices" | grep -E '^iPhone Duo\t' | head -1 | cut -f2 || true)

      if [[ -n "$duo_id" ]]; then
        local duo_existing
        duo_existing=$(echo "$devices_json" | jq -r \
          --arg rt "$ios_runtime_id" --arg name "$duo_name" \
          '.devices[$rt] // [] | map(select(.isAvailable and .name == $name)) | length' 2>/dev/null || echo "0")
        if [[ "$duo_existing" -gt 0 ]]; then
          log_ok "${duo_name} (iOS ${ios_version}) already exists"
        else
          read -r -p "Create ${duo_name} (iOS ${ios_version})? [y/N] " confirm || true
          if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
            confirm_line "Create ${duo_name} (iOS ${ios_version})? ${GREEN}Yes${CLEAR}"
            xcrun simctl create "$duo_name" "$duo_id" "$ios_runtime_id" >/dev/null
            log_ok "Created ${duo_name} (iOS ${ios_version})"
          else
            confirm_line "Create ${duo_name} (iOS ${ios_version})? ${YELLOW}No${CLEAR}"
          fi
        fi
      fi

      if [[ -z "$iphone_id" && -z "$duo_id" ]]; then
        log_warn "No compatible iPhone device types for iOS ${ios_version}"
      fi
    fi
  fi

  # tvOS simulator
  if [[ -n "$tvos_version" ]]; then
    local tvos_runtime_id
    tvos_runtime_id=$(echo "$runtimes_json" | jq -r \
      --arg v "$tvos_version" \
      '.runtimes[] | select(.name == "tvOS \($v)") | .identifier' 2>/dev/null || true)

    if [[ -z "$tvos_runtime_id" ]]; then
      log_info "tvOS ${tvos_version} runtime not installed; skipping simulator"
    else
      # Get first Apple TV from this runtime's supported device types
      local atv_name atv_id
      atv_name=$(echo "$runtimes_json" | jq -r \
        --arg v "$tvos_version" \
        '.runtimes[] | select(.name == "tvOS \($v)") | .supportedDeviceTypes[] | select(.name | test("Apple TV")) | .name' 2>/dev/null | head -1 || true)
      atv_id=$(echo "$runtimes_json" | jq -r \
        --arg v "$tvos_version" \
        '.runtimes[] | select(.name == "tvOS \($v)") | .supportedDeviceTypes[] | select(.name | test("Apple TV")) | .identifier' 2>/dev/null | head -1 || true)

      if [[ -n "$atv_id" ]]; then
        local atv_existing
        atv_existing=$(echo "$devices_json" | jq -r \
          --arg rt "$tvos_runtime_id" --arg name "$atv_name" \
          '.devices[$rt] // [] | map(select(.isAvailable and .name == $name)) | length' 2>/dev/null || echo "0")
        if [[ "$atv_existing" -gt 0 ]]; then
          log_ok "${atv_name} (tvOS ${tvos_version}) already exists"
        else
          read -r -p "Create ${atv_name} (tvOS ${tvos_version})? [y/N] " confirm || true
          if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
            confirm_line "Create ${atv_name} (tvOS ${tvos_version})? ${GREEN}Yes${CLEAR}"
            xcrun simctl create "$atv_name" "$atv_id" "$tvos_runtime_id" >/dev/null
            log_ok "Created ${atv_name} (tvOS ${tvos_version})"
          else
            confirm_line "Create ${atv_name} (tvOS ${tvos_version})? ${YELLOW}No${CLEAR}"
          fi
        fi
      else
        log_warn "No compatible Apple TV device types for tvOS ${tvos_version}"
      fi
    fi
  fi
}

main() {
  check_dependencies
  cleanup_simulators
  cleanup_runtimes
  cleanup_xcode
  cleanup_clt
  install_xcode
  install_runtimes
  install_simulators
}

main "$@"
