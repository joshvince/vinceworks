# sandbox: one remote dev environment for every project

`sandbox` is one rootless Podman container, `vinceworks-sandbox`, running on the home Ubuntu box (`vince-archive`). It holds every personal project checkout, a Postgres server, tmux and Claude Code, and it behaves like a second laptop: agents run inside it with very high autonomy, using Paseo worktrees for parallel sessions, opening PRs that get reviewed and deployed from the Mac.

One container rather than one per project. The per-project model in the old `projects/` directory turned out to be the source of nearly all the complexity: a port mapper, a per-project secrets directory, a per-project Postgres volume, stale ssh-agent socket detection, and shims to route a host-level Paseo daemon into the right container. It also meant one project's container could not see another project's checkout, which made intertwined projects awkward. The goal was never per-project isolation, so a single stable machine with a fraction of the moving parts serves it better.

The container boundary is kept for one reason: production (`postcard` and its Postgres on host loopback 5432, nginx, Filebrowser) shares the box. The sandbox has its own network namespace, no host network, no Docker socket and no volumes shared with production, so agents running inside it cannot reach production.

## How it fits together

- **One rebuildable image.** Ubuntu 24.04 plus build tools, `mise`, a Postgres server, Node 22, and OpenCode and the Paseo CLI as npm globals on a system path (because the bind-mounted home would hide anything a curl installer wrote there at build time). Claude Code is installed by `ai.sh` with the native installer into the persistent home on first start, so it self-updates with `claude update` and survives rebuilds.
- **A persistent home**, bind-mounted from `/home/josh/vinceworks-sandbox` on the host to `/home/josh` in the container, with the container user taking uid 1000 via `--userns=keep-id`. Everything that should survive a rebuild (repos, gems, mise installs, sshd keys, Paseo state) lives there.
- **A Quadlet unit** at `~/.config/containers/systemd/vinceworks-sandbox.container` with `Restart=always`, so the container comes back after `systemctl --user start` and after a host reboot. Linger is enabled for `josh` so the user manager stays up with no session attached.
- **Unprivileged sshd on host port 2222**, running as `josh` inside the container. Host keys and `authorized_keys` live in the persistent home, not the image.
- **The Paseo daemon** listens on `127.0.0.1:6767` inside the container and is reached only through the sshd tunnel: Paseo's SSH transport runs `ssh -W 127.0.0.1:6767` against port 2222, it never starts or installs anything remotely. The entrypoint execs the daemon in the foreground as the container's main process, so killing it restarts the whole container.
- **Postgres** runs inside the container as a system service, with data in the named volume `vinceworks-sandbox-pg`. Worktrees of one repo share one dev database, the same as on the laptop.
- **Ports**: 2222 for sshd, and 4100 to 4199 published for dev servers. Each repo's `paseo.json` sets `worktree.servicePorts.range` to `4100-4199`, and apps bind the `PASEO_WORKTREE_PORT` environment variable Paseo exports into the worktree.
- **Git works through `gh`.** There is no SSH key. A fine-grained GitHub PAT is logged in once with `gh auth login --with-token`, then `gh auth setup-git` points git's credential helper at it.
- **Caps**: 3 CPUs, 10 GB of memory, set in the Quadlet unit's `PodmanArgs`.

## Commands

All run on the Mac.

```sh
vinceworks sandbox up                     # start the sandbox, building it first if needed
vinceworks sandbox rebuild                # rebuild the image and restart the sandbox
vinceworks sandbox status                 # show systemd status for the sandbox
vinceworks sandbox push <repo> <paths...> # copy files from ~/projects/<repo> on the Mac into the sandbox
vinceworks tmux                           # ssh in and attach the "main" tmux session
```

To clone a new repo, run this inside the sandbox, over `vinceworks tmux` or a Paseo session:

```sh
gh repo clone owner/repo ~/projects/repo
```

## Paseo

Add the sandbox as a host in Paseo Desktop on the Mac:

```
ssh://josh@vince-archive:2222
```

Worktrees live under `~/.paseo/worktrees` in the sandbox. Each repo that wants worktree support commits its own `paseo.json` at the repo root. For vincetagram:

```json
{
  "worktree": {
    "servicePorts": { "range": "4100-4199" },
    "setup": [
      "cp \"$PASEO_SOURCE_CHECKOUT_PATH/.env\" .env",
      "cp \"$PASEO_SOURCE_CHECKOUT_PATH/config/master.key\" config/master.key"
    ]
  }
}
```

Hooks do plumbing only: copying `.env`, `config/master.key` or SQLite files from the main checkout into the new worktree. No `bundle install` and no application code belongs in a hook.

## Secrets

Files that are not committed to the repo, such as `.env` and `config/master.key`, live untracked in the main checkout on the sandbox, at `~/projects/<repo>/`. Push them from the Mac:

```sh
vinceworks sandbox push vincetagram .env config/master.key
```

A repo's `worktree.setup` hook then copies them out of the main checkout into every new worktree. Never push the production `.env`.

## Host prerequisites (once)

On the box:

1. `id josh` should report uid 1000. The build passes the real uid and gid as build args either way.
2. Rootless Podman needs three things in place: `podman` itself installed; `/etc/subuid` and `/etc/subgid` each containing a range for `josh` (the default `josh:100000:65536` is what is there already and is fine as is); and lingering enabled for `josh` with `sudo loginctl enable-linger josh`. Lingering is not optional. Without it, systemd tears down the user manager the moment the last SSH session for `josh` closes, and that takes the container down with it.
3. `mkdir -p ~/vinceworks-sandbox` and clone vinceworks to `~/vinceworks`.

On the Mac:

