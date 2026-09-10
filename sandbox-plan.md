# Plan: one sandbox container for all projects

Status: agreed design, not yet built. Replaces the per-project model in `projects/`. Delete this file when the work is merged.

## Why

The per-project container model turned out to be the source of nearly all the complexity in `projects/`: the port mapper, the per-project config and secrets directories, the per-project Postgres volume, the stale ssh-agent socket detection, and finally the two Paseo shims that route a host-level daemon into the right container. It also made intertwined projects awkward, since one container could not see another project's checkout.

The goal was never per-project isolation. The goal is one stable machine that is not the laptop, where agents can run with very high autonomy, using Paseo worktrees for parallel sessions, opening PRs that get reviewed and deployed from the laptop. One container that behaves like a second laptop does that with a fraction of the moving parts. The container boundary is kept for one reason: production (`postcard` and its Postgres on host loopback 5432, nginx, Filebrowser) shares the box, and agents must not be able to reach it.

## Decisions

Settled in discussion on 2026-09-09. Not up for relitigation during the build.

| Area | Decision |
|---|---|
| Isolation unit | One rootless Podman container, `vinceworks-sandbox`, on `vince-archive` |
| Autonomy | Full. Agents run with permissions bypassed, have sudo, may `apt install` |
| Production | Hard boundary. Own network namespace, no host network, no Docker socket, no shared volumes with production |
| Base vs state | Rebuildable image from a Dockerfile. Persistent home bind-mounted from `/home/josh/vinceworks-sandbox` on the host to `/home/josh` in the container, uid 1000 via `--userns=keep-id` |
| Interface | Paseo Desktop on the Mac as the primary interface, added as an SSH host. `vinceworks tmux` as the escape hatch |
| Way in | Unprivileged sshd inside the container running as josh, host port 2222, host keys and config in `~/.ssh/sshd/` in the persistent home |
| Reboot | Quadlet unit under `~/.config/containers/systemd/`. Linger is already enabled for josh |
| Paseo daemon | Started by the entrypoint in the foreground. Daemon death restarts the container |
| Postgres | Inside the container as a system service, data in one named volume `vinceworks-sandbox-pg`. Worktrees of a repo share one dev database, same as the laptop |
| Ports | 2222 for sshd. 4100 to 4199 for dev servers. Each repo's `paseo.json` sets `worktree.servicePorts.range` to `4100-4199` and apps bind `PASEO_WORKTREE_PORT` |
| Caps | 3 cpus, 10 GB |
| Git credential | No SSH key. A fine-grained PAT for joshvince personal repos only: Contents read/write, Pull requests read/write, Metadata read, one year expiry. `gh auth login --with-token` once, then `gh auth setup-git` so git uses HTTPS through gh |
| Repo scope | Personal repos only. Carwow code never goes on the box |
| Secrets | Files, untracked, in the main checkout at `~/projects/<repo>/`. Pushed from the Mac with `vinceworks sandbox push`. Paseo worktree setup hooks copy them into each worktree |
| Hooks | `paseo.json` committed to each repo. Hooks do plumbing only: copy `.env`, `config/master.key`, SQLite files. No `bundle install` or application code in hooks |
| Provisioned every start | `ai.sh` (agents and skills), `.gitconfig`, `.gitmessage.txt`, `.gitignore_global`, `.zshrc`, `.tmux.conf` |
| Done by hand once | `claude` login, `gh` login, Paseo `config.json` copied from the Mac |
| Reach | LAN only. Tailscale and a real hostname stay in `TODO.md` |
| Naming | Repo directory `sandbox/`, CLI `vinceworks sandbox <cmd>` and `vinceworks tmux` |

Facts from the Paseo 0.7.2 source that the design relies on:

- The SSH host transport runs a single `ssh -T -o BatchMode=yes ... [-p PORT] -W 127.0.0.1:6767 host`. It never executes `paseo` on the remote and does not start or install the daemon. A non-22 port in the URL is supported.
- `paseo.json` at a repo root supports `worktree.setup` and `worktree.teardown` command lists, run in the new worktree with `PASEO_SOURCE_CHECKOUT_PATH`, `PASEO_WORKTREE_PATH`, `PASEO_BRANCH_NAME` and `PASEO_WORKTREE_PORT` exported.
- `worktree.servicePorts.range` makes `PASEO_WORKTREE_PORT` come from that range. Without it the port is random.
- The daemon on the remote needs Node 20.11 or newer and `npm install -g @getpaseo/cli`.

