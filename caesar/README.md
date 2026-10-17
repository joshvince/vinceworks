# Caesar: the vinceworks side

Caesar is a persistent orchestrator agent. He runs on the home server beside the sandbox, watches the coding agents working there, and starts and steers sessions for me. His own code (the web app, the API and the agent logic) lives in the separate `caesar` repo. This directory holds what runs him: the container's quadlet, the host snapshot timer and the `vinceworks caesar` command.

## How is it put together?

- Caesar runs in his own rootless podman container, a systemd user quadlet ([`caesar.container`](caesar.container)) beside `vinceworks-sandbox` rather than inside it. His memory and his secrets, apart from an OpenCode key he may share with the sandbox, sit out of the coding agents' reach, and he stays up through sandbox restarts.
- He joins the tailnet from inside the container as his own device, tagged `tag:caesar`. The tailnet policy grants my Mac and iPhones port 443 on that tag, and that is how he is reached.
- He reaches the Paseo daemon in the sandbox through an SSH tunnel to the sandbox's sshd on port 2222. The tunnel key is generated on the host. Its entry in the sandbox's `authorized_keys` allows local port forwards to `127.0.0.1:6767` and nothing else: `permitopen` pins the destination and the forced command `/bin/false` ends any session that asks for a shell.
- He sees the host through a snapshot. A systemd user timer writes `~/caesar-host-stats/snapshot.json` every minute, and the container reads it from `/host-stats`.
- The source reaches the box as a `git archive` streamed over SSH from the Mac, and the image is built there.

| File | Purpose |
|---|---|
| `caesar` | The Mac-side CLI behind `vinceworks caesar` |
| `host/caesar-host` | The host-side script the CLI calls over SSH |
| `caesar.container` | The quadlet for Caesar's container |
| `host/host-snapshot` | Writes the host snapshot |
| `host/caesar-host-snapshot.service` and `.timer` | The systemd user units that run it every minute |

## Setting it up (once)

### In the Tailscale admin console

The policy grants access to named devices. The box is registered as one of my own devices and the sandbox's traffic leaves through it, so a grant to my user would also let the coding agents in the sandbox reach Caesar as me.

1. Add `tag:caesar` to `tagOwners`.
2. Add a host alias for the Mac and for each iPhone, one alias per device.
3. Grant those aliases `tcp:443` to `tag:caesar`:

   ```json
   "hosts": {
     "josh-mac": "<the Mac's tailnet address>",
     "josh-iphone": "<the iPhone's tailnet address>"
   },
   "tagOwners": { "tag:caesar": ["autogroup:admin"] },
   "grants": [{ "src": ["josh-mac", "josh-iphone"], "dst": ["tag:caesar"], "ip": ["tcp:443"] }]
   ```

4. Make sure HTTPS certificates are enabled for the tailnet (DNS page). Enabling HTTPS puts Caesar's device name in public certificate logs, so the name is public and the policy is the access control.
5. Create an auth key (Settings, Keys): single-use, pre-approved, ephemeral off, tagged `tag:caesar`. `setup` asks for it.

### On the box and the Mac

1. Pull vinceworks on the box (`git -C ~/vinceworks pull`). The host-side scripts and units run from that checkout.
2. Start the sandbox once (`vinceworks sandbox up`), so its sshd has generated its host key.
3. Export `OPENCODE_API_KEY` in the shell on the Mac. `setup` uses `CAESAR_OPENCODE_API_KEY` instead when it is set, which gives Caesar an OpenCode key of his own.
4. Run:

   ```sh
   vinceworks caesar setup
   vinceworks caesar setup --force                                  # rewrite secrets.env and a staged auth key
   vinceworks caesar setup --tailscale-authkey-file ~/caesar.key    # read the auth key from a file
   ```

`setup` is safe to re-run and prints `[ok]` for what it did and `[skip]` for what was already in place. On the box it:

- creates `~/caesar-data` (0700), `~/caesar-data/ssh` (0700) and `~/caesar-host-stats`;
- installs the quadlet into `~/.config/containers/systemd` and the snapshot units into `~/.config/systemd/user`, then enables the snapshot timer;
- generates the tunnel key if it is missing, and appends it to the sandbox's `authorized_keys` as `restrict,port-forwarding,permitopen="127.0.0.1:6767",command="/bin/false" ssh-ed25519 <key> vinceworks:caesar-tunnel`;
- writes `known_hosts` from the sandbox sshd's host key;
- writes `secrets.env` from the Mac's `$CAESAR_OPENCODE_API_KEY`, or `$OPENCODE_API_KEY` when that is unset, when the file is missing or with `--force`;
- asks on the Mac for the Tailscale auth key (a silent prompt) while Caesar is unregistered, and stages it as `tailscale-authkey`. Secrets travel on ssh's stdin, so they stay out of the process lists on both machines.

When a start fails to register him, the entrypoint keeps `tailscale-authkey` for the next start. Replace a bad key with `vinceworks caesar setup --force`, then `vinceworks caesar deploy` to restart him. To register him from scratch, remove `~/caesar-data/tailscale` on the box and run `setup` and `deploy` again.

## Deploying

```sh
vinceworks caesar deploy          # main
vinceworks caesar deploy <ref>    # any branch, tag or commit
```

`deploy` takes the ref from the local caesar repo (`~/projects/caesar`, or `CAESAR_LOCAL`) and checks it exists. It streams `git archive` of that ref into `~/caesar-src.new` on the box and swaps that into `~/caesar-src`. Then it runs `podman build -t localhost/caesar:latest ~/caesar-src`, reloads systemd and restarts the unit. Only committed files are shipped. It prints the short SHA it deployed.

The first deploy is also Caesar's first start: the entrypoint registers him on the tailnet with the staged auth key and deletes the key file. He then answers at `https://caesar.<tailnet>.ts.net` from the Mac and the iPhones.

`CAESAR_HOST` (default `vince-archive`) changes the SSH host for every command.

## Status and logs

```sh
vinceworks caesar status    # systemctl status, plus tailscale status from inside the container
vinceworks caesar logs      # follow the unit's journal
```

## Caesar's data directory

`~/caesar-data` on the box (0700) is mounted at `/data`:

| Path | Contents |
|---|---|
| `secrets.env` (0600) | `OPENCODE_API_KEY=<value>` |
| `tailscale-authkey` (0600) | The single-use auth key, present until the first registration; the entrypoint deletes it |
| `ssh/id_ed25519` and `.pub` | The tunnel key, generated on the host |
| `ssh/known_hosts` | One line, `vinceworks-sandbox <the sandbox sshd's ed25519 host key>`; the entrypoint connects with `HostKeyAlias=vinceworks-sandbox` |
| `tailscale/` | Tailscale's state, created by the entrypoint |

Caesar's own state (database, transcripts and knowledge base) is written under the same directory.

## The host snapshot

`host/host-snapshot` writes `snapshot.json` to a temporary file and renames it into place, so a reader always sees a whole file. `host-snapshot --print` writes the same JSON to stdout. It holds:

- `timestamp` (UTC), `uptime_seconds`, `cpu_count` and `load_average`;
- `memory`: total, available and swap, in bytes, from `/proc/meminfo`;
- `disk`: total, used and available bytes for `/` and `/home`;
- `top_by_rss` and `top_by_cpu`: ten processes each, with pid, user, command name, RSS in bytes and `cpu_percent` over a one second sample (a share of one core, so it can exceed 100);
- `containers`: `podman stats --no-stream --format json` for my containers, or `null` when the podman call fails.
