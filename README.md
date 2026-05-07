# Vinceworks

Personal dotfiles and tooling, managed via symlinks so changes sync across machines through git.

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
**Run on an existing machine** to pick up changes from the repo — installs any new Homebrew packages and creates symlinks for any new dotfiles. Skips anything already in place.

```sh
vinceworks:update
vinceworks:update --force   # also overwrite existing symlinks
```

---

### `vinceworks:ai`
Sets up AI tooling and syncs agents. Installs Claude Code and OpenCode if not already present, then symlinks all agent definitions from `ai/agents/` into `~/.claude/agents/` and `~/.opencode/agents/` so they're available globally across all projects. Re-run whenever you add a new agent.

```sh
vinceworks:ai
vinceworks:ai --force   # replace existing agents or wrong-target symlinks
```

To add a new shared agent, drop a `.md` file into `ai/agents/` and re-run `vinceworks:ai`.

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
