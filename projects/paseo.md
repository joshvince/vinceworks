# Paseo on vince-archive: investigation notes

Status: **investigation only, stopped pending a decision.** Nothing here is wired into `Dockerfile`, `entrypoint.sh`, or `projects-host`. See "State currently on the host" at the bottom for exactly what's live on `vince-archive` right now and how to remove it.

Parked TODO item this replaces: "Paseo on the box" in `../TODO.md`.

## Goal

Run one Paseo daemon for the whole box, reachable as a single "host" from the Paseo Desktop app on the Macbook over the LAN, with agent sessions actually executing inside the relevant `project-<name>` container — its toolchain, its Postgres, its git agent socket — not on the bare host.

## Why one daemon, not one per container

Considered and rejected: running a Paseo daemon *inside* each project container (one "host" per project in the Desktop app). That would colocate the daemon with the toolchain for free, but Paseo's SSH transport (`paseo --host ssh://user@host`) turned out to need a real sshd at the far end — confirmed from the app's own bundled source, it does `ssh -W 127.0.0.1:PORT host`, which asks the *remote sshd* to open the loopback connection. Project containers have no sshd (deliberately — see the main `projects/README.md`), and a `ProxyCommand` into `podman exec` doesn't help, since that gives the SSH client nothing that speaks the SSH protocol. It also would have meant one published port and one host entry per project, forever.

(Side finding, unrelated to Paseo: the parked "Zed remote dev" idea in `../TODO.md` has this identical flaw. Zed also speaks real SSH protocol to the far end, so it would need `sshd -i` inside the container, not just a `ProxyCommand`.)

Chosen instead: one daemon, on the bare host, reachable through the box's own already-existing sshd at the default port. The cost is that the daemon has no project toolchain of its own — solved with a shim, not a container.

## Architecture

```
                                    MACBOOK (LAN)
  ┌─────────────────────────────────────────────────────────┐
  │  Paseo Desktop app                                        │
  │  Add host → Remote SSH → ssh://josh@vince-archive         │
  └───────────────────────────┬───────────────────────────────┘
                               │ existing OpenSSH client,
                               │ existing SSH access
                               ▼
                    VINCE-ARCHIVE (Ubuntu box, host OS)
  ┌───────────────────────────────────────────────────────────┐
  │  sshd  →  tunnels to 127.0.0.1:6767                        │
  │                                                             │
  │  Paseo daemon (host process, runs as josh)                 │
  │    PATH = ~/.paseo-poc/bin:...                              │
  │    workspace cwd = /home/josh/projects/vincetagram          │
  │    execs "claude" found on PATH  ───────────┐              │
  │    $SHELL (for terminals) = .../bin/shell    │              │
  │                                              │              │
  │  paseo-claude-shim.sh / paseo-shell-shim.sh │              │
  │    resolve project from $PWD, then:          │              │
  │    podman exec -w "$PWD" project-<name> \    │              │
  │      mise exec -- claude "$@"  ◄─────────────┘              │
  └───────────────────────────┬───────────────────────────────┘
                               │ podman exec
                               ▼
              ┌───────────────────────────────────────┐
              │ podman container: project-vincetagram  │
              │  - real `claude` binary, logged in      │
              │  - mise-installed Ruby/Node/gems        │
              │  - Postgres (unix socket)                │
              │  - git ssh-agent socket                  │
              │  - gh CLI, logged in (projects-gh vol.)  │
              │  - repo bind-mounted at the same path    │
              │    it has on the host                    │
              └───────────────────────────────────────┘
```

The daemon itself is thin: its whole job is picking which `project-<name>` container to route into based on the workspace path, then getting out of the way.

## The shims

Two scripts, both in `host/` next to this file:

- `host/paseo-claude-shim.sh` — stands in for `claude` on the daemon's `PATH`. Paseo spawns the provider CLI as a child process and talks to it over stdio, resolved via PATH — confirmed empirically (daemon's own `provider` status only reports `Claude available` once this shim is ahead of anything else on `PATH`). The shim resolves which project a workspace path belongs to from `$PWD`, then runs `podman exec -i -w "$PWD" project-<name> mise exec -- claude "$@"`. The `mise exec --` matters: a bare `podman exec ... claude` skips the project's toolchain entirely, because mise activation normally happens once in the login shell tmux starts, and this exec bypasses that shell — confirmed by a first attempt reporting `bundle: command not found` until the fix.
- `host/paseo-shell-shim.sh` — same resolution, for Paseo's separate "workspace terminal" feature. That feature spawns the daemon's `$SHELL` directly via `node-pty`, with no PATH/provider resolution involved (confirmed via `ps` on the host mid-session: it was launching a real `/bin/bash`, not going through the claude shim at all). Setting the daemon's `SHELL` environment variable to this script redirects it the same way.

