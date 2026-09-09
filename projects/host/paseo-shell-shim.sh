#!/usr/bin/env bash
# Stands in for the host-level Paseo daemon's $SHELL, so a workspace
# "terminal" (a plain interactive shell, not an agent run) lands inside the
# right project container instead of on the bare host. See
# ../../paseo-host-plan.md and paseo-claude-shim.sh, which does the same
# thing for agent runs. Paseo sets the child's cwd before exec, so $PWD here
# is already the terminal's working directory.
set -euo pipefail

root="/home/josh/projects"
case "$PWD" in
  "$root"/*)
    rel=${PWD#"$root"/}
    name=${rel%%/*}
    ;;
  *)
    echo "shell shim: PWD ($PWD) is not under $root" >&2
    exec /bin/bash "$@"
    ;;
esac

exec podman exec -it -w "$PWD" "project-$name" zsh
