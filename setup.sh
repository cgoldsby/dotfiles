#!/bin/bash

GREEN='\033[1;32m'
CLEAR='\033[0m'

logs () {
	echo -e "${GREEN}✓${CLEAR} $1"
}

install_zsh () {
	# Test to see if zshell is installed.
	if [ ! -f /bin/zsh -o -f /usr/bin/zsh ]; then
		sudo apt-get install -y git zsh
		logs "zsh installed"
	fi

	# Set the default shell to zsh if it isn't currently set to zsh
	if [[ ! $(echo $SHELL) == $(which zsh) ]]; then
		chsh -s $(which zsh)
      logs "zsh set as default shell"
    fi

	if [ ! -d $HOME/.zprezto ]; then
		zprezto/setup.zsh
		logs "zsh setup"
	fi

	logs "zsh configured"
}

install_brew () {
	if [ ! -f "`which brew`" ]; then
	  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		logs "homebrew installed"
	else
	  brew update
		logs "homebrew updated"
	fi
}

install_m-cli () {
	if [ ! -f "`which m`" ]; then
	  brew install m-cli
	  logs "m-cli installed"
	else
		brew upgrade --cleanup m-cli 2>/dev/null
		logs "m-cli upgraded"
	fi
}

install_tig () {
	if [ ! -f "`which tig`" ]; then
	  brew install tig
	  logs "tig installed"
	else
		brew upgrade --cleanup tig 2>/dev/null
		logs "tig upgraded"
	fi
}

setup_zprezto () {
	ln -sf `pwd`/zprezto/zpreztorc $HOME/.zpreztorc
	cp zprezto/themes/prompt_cgoldsby_setup $HOME/.zprezto/modules/prompt/functions
	logs "zprezto configured"
}

setup_iterm () {
	# Don’t display the annoying prompt when quitting iTerm
	defaults write com.googlecode.iterm2 PromptOnQuit -bool false
	defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
	defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$(pwd)/iterm"
	logs "iTerm configured"
}

setup_terminal () {
	defaults write $HOME/Library/Preferences/com.apple.Terminal.plist "Default Window Settings" -string "Pro"
	defaults write $HOME/Library/Preferences/com.apple.Terminal.plist "Startup Window Settings" -string "Pro"
	logs "terminal configured"
}

setup_shell () {
	ln -sf `pwd`/shell/bashrc $HOME/.bashrc
	ln -sf `pwd`/shell/zshrc $HOME/.zshrc
	logs "shell configured"
}

setup_vim () {
	mkdir -p $HOME/.vim/colors
        cp -af `pwd`/vim/colors/*.vim $HOME/.vim/colors/

	ln -sf `pwd`/vim/vimrc $HOME/.vimrc
	logs "vim configured"
}

setup_desktop () {
	image_path=`pwd`/desktop/wallpaper14.heic
	osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"${image_path}\""
 	osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
	logs "desktop configured"
}

setup_finder () {
  chflags nohidden ~/Library/
	m finder showextensions YES
  logs "finder configured"
}

setup_dock () {
	m dock autohide NO
	m dock magnification NO
	m dock position BOTTOM
	logs "dock configured"
}

setup_git_aliases () {
	git config --global alias.smartlog "log --graph --pretty=format:'commit: %C(bold red)%h%Creset %C(red)<%H>%Creset %C(bold magenta)%d %Creset%ndate: %C(bold yellow)%cd %Creset%C(yellow)%cr%Creset%nauthor: %C(bold blue)%an%Creset %C(blue)<%ae>%Creset%n%C(cyan)%s%n%Creset'"
	git config --global alias.sl '!git smartlog'
	logs "git aliases configured"
}

install_zsh
install_brew
install_m-cli
install_tig
setup_zprezto
setup_iterm
setup_shell
setup_vim
setup_terminal
setup_desktop
setup_finder
setup_dock
setup_git_aliases
