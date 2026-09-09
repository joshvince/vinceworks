# Plan: replace Docker with Podman on vince-archive

Status: **ready to run**, unblocked on 2026-09-09 when the box was upgraded to Ubuntu 24.04. Nothing has been installed or changed on the box yet.

This plan was parked earlier the same day because `vince-archive` was on Ubuntu 22.04, whose only podman is 3.4.4 from December 2021 — too old for the rootless and `--userns=keep-id` behaviour the whole approach leans on. The box now runs Ubuntu 24.04.5 with podman 4.9.3 available from the standard archive, so the plan holds as written with the corrections in section 1.

## The premise

The working assumption was that this is a drop-in swap once the config points at Podman's Unix socket. It is a drop-in swap, but the socket is not the part that matters.

Nothing in this repo talks to a container socket. `projects/host/projects-host` shells out to the `docker` CLI seventeen times and reads its output. Podman ships a CLI that takes the same flags and prints the same Go-template fields, so the port is a CLI swap plus a short list of behaviour changes that come from Podman being rootless and daemonless rather than from Podman being a different tool.

The socket (`/run/user/1000/podman/podman.sock`) is worth enabling anyway, but only for clients that speak the Docker HTTP API — Testcontainers in a project's test suite, or the "Paseo on the box" item parked in `TODO.md`. It does nothing for the `projects` tooling itself.

## Decisions

### Rootless, not rootful

Podman can run as root and behave almost exactly like Docker, including uid mapping. Rootless is the better fit here:

- The setup already goes out of its way to keep a coding agent inside the container away from the host — only the ssh-agent socket goes in, never the private key. Rootless extends that: a container escape lands on an unprivileged user, not root.
- Membership of the `docker` group is root-equivalent on the host. Dropping it would be a real gain, though not yet — see the note below.
- The scripts stay free of `sudo`.

Keep the weighting honest, though. On a home box serving private applications behind an outbound-only tunnel, the container-escape scenario is theoretical. The concrete win available today is losing the daemon; the hardening is a bonus, not the reason.

The `docker` group is not a win yet. postcard still runs on Docker and is administered as `josh`, so removing `josh` from that group would put `sudo` in front of every `docker ps`, `docker compose up` and log check on production. That trade is not worth making to close a theoretical gap. The group can go when postcard moves off Docker too, and not before.

The cost is two things rootful would not need: `--userns=keep-id` for bind-mount ownership, and lingering so containers survive SSH logout. Both are one-time host setup.

### Keep Docker installed, select the engine with a variable

Do not install `podman-docker`. It drops a `/usr/bin/docker` shim that shadows the real binary, which is exactly wrong on a box where production is still on Docker.

Instead add one variable to `projects-host`:

```sh
ENGINE=${PROJECTS_ENGINE:-podman}
```

and route every call through it. Rollback is then `PROJECTS_ENGINE=docker vinceworks projects ...` with no code revert, and both engines sit on the box side by side for as long as you want them to.

## What changes

### 1. Host preparation

Re-verified on the box on 2026-09-09, after the 24.04 upgrade:

| Check | Result |
| --- | --- |
| Host OS | Ubuntu 24.04.5, kernel 6.8 |
| podman candidate | 4.9.3+ds1-1ubuntu0.2 from `noble-updates`, not installed yet |
| `apt-get install -s podman uidmap fuse-overlayfs` | 8 new packages, **0 to remove**, nothing touching Docker |
| cgroups | v2 (`cgroup2fs`) |
| Delegated controllers | `cpu memory pids` — **`cpu` is now delegated**, so `--cpus` works without extra config. This was the one thing 22.04 got wrong |
| Unprivileged user namespaces | `kernel.unprivileged_userns_clone = 1`, but see the AppArmor note below |
| subuid / subgid | `josh:100000:65536` already present in both. Nothing to do |
| Lingering | `Linger=no` — needs enabling |
| Disk | 466 GB filesystem, 60 GB used, 387 GB free |
| Memory | 15 GiB total, 857 MiB in use |

