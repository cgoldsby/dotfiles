#!/bin/bash
# install.sh — Dotfiles installer (macOS + Ghostty + Starship)

set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CLEAR='\033[0m'

log_ok()   { echo -e "${GREEN}✓${CLEAR} $1"; }
log_warn() { echo -e "${YELLOW}!${CLEAR} $1"; }

# Create a symlink, backing up any existing non-symlink file
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

# Homebrew
setup_homebrew() {
  if ! command -v brew &>/dev/null; then
    log_warn "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  brew update --quiet
  log_ok "Homebrew ready"
}

# NVM
setup_nvm() {
  if [[ ! -d "$HOME/.nvm" ]]; then
    log_warn "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash
  fi
  log_ok "nvm"
}

# Tools
setup_tools() {
  local casks=(
    ghostty
  )
  local formulae=(
    starship
    zsh-syntax-highlighting
    zsh-autosuggestions
    zsh-completions
    zsh-history-substring-search
    fzf
    rbenv
    m-cli
    mole
  )

  for cask in "${casks[@]}"; do
    if ! brew list --cask "$cask" &>/dev/null; then
      brew install --cask --force "$cask"
    fi
    log_ok "$cask"
  done

  for formula in "${formulae[@]}"; do
    if ! brew list "$formula" &>/dev/null; then
      brew install "$formula"
    fi
    log_ok "$formula"
  done
}

# Claude Code CLI
setup_claude() {
  if ! command -v claude &>/dev/null; then
    log_warn "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  log_ok "claude"
}

# Shell
setup_shell() {
  symlink "$DOTFILES/shell/zshrc"         "$HOME/.zshrc"
  symlink "$DOTFILES/shell/shell_aliases" "$HOME/.shell_aliases"
  if [[ "$SHELL" != "$(which zsh)" ]]; then
    chsh -s "$(which zsh)"
    log_ok "Set zsh as default shell"
  fi
}

# Starship
setup_starship() {
  symlink "$DOTFILES/starship/starship.toml" "$HOME/.config/starship.toml"
}

# Ghostty
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

# Vim
setup_vim() {
  mkdir -p "$HOME/.vim/colors"
  cp -af "$DOTFILES/vim/colors/"*.vim "$HOME/.vim/colors/"
  symlink "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
}

# Git aliases
setup_git() {
  git config --global alias.smartlog \
    "log --graph --pretty=format:'commit: %C(bold red)%h%Creset %C(red)<%H>%Creset %C(bold magenta)%d %Creset%ndate: %C(bold yellow)%cd %Creset%C(yellow)%cr%Creset%nauthor: %C(bold blue)%an%Creset %C(blue)<%ae>%Creset%n%C(cyan)%s%n%Creset'"
  git config --global alias.sl '!git smartlog'
  log_ok "Git aliases"
}

# macOS system settings (opt-in via --macos)
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
  local wallpaper="$DOTFILES/desktop/Monterey Graphic.heic"
  if [[ -f "$wallpaper" ]]; then
    osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"${wallpaper}\""
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
    log_ok "Desktop wallpaper"
  else
    log_warn "Wallpaper not found: $wallpaper"
  fi
}

# Main
main() {
  echo "Installing dotfiles from $DOTFILES"
  echo ""

  setup_homebrew
  setup_nvm
  setup_tools
  setup_claude
  setup_shell
  setup_starship
  setup_ghostty
  setup_vim
  setup_git

  if [[ "${1:-}" == "--macos" ]]; then
    setup_macos
    setup_desktop
  fi

  echo ""
  log_ok "Done. Open a new shell or run: source ~/.zshrc"
}

main "$@"
