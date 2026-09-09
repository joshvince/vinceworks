#!/usr/bin/env bash
# Runs on every container start as josh. Provisions dotfiles, sshd, and
# Postgres, then execs the Paseo daemon in the foreground.
set -euo pipefail

vinceworks="$HOME/vinceworks"
sshd_dir="$HOME/.ssh/sshd"
user=$(id -un)

echo "Configuring git and shell..."
for f in .gitconfig .gitmessage.txt .gitignore_global; do
  cp "$vinceworks/$f" "$HOME/$f"
done
cp "$vinceworks/sandbox/zshrc" "$HOME/.zshrc"
cp "$vinceworks/sandbox/zshenv" "$HOME/.zshenv"
cp "$vinceworks/sandbox/tmux.conf" "$HOME/.tmux.conf"
git config --global --unset-all credential.helper 2>/dev/null || true

echo "Installing AI tooling..."
zsh "$vinceworks/ai.sh" >/dev/null

echo "Preparing sshd..."
mkdir -p "$HOME/projects" "$sshd_dir"
chmod 700 "$sshd_dir"
chmod 700 "$HOME/.ssh"
[[ -f "$sshd_dir/ssh_host_ed25519_key" ]] || ssh-keygen -t ed25519 -N '' -f "$sshd_dir/ssh_host_ed25519_key"
[[ -f "$sshd_dir/authorized_keys" ]] || cp "$vinceworks/sandbox/authorized_keys" "$sshd_dir/authorized_keys"
chmod 600 "$sshd_dir/authorized_keys"

echo "Starting postgres..."
sudo service postgresql start >/dev/null
if ! sudo -u postgres psql -tAc "select 1 from pg_roles where rolname = '$user'" | grep -q 1; then
  sudo -u postgres createuser -s "$user"
fi

echo "Starting sshd..."
# A backgrounded sshd cannot trip set -e, so we test the config and keys first.
/usr/sbin/sshd -t -f /etc/ssh/sandbox_sshd_config
/usr/sbin/sshd -f /etc/ssh/sandbox_sshd_config -D -e &

if gh auth status >/dev/null 2>&1; then
  gh auth setup-git
fi

echo "Installing toolchains in the background (log: ~/mise-install.log)..."
# Runs in the background so sshd and Paseo are reachable while a new Ruby compiles.
(
  for dir in "$HOME"/projects/*/; do
    [[ -d "$dir" ]] || continue
    (cd "$dir" && mise trust --yes >/dev/null 2>&1; mise install)
  done
) > "$HOME/mise-install.log" 2>&1 &

echo "sandbox: ready"

# The pid file survives in the bind-mounted home, and a stale one makes the daemon refuse to start if a new process has that pid.
rm -f "$HOME/.paseo/paseo.pid"
exec paseo daemon start --foreground --listen 127.0.0.1:6767 --home "$HOME/.paseo"
