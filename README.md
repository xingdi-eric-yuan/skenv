# skenv

**virtualenv for AI coding skills.** Manage separate skill sets for Claude Code and GitHub Copilot CLI — switch between them instantly.

```
skenv activate research     # Claude & Copilot see research skills
skenv activate webdev       # now they see webdev skills instead
```

---

## Quick Start

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/bin/skenv
chmod +x ~/bin/skenv

# 2. Create and activate — imports your existing skills automatically
skenv create research
skenv activate research       # asks to backup, then offers to import existing skills

# 3. Create another from an existing environment
skenv create webdev --from research
skenv activate webdev
skenv uninstall python-research   # remove what you don't need
skenv install ~/my-skills/react-patterns

# Switch between them
skenv activate research
```

> **First-time safety:** The very first `skenv activate` asks you to confirm you've backed up your skills, snapshots them into `_pre-skenv`, then offers to import them into your new environment. Use `-y` / `SKENV_YES=1` to skip prompts in scripts.

---

## Why skenv?

Claude Code and Copilot CLI discover skills from folders on disk (`~/.claude/skills/` and `~/.copilot/skills/`). If you work on different kinds of projects, you need different skills — but there's no built-in way to swap them.

**skenv** solves this the same way Python's `venv` solves package management:

- Each environment is **fully isolated** — activating one replaces all skills
- Environments are stored centrally, skills are **copied** (self-contained)
- A **base layer** lets you keep always-on skills across all environments
- Environments can **inherit** from each other to avoid duplication

---

## Installation

### Option A: Direct download

```bash
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/bin/skenv
chmod +x ~/bin/skenv
```

### Option B: Clone and symlink

```bash
git clone https://github.com/xingdi-eric-yuan/skenv.git ~/.skenv-repo
ln -sf ~/.skenv-repo/skenv ~/bin/skenv
```

> Make sure `~/bin` (or wherever you place it) is on your `$PATH`.

### Shell integration (optional but recommended)

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
eval "$(skenv hook zsh)"          # auto-activate + prompt
eval "$(skenv completion zsh)"    # tab completion
```

Replace `zsh` with `bash` if needed. This gives you:

- **Auto-activation:** Put a `.skenv` file in any project directory (containing an env name), and skenv activates it automatically when you `cd` in.
- **Prompt indicator:** Shows `[skenv:research]` in your prompt when an env is active.
- **Tab completion:** Complete commands, environment names, and skill names.

---

## How It Works

```
~/.skenv/                          SKENV_HOME (all envs live here)
|-- .active                        tracks which env is active
|-- .base/                         base layer (always-on skills)
|   `-- always-zsh/
|       `-- SKILL.md
|-- .registry                      name-to-path mappings
|-- _pre-skenv/                    auto-backup of your original skills
|   |-- zsh-shell/
|   `-- my-linter -> ~/tools/custom-skills/my-linter
|-- research/                      an environment
|   |-- python-research/
|   |   |-- SKILL.md
|   |   `-- .skenv-meta
|   `-- latex-paper/
|       `-- SKILL.md
`-- webdev/                        another environment
    |-- react-patterns -> ~/skills/react-patterns   (--link mode)
    `-- react-patterns.skenv-meta

~/.claude/skills/                  Claude Code reads from here
|-- always-zsh -> ~/.skenv/.base/always-zsh
`-- python-research -> ~/.skenv/research/python-research

~/.copilot/skills/                 Copilot CLI reads from here
|-- always-zsh -> ~/.skenv/.base/always-zsh
`-- python-research -> ~/.skenv/research/python-research
```

**On `activate`:** skenv wipes both skill directories, then symlinks: base layer first, then the environment's skills. This is a clean swap — only the active env's skills are visible.

**Layering order** (later wins on name conflict):

```
base layer  ->  parent envs (if inherited)  ->  active env
```

---

## Commands

### Environment management

| Command | Description |
|---------|-------------|
| `skenv create <name> [--from <env>]` | Create a new environment (optionally from existing) |
| `skenv activate [-y\|--yes] <name>` | Activate env — clean swap into skill directories |
| `skenv deactivate` | Remove all symlinks, clear active env |
| `skenv list` | List all environments (`*` = active) |
| `skenv status` | Show which env is currently active |
| `skenv clone <src> <dst>` | Deep-copy an environment |
| `skenv delete <name>` | Delete an environment |
| `skenv diff <a> <b>` | Compare skills between two environments |

### Skill management

| Command | Description |
|---------|-------------|
| `skenv install <path> [--env N] [--link]` | Install a skill (copy or symlink) |
| `skenv uninstall <name> [--env N]` | Remove a skill |
| `skenv ls [name]` | List skills in an env (default: active) |

### Base layer (always-on skills)

