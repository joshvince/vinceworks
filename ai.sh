#!/usr/bin/env zsh
# Installs AI tools and propagates shared agent/skill definitions into Claude Code.
#
# The agent files in ./ai/agents keep OpenCode's frontmatter format and are translated on
# the way into ~/.claude/agents/, which wants `name` + `description` and no permission
# block. Skill directories need no translation: SKILL.md is the same format everywhere.
#
# Use --force to overwrite existing files / wrong-target symlinks.
# Use --update to update installed tools without installing missing ones or syncing files.

set -euo pipefail

FORCE=false
UPDATE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --update) UPDATE=true ;;
  esac
done

VINCEWORKS_DIR=$(dirname "$(realpath "$0")")

if $UPDATE; then
  print "\nUpdating installed AI tools..."

  if command -v pi &>/dev/null; then
    print "  Updating pi and its extensions..."
    pi update --extensions
  else
    print "  [skip]    pi not installed"
  fi

  if command -v claude &>/dev/null; then
    print "  Updating Claude Code..."
    claude update
  else
    print "  [skip]    Claude Code not installed"
  fi

  if command -v paseo &>/dev/null; then
    print "  Updating Paseo..."
    if [[ "${VINCEWORKS_CONTEXT:-}" == sandbox ]]; then
      npm install -g --prefix "$HOME/.local" @getpaseo/cli@latest
    else
      npm install -g @getpaseo/cli@latest
    fi
  else
    print "  [skip]    Paseo not installed"
  fi

  if [[ "${VINCEWORKS_CONTEXT:-}" == sandbox ]] && command -v paseo &>/dev/null; then
    print "\nDone. Restart the sandbox to run the new Paseo daemon."
  else
    print "\nDone."
  fi
  exit 0
fi

# --- Tools ---

print "\nChecking AI tools..."

if command -v claude &>/dev/null; then
  print "  [skip]    Claude Code already installed"
else
  print "  Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

if [[ "${VINCEWORKS_CONTEXT:-}" == sandbox ]]; then
  if [[ -x "$HOME/.local/bin/paseo" ]]; then
    print "  [skip]    Paseo already installed"
  else
    print "  Installing Paseo into ~/.local..."
    if ! npm install -g --prefix "$HOME/.local" @getpaseo/cli@latest; then
      print -u2 "  [warn]    Paseo install failed, so the daemon starts from the copy baked into the image"
    fi
  fi
fi

"$VINCEWORKS_DIR/pi.sh" "$@"

# --- Agents ---

AGENTS_SOURCE="$VINCEWORKS_DIR/ai/agents"
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

print "\nWriting Claude Code agents (frontmatter translated)..."
mkdir -p "$CLAUDE_AGENTS_DIR"
for agent_file in "${agent_files[@]}"; do
  install_claude_agent "$agent_file" "$CLAUDE_AGENTS_DIR/${agent_file:t}"
done

# --- Skills ---

SKILLS_SOURCE="$VINCEWORKS_DIR/ai/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"

# Symlink a skill directory into a provider's skills dir. SKILL.md is the same
# format across harnesses, so no translation step is needed (unlike agents).
link_skill() {
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
      rm -rf "$dest" && ln -s "$src" "$dest"
      print "  [replaced] $dest (was a real directory or file)"
    else
      print "  [warn]    $dest exists and isn't our symlink — skipping (use --force)"
    fi
  else
    ln -s "$src" "$dest"
    print "  [linked]  $dest"
  fi
}

skill_dirs=("$SKILLS_SOURCE"/*(N/))
if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  print "\nNo skill directories found in $SKILLS_SOURCE — skipping skills."
else
  print "\nLinking skills into Claude Code and ~/.agents/skills..."
  mkdir -p "$CLAUDE_SKILLS_DIR" "$AGENTS_SKILLS_DIR"
  for skill_dir in "${skill_dirs[@]}"; do
    link_skill "$skill_dir" "$CLAUDE_SKILLS_DIR/${skill_dir:t}"
    link_skill "$skill_dir" "$AGENTS_SKILLS_DIR/${skill_dir:t}"
  done
fi

print "\nDone. Use --force to replace existing files or wrong-target symlinks."
