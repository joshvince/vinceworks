#!/usr/bin/env zsh

# Symlink shared agent definitions from vinceworks into the current project.
# Usage: link-agents [--force]

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

# Resolve VINCEWORKS_DIR from this script's real location (ai/link-agents.sh → two levels up)
SCRIPT_REAL=$(realpath "$0")
VINCEWORKS_DIR=$(dirname "$(dirname "$SCRIPT_REAL")")
AGENTS_SOURCE="$VINCEWORKS_DIR/ai/agents"

TARGET_DIRS=(".claude/agents" ".opencode/agents")
GITIGNORE_MARKER="vinceworks-shared-agents"

if [[ ! -d "$AGENTS_SOURCE" ]]; then
  print "No agents directory found at $AGENTS_SOURCE — nothing to do."
  exit 0
fi

agent_files=("$AGENTS_SOURCE"/*.md(N))
if [[ ${#agent_files[@]} -eq 0 ]]; then
  print "No agent files found in $AGENTS_SOURCE — nothing to do."
  exit 0
fi

# Find project root
GIT_REPO=true
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  GIT_REPO=false
  PROJECT_ROOT="$PWD"
  print "Not a git repo — symlinks will be created but .gitignore will not be updated."
}

# Symlink each agent into each target directory
for target_dir in "${TARGET_DIRS[@]}"; do
  full_target="$PROJECT_ROOT/$target_dir"
  mkdir -p "$full_target"

  for agent_file in "${agent_files[@]}"; do
    agent_name=$(basename "$agent_file")
    dest="$full_target/$agent_name"

    if [[ -L "$dest" ]]; then
      current_target=$(readlink "$dest")
      if [[ "$current_target" == "$agent_file" ]]; then
        print "  [ok]      $dest"
        continue
      else
        if $FORCE; then
          rm "$dest"
          ln -s "$agent_file" "$dest"
          print "  [replaced] $dest (was -> $current_target)"
        else
          print "  [warn]    $dest is a symlink to a different target — skipping (use --force)"
        fi
      fi
    elif [[ -e "$dest" ]]; then
      if $FORCE; then
        rm "$dest"
        ln -s "$agent_file" "$dest"
        print "  [replaced] $dest (was a regular file)"
      else
        print "  [warn]    $dest exists as a regular file — skipping (use --force)"
      fi
    else
      ln -s "$agent_file" "$dest"
      print "  [linked]  $dest -> $agent_file"
    fi
  done
done

# Update .gitignore if in a git repo
if $GIT_REPO; then
  gitignore="$PROJECT_ROOT/.gitignore"

  if [[ -f "$gitignore" ]] && grep -qF "$GITIGNORE_MARKER" "$gitignore"; then
    print "  [ok]      .gitignore already managed"
  else
    # Check for conflicting un-ignore rules
    if [[ -f "$gitignore" ]] && grep -qE '^\!.*\.claude/agents|^\!.*\.opencode/agents' "$gitignore"; then
      print "  [warn]    .gitignore has explicit un-ignore rules for agent directories."
      print "            Review .gitignore manually — not appending to avoid conflicts."
    else
      {
        printf '\n# %s\n' "$GITIGNORE_MARKER"
        printf '.claude/agents/*.md\n'
        printf '.opencode/agents/*.md\n'
      } >> "$gitignore"
      print "  [added]   .gitignore entries for shared agents"
    fi
  fi
fi

print ""
print "Done. Use --force to replace existing files or wrong-target symlinks."
