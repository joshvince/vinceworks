# sandbox: one remote dev environment for every project

`sandbox` is a single rootless Podman container, `vinceworks-sandbox`, running on the home Ubuntu box (`vince-archive`). It holds every personal project checkout, a Postgres server, tmux and Claude Code. It behaves like a second laptop: agents run inside it with a lot of autonomy, using Paseo worktrees to work on several things at once and opening PRs that are reviewed and deployed from the Mac. It is reachable from anywhere, not just the home network. Paseo Desktop and the Paseo mobile app connect in to control agents, and Tailscale makes the dev servers running inside it reachable from the Mac or phone when away from home.

There is one container, not one per project. The per-project setup in the old `projects/` directory caused nearly all of the complexity: a port mapper, a secrets directory per project, a Postgres volume per project, detection of stale ssh-agent sockets, and shims to route a host-level Paseo daemon into the right container. It also meant one project's container could not see another project's checkout, which was awkward when projects depended on each other. Isolating projects from each other was never the goal. A single stable machine with far fewer moving parts serves the real goal better.

The container boundary exists for one reason: production shares the box (`postcard` and its Postgres on host loopback 5432, nginx, Filebrowser). The sandbox has its own network namespace, no host network, no Docker socket and no volumes shared with production. Agents running inside it cannot reach production.

## Commands

All run on the Mac.

```sh
vinceworks sandbox up                     # start the sandbox, building it first if needed
vinceworks sandbox rebuild                # rebuild the image and restart the sandbox
vinceworks sandbox status                 # show systemd status for the sandbox
vinceworks sandbox push <url|name> [paths...] # clone a repo into the sandbox if needed and copy its secret files in
vinceworks sandbox ps                     # list worktrees, their ports and what is listening
vinceworks tmux                               # ssh in and attach the "main" tmux session
```

`ps` shows what is actually listening in the published port range and which checkout each server runs from. Every row it lists is reachable from the Mac, whether the app was started by Paseo's `server` script or by hand in tmux. A server started by hand on the default port 3000 shows up as `unpublished` and cannot be reached from the Mac, because 3000 belongs to production on the host. Any checkout that has been through `checkout-setup` or `alloc-port` already has a published `PORT` in its `.env`, and `bin/dev` picks it up on its own. So the fix for an `unpublished` row is to run `sandbox/alloc-port <dir>` against that checkout, not to set the port by hand on the command line.

`push` clones the repo for you, so there is no need to clone a new one by hand first. If you would rather clone from inside the sandbox, run this over `vinceworks tmux` or in a Paseo session:

```sh
gh repo clone owner/repo ~/projects/repo
```

## Paseo

Add the sandbox as a host in Paseo Desktop on the Mac, via "Remote SSH":

```
ssh://josh@vince-archive.tail1d48f4.ts.net:2222
```

Paseo Desktop runs `ssh` with this exact address, not through a `~/.ssh/config` alias. So `~/.ssh/config` needs a `Host` block that matches this exact hostname and sets the right `IdentityFile`; the `vinceworks-sandbox` alias used elsewhere is not enough on its own. The Tailscale hostname works both at home and away; the LAN IP only worked at home.

