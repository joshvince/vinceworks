# Agent SSH access to production boxes

Plan for giving agents their own, scoped SSH access to production servers on a per-project basis, so an agent can read/copy files from a live box without me handing over my own credentials or shell access.

## Goal

An agent working on a project should be able to pull files (config, logs, data) from that project's production box, read-only, without ever being able to write, delete, or get a shell. Access must be revocable per project without affecting other projects, and some of these projects are commercial or private, so nothing here should default to "on."

## Decisions

- **Enforcement**: read-only is enforced at the SSH layer, not just via OS file permissions. Each key's `authorized_keys` entry uses a forced command wrapping `rrsync` in read-only mode, scoped to that project's own directory (`rrsync -ro /srv/<project>`), plus `restrict` (covers `no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding` in one option). Even if the bot user's file permissions are ever misconfigured to allow writes, the key itself cannot execute anything but a read-only rsync pull.
- **Key granularity**: one ed25519 keypair per project+host pair. No shared bot key across projects. This gives per-project revocation without touching other projects' access.
- **Bot user provisioning**: a second, low-privilege OS user (e.g. `vinceworks-bot`) is created on the box manually, outside of vinceworks tooling. The CLI prints a copy-paste provisioning script (create user, lock down sshd `Match` block) but never runs it remotely itself — it doesn't need root on the box. The script must state the exact grants (group/ACLs) and explicitly exclude secrets (`.env`, credentials files) from what the bot user can read — "read-only against the box" only means "read-only against production" if secrets are excluded, since a leaked credential plus sandbox network reach is effectively write access.
- **Path scope**: each key's `rrsync` is scoped to that one project's directory, not the whole filesystem — see enforcement above. Revised from an earlier whole-filesystem-read decision after review flagged that whole-filesystem read-only still exposes other projects' secrets on shared boxes.
- **Local key co-location**: all a project's keys live in the same sandbox container, so an agent on project A could in principle read project B's on-disk key too. Considered and accepted as moot: projects sharing a box are similar enough in trust level that this isn't a meaningful additional exposure. Not building per-session key isolation for this reason.
- **Key storage**: private keys are persisted on disk, one file per project+host, `chmod 600`, only where the agent actually runs (the sandbox, not my laptop). No 1Password involvement in the live/runtime path, and no standing token anywhere — a 1Password service-account token would unlock the whole vault, which is a far bigger blast radius than one key that can only do a read-only rsync pull on one project directory. This matters because agents need to work unattended; a design that requires me to unlock something first defeats that. 1Password is optional and out-of-band: I can stash a manual backup copy of a key there myself for disaster recovery, but nothing in the system reads from or writes to it automatically.
- **Admin key stays on the Mac**: `keygen` runs in the sandbox (the bot private key never leaves it), but `install`/`revoke` run from my Mac using my own admin key — that key must never touch the sandbox, or a sandbox compromise gets both the scoped bot key and my real credentials.
- **Default-deny**: no project gets a key unless explicitly opted in.
- **Host key pinning**: `install` writes the box's host key to `known_hosts` at setup time. An unattended agent can't handle a first-connection host key prompt — it'll either hang or blindly accept, and blind-accept defeats the point of pinning anything.
- **Per-project SSH config**: an entry per project+host in `~/.ssh/config` in the sandbox (`IdentityFile`, `IdentitiesOnly yes`) so the agent doesn't need to know key paths.
- **Audit**: bot user's sshd `Match` block sets `LogLevel VERBOSE`, logging the key fingerprint per connection. Cheap, and the only real audit trail for unattended access. `authorized_keys` lines get a comment tag (`vinceworks:<project>:<host>`) so revoke is a grep, not a guess.

## CLI commands

- `vinceworks ssh keygen <project> <host>` — generates the ed25519 keypair, writes the private half to disk in the sandbox (`chmod 600`), and prints:
  - the public key plus the forced-command, tagged `authorized_keys` line, scoped to the project's directory
  - a provisioning script for the bot user + sshd hardening (grants, secrets exclusion, `LogLevel VERBOSE`), for me to run manually as root on the box
- `vinceworks ssh install <project> <host>` — run from the Mac, never the sandbox. SSHes in with my own admin key, appends the forced-command line to the bot user's `authorized_keys`, and pins the box's host key into the sandbox's `known_hosts`.
- `vinceworks ssh revoke <project> <host>` — run from the Mac. Strips the tagged `authorized_keys` line and deletes the key file from the sandbox.

`install` and `revoke` are thin wrappers around one-line SSH commands — not worth building as CLI commands until doing them by hand actually gets painful. Ship `keygen` plus the provisioning script first, run it against one test box by hand, then decide.

## Non-goals / out of scope for now

- Remote user/box provisioning by the CLI (stays manual, run as root by me).
- Write or push access of any kind — this is read-only, full stop.
- Isolating one project's key from another's on the same sandbox container (see local key co-location, accepted as moot).
- `install`/`revoke` as CLI commands, until running them by hand becomes painful.

## Rollout order

1. `vinceworks ssh keygen` + on-disk key storage in the sandbox
2. Provisioning script output (grants, secrets exclusion, host key, audit logging) + manual bot-user setup on one test box
3. Install/revoke by hand as plain SSH commands
4. Wire key loading into the agent session flow (load into ssh-agent at session start, no manual unlock step)
5. Build `vinceworks ssh install` / `revoke` only if the manual version starts to hurt
