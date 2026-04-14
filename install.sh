#!/bin/bash
# install.sh — Dotfiles installer (macOS + Ghostty + Starship)

set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
CLEAR='\033[0m'

log_ok()      { echo -e "${GREEN}✓${CLEAR} $1"; }
log_warn()    { echo -e "${YELLOW}!${CLEAR} $1"; }
log_info()    { echo -e "${BLUE}›${CLEAR} $1"; }
log_section() { echo -e "\n${BOLD}=> $1${CLEAR}"; }

symlink() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mv "$dst" "${dst}.backup.$(date +%Y%m%d%H%M%S)"
    log_warn "Backed up existing $(basename "$dst")"
  fi
  ln -sf "$src" "$dst"
  log_ok "Linked $(basename "$dst")"
}

setup_homebrew() {
  if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -d /opt/homebrew/share ]]; then
    chmod -R g-w /opt/homebrew/share
  fi
  brew update --quiet
  log_ok "Homebrew"
}

setup_nvm() {
  if [[ ! -d "$HOME/.nvm" ]]; then
    log_info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash
  fi
  log_ok "NVM"
}

setup_tools() {
  brew bundle --file="$DOTFILES/Brewfile"
  log_ok "Homebrew packages"
}

setup_claude() {
  if ! command -v claude &>/dev/null; then
    log_info "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  log_ok "Claude Code"
}

setup_shell() {
  symlink "$DOTFILES/shell/zshrc"                "$HOME/.zshrc"
  symlink "$DOTFILES/shell/shell_aliases"        "$HOME/.shell_aliases"
  symlink "$DOTFILES/shell/zsh_highlight_styles" "$HOME/.zsh_highlight_styles"

  local zsh_path
  zsh_path="$(which zsh)"
  if [[ "$SHELL" != "$zsh_path" ]]; then
    if ! grep -q "^$zsh_path$" /etc/shells; then
      log_info "Adding $zsh_path to /etc/shells (requires sudo)"
      echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi
    chsh -s "$zsh_path"
    log_ok "Default shell → zsh"
  fi
}

setup_starship() {
  symlink "$DOTFILES/starship/starship.toml" "$HOME/.config/starship.toml"
  log_ok "Starship"
}

setup_ghostty() {
  mkdir -p "$HOME/.config/ghostty"
  local icons=("$DOTFILES/ghostty/"*.icns)
  if [[ -f "${icons[0]}" ]]; then
    cp -f "${icons[@]}" "$HOME/.config/ghostty/"
    log_ok "Ghostty icons"
  else
    log_warn "No Ghostty icons found — skipping"
  fi
  symlink "$DOTFILES/ghostty/config" "$HOME/.config/ghostty/config"
}

setup_ghostty_terminfo() {
  local terminfo_src="/Applications/Ghostty.app/Contents/Resources/terminfo"
  if [[ ! -d "$terminfo_src" ]]; then
    log_warn "Ghostty terminfo source not found — skipping"
    return
  fi
  mkdir -p "$HOME/.terminfo/78" "$HOME/.terminfo/67"
  cp -f "$terminfo_src/78/xterm-ghostty" "$HOME/.terminfo/78/"
  cp -f "$terminfo_src/67/ghostty"       "$HOME/.terminfo/67/"
  log_ok "Ghostty terminfo"
}

setup_vim() {
  mkdir -p "$HOME/.vim/colors"
  cp -af "$DOTFILES/vim/colors/"*.vim "$HOME/.vim/colors/"
  symlink "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
  log_ok "Vim"
}

setup_vscode() {
  local vscode_user="$HOME/Library/Application Support/Code/User"
  local live="$vscode_user/settings.json"
  local portable="$DOTFILES/vscode/settings.json"
  mkdir -p "$vscode_user"
  if [[ -f "$live" ]]; then
    python3 -c "
import json, re, sys
content = open(sys.argv[1]).read()
content = re.sub(r'//[^\n]*', '', content)
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r',(\s*[}\]])', r'\1', content)
print(json.dumps(json.loads(content)))
" "$live" | jq -s '.[0] * .[1]' - "$portable" > /tmp/vscode_settings.json \
      && mv /tmp/vscode_settings.json "$live"
  else
    cp "$portable" "$live"
  fi
  log_ok "VS Code settings"
  if command -v code &>/dev/null; then
    while IFS= read -r ext; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      code --install-extension "$ext" --force 2>/dev/null
    done < "$DOTFILES/vscode/extensions.txt"
    log_ok "VS Code extensions"
  else
    log_warn "VS Code CLI (code) not found — skipping extensions"
  fi
}

setup_ssh() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  symlink "$DOTFILES/ssh/config" "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
  log_ok "SSH config"
}

setup_git() {
  git config --global alias.smartlog \
    "log --graph --pretty=format:'commit: %C(bold red)%h%Creset %C(red)<%H>%Creset %C(bold magenta)%d %Creset%ndate: %C(bold yellow)%cd %Creset%C(yellow)%cr%Creset%nauthor: %C(bold blue)%an%Creset %C(blue)<%ae>%Creset%n%C(cyan)%s%n%Creset'"
  git config --global alias.sl '!git smartlog'
  log_ok "Git aliases"
}

setup_macos() {
  chflags nohidden ~/Library/
  defaults write com.apple.finder AppleShowAllExtensions -bool true
  defaults write com.apple.dock autohide                 -bool false
  defaults write com.apple.dock magnification            -bool false
  defaults write com.apple.dock orientation              -string bottom
  killall Finder 2>/dev/null || true
  killall Dock   2>/dev/null || true
  log_ok "macOS settings"
}

setup_desktop() {
  local wallpaper="$DOTFILES/desktop/time-exodus-rockets.heic"
  if [[ -f "$wallpaper" ]]; then
    osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"${wallpaper}\""
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
    log_ok "Desktop wallpaper"
  else
    log_warn "Wallpaper not found: $wallpaper"
  fi
}

main() {
  local do_macos=false do_xcode=false
  for arg in "$@"; do
    case "$arg" in
      --macos) do_macos=true ;;
      --xcode) do_xcode=true ;;
    esac
  done

  echo "Installing dotfiles from $DOTFILES"

  log_section "Bootstrap"
  setup_homebrew
  setup_nvm
  setup_tools
  setup_claude

  log_section "Dotfiles"
  setup_shell
  setup_starship
  setup_ghostty
  setup_ghostty_terminfo
  setup_vim
  setup_vscode
  setup_ssh
  setup_git

  if $do_macos; then
    log_section "macOS"
    setup_macos
    setup_desktop
  fi

  if $do_xcode; then
    "$DOTFILES/setup_xcode.sh"
  fi

  echo ""
  log_ok "Done. Open a new shell or run: source ~/.zshrc"
}

main "$@"
