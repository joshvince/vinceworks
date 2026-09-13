#!/usr/bin/env bash
set -euo pipefail

BOT_USER=vinceworks-bot

if ! id "$BOT_USER" &>/dev/null; then
  useradd --system --create-home --shell /bin/bash "$BOT_USER"
fi

install -d -m 700 -o "$BOT_USER" -g "$BOT_USER" "/home/$BOT_USER/.ssh"
touch "/home/$BOT_USER/.ssh/authorized_keys"
chmod 600 "/home/$BOT_USER/.ssh/authorized_keys"
chown "$BOT_USER:$BOT_USER" "/home/$BOT_USER/.ssh/authorized_keys"

rm -- "$0"
