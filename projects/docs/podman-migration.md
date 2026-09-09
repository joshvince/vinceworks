# Plan: replace Docker with Podman on vince-archive

Status: **parked on 2026-09-09**, blocked on the host OS. Nothing has been installed or changed on the box.

## Why this is parked

`vince-archive` runs Ubuntu 22.04.5, not 24.04. An earlier draft of this plan assumed 24.04 by mistake — that is the container image's base (`FROM ubuntu:24.04` in the Dockerfile), not the host.

That matters because 22.04's only podman is **3.4.4, from December 2021**, and there is no newer one without a third-party package source. This plan leans entirely on rootless mode and `--userns=keep-id`, which is exactly the area that was rough in 2021-era podman. Adding an unvetted repo to a box that serves the family archive is not a trade worth making for a development convenience.

Revisit when the box moves to Ubuntu 24.04, which carries podman 4.9.3. 22.04 reaches end of life in April 2027, so that upgrade is coming anyway. The rest of this plan holds as written, with the corrections noted in section 1.

The one thing here worth doing independently is the production database bind, which has nothing to do with podman. See "Separate job for later" below.

## The premise, corrected

The working assumption was that this is a drop-in swap once the config points at Podman's Unix socket. It is a drop-in swap, but the socket is not the part that matters.

Nothing in this repo talks to a container socket. `projects/host/projects-host` shells out to the `docker` CLI seventeen times and reads its output. Podman ships a CLI that takes the same flags and prints the same Go-template fields, so the port is a CLI swap plus a short list of behaviour changes that come from Podman being rootless and daemonless rather than from Podman being a different tool.

The socket (`/run/user/1000/podman/podman.sock`) is worth enabling anyway, but only for clients that speak the Docker HTTP API — Testcontainers in a project's test suite, or the "Paseo on the box" item parked in `TODO.md`. It does nothing for the `projects` tooling itself.

## Decisions

### Rootless, not rootful

Podman can run as root and behave almost exactly like Docker, including uid mapping. Rootless is the better fit here:

- The setup already goes out of its way to keep a coding agent inside the container away from the host — only the ssh-agent socket goes in, never the private key. Rootless extends that: a container escape lands on an unprivileged user, not root.
- Membership of the `docker` group is root-equivalent on the host. Dropping it is a real gain.
- The scripts stay free of `sudo`.

Keep the weighting honest, though. On a home box serving private applications behind an outbound-only tunnel, the container-escape scenario is theoretical. The concrete wins are dropping a root-equivalent group and losing the daemon; the hardening is a bonus, not the reason.

The cost is three things that rootful would not need: `--userns=keep-id` for bind-mount ownership, lingering so containers survive SSH logout, and an extra systemd unit for restart-on-boot. All three are one-time host setup.

### Keep Docker installed, select the engine with a variable

Do not install `podman-docker`. It drops a `/usr/bin/docker` shim that shadows the real binary, which is exactly wrong on a box where production may still be on Docker.

Instead add one variable to `projects-host`:

```sh
ENGINE=${PROJECTS_ENGINE:-podman}
```

and route every call through it. Rollback is then `PROJECTS_ENGINE=docker vinceworks projects ...` with no code revert, and both engines sit on the box side by side for as long as you want them to.

## What changes

### 1. Host preparation

Verified on the box on 2026-09-09, before this was parked:

| Check | Result |
| --- | --- |
| Host OS | Ubuntu 22.04.5, kernel 5.15 — **the blocker**; 24.04 is what this plan needs |
| podman available | 3.4.4 only. On 24.04 it would be 4.9.3 |
| `apt-get -s install podman` | 28 new packages, **0 to remove**, nothing touching Docker |
| cgroups | v2 (`cgroup2fs`) — needed for rootless resource limits |
| Delegated controllers | `memory` and `pids` only. **`cpu` is not delegated**, so `--cpus` would silently do nothing |
| Unprivileged user namespaces | allowed (`kernel.unprivileged_userns_clone = 1`) |
| subuid / subgid | `josh:100000:65536` already present in both. Nothing to do |
| `slirp4netns` | already installed (1.0.1) |
| `uidmap`, `fuse-overlayfs` | not installed; the podman install pulls both in |
| Lingering | `Linger=no` — needs enabling |

