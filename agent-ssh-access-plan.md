# Agent SSH access to production boxes

Plan for giving agents their own, scoped SSH access to production servers on a per-project basis, so an agent can read/copy files from a live box without me handing over my own credentials or shell access.

## Goal

An agent working on a project should be able to pull files (config, logs, data) from that project's production box, read-only, without ever being able to write, delete, or get a shell. Access must be revocable per project without affecting other projects, and some of these projects are commercial or private, so nothing here should default to "on."

## Decisions

- **Enforcement**: read-only is enforced at the SSH layer, not just via OS file permissions. Each key's `authorized_keys` entry uses a forced command wrapping `rrsync` in read-only mode, with `no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding`. Even if the bot user's file permissions are ever misconfigured to allow writes, the key itself cannot execute anything but a read-only rsync pull.
- **Key granularity**: one ed25519 keypair per project+host pair. No shared bot key across projects. This gives per-project revocation without touching other projects' access.
- **Bot user provisioning**: a second, low-privilege OS user (e.g. `vinceworks-bot`) is created on the box manually, outside of vinceworks tooling. The CLI prints a copy-paste provisioning script (create user, lock down sshd `Match` block) but never runs it remotely itself — it doesn't need root on the box.
- **Path scope**: keys get whole-filesystem read access (as readable by the bot user), not locked to a single project directory. Note: on a box that hosts multiple projects, this means a leaked key for project A can also read project B's files on that box. Accepted tradeoff — isolation is only as strong as "one box = one project" in that case.
- **Key storage**: private keys are persisted on disk, one file per project+host, `chmod 600`, only where the agent actually runs (the sandbox, not my laptop). No 1Password involvement in the live/runtime path, and no standing token anywhere — a 1Password service-account token would unlock the whole vault, which is a far bigger blast radius than one key that can only do a read-only rsync pull on one box. This matters because agents need to work unattended; a design that requires me to unlock something first defeats that. 1Password is optional and out-of-band: I can stash a manual backup copy of a key there myself for disaster recovery, but nothing in the system reads from or writes to it automatically.
- **Default-deny**: no project gets a key unless explicitly opted in.

## CLI commands

- `vinceworks ssh keygen <project> <host>` — generates the ed25519 keypair, writes the private half to disk in the sandbox (`chmod 600`), and prints:
  - the public key plus the forced-command `authorized_keys` line
  - a provisioning script for the bot user + sshd hardening, for me to run manually as root on the box
- `vinceworks ssh install <project> <host>` — SSHes in with my own admin key and appends the forced-command line to the bot user's `authorized_keys`.
- `vinceworks ssh revoke <project> <host>` — strips the `authorized_keys` line and marks the 1Password item revoked.

## Non-goals / out of scope for now

- Remote user/box provisioning by the CLI (stays manual, run as root by me).
- Write or push access of any kind — this is read-only, full stop.
- Cross-project isolation on shared boxes (see path scope tradeoff above).

## Rollout order

1. `vinceworks ssh keygen` + on-disk key storage in the sandbox
2. Provisioning script output + manual bot-user setup on one test box
3. `vinceworks ssh install`
4. `vinceworks ssh revoke`
5. Wire key loading into the agent session flow (load into ssh-agent at session start, no manual unlock step)
