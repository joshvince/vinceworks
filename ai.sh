#!/usr/bin/env zsh
# Installs AI tools and propagates shared agent definitions into Claude Code and OpenCode.
#
# Agent files in ./ai/agents are written in OpenCode's frontmatter format. We:
#   - symlink them into ~/.config/opencode/agents/ (OpenCode reads this dir)
#   - translate-and-copy them into ~/.claude/agents/ (Claude Code uses a different
#     frontmatter shape — `name` + `description`, no per-tool permission block)
#
# Use --force to overwrite existing files / wrong-target symlinks.

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
OPENCODE_AGENTS_DIR="$HOME/.config/opencode/agents"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"

if [[ ! -d "$AGENTS_SOURCE" ]]; then
  print "\nNo agents directory found at $AGENTS_SOURCE — nothing to do."
  exit 0
fi

agent_files=("$AGENTS_SOURCE"/*.md(N))
if [[ ${#agent_files[@]} -eq 0 ]]; then
  print "\nNo agent files found in $AGENTS_SOURCE — nothing to do."
  exit 0
fi

# Symlink an OpenCode-format agent into OpenCode's agents dir.
link_opencode_agent() {
  local src=$1 dest=$2
  if [[ -L "$dest" ]]; then
    local current_target=$(readlink "$dest")
    if [[ "$current_target" == "$src" ]]; then
      print "  [ok]      $dest"
    elif $FORCE; then
      rm "$dest" && ln -s "$src" "$dest"
      print "  [replaced] $dest (was -> $current_target)"
    else
      print "  [warn]    $dest points elsewhere — skipping (use --force)"
    fi
  elif [[ -e "$dest" ]]; then
    if $FORCE; then
      rm "$dest" && ln -s "$src" "$dest"
      print "  [replaced] $dest (was a regular file)"
    else
      print "  [warn]    $dest exists as a regular file — skipping (use --force)"
    fi
  else
    ln -s "$src" "$dest"
    print "  [linked]  $dest"
  fi
}

# Write the Claude Code translation of an OpenCode-format agent to `dest`.
# Tools field is omitted intentionally — current source files use only allow/ask
# (no deny), so the faithful Claude equivalent is "all tools available".
write_claude_agent() {
  local src=$1 dest=$2
  local name=$(basename "$src" .md)
  local description=$(awk '
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      print
      exit
    }
  ' "$src")

  if [[ -z "$description" ]]; then
    print "  [error]   $src has no description in frontmatter — skipping"
    return 1
  fi

  {
    print -- "---"
    print -- "name: $name"
    print -- "description: $description"
    print -- "---"
    awk '
      /^---[[:space:]]*$/ { fm++; next }
      fm >= 2 { print }
    ' "$src"
  } > "$dest"
}

# Translate-and-copy a Claude-format agent into Claude Code's agents dir.
install_claude_agent() {
  local src=$1 dest=$2

  # Old layout left a symlink here. Replace only with --force.
  if [[ -L "$dest" ]]; then
    if $FORCE; then
      rm "$dest"
      write_claude_agent "$src" "$dest" || return 1
      print "  [replaced] $dest (was a symlink — old layout)"
    else
      print "  [warn]    $dest is a symlink (old layout) — skipping (use --force)"
    fi
    return 0
  fi

  if [[ -f "$dest" ]]; then
    local tmp=$(mktemp)
    if ! write_claude_agent "$src" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    if cmp -s "$tmp" "$dest"; then
      print "  [ok]      $dest"
      rm -f "$tmp"
    elif $FORCE; then
      mv "$tmp" "$dest"
      print "  [replaced] $dest"
    else
      print "  [warn]    $dest content differs — skipping (use --force)"
      rm -f "$tmp"
    fi
    return 0
  fi

  write_claude_agent "$src" "$dest" || return 1
  print "  [written] $dest"
}

print "\nLinking OpenCode agents..."
mkdir -p "$OPENCODE_AGENTS_DIR"
for agent_file in "${agent_files[@]}"; do
  link_opencode_agent "$agent_file" "$OPENCODE_AGENTS_DIR/${agent_file:t}"
done

print "\nWriting Claude Code agents (frontmatter translated)..."
mkdir -p "$CLAUDE_AGENTS_DIR"
for agent_file in "${agent_files[@]}"; do
  install_claude_agent "$agent_file" "$CLAUDE_AGENTS_DIR/${agent_file:t}"
done

print "\nDone. Use --force to replace existing files or wrong-target symlinks."