So on a 24.04 box the preparation reduces to:

```sh
sudo apt update && sudo apt install podman
sudo loginctl enable-linger josh
```

**Lingering is not optional.** Without it, systemd tears down the user manager when the last SSH session closes, taking every rootless container with it. The whole model here is long-lived detached containers reached over SSH, so skipping this breaks the tool on the first disconnect.

To make `--cpus` work, `cpu` also has to be delegated to the user slice:

```
# /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
```

`--memory` works without it, and memory is the cap that matters.

Debian and Ubuntu deliberately ship no `unqualified-search-registries`, so an unqualified `FROM ubuntu:24.04` fails the build. Fix it in the Dockerfile rather than in host config (see below) so the build does not depend on box state.

Disk is not a concern: one 466 GB filesystem holds `/`, `/home` and `/var/lib/docker`, currently 61 GB used. Rootless podman would store images and volumes under `~/.local/share/containers` on that same volume.

Optional, for clients that speak the Docker API — Testcontainers, or the "Paseo on the box" item in `TODO.md`:

```sh
systemctl --user enable --now podman.socket
# then: export DOCKER_HOST=unix:///run/user/1000/podman/podman.sock
```

### 2. `projects/Dockerfile`

One required change:

```
FROM docker.io/library/ubuntu:24.04
```

Everything else builds as-is. Buildah handles `COPY --chmod=755`, and the `userdel -r ubuntu` / `useradd -u 1000` dance still works inside the build's user namespace because the default 65536-wide subuid range covers uid 1000.

### 3. `projects/host/projects-host`

Add the `ENGINE` variable next to `IMAGE`, then replace `docker` at lines 48, 143, 180, 194, 203, 222, 224, 232, 243, 244, 252, 258, 267, 271 and 299 with `"$ENGINE"`.

Three changes in `cmd_start`:

**Drop `--restart unless-stopped`.** Podman has no daemon watching containers at boot, and its `podman-restart.service` deliberately does not restart containers with the `unless-stopped` policy — a long-standing divergence from Docker. The flag as written would silently do nothing.

Decided: remove the flag rather than swap it for `--restart always`. `cmd_attach` already calls `cmd_start` when the container is not running, so the first attach after a reboot starts it and waits a few seconds for the entrypoint. Nothing is lost, because tmux state does not survive a container restart in either case — a reboot kills the running processes whoever starts the container back up. The box has been up 48 days, so this is rare.

**Add `--userns=keep-id`.** This is the change that makes the bind mounts work. By default a rootless container maps host uid 1000 to container uid 0, and container uid 1000 to a subuid around 100999. Without `keep-id`:

- files written inside the repo at `/home/josh/projects/<name>` land on the host owned by a subuid, not by josh;
- the mounted ssh-agent socket is owned by the wrong uid inside the container and git over SSH fails.

`--userns=keep-id` maps host josh to container josh one-to-one and both problems disappear. The explicit form `--userns=keep-id:uid=1000,gid=1000` is equivalent here and clearer about intent.

**Add resource caps.** The box has 15 GiB of RAM and one shared filesystem, so a runaway dev container is the most likely way production gets hurt — no escape or attacker required. Add to the `podman run`:

```
--memory 4g --cpus 4
```

4 GB rather than 8 GB per container, so one or two can run alongside postcard. Each dev container also runs its own Postgres, counted in that budget.

Everything else in the file is already Podman-compatible:

| Call | Notes |
| --- | --- |
| `inspect -f '{{.State.Status}}'` | Same field, same template engine |
| `ps --filter name='^project-'` | Podman's name filter is a regex too |
| `logs -f ... \| sed '/^projects: ready$/q'` | Works; still exits on the marker line |
| `volume rm`, `image inspect`, `build --build-arg` | Identical |
| `exec -it -w ... tmux new -A` | Identical |
| `--init` | Podman uses catatonit instead of tini |

