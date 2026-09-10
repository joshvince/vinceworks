# Agent SSH access to production boxes

Plan for giving agents their own, scoped SSH access to production servers on a per-project basis, so an agent can read/copy files from a live box without me handing over my own credentials or shell access.

## Goal

An agent working on a project should be able to pull files (config, logs, data) from that project's production box, read-only, without ever being able to write, delete, or get a shell. Access must be revocable per project without affecting other projects, and some of these projects are commercial or private, so nothing here should default to "on."

## Decisions

- **Enforcement**: read-only is enforced at the SSH layer, not just via OS file permissions. Each key's `authorized_keys` entry uses a forced command wrapping `rrsync` in read-only mode, with `no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding`. Even if the bot user's file permissions are ever misconfigured to allow writes, the key itself cannot execute anything but a read-only rsync pull.
- **Key granularity**: one ed25519 keypair per project+host pair. No shared bot key across projects. This gives per-project revocation without touching other projects' access.
- **Bot user provisioning**: a second, low-privilege OS user (e.g. `vinceworks-bot`) is created on the box manually, outside of vinceworks tooling. The CLI prints a copy-paste provisioning script (create user, lock down sshd `Match` block) but never runs it remotely itself — it doesn't need root on the box.
- **Path scope**: keys get whole-filesystem read access (as readable by the bot user), not locked to a single project directory. Note: on a box that hosts multiple projects, this means a leaked key for project A can also read project B's files on that box. Accepted tradeoff — isolation is only as strong as "one box = one project" in that case.
- **Key storage**: private keys live in 1Password, one item per project+host. Local SSH auth still goes through the built-in ssh-agent (not the 1Password SSH agent integration), consistent with existing setup for other private-project SSH access. Keys are pulled into the local agent transiently for a task and never persisted to disk long-term.
- **Default-deny**: no project gets a key unless explicitly opted in.

## CLI commands

- `vinceworks ssh keygen <project> <host>` — generates the ed25519 keypair, pushes the private half to a 1Password item, and prints:
  - the public key plus the forced-command `authorized_keys` line
  - a provisioning script for the bot user + sshd hardening, for me to run manually as root on the box
- `vinceworks ssh install <project> <host>` — SSHes in with my own admin key and appends the forced-command line to the bot user's `authorized_keys`.
- `vinceworks ssh revoke <project> <host>` — strips the `authorized_keys` line and marks the 1Password item revoked.

## Non-goals / out of scope for now

- Remote user/box provisioning by the CLI (stays manual, run as root by me).
- Write or push access of any kind — this is read-only, full stop.
- Cross-project isolation on shared boxes (see path scope tradeoff above).

## Rollout order

1. `vinceworks ssh keygen` + 1Password storage
2. Provisioning script output + manual bot-user setup on one test box
3. `vinceworks ssh install`
4. `vinceworks ssh revoke`
5. Wire runtime key retrieval into the agent session flow (transient ssh-agent load per task)
