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

`sandbox/alloc-port` and `sandbox/checkout-setup` were exercised inside the sandbox on 2026-09-10: fresh worktree setup, idempotent re-run, replacement of an out-of-range `PORT=3000`, replacement of an in-range port already claimed by another checkout, skipping a port with a live listener, and five concurrent allocations yielding five distinct ports. Proven for real on a vincetagram worktree the same day, reachable from the Mac on its allocated port.

Also settled on 2026-09-10: foreman's `.env` beats the environment it inherits, so `bin/dev` exporting `PORT="${PORT:-3000}"` before handing off does not defeat an allocated port. A `Procfile.dev` only needs changing when it pins the port itself, as vincetagram's did.

Not verified: a host reboot. Nobody has rebooted the box since the unit was installed.

## Port allocation

`sandbox/alloc-port <dir>` writes a `PORT` in 4100-4199 into a directory's `.env`, treating every `.env` under `~/projects` and `~/.paseo/worktrees` as the allocation registry rather than keeping separate state. It takes an exclusive `flock` so concurrent worktree creation cannot collide, and it is idempotent: an in-range `PORT` is left alone, while an out-of-range or already-claimed one is replaced and the replacement logged to stderr.

`sandbox/checkout-setup <worktree> [source-checkout]` is the entry point a worktree tool calls. It copies `.env`, `config/master.key` and `config/credentials/*.key` from the main checkout without overwriting anything, then calls `alloc-port`. It derives the source checkout from git when not given one, and reads no `PASEO_*` variables, so it is not Paseo-specific. `sandbox/README.md` documents the resulting `paseo.json`, down to a one-line `worktree.setup` adapter.

## The immediate next task

Land the branches that are still out. vincetagram's `paseo.json`, its `Procfile.dev` fix and its development `.env` sit on the `romantic-leopard` worktree, unmerged. sterling_vault has not been converted at all. Once both are on `main` and the box has pulled them, PR #9 can merge and this file and `sandbox-plan.md` can go.

Fixed on 2026-09-10, so it is no longer a blocker: agents could not run `rspec` or `bundle`, because `mise activate` runs from `.zshrc` and non-interactive shells never read it. `sandbox/zshenv` now appends `~/.local/share/mise/shims` to `PATH`. The shims resolve the project's own toolchain from any directory, verified over a plain ssh command in vincetagram, in one of its worktrees and in sterling_vault, which pin different Ruby versions. Appended rather than prepended, so nothing on `PATH` can ever be shadowed; none of the 42 shims collides with an existing command today, and the system `node` that the Paseo CLI and OpenCode depend on stays authoritative. Interactive shells are unaffected, still resolving through `mise activate`. The change is applied by hand to the running container as well as committed, so it survives until the next rebuild either way.

## Repo state, as of 2026-09-10

vincetagram works end to end. Its `paseo.json`, its `Procfile.dev` fix to `-p ${PORT:-3000}` and a development-only `.env` all live on the `romantic-leopard` worktree and are not merged to `main` yet, so `~/projects/vincetagram` still holds the old `Procfile.dev` and no `paseo.json` until that lands.

The `.env` originally pushed into vincetagram was the production file, complete with the production database password, the Kamal registry password and the Rails master key, against the rule in `sandbox/README.md`. The sandbox copy is now development-only. The Mac copy is still production, which is correct, since Kamal deploys from there. `sandbox push` will not re-copy it, because it refuses a checkout that already exists.

sterling_vault is converted and on `main`: `paseo.json` calls `checkout-setup` and the old `script/paseo-worktree-setup.sh` is deleted. Its `Procfile.dev` needs no change, because it never pinned a port. Its `.env` in the source checkout is empty, which is harmless — `checkout-setup` copies the empty file and `alloc-port` writes `PORT` into the worktree's copy.

## Parked

`TODO.md` holds pi as the harness, opencode-go as its model provider, Tailscale and a resolvable hostname for the box. Tailscale probably subsumes the hostname.

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