### 4. Port publishing

No change needed, but worth understanding. Ports start at 4100, so nothing is below 1024 and `net.ipv4.ip_unprivileged_port_start` does not need touching.

Rootless Podman publishes through a per-container forwarder process, which still appears in `ss -ltn`. So `bound_ports()`, the pre-`run` re-check and the reserved-port logic all keep working unchanged, and Podman refuses an already-bound port the same way Docker does. Production on 80, 443, 3000, 5432 and 8080 stays safe.

The one visible difference: Podman 4.9.3 defaults to slirp4netns for rootless networking, which rewrites the source address, so an app inside the container sees inbound connections as coming from 127.0.0.1. That only matters for an app that logs or rate-limits by remote IP. Podman 5.x defaults to pasta, which preserves the client IP — a reason to go newer eventually, not now.

### 5. `projects/entrypoint.sh`

No changes expected. Two things to verify on the first run rather than assume:

- **`sudo service postgresql start`.** Podman does not mount the container filesystem `nosuid` and does not set `PR_NO_NEW_PRIVS`, so setuid `sudo` works in a rootless container. This is still the single most likely thing to break, so smoke-test it first.
- **Postgres data ownership on `project-<name>-pg`.** A fresh volume gets the right ownership from the container. A volume migrated from Docker may not; fix with `podman unshare chown -R` (see below).

### 6. State migration

There is one project on the box, `vincetagram`, and the volumes are small: `projects-mise` 343 MB, `project-vincetagram-pg` 73 MB, `projects-claude` 6 MB, `projects-gh` 900 bytes, `projects-go` empty. Nothing here justifies a tar-and-restore dance.

Rebuild instead. The repos under `~/projects` and the state under `~/.projects` are plain host directories and are untouched by any of this, so a fresh Podman container picks the project straight back up. `mise install` refetches the toolchain, `claude` and `gh auth login` need one login each.

The development database in `project-vincetagram-pg` is not worth keeping, so nothing needs to be carried across at all. Delete the old Docker volumes once the Podman ones have run for a while without trouble.

### 7. Doing the switch

One project to move, so this is short. Nothing here touches postcard, the archive, or any of their data.

1. Do the host preparation. Run `apt-get install --dry-run podman` first and stop if it proposes removing or reconfiguring anything Docker-related. Verify linger afterwards with `loginctl show-user josh | grep Linger`.
2. Change the Dockerfile and `projects-host`, push, then `vinceworks projects sync`. Running containers are unaffected until something is rebuilt.
3. `PROJECTS_ENGINE=podman vinceworks projects new joshvince/<throwaway>` — a fresh project, not vincetagram. Confirm in order: image builds, container starts, `mise install` completes, Postgres starts, git push works through the agent socket, the app answers on its host port, tmux survives detach and reattach.
4. `docker stop project-vincetagram`, then `vinceworks projects start vincetagram` under Podman. Do not remove the Docker container yet.
5. Leave it a week. Keep the old Docker container stopped but not deleted, in case something turns up.
6. Then delete it: `docker rm project-vincetagram`, plus the old `projects-*` and `project-vincetagram-pg` Docker volumes. Leave Docker itself installed — postcard still needs it.

Rollback at any point is `PROJECTS_ENGINE=docker` plus `docker start project-vincetagram`.

## Coexistence with production on the same box

The box also serves a few private applications — the family archive and postcard — over a Cloudflare Tunnel. Production and dev containers share a host, so it is worth knowing where they touch. Checked 2026-09-09.

Production stays on Docker, dev moves to rootless Podman, both engines coexist. There is ample disk for two image stores.

| Service | Where | Host port |
| --- | --- | --- |
| postcard (vincetagram) web | `postcard-web-1` container | `0.0.0.0:3000` |
| postcard Postgres | `postcard-postgres-db-1` container | `0.0.0.0:5432` |
| nginx | host systemd service | `0.0.0.0:80`, `0.0.0.0:443` |
| Filebrowser | host systemd service | `127.0.0.1:8080` |
| cloudflared | host systemd service | outbound only |