Once `claude` (or the terminal's shell) starts inside the container via `podman exec`, everything it forks after that — every Bash tool call, `bundle exec rspec`, `rails db:migrate`, git commands — is a child of that already-inside-the-container process and inherits the container for free. Only the top-level entry point needs shimming.

The real `claude` binary is never installed on the host. Auth already lives in the `projects-claude` volume, reused as-is.

## What's proven end-to-end

- The daemon starts on `127.0.0.1:6767` with no password required (loopback bind, `--no-relay`).
- An agent run through the CLI (`paseo run ... --provider claude`) really executes inside the container: `hostname` returned `vincetagram` (the container's hostname, not the host's `vince-family-archive`), `pwd` matched, and — once the `mise exec --` fix was in place — `bundle -v` / `ruby -v` returned the container's actual toolchain (Ruby 3.1.2), not "not found."
- The same is true from the Paseo Desktop app on the Mac, connected over `ssh://josh@vince-archive` — both an agent run and an interactive terminal correctly land inside `project-vincetagram`.
- `gh` CLI is now authenticated inside the containers (`gh auth login --with-token`, done once in `project-vincetagram`). Because `projects-gh` is one volume shared across every project container (unlike the per-project `-pg` Postgres volume), this is a one-time, all-projects action, not per-project. This part is **real and intentionally kept**, independent of whether the rest of this Paseo work continues.

## Worktree isolation: investigated, not built, and it surfaces a real problem

Paseo's `worktree` isolation mode (as opposed to `local`, which is what everything above uses) creates a managed git worktree per workspace, intended to let multiple agents work on different branches of the same repo concurrently. Tried this from the Desktop app, and it broke immediately and correctly: the shim refused because the worktree was created at `~/.paseo-poc/home/worktrees/22cq0tpn/gracious-baboon`, outside `/home/josh/projects`, invisible to the container.

Investigated further, empirically, without building anything:

- The per-project parent segment (`22cq0tpn` above) is **stable** — two separate worktrees created for the same project land under the same parent. One bind mount per project, done once, would cover every future worktree for that project.
- That segment is **not controllable** — `--worktree-slug` only sets the leaf directory name, not the parent. It's assigned internally per project and isn't recorded in Paseo's own `projects.json`; the only way to learn it is to create one worktree and read back its path.
- The `.git` back-reference resolves correctly on both sides of any future mount for free: a worktree's `.git` file points at `/home/josh/projects/vincetagram/.git/worktrees/<name>` — the main repo's real, already-correct path — so there's no path-translation problem to solve there.
- Archiving a workspace cleanly removes only its own worktree leaf and prunes `git worktree list`; it doesn't touch the shared parent, so mounting that parent long-term is safe against individual workspace cleanup.

So the mechanical part (making the container able to *see* a worktree) is well-understood and would work: discover each project's slug once, persist it, add a second bind mount to `projects-host`'s `cmd_start`, extend both shims to also resolve `<PASEO_HOME>/worktrees/<slug>/...` paths.

**The problem worth stopping on:** a worktree only gives an agent its own working directory and branch. It does **not** give it its own container. Every worktree for a project still shares that project's single container — the same Postgres instance, the same mise-installed gems, the same running processes. Two worktree-based agents on different branches, both migrating the dev database or needing different gem versions at the same time, will collide. The entire point of worktree isolation — letting agents run genuinely in parallel — is undermined by the fact that "parallel" agents on the same project would still be fighting over one shared runtime underneath. This isn't a bug to fix in the shim; it's a mismatch between what worktree mode is *for* and what this box's one-container-per-project model can actually offer it. Worth deciding deliberately (e.g. is "worktrees on the same container" only useful for non-concurrent, non-DB-touching work, in which case it's fine — or does real support require something heavier, like a second Postgres/mise state per worktree, which starts to look like a container per worktree, not per project) before building the mechanical part above.

## Decisions needed before doing anything more

- Should `PASEO_HOME` move somewhere permanent? It's currently the throwaway `~/.paseo-poc/home`; if worktree support is ever built, a container's bind mount would hardcode a path under it, so it would need to be a real, stable location first.
- Is worktree support worth building at all, given the shared-container problem above, or should this stay `local`-isolation only?
- Should the daemon become a real `systemd --user` unit (survives reboot, matches how the Podman containers already rely on `loginctl enable-linger`), or stay ad hoc until worktree support is decided?

## State currently on the host (`vince-archive`) — not committed, needs cleanup if this is abandoned

Everything below is real, live state on the box right now. None of it is referenced by any committed file except this one.

- **`~/.local/bin/mise` and `~/.local/share/mise`** — a host-level `mise` install (separate from the one already baked into every project container's image). Installed Node 22 via `mise use -g node@22`, which wrote `[tools] node = "22"` into `~/.config/mise/config.toml`. Remove with `mise uninstall node@22` and delete both paths to fully remove `mise` from the host.
- **`~/.paseo-poc/`** (767 MB) — everything else: the `@getpaseo/cli` npm install (under the host mise's node), the daemon's `PASEO_HOME` (`~/.paseo-poc/home`, including its own project/workspace registry, logs, and a failed local-speech-model download attempt that doesn't affect anything), and both deployed shim scripts (`~/.paseo-poc/bin/claude`, `~/.paseo-poc/bin/shell`). Remove entirely with `rm -rf ~/.paseo-poc` after stopping the daemon.
- **The daemon process itself is currently running** (PID 47812 at last check, backgrounded via `paseo daemon start`, not a systemd unit — dies on reboot, but is live right now and reachable at `127.0.0.1:6767`). Stop it with `PASEO_HOME=~/.paseo-poc/home paseo daemon stop` (needs the host mise's node on `PATH`) before removing `~/.paseo-poc`.
- **Two test worktrees created during investigation were already archived and cleaned up** — `git worktree list` on `/home/josh/projects/vincetagram` shows only the main worktree. The now-empty per-project directory (`~/.paseo-poc/home/worktrees/22cq0tpn`) goes away with the `rm -rf` above.
- **Not part of the teardown, intentionally kept:** `gh` authentication inside the containers (shared `projects-gh` volume). This is independent of whether Paseo continues and is useful regardless.
