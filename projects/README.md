# projects: per-project remote dev environments

Each project gets its own development environment: one Docker container on the home Ubuntu box (`vince-archive`), with the repo, language toolchain, database, tmux and Claude Code inside. From the Mac, two commands do most of the work:

```sh
vinceworks projects new joshvince/vincetagram   # clone, build, start, attach
vinceworks projects vincetagram                 # attach to a running one
```

The production services already on the box (vincetagram as `postcard`, Filebrowser, nginx) are untouched. They own host ports 80, 443, 3000, 5432 and 8080, and the port mapper below never allocates those.

## How it fits together

- **One image for everything.** Ubuntu 24.04 plus build tools, `mise`, tmux, zsh, a Postgres server and Claude Code. Language versions come from each repo's own files (`.ruby-version`, `.node-version`, `.tool-versions`, `.go-version`, `go.mod`) at container start.
- **One long-lived container per project**, named `project-<name>`, with the repo bind-mounted at `/home/josh/projects/<name>`. The path is the same inside and outside the container.
- **Plain `docker run` from a bash script**, not compose. Every container is the same shape except for name, path and port.
- **Postgres runs inside the container** and is never published to the host. Rails' default development config uses the Unix socket and the OS user, so most apps need no database config at all. Data lives in a per-project volume.
- **tmux inside the container** holds your sessions. Detach and everything keeps running.
- **Shared volumes:** `projects-mise` (Ruby, Node and Go installs plus gems, so a compiled Ruby is reused by every project), `projects-claude` (`~/.claude`, one login for all projects) and `projects-go`. Each project also gets `project-<name>-pg` for its database.
- **Git works** through the box's ssh-agent. `start` loads a dedicated passphrase-less key, `~/.ssh/projects_ed25519`, into keychain and passes only the agent socket into the container. Containers never see the private key, so a coding agent inside cannot copy it. `gh` is installed and shares one login across containers via the `projects-gh` volume.
- **Connecting** is SSH to the host, then `docker exec` into the container and attach tmux. There is no sshd inside containers. The box is reachable on the home LAN only for now; Tailscale is parked in `TODO.md`.

## Commands

All run on the Mac. Each one is a single SSH call to the host script.

```sh
vinceworks projects <name> [session]            # attach (session defaults to "main")
vinceworks projects new <owner/repo> [name]     # clone, allocate a port, build image if needed, start, attach
vinceworks projects ls                          # name, status, host port, services, repo, secrets present
vinceworks projects stop <name>
vinceworks projects rm <name>                   # removes the container only; repo, secrets, database survive
vinceworks projects rm <name> --purge           # also deletes repo, state, database volume and port registry line
vinceworks projects rebuild [name]              # rebuild the image, recreate the container(s)
vinceworks projects secrets <name> <relpath>... # scp files from ~/projects/<name> on the Mac into the host secrets dir, then restart
vinceworks projects open <name>                 # open http://vince-archive:<port> in the browser
vinceworks projects sync                        # git pull vinceworks on the host after you push tooling changes
```

## Port mapper

Every app listens on port 3000 inside its own container. The host script maps one host port per project:

- Registry: `/home/josh/.projects/ports`, one line per project, `<name> <host-port>`.
- Reserved and never allocated: 80, 443, 3000, 5432, 8080, plus any lines in `/home/josh/.projects/ports.reserved`.
- Allocation starts at 4100 and steps by 10. It skips reserved ports, anything already in the registry, and anything `ss -ltn` shows bound on the host. The first free port wins.
- `start` re-checks the port with `ss -ltn` immediately before `docker run` and aborts if something else has taken it. Docker refuses a bound port too, so production can never be displaced.
- Only `<host-port>:3000` is published. Postgres and anything else inside the container stays private.

## Secrets

Files that are not in git (`config/master.key`, `.env`) live on the host in `/home/josh/.projects/<name>/secrets/` using repo-relative paths. The directory is mounted read-only into the container, and the entrypoint copies each file into the repo on every start. Push them from the Mac:

```sh
vinceworks projects secrets vincetagram config/master.key .env
```

Use a development-only `.env`. Never copy the production one.

## Files

```
vinceworks            top-level CLI at the repo root; `vinceworks projects ...` forwards here
projects/
  README.md           this file
  projects            Mac-side CLI
  Dockerfile          the generic image
  entrypoint.sh       runs on every container start
  tmux.conf           copied to ~/.tmux.conf in the image
  zshrc               small container-only zshrc
  host/projects-host  host-side implementation, runs on the Ubuntu box
```