nginx routes by hostname: `archive.*` to Filebrowser on 8080, everything else to postcard on 3000. Its server blocks live in the `joshvince/vince-family-archive-config` repo. The tunnel is outbound-only and nothing is port-forwarded, so none of these ports are reachable from the internet — the `0.0.0.0` binds are visible on the home LAN and to containers, and that is all.

The concern is an over-eager agent breaking something annoying to fix, not an attacker. Two things are worth doing. The rest is noted and left alone.

### Worth doing: resource caps

The most likely way an agent hurts production, and it needs no attacker at all: a runaway test suite or build eats the box. 15 GiB of RAM total, and one 466 GB filesystem shared by `/`, `/home` and `/var/lib/docker`. Add to the `podman run` in `cmd_start`:

```
--memory 4g --cpus 4
```

That leaves room for postcard and a second dev container. Each dev container also runs its own Postgres, counted in that budget. Disk is less pressing at 386 GB free, but `docker builder prune` reclaims about 8 GB of stale build cache whenever it is wanted.

### Separate job for later: loopback-bind the production database

Deliberately not part of the Podman work. It touches production and has nothing to do with containers for development, so it should be done on its own, another time.

`postcard-postgres-db-1` publishes `0.0.0.0:5432`, and a dev container can reach it at `172.17.0.1:5432` — confirmed by testing from inside `project-vincetagram`. An agent debugging a database problem does not need to break out of anything to find it. The credentials live in `/home/josh/postcard/.env`, which is not mounted into dev containers, so it is not an open door; the concern is only that a dropped production table would be annoying.

The change is one line in `joshvince/vincetagram`'s `docker-compose.yml`, checked out on the box at `/home/josh/postcard`:

```yaml
ports:
  - "127.0.0.1:5432:5432"
```

Nothing connects to that database from the Mac, and `postcard-web-1` reaches it over the compose network by service name, so the host publish is not doing anything useful. The cost is restarting `postcard-postgres-db-1`, which will make the web app error for a few seconds while it reconnects. Worth doing while watching, not as a side effect of something else.

Leave `web`'s `3000:3000` alone. nginx needs it and LAN access is useful for debugging.

## Documentation to update

- `projects/README.md` — lines 3, 16, 21, 47, 67, 119, 132 and 133 all name Docker. Line 119 (`groups josh` should include `docker`) is replaced by the subuid and linger checks. Line 133's `docker run --rm -v ... chown` recipe becomes the `podman unshare chown` form.
- `README.md` line 45.
- `TODO.md` — note under the Paseo item that `podman.socket` plus `DOCKER_HOST` is the lever if Paseo needs a container API.

## Effort

Host preparation and the script change are about an hour together. With one project and nothing to copy across, the switch itself is another hour. Call it a morning, then leave it a week before deleting the Docker side.

## References

- [Understanding rootless Podman's user namespace modes](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes)
- [How to Use the --userns=keep-id Option in Podman](https://oneuptime.com/blog/post/2026-03-17-use-userns-keep-id-option-podman/view)
- [podman-restart.service does not restart "unless-stopped" containers (podman#17851)](https://github.com/containers/podman/issues/17851)
- [User-level podman-restart.service does not work properly on reboot (podman#22451)](https://github.com/containers/podman/issues/22451)
- [Rootless Podman stops after logout/reboot: linger and restart fix](https://www.golinuxcloud.com/podman-container-stops-after-logout/)
- [podman 4.9.3 in Ubuntu Noble](https://launchpad.net/ubuntu/noble/+package/podman)
- [Fixing short-name resolution errors in Podman](https://haseebmajid.dev/posts/2024-06-15-til-how-to-fix-did-no-resolve-alias-errors-in-podman/)
- [How to Migrate Docker Volumes to Podman](https://oneuptime.com/blog/post/2026-03-18-migrate-docker-volumes-podman/view)
- [Security features of Apptainer vs rootless Podman, part 2](https://ciq.com/blog/security-features-of-apptainer-vs-rootless-podman-part-2)
