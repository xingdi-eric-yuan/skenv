# skenv

**virtualenv for AI coding skills.** Different projects need different skills — skenv lets you swap entire skill sets in one command, just like Python's `venv` swaps packages.

```bash
skenv create research --copilot       # create a skill environment
skenv install ~/skills/deep-reading   # add skills to it
skenv activate research               # your AI agent now sees only these skills

skenv activate webdev                 # switch — instant clean swap
```

Works with **Claude Code** (`~/.claude/skills/`) and **GitHub Copilot CLI** (`~/.copilot/skills/`).

---

## Quick Start

```bash
# Install
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/.local/bin/skenv
chmod +x ~/.local/bin/skenv
export PATH="$HOME/.local/bin:$PATH"  # add to shell rc to persist

# Create, populate, activate
skenv create myenv --copilot          # or omit flag for claude (default)
skenv activate myenv                  # backs up existing skills on first run
skenv install ~/my-skills/python-research
skenv install ~/my-skills/react --link    # symlink: stays in sync with source

# Switch environments
skenv create webdev --copilot
skenv activate webdev                 # clean swap — only webdev skills visible
```

---

## Why skenv?

AI coding agents discover skills from a single directory. When you work across projects — research, web apps, infra — you need different skill sets, but there's no built-in way to swap them.

**skenv** manages named skill environments. Activating one does a clean swap of the agent's skill directory. You get:

- **Per-project skill sets** — `cd` into a project directory and the right skills activate automatically
- **Instant switching** — one command to swap everything
- **Base layer** — always-on skills shared across all environments
- **Inheritance** — extend environments without duplicating skills
- **Packages & hooks** — install skill packages with lifecycle hooks in one step

---

## Installation

**Direct download:**

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/.local/bin/skenv
chmod +x ~/.local/bin/skenv
```

**Or clone:**

```bash
git clone https://github.com/xingdi-eric-yuan/skenv.git ~/.skenv-repo
ln -sf ~/.skenv-repo/skenv ~/.local/bin/skenv
```

Ensure `~/.local/bin` is on your `$PATH`, then run `skenv help` to verify.

### Shell integration (recommended)

Add to `~/.zshrc` or `~/.bashrc` (after oh-my-zsh if applicable):

```bash
eval "$(skenv hook zsh)"          # auto-activate + prompt
eval "$(skenv completion zsh)"    # tab completion
```

This enables:
- **Auto-activation** — drop a `.skenv` file in a project dir, skenv activates on `cd`
- **Prompt indicator** — shows `[skenv:copilot:myenv]` when active
- **Tab completion** for all commands

To show the prompt, add `$(_skenv_prompt)` to your `$PROMPT`:

```bash
# oh-my-zsh (after source $ZSH/oh-my-zsh.sh)
PROMPT='$(_skenv_prompt)'"$PROMPT"
```

---

## How It Works

```
~/.skenv/
├── .active-claude              which claude env is active
├── .active-copilot             which copilot env is active
├── .base/                      always-on skills (shared across envs)
├── research/                   an environment
│   ├── .platform               "copilot"
│   ├── python-research/SKILL.md
│   └── latex-paper/SKILL.md
└── webdev/
    ├── .platform               "claude"
    └── react-patterns -> ~/skills/react

~/.copilot/skills/              agent reads from here (symlinks managed by skenv)
├── always-zsh -> ~/.skenv/.base/always-zsh
└── python-research -> ~/.skenv/research/python-research
```

On `activate`, skenv wipes the agent's skill directory and symlinks: base layer → parent envs → active env. Only one env per platform is active at a time.

---

## Platform

Each environment targets one platform, set at creation:

```bash
skenv create my-env               # claude (default) → ~/.claude/skills/
skenv create my-env --copilot     # copilot → ~/.copilot/skills/
```

You can have one claude env and one copilot env active simultaneously. The platform is locked at creation.

---

## Commands

### Environments

| Command | Description |
|---------|-------------|
| `create <name> [--claude\|--copilot] [--from <env>]` | Create environment |
| `activate [-y] <name>` | Activate (clean swap) |
| `deactivate [--claude\|--copilot]` | Deactivate (no flag = all) |
| `list` | List environments |
| `status` | Show what's active |
| `clone <src> <dst>` | Deep-copy environment |
| `delete <name>` | Delete environment |
| `diff <a> <b>` | Compare two environments |

### Skills

| Command | Description |
|---------|-------------|
| `install <path> [--env N] [--link]` | Add a skill (copy or symlink) |
| `uninstall <name> [--env N]` | Remove a skill |
| `ls [name]` | List skills in environment |
| `install-package <path> [--env N] [--link]` | Install skill package (skills + hooks) |

### Hooks

| Command | Description |
|---------|-------------|
| `hooks apply [pkg] [--project <dir>]` | Apply hooks to a project |
| `hooks remove <pkg> [--project <dir>]` | Remove hooks from a project |
| `hooks list [--env <name>]` | List installed hook packages |

### Base Layer

| Command | Description |
|---------|-------------|
| `base install <path> [--link]` | Add always-on skill |
| `base uninstall <name>` | Remove always-on skill |
| `base ls` | List always-on skills |

### Advanced

| Command | Description |
|---------|-------------|
| `inherit <child> <parent>` | Inherit skills (same platform) |
| `freeze [name]` / `init <name> --from <file>` | Export/import manifest |
| `run <env> -- <cmd...>` | Temporary activation for one command |
| `registry add\|remove\|list` | Named skill shortcuts |
| `hook [bash\|zsh]` / `completion [bash\|zsh]` | Shell integration scripts |

---

## Key Concepts

**Linked vs copied:** `--link` symlinks to source (stays in sync, good for development). Default copies (self-contained). `skenv ls` shows `(linked)` and `(outdated)` indicators.

**Packages:** A directory with `skills/` and optionally `hooks/`. One command installs everything:

```bash
skenv install-package ~/ShadowFrog --link
```

**Hooks:** Skills are user-global; hooks are project-scoped. Apply them per-project:

```bash
cd ~/projects/my-app && skenv hooks apply
```

Hooks merge into the project's config (`.github/hooks/hooks.json` for Copilot, `.claude/settings.json` for Claude). Multiple packages coexist; each is tagged for clean removal.

**Inheritance:** `skenv inherit child parent` — child sees parent's skills plus its own.

**Auto-activation:** `echo "research" > .skenv` in a project dir — skenv activates on `cd`.

**Registry:** `skenv registry add react ~/skills/react` — then `skenv install react`.

**Freeze/init:** `skenv freeze > env.manifest` exports; `skenv init new --from env.manifest` recreates.

---

## FAQ

**What happens to my existing skills?**
First `activate` backs them up to `_pre-skenv-<platform>` (after confirmation). Activate that env to restore.

**Does it work on Linux?**
Yes. Pure bash 3.2+, no dependencies.

**Can environments share skills?**
Three ways: base layer (always-on), inheritance, or `--link` to a shared source.

---

## License

MIT
