# Vinceworks

This is a repo handling most of what I need to develop software. It started as a classic dotfiles repo, but has grown in ambition with the advent of [automatic programming](https://antirez.com/news/159) aka vibecoding.  

The repo now houses a broad CLI-esque program that I can use to:

- setup a new or sync dev machines with my preferred dev tool settings, including terminals, AI harnesses etc
- maintain 'agent definitions' or system prompts I use when writing code with AI
- run a 'remote' sandbox on my home server that gives agents a sandboxed environment to do the heavy lifting on my own projects


## Commands

### `vinceworks:dev-machine-setup`
**Run once on a fresh machine.** Asks which terminal to install (iTerm2 or Ghostty), then installs Homebrew, all packages from the Brewfile, shell tools (oh-my-zsh, Powerlevel10k, nvm), and wires up all dotfiles as symlinks. On a brand new machine, run the script directly since the alias won't exist yet:

```sh
git clone <this-repo> ~/vinceworks
cd ~/vinceworks
./dev-machine-setup.sh
```

After it completes, open a new shell and run `p10k configure` to set up your prompt theme.

---

### `vinceworks:update`
**Run on an existing machine** to pick up changes from the repo — creates symlinks for any new dotfiles and copies any new fonts. Skips anything already in place. Homebrew is left untouched unless you ask for it.

```sh
vinceworks:update
vinceworks:update --force      # also overwrite existing symlinks
vinceworks:update --packages   # also run brew bundle for missing packages
```

---

### `vinceworks:ai`
Sets up AI tooling and syncs agents and skills. Installs Claude Code and OpenCode if not already present, then symlinks all agent definitions from `ai/agents/` into `~/.claude/agents/` and `~/.opencode/agents/`, and all skill directories from `ai/skills/` into `~/.claude/skills/` and `~/.config/opencode/skills/`, so they're available globally across all projects. Re-run whenever you add a new agent or skill.

```sh
vinceworks:ai
vinceworks:ai --force   # replace existing agents/skills or wrong-target symlinks
```

To add a new shared agent, drop a `.md` file into `ai/agents/` and re-run `vinceworks:ai`.

To add a new shared skill, drop a `<skill-name>/SKILL.md` directory into `ai/skills/` and re-run `vinceworks:ai`.

---

### `vinceworks sandbox`
One rootless Podman container, `vinceworks-sandbox`, on the home Ubuntu box, holding every personal project checkout, Postgres, tmux and Claude Code. `vinceworks sandbox up` starts it, `vinceworks sandbox rebuild` rebuilds the image, and `vinceworks sandbox push <repo> <paths...>` copies secret files in. Paseo Desktop on the Mac is the primary way in, reachable from outside the home network over Tailscale, with `vinceworks tmux` as the escape hatch when you want a shell directly. The `vinceworks` command lives at the repo root and also wraps `update`, `ai` and `dev-machine-setup`. See [sandbox/README.md](sandbox/README.md).

---

## What's managed

| File | Purpose |
|---|---|
| `.zshrc` / `.zshenv` | Zsh shell config |
| `.gitconfig` / `.gitmessage.txt` / `.gitignore_global` | Git config |
| `.macosdefaults.sh` | macOS system preferences |
| `Brewfile` | Homebrew packages |
| `.shortcuts` | Public shell aliases (checked in) |
| `.shortcuts.private` | Private/sensitive aliases (gitignored, local only) |

### Shortcuts

`.shortcuts` is for shareable aliases. `.shortcuts.private` is for anything sensitive (server IPs, credentials, etc.) — it's gitignored and never leaves the machine. Both are sourced automatically by `.zshrc`.
