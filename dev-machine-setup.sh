#!/usr/bin/env zsh
# Full setup for a fresh machine. Run once; assumes nothing is pre-installed.

set -euo pipefail

install_cask() {
  local cask=$1 app_path=$2
  if [[ -d "$app_path" ]]; then
    print "  [skip]    $cask already installed"
  else
    brew install --cask "$cask" && print "  [installed] $cask"
  fi
}

# --- Terminal choice (asked up front before anything downloads) ---

print "Which terminal would you like to install?"
print "  1) iTerm2"
print "  2) Ghostty"
print "  3) Skip"
read -r "TERMINAL_CHOICE?> "

case "$TERMINAL_CHOICE" in
  1) TERMINAL_CASK="iterm2";  TERMINAL_APP="/Applications/iTerm.app" ;;
  2) TERMINAL_CASK="ghostty"; TERMINAL_APP="/Applications/Ghostty.app" ;;
  *) TERMINAL_CASK="" ;;
esac

# --- Homebrew first (also installs Xcode CLT, needed for git clones below) ---

print "\nChecking Homebrew..."

if ! command -v brew &>/dev/null; then
  print "  Installing Homebrew — this will also install Xcode Command Line Tools"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
else
  print "  [skip]    Homebrew already installed"
fi

brew update
brew bundle --no-upgrade --file="$HOME/vinceworks/Brewfile"

# --- Terminal ---

if [[ -n "$TERMINAL_CASK" ]]; then
  print "\nInstalling terminal..."
  install_cask "$TERMINAL_CASK" "$TERMINAL_APP"
fi

# --- Shell tools (after Homebrew so CLT is guaranteed available) ---

print "\nInstalling shell tools..."

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  print "  [skip]    oh-my-zsh already installed"
fi

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
  print "  [skip]    powerlevel10k already installed"
fi

if [[ ! -d "$HOME/.nvm" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
else
  print "  [skip]    nvm already installed"
fi

# --- Dotfiles ---

print "\nCreating symlinks..."

touch "$HOME/.credentials"

# oh-my-zsh generates its own .zshrc — remove it so we can symlink ours
rm -f "$HOME/.zshrc"

ln -s "$HOME/vinceworks/.zshrc"            "$HOME/.zshrc"
ln -s "$HOME/vinceworks/.zshenv"           "$HOME/.zshenv"
ln -s "$HOME/vinceworks/.gitconfig"        "$HOME/.gitconfig"
ln -s "$HOME/vinceworks/.gitmessage.txt"   "$HOME/.gitmessage.txt"
ln -s "$HOME/vinceworks/.gitignore_global" "$HOME/.gitignore_global"
ln -s "$HOME/vinceworks/.macosdefaults.sh" "$HOME/.macosdefaults.sh"
ln -s "$HOME/vinceworks/Brewfile"          "$HOME/Brewfile"
ln -s "$HOME/vinceworks/.shortcuts"        "$HOME/.shortcuts"
ln -s "$HOME/vinceworks/.shortcuts.private" "$HOME/.shortcuts.private"

print "  [linked]  dotfiles"

print "\nDone. Open a new shell to load your config."
print "Run 'p10k configure' to set up your prompt theme."
