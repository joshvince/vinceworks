#!/usr/bin/env zsh

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

# Creates a symlink src -> dest, skipping if dest already exists.
# With --force, replaces any existing file or symlink.
link() {
  local src=$1 dest=$2
  if [[ -e "$dest" || -L "$dest" ]]; then
    if $FORCE; then
      rm "$dest"
      ln -s "$src" "$dest"
      print "  [replaced] $dest"
    else
      print "  [skip]    $dest already exists (use --force to overwrite)"
    fi
    return
  fi
  ln -s "$src" "$dest"
  print "  [linked]  $dest"
}

# Installs a Homebrew cask if the app isn't already present.
# With --force, reinstalls even if already present.
install_cask() {
  local cask=$1 app_path=$2
  if [[ -d "$app_path" ]]; then
    if $FORCE; then
      brew install --cask --force "$cask" && print "  [reinstalled] $cask"
    else
      print "  [skip]    $cask already installed (use --force to reinstall)"
    fi
  else
    brew install --cask "$cask" && print "  [installed] $cask"
  fi
}

# --- Terminal ---

print "Which terminal would you like to install?"
print "  1) iTerm2"
print "  2) Ghostty"
print "  3) Skip"
read -r "TERMINAL_CHOICE?> "

case "$TERMINAL_CHOICE" in
  1) TERMINAL_CASK="iterm2";   TERMINAL_APP="/Applications/iTerm.app" ;;
  2) TERMINAL_CASK="ghostty";  TERMINAL_APP="/Applications/Ghostty.app" ;;
  *) TERMINAL_CASK="" ;;
esac

# --- Shell tools (skipped if already present) ---

print "\nChecking shell tools..."

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
else
  print "  [skip]    nvm already installed"
fi

# --- Homebrew ---

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

# --- Dotfiles ---

print "\nCreating symlinks..."

touch "$HOME/.credentials"

link "$HOME/vinceworks/.zshrc"            "$HOME/.zshrc"
link "$HOME/vinceworks/.zshenv"           "$HOME/.zshenv"
link "$HOME/vinceworks/.gitconfig"        "$HOME/.gitconfig"
link "$HOME/vinceworks/.gitmessage.txt"   "$HOME/.gitmessage.txt"
link "$HOME/vinceworks/.gitignore_global" "$HOME/.gitignore_global"
link "$HOME/vinceworks/.macosdefaults.sh" "$HOME/.macosdefaults.sh"
link "$HOME/vinceworks/Brewfile"          "$HOME/Brewfile"
link "$HOME/vinceworks/.shortcuts"        "$HOME/.shortcuts"
link "$HOME/vinceworks/.shortcuts.private" "$HOME/.shortcuts.private"

# --- Tools ---

print "\nSetting up tools..."

mkdir -p "$HOME/.local/bin"
link "$HOME/vinceworks/ai/link-agents.sh" "$HOME/.local/bin/link-agents"

print "\nDone. Run with --force to overwrite existing symlinks and reinstall apps."