## Target layout

```
vinceworks                  top-level CLI: sandbox, tmux, update, ai, dev-machine-setup
sandbox/
  README.md                 how it fits together, commands, host prerequisites, gotchas
  sandbox                   Mac-side CLI: up, rebuild, push
  Dockerfile                the image
  entrypoint.sh             runs on every container start
  sandbox.container         Quadlet unit, installed to ~/.config/containers/systemd/ on the box
  sshd_config               unprivileged sshd config, copied into the image
  host/sandbox-host         host-side script: build, up, rebuild, install-unit
  tmux.conf                 copied to ~/.tmux.conf on every start
  zshrc                     copied to ~/.zshrc on every start
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

## Components

### Dockerfile

Start from the existing `projects/Dockerfile` and change:

- Add `openssh-server` (for the `sshd` binary; the service is not enabled), `nodejs` from NodeSource or a mise-managed global Node, and `npm install -g @getpaseo/cli` pinned to a version. `rebuild` upgrades it.
- Keep Claude Code and OpenCode baked in.
- Drop the pre-created volume mount points. The whole home comes from the bind mount.
- Copy `sshd_config` to `/etc/ssh/sandbox_sshd_config` or similar. The entrypoint runs sshd with `-f` pointing at it.
- Keep `MISE_*`, `CLAUDE_CONFIG_DIR`, `TERM`, `SHELL`, `BINDING=0.0.0.0`.

### entrypoint.sh

Runs as josh on every start. In order:

1. Copy `.gitconfig`, `.gitmessage.txt`, `.gitignore_global`, `.zshrc`, `.tmux.conf` from the read-only vinceworks mount into home, dropping the macOS credential helper. Run `ai.sh`.
2. Ensure `~/projects` and `~/.ssh/sshd` exist. Generate an ed25519 host key into `~/.ssh/sshd/` if missing. Seed `~/.ssh/sshd/authorized_keys` from a file in the read-only vinceworks mount if it does not exist yet.
3. `sudo service postgresql start`, create a superuser role for josh if missing. Unconditional now, no service detection.
4. Start sshd: `/usr/sbin/sshd -f <config> -h ~/.ssh/sshd/ssh_host_ed25519_key -p 2222 -o AuthorizedKeysFile=~/.ssh/sshd/authorized_keys`. Unprivileged sshd listens fine on 2222 without root.
5. `gh auth setup-git` if `gh auth status` succeeds, so a rebuilt image picks up the credential helper again.
6. `exec paseo daemon run` in the foreground with `PASEO_HOME=~/.paseo` and listen on `127.0.0.1:6767`. Check the exact subcommand in `paseo daemon --help`; the intent is a foreground process, not the backgrounding `daemon start`.

No tmux session creation. `vinceworks tmux` creates `main` on demand.

### sandbox.container (Quadlet)

```
[Unit]
Description=vinceworks sandbox

[Container]
Image=localhost/vinceworks-sandbox:latest
ContainerName=vinceworks-sandbox
HostName=vinceworks-sandbox
UserNS=keep-id:uid=1000,gid=1000
Volume=/home/josh/vinceworks-sandbox:/home/josh
Volume=/home/josh/vinceworks:/home/josh/vinceworks:ro
Volume=vinceworks-sandbox-pg:/var/lib/postgresql
PublishPort=2222:2222
PublishPort=4100-4199:4100-4199
Environment=RAILS_DEVELOPMENT_HOSTS=192.168.1.200,vince-archive
PodmanArgs=--memory 10g --cpus 3 --init

[Service]
Restart=always

