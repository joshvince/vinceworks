#!/usr/bin/env zsh
# Installs pi and writes its global settings.
#
# Use --force to overwrite an existing settings file.

set -euo pipefail

FORCE=false
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

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

PI_SETTINGS_DIR="$HOME/.pi/agent"
PI_SETTINGS_FILE="$PI_SETTINGS_DIR/settings.json"

if [[ -f "$PI_SETTINGS_FILE" ]] && ! $FORCE; then
  print "\n  [skip]    $PI_SETTINGS_FILE already exists (use --force)"
else
  mkdir -p "$PI_SETTINGS_DIR"
  cat > "$PI_SETTINGS_FILE" <<'JSON'
{
  "defaultProvider": "opencode-go",
  "defaultModel": "deepseek-v4.1-flash",
  "enabledModels": [
    "opencode-go/deepseek-v4-flash",
    "opencode-go/deepseek-v4.1-flash",
    "opencode-go/deepseek-v4-flash-vision-exp",
    "opencode-go/deepseek-v4-pro",
    "opencode-go/qwen3.8-flash",
    "opencode-go/qwen3.8-max",
    "opencode-go/gpt-5.6-luna",
    "opencode-go/muse-spark-1.3-contributor"
  ]
}
JSON
  print "\n  [written] $PI_SETTINGS_FILE"
fi

print "\nDone. Use --force to replace existing settings."
