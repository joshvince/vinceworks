#!/usr/bin/env bash
# Runs on every container start as the project user. Prepares the repo, starts
# services, installs the toolchain, then idles while tmux holds the sessions.
set -euo pipefail

name=${PROJECT_NAME:?PROJECT_NAME is not set}
user=$(id -un)
project_dir="$HOME/projects/$name"
secrets_dir="$HOME/.secrets"
vinceworks="$HOME/vinceworks"

log() { printf '  [%s] %s\n' "$1" "$2"; }

[[ -d "$project_dir" ]] || { log error "$project_dir is missing"; exit 1; }

echo "Copying secrets..."
if [[ -d "$secrets_dir" ]]; then
  while IFS= read -r -d '' file; do
    rel=${file#"$secrets_dir"/}
    mkdir -p "$(dirname "$project_dir/$rel")"
    cp "$file" "$project_dir/$rel"
    log secret "$rel"
  done < <(find "$secrets_dir" -type f -print0)
fi

echo "Configuring git..."
for f in .gitconfig .gitmessage.txt .gitignore_global; do
  [[ -f "$vinceworks/$f" ]] && cp "$vinceworks/$f" "$HOME/$f"
done
git config --global --unset-all credential.helper 2>/dev/null || true
log ok "gitconfig"

case ",${PROJECT_SERVICES:-}," in
  *,postgres,*)
    echo "Starting postgres..."
    sudo service postgresql start >/dev/null
    if ! sudo -u postgres psql -tAc "select 1 from pg_roles where rolname = '$user'" | grep -q 1; then
      sudo -u postgres createuser -s "$user"
      log created "postgres role $user"
    fi
    log ok "postgres"
    ;;
esac

echo "Installing toolchain with mise..."
cd "$project_dir"
mise trust --yes 2>/dev/null || true
mise install
log ok "$(mise ls --current 2>/dev/null | awk '{print $1"@"$2}' | paste -sd' ' -)"

echo "Installing AI tooling..."
zsh "$vinceworks/ai.sh" >/dev/null
log ok "agents and skills"

if ! tmux has-session -t main 2>/dev/null; then
  tmux new-session -d -s main -n claude -c "$project_dir"
  tmux new-window -t main -n server -c "$project_dir"
  tmux new-window -t main -n shell -c "$project_dir"
  tmux select-window -t main:claude
  tmux send-keys -t main:claude 'claude'
  log created "tmux session main (claude, server, shell)"
fi

echo "projects: ready"
exec sleep infinity
