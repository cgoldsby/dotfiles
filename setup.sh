#!/bin/bash

install_zsh () {
	# Test to see if zshell is installed.
	if [ ! -f /bin/zsh -o -f /usr/bin/zsh ]; then
		sudo apt-get install -y git zsh
		zprezto/setup.zsh
		echo "✓ zsh installed"
	fi

	# Set the default shell to zsh if it isn't currently set to zsh
    if [[ ! $(echo $SHELL) == $(which zsh) ]]; then
      chsh -s $(which zsh)
      echo "✓ zsh set as default shell"
    fi
}

setup_zprezto () {
	cp zprezto/zpreztorc $HOME/.zpreztorc
	echo "✓ zprezto configured"
}

setup_iterm () {
	# Don’t display the annoying prompt when quitting iTerm
	defaults write com.googlecode.iterm2 PromptOnQuit -bool false
	defaults write com.googlecode.iterm2 PrefsCustomFolder -string "${HOME}/Sources/dotfiles/iterm"
	echo "✓ iTerm configured"
}

install_zsh
setup_zprezto
setup_iterm