So the preparation is two commands:

```sh
sudo apt install podman
sudo loginctl enable-linger josh
```

**Lingering is not optional.** Without it, systemd tears down the user manager when the last SSH session closes, taking every rootless container with it. The whole model here is long-lived detached containers reached over SSH, so skipping this breaks the tool on the first disconnect.

The install pulls in `buildah`, `catatonit`, `conmon`, `fuse-overlayfs`, `libslirp0`, `passt` and `slirp4netns` alongside podman itself. `passt` means pasta is on the box even though podman 4.9.3 still defaults to slirp4netns.

The `delegate.conf` drop-in that an earlier draft of this plan called for is no longer needed. 24.04 delegates `cpu` to the user slice out of the box.

#### AppArmor and unprivileged user namespaces — new in 24.04

24.04 sets `kernel.apparmor_restrict_unprivileged_userns = 1`, which blocks unconfined binaries from creating user namespaces. On the box today, `unshare -U -r whoami` fails with `write failed /proc/self/uid_map: Operation not permitted`, so the restriction is live.

Rootless podman needs exactly that capability. Ubuntu handles it by shipping an AppArmor profile at `/etc/apparmor.d/podman` that names `/usr/bin/podman`, runs it `flags=(unconfined)` and grants `userns`. The profile is already on the box — it comes from the `apparmor` package, not from podman — so rootless should work the moment podman is installed.

This is the one genuinely new risk 24.04 introduces and it is not something to assume. The first smoke test after installing is `podman run --rm docker.io/library/alpine echo ok`. If that fails on a user-namespace error, the profile is not being applied and the options are a `local/podman` override or, as a last resort, relaxing the sysctl.

Debian and Ubuntu deliberately ship no `unqualified-search-registries`, so an unqualified `FROM ubuntu:24.04` fails the build. Fix it in the Dockerfile rather than in host config (see below) so the build does not depend on box state.

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

Add the `ENGINE` variable next to `IMAGE`, then replace every `docker` invocation with `"$ENGINE"`.

Three changes in `cmd_start`:

**Drop `--restart unless-stopped`.** Podman has no daemon watching containers at boot, and its `podman-restart.service` deliberately does not restart containers with the `unless-stopped` policy — a long-standing divergence from Docker. The flag as written would silently do nothing.

Decided: remove the flag rather than swap it for `--restart always`. `cmd_attach` already calls `cmd_start` when the container is not running, so the first attach after a reboot starts it and waits a few seconds for the entrypoint. Nothing is lost, because tmux state does not survive a container restart in either case — a reboot kills the running processes whoever starts the container back up.

**Add `--userns=keep-id:uid=$(id -u),gid=$(id -g)`.** This is the change that makes the bind mounts work. By default a rootless container maps host uid 1000 to container uid 0, and container uid 1000 to a subuid around 100999. Without `keep-id`:

- files written inside the repo at `/home/josh/projects/<name>` land on the host owned by a subuid, not by josh;
- the mounted ssh-agent socket is owned by the wrong uid inside the container and git over SSH fails.

`keep-id` maps host josh to container josh one-to-one and both problems disappear.

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

The one visible difference: Podman 4.9.3 defaults to slirp4netns for rootless networking, which rewrites the source address, so an app inside the container sees inbound connections as coming from 127.0.0.1. That only matters for an app that logs or rate-limits by remote IP. Podman 5.x defaults to pasta, which preserves the client IP; `passt` is installed here, so `--network pasta` is available to try if the source address ever matters.

### 5. `projects/entrypoint.sh`

No changes expected. Two things to verify on the first run rather than assume:

- **`sudo service postgresql start`.** Podman does not mount the container filesystem `nosuid` and does not set `PR_NO_NEW_PRIVS`, so setuid `sudo` works in a rootless container. This is still the single most likely thing to break, so smoke-test it first.
- **Postgres data ownership on `project-<name>-pg`.** A fresh volume gets the right ownership from the container.

### 6. State migration

