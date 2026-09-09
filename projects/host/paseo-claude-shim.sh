#!/usr/bin/env bash
# Stands in for `claude` on the host-level Paseo daemon's PATH (see
# ../../paseo-host-plan.md). Resolves which project container a workspace
# path belongs to and execs the real `claude` inside it, so the agent runs
# with that project's toolchain instead of the bare host's.
set -euo pipefail

root="/home/josh/projects"
case "$PWD" in
  "$root"/*)
    rel=${PWD#"$root"/}
    name=${rel%%/*}
    ;;
  *)
    echo "claude shim: PWD ($PWD) is not under $root" >&2
    exit 1
    ;;
esac


# `mise exec --` activates the project's pinned toolchain (Ruby/Node/etc)
# non-interactively. A plain `claude` exec would skip that: mise activation
# normally happens once, in the login shell tmux starts, and inherits from
# there — but this exec bypasses that shell entirely.
exec podman exec -i -w "$PWD" "project-$name" mise exec -- claude "$@"