The Paseo mobile app has no "Remote SSH" option. It offers only relay pairing (by QR code or link, from this host's Settings → Pair Device in Desktop) or a raw TCP direct connection. Relay is what puts agent control on the phone. It does not carry the preview-port traffic described below; for that, the phone needs to be on the same tailnet.

Worktrees live under `~/.paseo/worktrees` in the sandbox. Each repo that wants worktree support commits its own `paseo.json` at the root of the repo. Here is vincetagram's:

```json
{
  "worktree": {
    "setup": [
      "~/vinceworks/sandbox/checkout-setup \"$PASEO_WORKTREE_PATH\""
    ]
  },
  "scripts": {
    "server": { "type": "service", "command": "bin/dev" }
  }
}
```

`worktree.setup` is a single line that hands off to vinceworks. `sandbox/checkout-setup <worktree> [source-checkout]` copies `.env`, `config/master.key` and `config/credentials/*.key` from the main checkout into the new worktree, never overwriting anything already there, and then calls `sandbox/alloc-port`. When the source checkout is left out, as it is here, the script works it out from git, so Paseo only has to supply `$PASEO_WORKTREE_PATH`.

`alloc-port` picks a port that is free according to both `ss -ltn` and every other checkout's `.env`, and writes it into the worktree's `.env` as `PORT`. It is safe to run more than once. A port that is already in range is left alone, so a running app never has its port moved. A port outside the range is replaced, and the replacement is logged. The `.env` files under `~/projects` and `~/.paseo/worktrees` are the record of which ports are taken. Deleting a worktree frees its port, and there is no separate state file that could fall out of sync.

`scripts.server` needs no `PASEO_PORT` prefix, because `.env` already holds `PORT`. Plain `bin/dev` lands on the allocated port whether Paseo started it or an agent typed it in tmux. The port allocation logic lives in vinceworks rather than in `paseo.json`, so swapping Paseo for another worktree tool means changing only the one setup line above.

Hooks do plumbing only: they copy secrets and SQLite files from the main checkout, and nothing more. No `bundle install` and no application code belongs in a hook.

## Secrets

`vinceworks sandbox push <url|name>` refuses to run if `~/projects/<name>` already exists in the sandbox, so it never overwrites a checkout or its secrets. Otherwise it clones the repo, then copies `.env`, `config/master.key` and `config/credentials/*.key` from `~/projects/<name>` on the Mac, if that folder exists. To copy other files too, such as SQLite databases, pass their repo-relative paths. Giving a bare name uses that Mac folder's `origin` URL; giving a URL works without any local checkout. To update a secret in an existing checkout, `scp` it by hand to `vinceworks-sandbox:projects/<name>/<path>`. Never push the production `.env`.

The repo's `worktree.setup` hook then copies the pushed files from the main checkout into every new worktree.

## Host prerequisites (once)

On the box:

1. `id josh` should report uid 1000. Either way, the build passes the real uid and gid in as build args.
2. Rootless Podman needs three things: `podman` itself installed; a range for `josh` in each of `/etc/subuid` and `/etc/subgid` (the default `josh:100000:65536` is already there and is fine); and lingering enabled for `josh` with `sudo loginctl enable-linger josh`. Lingering is not optional. Without it, systemd shuts down the user manager as soon as the last SSH session for `josh` closes, and the container goes down with it.
3. `mkdir -p ~/vinceworks-sandbox` and clone vinceworks to `~/vinceworks`.

On the Mac:

4. Join the box and the Mac to the same Tailscale tailnet (and the phone too, if you want the preview ports on it). In the tailnet's Access Controls, replace the default "allow all" starter policy rather than adding a grant next to it. Tailscale ACLs are allow lists, so as long as the starter policy is there, every port on every device stays reachable, production's included. Restrict tailnet peers to only `vince-archive:2222` and `vince-archive:4100-4199`.

5. Add a `vinceworks-sandbox` entry to `~/.ssh/config`. Use the Tailscale hostname so it works both at home and away:

   ```
   Host vinceworks-sandbox
       HostName vince-archive.tail1d48f4.ts.net
       Port 2222
       User josh
       IdentityFile <same IdentityFile as your vince-archive entry>
   ```

   Paseo Desktop's "Remote SSH" dialog runs `ssh` with the hostname exactly as typed, not through this alias, so add a second block that matches that exact hostname too:

   ```
   Host vince-archive.tail1d48f4.ts.net
       User josh
       IdentityFile <same IdentityFile as your vince-archive entry>
       IdentitiesOnly yes
   ```

6. Add the same `ControlMaster auto`, `ControlPath ~/.ssh/cm-%r@%h:%p` and `ControlPersist 10m` lines that speed up `vince-archive` under both new blocks too, so repeated connections are instant.

## First boot (once)

1. `vinceworks tmux` to get a shell inside the sandbox.
2. `gh auth login --with-token` with the fine-grained PAT (Contents read/write, Pull requests read/write, Metadata read, personal repos only).
3. `gh auth setup-git` so git uses the token over HTTPS.
4. `claude` to log in to Claude Code.
5. Copy `~/.paseo/config.json` from the Mac into `~/.paseo/` in the sandbox.

## tmux

tmux inside the sandbox is configured by [`sandbox/tmux.conf`](tmux.conf). `vinceworks tmux` attaches the `main` session.