There is nothing to migrate. The `projects` tooling is new and has one project on the box, `vincetagram`, whose container is already dead — `project-vincetagram` shows `Exited (127)` from the 24.04 upgrade.

The repos under `~/projects` and the state under `~/.projects` are plain host directories and are untouched by any of this, so a fresh Podman container picks the project straight back up. `mise install` refetches the toolchain, `claude` and `gh auth login` need one login each. The development database in `project-vincetagram-pg` is not worth keeping.

The Docker volumes that back the dev side are small — `projects-mise` 343 MB, `project-vincetagram-pg` 73 MB, `projects-claude` 6 MB, `projects-gh` 900 bytes, `projects-go` empty — so leaving them in place costs nothing while the Podman side beds in. `postcard_postgres_data` is production and is not touched by any of this.

### 7. Doing the switch

1. Host preparation, as in section 1. Verify linger afterwards with `loginctl show-user josh | grep Linger`.
2. `podman run --rm docker.io/library/alpine echo ok` — the AppArmor user-namespace smoke test. Stop here if it fails.
3. Change the Dockerfile and `projects-host`, push, then `vinceworks projects sync`.
4. `vinceworks projects new joshvince/<throwaway>` — a fresh project, not vincetagram, so the first run of everything happens somewhere disposable.
5. Work through the cutover checklist below on the throwaway.
6. `vinceworks projects rm <throwaway> --purge`, then `vinceworks projects start vincetagram` under Podman.

Rollback at any point is `PROJECTS_ENGINE=docker`, plus `docker start project-vincetagram` if the old container is still around.

#### Cutover checklist

This is the gate for calling the migration done and deleting the Docker-side dev volumes. It is a checklist, not a waiting period — there is no scheduled job or slow-accumulating state in these containers, so nothing is learned by letting the clock run. Every item below can be done in one sitting.

- [ ] `podman build` completes and the image is tagged `projects:latest`
- [ ] container starts and the entrypoint prints `projects: ready`
- [ ] `mise install` completes and the toolchain resolves inside the container
- [ ] `sudo service postgresql start` works — the most likely rootless failure
- [ ] the app answers on its host port from the Mac
- [ ] a `git push` succeeds through the forwarded ssh-agent socket, and `gh auth status` is clean
- [ ] files written inside the container land on the host owned by `josh`, not a subuid — `ls -l ~/projects/<name>` on the host
- [ ] tmux survives detach and reattach
- [ ] **reboot the box deliberately** and confirm the container comes back on the next `attach`. This is the real test of lingering and of dropping `--restart`; do it on purpose rather than waiting for a reboot to happen
- [ ] postcard and Filebrowser still serve after that reboot

Once every box is ticked, delete the old dev-side Docker volumes (`projects-mise`, `projects-claude`, `projects-gh`, `projects-go`, `project-vincetagram-pg`) and the dead `project-vincetagram` container. Leave Docker itself installed and leave `postcard_postgres_data` alone — production still needs both.

Leave `josh` in the `docker` group as well, for the reason given under "Rootless, not rootful".

## Coexistence with production on the same box

The box also serves a few private applications — the family archive and postcard — over a Cloudflare Tunnel. Production and dev containers share a host, so it is worth knowing where they touch. Re-checked after the 24.04 upgrade on 2026-09-09; everything below came back up.

Production stays on Docker, dev moves to rootless Podman, both engines coexist. Rootless podman stores its images and volumes under `~/.local/share/containers`, a different tree from `/var/lib/docker`, and talks to no daemon, so it cannot see or touch a Docker container. There is ample disk for two image stores.

| Service | Where | Host port | State after upgrade |
| --- | --- | --- | --- |
| postcard (vincetagram) web | `postcard-web-1` container | `0.0.0.0:3000` | up |
| postcard Postgres | `postcard-postgres-db-1` container | `0.0.0.0:5432` | up, healthy |
| nginx | host systemd service | `0.0.0.0:80`, `0.0.0.0:443` | active |
| Filebrowser | host systemd service | `127.0.0.1:8080` | active |
| cloudflared | host systemd service | outbound only | active |