| Command | Description |
|---------|-------------|
| `skenv base install <path> [--link]` | Add a skill to the base layer |
| `skenv base uninstall <name>` | Remove a skill from the base layer |
| `skenv base ls` | List base layer skills |

### Advanced

| Command | Description |
|---------|-------------|
| `skenv inherit <child> <parent>` | Child env inherits parent's skills |
| `skenv freeze [name]` | Export env as a manifest file |
| `skenv init <name> --from <file>` | Recreate env from a manifest |
| `skenv run <env> -- <cmd...>` | Run a command with a temporary env |
| `skenv registry add <name> <path>` | Register a skill by name |
| `skenv registry remove <name>` | Unregister a skill |
| `skenv registry list` | Show all registered skills |
| `skenv hook [bash\|zsh]` | Print shell hook for auto-activate + prompt |
| `skenv completion [bash\|zsh]` | Print tab completion script |

---

## Concepts

### Environments

An environment is a named collection of skills stored in `~/.skenv/<name>/`. Only one env is active at a time. Activating an env does a **clean swap** — the skill directories contain _only_ that env's skills (plus the base layer).

```bash
skenv create research
skenv activate research
skenv install ~/my-skills/python-research
skenv install ~/my-skills/latex-paper
skenv ls
```

### Base Layer

Skills in the base layer are **always present** regardless of which env is active. Use this for skills you want everywhere (e.g., a shell helper skill).

```bash
skenv base install ~/my-skills/always-zsh
skenv base ls
```

Base skills are overridden if the active env has a skill with the same name.

### Linked vs Copied Skills

By default, `skenv install` **copies** the skill into the env — self-contained, won't break if you delete the source. Use `--link` to **symlink** instead — edits to the source propagate immediately.

```bash
skenv install ~/my-skills/foo            # copy (independent)
skenv install ~/my-skills/foo --link     # symlink (stays in sync)
```

`skenv ls` shows `(linked)` for symlinked skills and `(outdated)` for copied skills whose source has changed.

### Inheritance

An environment can inherit from a parent. The child sees all of the parent's skills plus its own. Child skills win on name conflict.

```bash
skenv create research-v2
skenv inherit research-v2 research
skenv activate research-v2    # sees research skills + research-v2 skills
```

### Registry

Register skill paths by name so you can install without typing full paths:

```bash
skenv registry add zsh-shell ~/my-skills/zsh-shell
skenv registry add react ~/my-skills/react-patterns
skenv registry list

skenv install zsh-shell       # looks up registry, installs from ~/my-skills/zsh-shell
```

### Freeze & Init

Export an environment as a manifest and recreate it elsewhere:

```bash
skenv freeze > research.manifest
skenv init research-v2 --from research.manifest
```

The manifest records each skill's name, source path, and install mode (`copy` or `link`). Base layer skills are prefixed with `@base:`.

### Auto-Activation

Create a `.skenv` file in a project directory containing an env name:

```bash
echo "research" > ~/projects/my-paper/.skenv
```

With the shell hook enabled (`eval "$(skenv hook zsh)"`), skenv auto-activates when you `cd` into that directory.

### Temporary Activation

Run a single command under a different env without changing your current state:

```bash
skenv run webdev -- claude "review this React component"
# your previous env is automatically restored
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SKENV_HOME` | `~/.skenv` | Root directory for all environments |

Skill directories synced on activate (hardcoded):
- `~/.claude/skills/` — Claude Code
- `~/.copilot/skills/` — GitHub Copilot CLI

---

## What's a Skill?

A skill is a directory containing a `SKILL.md` file. The markdown file describes a capability that the AI agent should use. skenv doesn't care about the contents — it just manages which skill directories are visible to Claude Code and Copilot CLI.

```
my-skill/
`-- SKILL.md     # instructions for the AI agent
```

---

## FAQ

**Q: What happens to my existing skills on first use?**
They're automatically backed up into the `_pre-skenv` environment on first activate (after you confirm). Run `skenv activate _pre-skenv` to restore them. This env is protected from deletion.

**Q: What does `deactivate` do?**
It removes all skills from the discovery directories. No env active = no skills visible. This matches how Python's `deactivate` removes the venv from your PATH.

**Q: Can I use skenv with only Claude Code or only Copilot CLI?**
Yes. skenv syncs to both directories, but if one doesn't exist, it simply creates it. Each tool only reads from its own directory.

**Q: Does it work on Linux?**
Yes. It's pure bash (3.2+) with no external dependencies. Works on macOS and Linux.

**Q: Can environments share skills without duplication?**
Yes, three ways: (1) the **base layer** for always-on skills, (2) **inheritance** for extending an env, or (3) `--link` mode to symlink from a shared source.

---

## Requirements

- **bash** 3.2+ (macOS default or any Linux)
- No other dependencies

---

## License

MIT