[Install]
WantedBy=default.target
```

Note the vinceworks checkout is mounted read-only inside the home at the same path it has on the host, so `ai.sh` and the dotfile copies work unchanged.

### host/sandbox-host

Runs on the box. About forty lines.

- `build`: `git pull --ff-only` in `~/vinceworks`, `podman build -t vinceworks-sandbox:latest sandbox/`.
- `install-unit`: copy `sandbox.container` into `~/.config/containers/systemd/`, `systemctl --user daemon-reload`.
- `up`: `install-unit` if missing, `build` if the image is missing, `systemctl --user start vinceworks-sandbox`.
- `rebuild`: `build`, `install-unit`, `systemctl --user restart vinceworks-sandbox`.

### sandbox (Mac CLI)

- `up` and `rebuild`: one SSH call each to `sandbox-host`.
- `push <repo> <paths...>`: for each path, `scp` from `~/projects/<repo>/<path>` on the Mac to `vinceworks-sandbox:projects/<repo>/<path>`, creating parent directories first. Refuses if the local file is missing.

### vinceworks (top level)

Replace `projects` with `sandbox`, add `tmux`:

```
tmux) exec ssh -t vinceworks-sandbox 'cd ~/projects && tmux new -A -s main' ;;
```

### Per-repo paseo.json

Committed to each personal repo. For vincetagram:

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

Copies must tolerate a missing source file on the laptop, so use `cp ... 2>/dev/null || true` or a small guard. Anything app-specific, such as `bundle install` or `db:prepare`, stays out of the hooks.

## Build order

Each step leaves the previous one working. Steps 1 to 3 are repo changes on this branch; 4 onwards touch the box.

1. Rename `projects/` to `sandbox/`. Delete `paseo.md`, both shims, and the old host script and Mac CLI. Keep `Dockerfile`, `entrypoint.sh`, `tmux.conf`, `zshrc` as starting points.
2. Write `Dockerfile`, `entrypoint.sh`, `sshd_config`, `sandbox.container`, `host/sandbox-host`, `sandbox`, and update `vinceworks`.
3. Rewrite `sandbox/README.md` and the `projects` section of the root `README.md`. Update `TODO.md`: drop the Paseo item, keep Tailscale and hostname.
4. Box cleanup (see checklist below).
5. On the box: `mkdir ~/vinceworks-sandbox`, pull the branch into `~/vinceworks`, run `sandbox-host up`. Watch `journalctl --user -u vinceworks-sandbox -f` for the first Ruby compile.
6. Mac: add the `vinceworks-sandbox` SSH host, run `vinceworks tmux`, log in `gh` with the PAT and run `gh auth setup-git`, log in `claude`, copy `~/.paseo/config.json` from the Mac into `~/.paseo/`.
7. Inside the sandbox: `gh repo clone joshvince/vincetagram ~/projects/vincetagram`. From the Mac: `vinceworks sandbox push vincetagram .env config/master.key`.
8. Paseo Desktop: add host `ssh://josh@vince-archive:2222`, open `~/projects/vincetagram`, create a worktree workspace, run an agent, confirm the app is reachable on the Mac at `http://192.168.1.200:<PASEO_WORKTREE_PORT>`.
9. Add `paseo.json` to vincetagram in its own PR.
10. Open the vinceworks PR. Delete this file in it.

## Box cleanup checklist

Only Podman objects and directories owned by the old tooling are touched. Nothing here names Docker, `postcard`, `~/postcard` or `~/postcard-active-storage-blobs`.

```sh
# Paseo proof of concept from PR #8
PASEO_HOME=~/.paseo-poc/home ~/.local/share/mise/installs/node/22.23.2/bin/node \
  ~/.local/share/mise/installs/node/22.23.2/lib/node_modules/@getpaseo/cli/bin/paseo daemon stop || pkill -f '@getpaseo/server'
rm -rf ~/.paseo-poc
rm -rf ~/.local/bin/mise ~/.local/share/mise ~/.config/mise

# Old per-project tooling
podman rm -f project-vincetagram
podman volume rm projects-mise projects-claude projects-gh projects-go project-vincetagram-pg
podman rmi projects:latest
rm -rf ~/projects ~/.projects
```

Before running: `docker ps` shows `postcard-web-1` and `postcard-postgres-db-1` before and after, unchanged.

## Verification

- `podman exec vinceworks-sandbox curl -s --max-time 2 http://host.containers.internal:5432` fails, and so does `psql -h 127.0.0.1 -p 5432` from inside. Production Postgres is not reachable.
- `ls /var/run/docker.sock` inside the container fails.
- `systemctl --user status vinceworks-sandbox` is active after `sudo reboot` on the box.
- Killing the paseo process inside the container brings the container back within seconds with sshd and Postgres restarted.
- `ssh vinceworks-sandbox hostname` prints `vinceworks-sandbox`.
- A Paseo worktree workspace on the Mac shows the sandbox path under `~/.paseo/worktrees/`, and `git worktree list` inside `~/projects/vincetagram` lists it.
- `vinceworks sandbox rebuild` keeps logins, repos and worktrees.

## Out of scope

Per-worktree databases. Tailscale. A resolvable hostname. Editor remote over the sshd (should work, not tested). `clone`, `sync`, `logs` subcommands. Migrating anything from the old volumes.