Host state outside git:

```
/home/josh/projects/<name>/              the repo
/home/josh/.projects/<name>/config       REPO=, PORT=, SERVICES=
/home/josh/.projects/<name>/secrets/     repo-relative secret files
/home/josh/.projects/ports               port registry
/home/josh/.projects/ports.reserved      optional extra reserved ports
```

## What happens on container start

1. Copy secrets into the repo.
2. Copy `.gitconfig`, `.gitmessage.txt` and `.gitignore_global` from vinceworks, dropping the macOS credential helper.
3. Point `gh` at SSH for git operations.
4. Start Postgres and create a superuser role for `josh` if the project uses it (auto-detected from the Gemfile on `new`).
5. `mise install` in the repo. The first Ruby compile takes 10 to 20 minutes and is cached in the shared volume after that. Node and Go are prebuilt and take seconds.
6. Run vinceworks' `ai.sh` so Claude Code has the shared agents and skills.
7. Create the tmux session `main` with windows `claude`, `server` and `shell`, then idle.

## tmux in five minutes

The prefix is Ctrl+a, written `C-a` below.

- A **window** is a tab. `C-a c` creates one, `C-a 1` to `C-a 9` jump, `C-a ,` renames, `C-a &` kills.
- A **pane** is a split inside a window. `C-a |` splits right, `C-a -` splits below, `C-a` plus an arrow key moves, `C-a x` kills.
- A **session** is a whole workspace. `main` is created for you. `vinceworks projects <name> scratch` from the Mac creates or attaches a second session called `scratch`. Inside tmux, `C-a s` lists sessions to switch between.
- `C-a d` detaches. Nothing stops.

```
C-a d        detach, everything keeps running     vinceworks projects <name>       reattach
C-a c        new window                            C-a 1..9                         jump to window
C-a n / p    next / previous window                C-a ,                            rename window
C-a |  C-a - split right / split below             C-a arrows                       move between panes
C-a x        kill pane                             C-a &                            kill window
C-a s        pick a session                        vinceworks projects <name> foo   new or existing session foo
C-a [        scroll mode, q to quit                mouse                            click, scroll, resize
C-a r        reload config                         tmux ls                          list sessions
```

## Host prerequisites (once)

On the box:

1. `id josh` should report uid 1000. The build passes the real uid and gid as build args either way.
2. `groups josh` should include `docker`.
3. `mkdir -p /home/josh/projects /home/josh/.projects` and clone vinceworks to `/home/josh/vinceworks`.
4. Create the GitHub key: `ssh-keygen -t ed25519 -N '' -C 'vince-archive projects' -f ~/.ssh/projects_ed25519`, then add `~/.ssh/projects_ed25519.pub` at github.com/settings/keys. `start` loads it into keychain automatically.
5. Save the output of `ss -ltn` as the baseline of production ports.

On the Mac:

6. Add `ControlMaster auto`, `ControlPath ~/.ssh/cm-%r@%h:%p` and `ControlPersist 10m` under `Host vince-archive` in `~/.ssh/config` so repeated calls are instant.

## Gotchas

- The first Ruby compile per version is slow. Logs stream during `new` so it does not look hung.
- Ruby 3.1 and newer build against OpenSSL 3 on Ubuntu 24.04. Older Rubies would need extra work.
- `ubuntu:24.04` ships an `ubuntu` user at uid 1000. The Dockerfile removes it so `josh` can take that uid.
- If a named volume ends up root-owned: `docker run --rm -v projects-claude:/v alpine chown -R 1000:1000 /v`.
- Only `known_hosts` and the agent socket enter the container. If `git` inside a container says permission denied, check `ssh-add -l` on the box shows `projects_ed25519` and that the public key is on GitHub. Deleting the key on GitHub revokes the box instantly.
- Rails 7.1 and newer block unknown hostnames in development. The container sets `RAILS_DEVELOPMENT_HOSTS` to cover `vince-archive` and the box's hostname.
- Two containers running `bundle install` for the same Ruby at the same time can race on the shared gem directory. Rerun if it happens.
- tmux state does not survive a container restart. The entrypoint recreates the three windows; running processes are gone.
- One Postgres per container is a dev-only model. Add sidecar containers to `start` if a project needs Redis or a pinned Postgres version.
