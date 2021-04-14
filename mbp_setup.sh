sudo port selfupdate
sudo port upgrade outdated

sudo port install cmake tmux git neovim py-neovim fzf ripgrep yarn fish wget ccache fd

sudo port install opencv4

defaults write -g ApplePressAndHoldEnabled -bool false

infocmp -x tmux-256color > xyz
/usr/bin/tic -x xyz
rm xyz

