#!/bin/bash

logs () {
	echo "✓ $1"
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
	fi
}

setup_zprezto () {
	ln -sf $HOME/Sources/dotfiles/zprezto/zpreztorc $HOME/.zpreztorc
	cp zprezto/themes/prompt_cgoldsby_setup $HOME/.zprezto/modules/prompt/functions
	logs "zprezto configured"
}

setup_iterm () {
	# Don’t display the annoying prompt when quitting iTerm
	defaults write com.googlecode.iterm2 PromptOnQuit -bool false
	defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
	defaults write com.googlecode.iterm2 PrefsCustomFolder -string "${HOME}/Sources/dotfiles/iterm"
	logs "iTerm configured"
}

setup_terminal () {
	defaults write $HOME/Library/Preferences/com.apple.Terminal.plist "Default Window Settings" -string "Pro"
	defaults write $HOME/Library/Preferences/com.apple.Terminal.plist "Startup Window Settings" -string "Pro"
	logs "terminal configured"
}

setup_shell () {
	ln -sf $HOME/Sources/dotfiles/shell/bashrc $HOME/.bashrc
	ln -sf $HOME/Sources/dotfiles/shell/zshrc $HOME/.zshrc
	logs "shell configured"
}

setup_desktop () {
	osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/Users/cgoldsby/Sources/dotfiles/desktop/wallpaper6.jpg"'
	logs "desktop configured"
}

setup_finder () {
  chflags nohidden ~/Library/
  logs "finder configured"
}

install_zsh
setup_zprezto
setup_iterm
setup_shell
setup_terminal
setup_desktop
setup_finder