nginx routes by hostname: `archive.*` to Filebrowser on 8080, everything else to postcard on 3000. Its server blocks live in the `joshvince/vince-family-archive-config` repo. The tunnel is outbound-only and nothing is port-forwarded, so none of these ports are reachable from the internet — the `0.0.0.0` binds are visible on the home LAN and to containers, and that is all.

The three things that could disturb production, and why they do not:

- **The podman install.** Simulated on the box: 8 packages in, none removed, nothing Docker-related reconfigured. Re-run `apt-get install -s podman` and stop if that ever stops being true.
- **Port collisions.** Dev ports start at 4100 and `projects-host` refuses to start a container on an already-bound port, checking `ss -ltn` immediately before `run`. 80, 443, 3000, 5432 and 8080 are also in `RESERVED_PORTS`.
- **Resource exhaustion.** The real risk, and what `--memory 4g --cpus 4` is for.

The concern is an over-eager agent breaking something annoying to fix, not an attacker.

### Separate job for later: loopback-bind the production database

Deliberately not part of the Podman work. It touches production and has nothing to do with containers for development, so it should be done on its own, another time.

`postcard-postgres-db-1` publishes `0.0.0.0:5432`, and a dev container can reach it at the host bridge address. An agent debugging a database problem does not need to break out of anything to find it. The credentials live in `/home/josh/postcard/.env`, which is not mounted into dev containers, so it is not an open door; the concern is only that a dropped production table would be annoying.

The change is one line in `joshvince/vincetagram`'s `docker-compose.yml`, checked out on the box at `/home/josh/postcard`:

```yaml
ports:
  - "127.0.0.1:5432:5432"
```

Nothing connects to that database from the Mac, and `postcard-web-1` reaches it over the compose network by service name, so the host publish is not doing anything useful. The cost is restarting `postcard-postgres-db-1`, which will make the web app error for a few seconds while it reconnects. Worth doing while watching, not as a side effect of something else.

Leave `web`'s `3000:3000` alone. nginx needs it and LAN access is useful for debugging.

### Unrelated cleanup noticed on the box

Ten stale `postcard-web-run-*` containers and one `gifted_booth` are sitting exited from two years ago. Harmless, but `docker container prune` would tidy them. Not part of this work.

## Documentation to update

- `projects/README.md` — lines 3, 16, 21, 47, 67, 119, 132 and 133 all name Docker. Line 119 (`groups josh` should include `docker`) is replaced by the subuid and linger checks. Line 133's `docker run --rm -v ... chown` recipe becomes the `podman unshare chown` form.
- `README.md` line 45.
- `TODO.md` — note under the Paseo item that `podman.socket` plus `DOCKER_HOST` is the lever if Paseo needs a container API.

## Effort

Host preparation and the script change are about an hour together. With one project and nothing to copy across, the switch itself is another hour. Call it a morning, including the reboot test.

## References

- [Understanding rootless Podman's user namespace modes](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes)
- [How to Use the --userns=keep-id Option in Podman](https://oneuptime.com/blog/post/2026-03-17-use-userns-keep-id-option-podman/view)
- [podman-restart.service does not restart "unless-stopped" containers (podman#17851)](https://github.com/containers/podman/issues/17851)
- [User-level podman-restart.service does not work properly on reboot (podman#22451)](https://github.com/containers/podman/issues/22451)
- [Rootless Podman stops after logout/reboot: linger and restart fix](https://www.golinuxcloud.com/podman-container-stops-after-logout/)
- [podman 4.9.3 in Ubuntu Noble](https://launchpad.net/ubuntu/noble/+package/podman)
- [Unprivileged user namespace restrictions in Ubuntu 24.04](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces)
- [Fixing short-name resolution errors in Podman](https://haseebmajid.dev/posts/2024-06-15-til-how-to-fix-did-no-resolve-alias-errors-in-podman/)
