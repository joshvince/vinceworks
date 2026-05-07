# vinceworks

Personal dotfiles and tooling, managed via symlinks so changes sync across machines through git.

## New machine setup

```sh
git clone <this-repo> ~/vinceworks
cd ~/vinceworks
./setup.sh
```

The script will first ask which terminal to install (iTerm2 or Ghostty), then work through the rest of the setup. It skips anything already installed and skips symlinks that already exist at the destination.

To reinstall apps and overwrite existing symlinks:

```sh
./setup.sh --force
```

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

## AI agents (`ai/`)

Shared agent definitions for Claude Code and OpenCode, defined once and symlinked into projects.

### Defining agents

Add `.md` files to `ai/agents/`. Each file is an agent definition in the format expected by Claude Code / OpenCode.

### Linking agents into a project

From any project directory:

```sh
link-agents
```

This creates symlinks in `.claude/agents/` and `.opencode/agents/` pointing back to the definitions here, and adds a `.gitignore` block so the symlinks aren't accidentally committed.

```sh
link-agents --force   # replace existing files or wrong-target symlinks
```

`link-agents` is safe to re-run — it skips anything already correct.
