# Handoff: the sandbox branch

Branch `sandbox-single-container`, PR #9, open, 14 commits ahead of `main`. Delete this file and `sandbox-plan.md` when the PR merges.

## What this branch does

Replaces the per-project container model that used to live in `projects/` with one long-lived rootless Podman container, `vinceworks-sandbox`, on the home Ubuntu box `vince-archive` (192.168.1.200). Agents work in it with high autonomy. Josh reviews and deploys from his Mac.

The design and the reasoning behind every decision are in `sandbox-plan.md`. Read that before changing anything structural. The user-facing documentation is `sandbox/README.md` and it is current.

The one boundary that matters: production (`postcard` web and Postgres under Docker, nginx, Filebrowser) shares the box. The sandbox has its own network namespace, no host network, no Docker socket. Verified unreachable from inside.

## State on the box, as of 2026-09-09

Live and working. The old per-project container, its volumes, `~/projects`, `~/.projects` and the Paseo proof of concept from PR #8 are all deleted. Production was never touched.

- Container up under a Quadlet unit at `~/.config/containers/systemd/vinceworks-sandbox.container`, `Restart=always`.
- Persistent home bind-mounted from `/home/josh/vinceworks-sandbox` to `/home/josh`.
- `~/vinceworks` on the box is checked out on this branch. Switch it back to `main` after the merge.
- Repos cloned: `~/projects/vincetagram`, `~/projects/sterling_vault`, both with `.env` and `config/master.key` pushed in. Note that Josh's local `sterling_vault/.env` is empty, so the copy in the sandbox is too.
- `gh` logged in with a fine-grained PAT (joshvince repos only, Contents and Pull requests read/write). `claude` logged in. Paseo `config.json` copied from the Mac.
- Paseo Desktop on the Mac connects as `ssh://josh@vince-archive:2222`. A PR has been opened from the sandbox successfully.

Mac side: `~/.ssh/config` has a `vinceworks-sandbox` host on port 2222 using the same key as `vince-archive`.

## Verified

Container starts and rebuilds without losing logins, repos, worktrees or the sshd host key. SSH from the Mac works. Production Postgres and the Docker socket are unreachable from inside. Killing the Paseo daemon restarts the container exactly once. A listener on a port in 4100 to 4199 inside a worktree is reachable from the Mac.

Not verified: a host reboot. Nobody has rebooted the box since the unit was installed.

## The immediate next task

Josh's last instruction, not started: write a script in the sandbox that prepares a new worktree, and have Paseo's `worktree.setup` hook call it.

The point is that the logic lives in vinceworks, not in each repo's `paseo.json`, so that when Paseo is replaced by pi or anything else, only the one-line adapter changes. Josh explicitly rejected triggering it from a global git `post-checkout` hook. It is called by the tool, not by git.

Proposed shape, agreed in conversation:

- New file `sandbox/checkout-setup`, runnable inside the sandbox as `~/vinceworks/sandbox/checkout-setup`. Paseo exports `PASEO_SOURCE_CHECKOUT_PATH`, `PASEO_WORKTREE_PATH` and `PASEO_BRANCH_NAME` to setup commands, so the script should take the source checkout and the worktree as arguments rather than reading Paseo's variables directly.
- It copies the untracked secret files from the source checkout into the worktree: `.env`, `config/master.key`, `config/credentials/*.key`. Never overwrite what is already there.
- It picks a free TCP port in 4100 to 4199 and appends `PORT=<port>` to the worktree's `.env`. Free means not in `ss -ltn` and not already claimed by a `PORT=` line in another worktree's `.env`.
- Each repo's `paseo.json` then reduces to the port range plus one setup line calling the script.

Why the port matters: only 4100 to 4199 is published to the LAN, because production owns 3000 on the host. `vinceworks sandbox ps` marks anything else as `unpublished`.

Blocker for Rails repos: `Procfile.dev` in vincetagram hardcodes `web: bin/rails server -p 3000`, so `PORT` is ignored. It needs to become `${PORT:-3000}`. That is a change in vincetagram, in its own PR, not in vinceworks.

## Known issues, in `TODO.md`

**Agents cannot run `rspec` or `bundle`.** Confirmed: a non-interactive shell has no toolchain, because `mise activate` runs from `.zshrc`, which only interactive shells read. `mise exec -- rspec` works, but no agent thinks to type that. The fix is one line: mise writes shims to `~/.local/share/mise/shims` and they resolve the project toolchain correctly from any directory, so adding that directory to `PATH` in `sandbox/zshenv` should fix it for agents, ssh commands and tmux alike. Worth testing that shims do not shadow anything unexpected before committing.

The rest of `TODO.md` is parked: pi as the harness, Tailscale, a resolvable hostname.

## Things learned the hard way

Do not install anything on Josh's Mac. Syntax-check bash 5 scripts by running `bash -n` inside the sandbox over ssh instead.

`/home/josh` inside the container is a bind mount, so anything the image installs into the home directory at build time is invisible at runtime. Claude Code is therefore installed natively into the persistent home by `ai.sh` on first start; OpenCode and the Paseo CLI are npm globals on a system path.

sshd starts sessions with a clean environment, so the entrypoint writes the image and unit environment into `~/.zshenv`. Anything new that the container needs in every shell goes there, not in the Dockerfile's `ENV`.

`~/vinceworks` inside the sandbox is the read-only mount of the box's own checkout. Paseo cannot create worktrees in it. To work on vinceworks itself from inside the sandbox, clone it to `~/projects/vinceworks` with `vinceworks sandbox push`.

Two bugs already found and fixed this way: a custom sshd config declares no sftp subsystem, so `scp` fails until one is added; and Paseo's pid file survives in the persistent home, so a restart loops until the entrypoint deletes it.

## Command map

On the Mac, all through the top-level `vinceworks` script:

```
vinceworks sandbox up                     start it, building first if needed
vinceworks sandbox rebuild                rebuild the image and restart
vinceworks sandbox status                 systemd status
vinceworks sandbox ps                     checkouts, their listeners and ports
vinceworks sandbox push <url|name> [paths...]   clone a repo in and copy its secrets
vinceworks tmux                           attach the "main" tmux session inside
```

`sandbox/host/sandbox-host` is the host-side half, reached over ssh to `vince-archive`. `sandbox/ps` runs inside the container.

A rebuild restarts the container and drops live Paseo sessions, so run it between sessions. The entrypoint changes on this branch that are not yet in the running container are the toolchain install pass and the environment export; both are already applied by hand to the running container.