4. Add a `vinceworks-sandbox` entry to `~/.ssh/config`, alongside the existing `vince-archive` entry:

   ```
   Host vinceworks-sandbox
       HostName 192.168.1.200
       Port 2222
       User josh
       IdentityFile <same IdentityFile as your vince-archive entry>
   ```

5. The same `ControlMaster auto`, `ControlPath ~/.ssh/cm-%r@%h:%p` and `ControlPersist 10m` lines that speed up `vince-archive` are worth adding under `Host vinceworks-sandbox` too, so repeated calls are instant.

## First boot (once)

1. `vinceworks tmux` to get a shell inside the sandbox.
2. `gh auth login --with-token` with the fine-grained PAT (Contents read/write, Pull requests read/write, Metadata read, personal repos only).
3. `gh auth setup-git` so git uses the token over HTTPS.
4. `claude` to log in to Claude Code.
5. Copy `~/.paseo/config.json` from the Mac into `~/.paseo/` in the sandbox.

## What happens on container start

1. Copy `.gitconfig`, `.gitmessage.txt`, `.gitignore_global`, `sandbox/zshrc` (to `~/.zshrc`), `sandbox/zshenv` (to `~/.zshenv`) and `sandbox/tmux.conf` (to `~/.tmux.conf`) from the read-only vinceworks mount, and unset the macOS git credential helper.
2. Run vinceworks' `ai.sh` so Claude Code has the shared agents and skills.
3. Ensure `~/projects` and `~/.ssh/sshd` exist. Generate an ed25519 sshd host key into `~/.ssh/sshd/` the first time, and seed `~/.ssh/sshd/authorized_keys` from the vinceworks mount the first time.
4. Start Postgres and create a superuser role for `josh` if it does not exist yet.
5. Start sshd on port 2222.
6. Run `gh auth setup-git` if `gh auth status` succeeds, so a rebuilt image picks the credential helper back up.
7. `exec paseo daemon start --foreground --listen 127.0.0.1:6767 --home ~/.paseo`, in the foreground as the container's main process.

## Files

```
vinceworks                  top-level CLI: sandbox, tmux, update, ai, dev-machine-setup
sandbox/
  README.md                 this file
  sandbox                   Mac-side CLI: up, rebuild, status, push
  Dockerfile                the image
  entrypoint.sh              runs on every container start
  sandbox.container          Quadlet unit, installed to ~/.config/containers/systemd/ on the box
  sshd_config                 unprivileged sshd config, copied into the image
  authorized_keys             seeds ~/.ssh/sshd/authorized_keys the first time the sandbox starts
  host/sandbox-host           host-side script: build, install-unit, up, rebuild, status
  tmux.conf                   copied to ~/.tmux.conf on every start
  zshrc                       copied to ~/.zshrc on every start
  zshenv                      copied to ~/.zshenv on every start
```

Host state outside git:

```
/home/josh/vinceworks-sandbox/            the container's home
/home/josh/vinceworks-sandbox/projects/   repos
/home/josh/vinceworks-sandbox/.paseo/     daemon state, worktrees
/home/josh/vinceworks-sandbox/.ssh/sshd/  sshd host keys and authorized_keys
/home/josh/.config/containers/systemd/vinceworks-sandbox.container
podman volume vinceworks-sandbox-pg
```

## tmux in five minutes

The prefix is Ctrl+a, written `C-a` below.

- A **window** is a tab. `C-a c` creates one, `C-a 1` to `C-a 9` jump, `C-a ,` renames, `C-a &` kills.
- A **pane** is a split inside a window. `C-a |` splits right, `C-a -` splits below, `C-a` plus an arrow key moves, `C-a x` kills.
- A **session** is a whole workspace. `main` is created for you by `vinceworks tmux`. Inside tmux, `C-a s` lists sessions to switch between; create another by hand with `tmux new -s foo`.
- `C-a d` detaches. Nothing stops.

```
C-a d        detach, everything keeps running     vinceworks tmux                  reattach
C-a c        new window                            C-a 1..9                         jump to window
C-a n / p    next / previous window                C-a ,                            rename window
C-a |  C-a - split right / split below             C-a arrows                       move between panes
C-a x        kill pane                             C-a &                            kill window
C-a s        pick a session                        tmux new -s foo                  new session foo, run inside the sandbox
C-a [        scroll mode, q to quit                mouse                            click, scroll, resize
C-a r        reload config                         tmux ls                          list sessions
```

## Gotchas

- The first Ruby compile per version is slow, about three minutes. It is not hung, it is compiling.
- Ruby 3.1 and newer build against OpenSSL 3 on Ubuntu 24.04. Older Rubies would need extra work.
- `docker.io/library/ubuntu:24.04` ships an `ubuntu` user at uid 1000. The Dockerfile removes it so `josh` can take that uid. The base image is fully qualified because Ubuntu's Podman ships no unqualified search registries, so an unqualified `ubuntu:24.04` fails the build.
- Rails 7.1 and newer block unknown hostnames in development. The Quadlet unit sets `RAILS_DEVELOPMENT_HOSTS` to cover the box's LAN IP and hostname.
- Packages an agent installs with `apt` inside a running container do not survive `rebuild`, since `rebuild` throws away the container and starts a fresh one from the image. Anything installed through `mise`, or gems installed into the home, do survive, because they land in the bind-mounted home rather than the container's writable layer.
- The sshd host key lives in the persistent home, not the image, so the Mac's `known_hosts` entry for `vinceworks-sandbox` stays valid across `rebuild`.
- Worktrees of one repo share one dev database, the same as on the laptop. There is no per-worktree database.
- The Paseo daemon runs as the container's main process. Killing it, including a crash, restarts the whole container: sshd and Postgres come back up too.
