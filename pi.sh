#!/usr/bin/env zsh
# Installs pi, applies shared settings, installs extensions, and reports on provider logins.
#
# Use --force to overwrite an existing settings file.

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

VINCEWORKS_DIR=$(dirname "$(realpath "$0")")

# pi needs a Node new enough to have shipped after its minimum-supported release.
node_new_enough() {
  local required=$1
  command -v node &>/dev/null || return 1
  local current=${$(node -v)#v}
  [[ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]
}

print "\nChecking pi..."

if command -v pi &>/dev/null; then
  print "  [skip]    pi already installed"
elif ! node_new_enough "22.19.0"; then
  print "  [skip]    pi requires Node >= 22.19.0 (found $(node -v 2>/dev/null || echo "none")), skipping"
else
  print "  Installing pi..."
  curl -fsSL https://pi.dev/install.sh | sh
fi

# --- pi settings ---

PI_SETTINGS_SOURCE="$VINCEWORKS_DIR/ai/pi/settings.json"
PI_SETTINGS_DIR="$HOME/.pi/agent"
PI_SETTINGS_FILE="$PI_SETTINGS_DIR/settings.json"

if [[ ! -f "$PI_SETTINGS_SOURCE" ]]; then
  print "\n  [error]   $PI_SETTINGS_SOURCE not found"
  exit 1
elif [[ -f "$PI_SETTINGS_FILE" ]] && ! $FORCE; then
  print "\n  [skip]    $PI_SETTINGS_FILE already exists (use --force)"
else
  mkdir -p "$PI_SETTINGS_DIR"
  cp "$PI_SETTINGS_SOURCE" "$PI_SETTINGS_FILE"
  print "\n  [copied]  $PI_SETTINGS_FILE"
fi

# --- pi extensions ---

if command -v pi &>/dev/null; then
  print "\n  Installing rpiv-todo extension..."
  pi install npm:@juicesharp/rpiv-todo

  print "  Installing pi-web-access extension..."
  pi install npm:pi-web-access
else
  print "\n  [skip]    pi not installed, skipping extensions"
fi

# --- pi providers ---

# openai-codex is OAuth-only (ChatGPT Plus/Pro): the one-time login happens by hand in pi's TUI.
if ! command -v pi &>/dev/null; then
  print "\n  [skip]    pi not installed, skipping provider logins"
elif pi auth check --provider openai-codex --no-refresh &>/dev/null; then
  print "\n  [skip]    openai-codex already logged in"
else
  print "\n  [warn]    openai-codex not logged in: run 'pi', then '/login openai-codex'"
fi

print "\nDone. Use --force to replace existing settings."
