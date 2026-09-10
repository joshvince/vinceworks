# Vinceworks sandbox: a remote dev environment for automatic programming

The sandbox is my remote development environment for all personal projects. It runs on my home server (a box behind my TV). It's a big podman container where I can let AI agents loose with a little more security than if I had them roaming around my own laptop. I use it for [automatic programming](https://antirez.com/news/159) aka vibecoding. 

## How is it put together?
I wouldn't call it simple, but it is straightforward.  

- I copy over git repos I am working on to the linux box
- Podman runs a single rootless container on the box containing a development environment and AI agent harnesses. I mount the git repos into this container.
- I have a [paseo](https://paseo.sh/) daemon running inside the container, which gives me a Paseo Host I can connect to
- This means I can start an agent chat session, running on a git worktree, and the agent is working inside the container.
- There is a narrow band of ports exposed from this container. Web applications started in the container can be exposed to the outside using this range of ports.
- I access the Paseo host or any of the ephemeral dev applications from a node in my tailnet like my phone or my laptop, meaning I can start ideas on my laptop and pick them up on my phone, and vice versa, while an agent does the real work.


## Cool, but why?
I want to go further into fully [automatic programming](https://antirez.com/news/159), running lots of agents with a lot of latitude, to see what I can achieve with it - I am a father of two young children, and often have ideas I cannot dedicate time at a computer to work on. Giving agents that much latitude on my personal device didn't sit right, and I have had this linux box behind my TV (serving personal web apps) for years now, so this felt like a perfect use of the extra compute.

It's not **safe** as such, but it is a lot safer than doing this stuff on my own laptop where I keep most of my digital life.

## `vinceworks` cli

I put together a simple command line interface to manage this, so I can run things like `vinceworks sandbox push` to move a project to the sandbox, or `vinceworks sandbox ps` to see what is currently running and how to access any web servers on the box. 

There are also fairly simple scripts to handle things like new worktrees being instantiated, and I am using `tmux` to be able to attach and detach into things without needing Paseo as the bridge.


## Paseo

[Paseo](https://paseo.sh/docs) is a very cool open source project that lets you easily run multiple git-worktree-based agent sessions. It has a nice UX and the killer app for me is the ability to use multiple hosts. It is the bridge between a machine (like my phone) and this podman container.  

Paseo lets you create a worktree for a session, and those worktrees end up inside the sandbox conatiner under `~/.paseo/worktrees`. 

To achieve this, each of the projects I am working on has its own `paseo.json` at the root of the repo. Here is an example:

```json
{
  "worktree": {
    "setup": "~/vinceworks/sandbox/checkout-setup \"$PASEO_WORKTREE_PATH\""
  }
}
```

`worktree.setup` runs whenever paseo creates a new git worktree. The `sandbox/checkout-setup` script in this repo copies over some gitignored env-related files that a typical app needs to run in development (for instance, the `.env` file) from the main checkout into the new worktree, never overwriting anything already there, and then calls `sandbox/alloc-port`. 

`alloc-port` picks a port within my specified range that is free according to both `ss -ltn` and every other checkout's `.env`, and writes it into the worktree's `.env` as `PORT`. It is safe to run more than once. A port that is already in range is left alone, so a running app never has its port moved. A port outside the range is replaced, and the replacement is logged. The `.env` files under `~/projects` and `~/.paseo/worktrees` are the record of which ports are taken. Deleting a worktree frees its port, and there is no separate state file that could fall out of sync.

Hooks do plumbing only: they copy secrets and SQLite files from the main checkout, and nothing more. No `bundle install` and no application code belongs in a hook.

# Setting it up

Here's what the clanker wrote on how to set it up, if I ever have to do it again.

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

7. Add the sandbox as a host in Paseo Desktop on the Mac, via "Remote SSH":

```
ssh://josh@vince-archive.tail1d48f4.ts.net:2222
```

## First boot (once)

1. `vinceworks tmux` to get a shell inside the sandbox.
2. `gh auth login --with-token` with the fine-grained PAT (Contents read/write, Pull requests read/write, Metadata read, personal repos only).
3. `gh auth setup-git` so git uses the token over HTTPS.
4. `claude` to log in to Claude Code.
5. Copy `~/.paseo/config.json` from the Mac into `~/.paseo/` in the sandbox.

## tmux

tmux inside the sandbox is configured by [`sandbox/tmux.conf`](tmux.conf). `vinceworks tmux` attaches the `main` session.
