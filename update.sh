#!/usr/bin/env zsh
# Updates dotfiles and packages on an existing machine.
# Skips anything already in place. Use --force to overwrite.

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

link() {
  local src=$1 dest=$2
  if [[ -e "$dest" || -L "$dest" ]]; then
    if $FORCE; then
      rm "$dest"
      ln -s "$src" "$dest"
      print "  [replaced] $dest"
    else
      print "  [skip]    $dest (use --force to overwrite)"
    fi
    return
  fi
  ln -s "$src" "$dest"
  print "  [linked]  $dest"
}

# --- Packages ---

print "\nUpdating packages..."
brew bundle --no-upgrade --file="$HOME/vinceworks/Brewfile"

# --- Dotfiles ---

print "\nUpdating symlinks..."

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

print "\nDone. Run with --force to overwrite existing symlinks."
