#!/usr/bin/env zsh
# Installs AI tools and links shared agent definitions into ~/.claude and ~/.opencode.
# Use --force to overwrite existing files.

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

# --- Tools ---

print "\nChecking AI tools..."

if command -v claude &>/dev/null; then
  print "  [skip]    Claude Code already installed"
else
  print "  Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

if command -v opencode &>/dev/null; then
  print "  [skip]    OpenCode already installed"
else
  print "  Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
fi

# --- Agents ---

VINCEWORKS_DIR=$(dirname "$(realpath "$0")")
AGENTS_SOURCE="$VINCEWORKS_DIR/ai/agents"
TARGET_DIRS=("$HOME/.claude/agents" "$HOME/.opencode/agents")

if [[ ! -d "$AGENTS_SOURCE" ]]; then
  print "\nNo agents directory found at $AGENTS_SOURCE — nothing to do."
  exit 0
fi

agent_files=("$AGENTS_SOURCE"/*.md(N))
if [[ ${#agent_files[@]} -eq 0 ]]; then
  print "\nNo agent files found in $AGENTS_SOURCE — nothing to do."
  exit 0
fi

print "\nLinking agents..."

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"

  for agent_file in "${agent_files[@]}"; do
    agent_name=$(basename "$agent_file")
    dest="$target_dir/$agent_name"

    if [[ -L "$dest" ]]; then
      current_target=$(readlink "$dest")
      if [[ "$current_target" == "$agent_file" ]]; then
        print "  [ok]      $dest"
      elif $FORCE; then
        rm "$dest" && ln -s "$agent_file" "$dest"
        print "  [replaced] $dest (was -> $current_target)"
      else
        print "  [warn]    $dest points elsewhere — skipping (use --force)"
      fi
    elif [[ -e "$dest" ]]; then
      if $FORCE; then
        rm "$dest" && ln -s "$agent_file" "$dest"
        print "  [replaced] $dest (was a regular file)"
      else
        print "  [warn]    $dest exists as a regular file — skipping (use --force)"
      fi
    else
      ln -s "$agent_file" "$dest"
      print "  [linked]  $dest"
    fi
  done
done

print "\nDone. Use --force to replace existing files or wrong-target symlinks."
