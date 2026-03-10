# skenv

**virtualenv for AI coding skills.** Manage separate skill environments for Claude Code or GitHub Copilot CLI — switch between them instantly.

```
skenv create research --copilot     # copilot environment
skenv create research               # claude environment (default)
skenv activate research             # copilot sees research skills
skenv activate webdev               # switch — now copilot sees webdev skills
```

---

## Quick Start

```bash
# 1. Install
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/.local/bin/skenv
chmod +x ~/.local/bin/skenv
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc to make permanent

# 2. Create and activate
skenv create myenv --copilot          # or just `skenv create myenv` for claude
skenv activate myenv                  # first time: asks to backup, offers to import existing skills

# 3. Install skills into the environment
skenv install ~/my-skills/python-research
skenv install ~/my-skills/react-patterns --link   # symlink (stays in sync with source)

# 4. Create another and switch
skenv create webdev --copilot
skenv activate webdev                 # clean swap — only webdev skills visible

# 5. Check what's active
skenv status                          # shows active env per platform
skenv ls                              # list skills in active env
```

> **First-time safety:** The first `skenv activate` for each platform asks you to confirm backup, snapshots existing skills into `_pre-skenv-<platform>`, then offers to import them into your new environment. Use `-y` / `SKENV_YES=1` to skip prompts in scripts.

---

## Why skenv?

Claude Code reads skills from `~/.claude/skills/`, Copilot CLI from `~/.copilot/skills/`. If you work on different projects, you need different skill sets — but there's no built-in way to swap them.

**skenv** solves this the same way Python's `venv` solves package management:

- Each environment targets a **single platform** (`--claude` or `--copilot`)
- Activating an env does a **clean swap** — only that env's skills are visible
- You can have **one env per platform** active simultaneously
- A **base layer** provides always-on skills across all environments
- Environments can **inherit** from each other to avoid duplication

---

## Installation

### Option A: Direct download

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/xingdi-eric-yuan/skenv/main/skenv -o ~/.local/bin/skenv
chmod +x ~/.local/bin/skenv
```

### Option B: Clone and symlink

```bash
git clone https://github.com/xingdi-eric-yuan/skenv.git ~/.skenv-repo
ln -sf ~/.skenv-repo/skenv ~/.local/bin/skenv
```

Then make sure `~/.local/bin` is on your `$PATH`. Add this to your `~/.zshrc` or `~/.bashrc` if it isn't already:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Reload your shell (`source ~/.zshrc`) or open a new terminal, then verify:

```bash
skenv help
```

### Shell integration (optional but recommended)

Add to your `~/.zshrc` or `~/.bashrc`, **after** oh-my-zsh/framework sourcing:

```bash
eval "$(skenv hook zsh)"          # auto-activate + prompt helper
eval "$(skenv completion zsh)"    # tab completion
```

Replace `zsh` with `bash` if needed. This gives you:

- **Auto-activation:** Put a `.skenv` file in any project directory (containing an env name), and skenv activates it automatically when you `cd` in.
- **Prompt indicator:** Shows `[skenv:copilot:myenv]` when an env is active.
- **Tab completion:** Complete commands, environment names, and skill names.

#### Prompt setup

The hook defines a `_skenv_prompt` function but you need to add it to your prompt.

**oh-my-zsh** (add after `source $ZSH/oh-my-zsh.sh`):
```bash
PROMPT='$(_skenv_prompt)'"$PROMPT"
```

**Plain zsh:**
```bash
PROMPT='$(_skenv_prompt)%~ %# '
```

**Bash:**
```bash
PS1='$(_skenv_prompt)\u@\h:\w\$ '
```

---

## How It Works

```
~/.skenv/                                SKENV_HOME (all envs live here)
|-- .active-claude                       tracks active claude env
|-- .active-copilot                      tracks active copilot env
|-- .base/                               base layer (always-on skills)
|   `-- always-zsh/
|       `-- SKILL.md
|-- .registry                            name-to-path mappings
|-- _pre-skenv-copilot/                  auto-backup of original copilot skills
|-- research/                            a copilot environment
|   |-- .platform                        contains "copilot"
|   |-- python-research/
|   |   |-- SKILL.md
|   |   `-- .skenv-meta
|   `-- latex-paper/
|       `-- SKILL.md
`-- webdev/                              a claude environment
    |-- .platform                        contains "claude"
    |-- react-patterns -> ~/skills/react  (--link mode)
    `-- react-patterns.skenv-meta

~/.copilot/skills/                       Copilot CLI reads from here
|-- always-zsh -> ~/.skenv/.base/always-zsh
`-- python-research -> ~/.skenv/research/python-research
```

**On `activate`:** skenv wipes the platform's skill directory, then symlinks: base layer first, then the environment's skills. Only one env per platform is active at a time.

**Layering order** (later wins on name conflict):

```
base layer  ->  parent envs (if inherited)  ->  active env
```

---

## Platforms

Each environment targets exactly one platform, set at creation time:

| Flag | Skills directory | Default |
|------|-----------------|---------|
| `--claude` | `~/.claude/skills/` | ✓ (default) |
| `--copilot` | `~/.copilot/skills/` | |

```bash
skenv create my-claude-env               # targets ~/.claude/skills/
skenv create my-copilot-env --copilot    # targets ~/.copilot/skills/
```

You can have **one env per platform active simultaneously**:

```bash
skenv activate my-claude-env             # activates in ~/.claude/skills/
skenv activate my-copilot-env            # activates in ~/.copilot/skills/ — both are now active
skenv status
# Active [claude]: my-claude-env (5 skills)
# Active [copilot]: my-copilot-env (8 skills)
```

The platform is locked to the environment — it cannot be changed after creation. Inheritance only works between envs on the same platform.

---

## Commands

### Environment management

| Command | Description |
|---------|-------------|
| `skenv create <name> [--claude\|--copilot] [--from <env>]` | Create a new environment |
| `skenv activate [-y\|--yes] <name>` | Activate env — clean swap into platform's skills dir |
| `skenv deactivate [--claude\|--copilot]` | Deactivate env(s). No flag = deactivate all |
| `skenv list` | List all environments (`*` = active, shows platform) |
| `skenv status` | Show active env per platform |
| `skenv clone <src> <dst>` | Deep-copy an environment (preserves platform) |
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
| `skenv inherit <child> <parent>` | Child env inherits parent's skills (same platform only) |
| `skenv freeze [name]` | Export env as a manifest file |
| `skenv init <name> --from <file> [--claude\|--copilot]` | Recreate env from a manifest |
| `skenv run <env> -- <cmd...>` | Run a command with a temporary env |
| `skenv registry add <name> <path>` | Register a skill by name |
| `skenv registry remove <name>` | Unregister a skill |
| `skenv registry list` | Show all registered skills |
| `skenv hook [bash\|zsh]` | Print shell hook for auto-activate + prompt |
| `skenv completion [bash\|zsh]` | Print tab completion script |

---

## Concepts

### Environments

An environment is a named collection of skills stored in `~/.skenv/<name>/`. Each env targets a single platform (`claude` or `copilot`). Activating an env does a **clean swap** — the platform's skill directory contains _only_ that env's skills (plus the base layer).

```bash
skenv create research --copilot
skenv activate research
skenv install ~/my-skills/python-research
skenv install ~/my-skills/latex-paper
skenv ls
```

### Base Layer

Skills in the base layer are **always present** regardless of which env is active. Use this for skills you want everywhere (e.g., a shell helper skill). Base layer skills are synced to whichever platform is active.

```bash
skenv base install ~/my-skills/always-zsh
skenv base ls
```

Base skills are overridden if the active env has a skill with the same name.

### Linked vs Copied Skills

By default, `skenv install` **copies** the skill into the env — self-contained, won't break if you delete the source. Use `--link` to **symlink** instead — edits to the source propagate immediately. Use `--link` for skills under active development.

```bash
skenv install ~/my-skills/foo            # copy (independent)
skenv install ~/my-skills/foo --link     # symlink (stays in sync)
```

`skenv ls` shows `(linked)` for symlinked skills and `(outdated)` for copied skills whose source has changed.

### Inheritance

An environment can inherit from a parent (same platform only). The child sees all of the parent's skills plus its own. Child skills win on name conflict.

```bash
skenv create research-v2 --copilot
skenv inherit research-v2 research       # both must be copilot
skenv activate research-v2               # sees research skills + research-v2 skills
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

The manifest records each skill's name, source path, install mode, and platform. Base layer skills are prefixed with `@base:`.

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
| `SKENV_YES` | unset | Set to `1` to skip confirmation prompts |

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
They're automatically backed up into a `_pre-skenv-<platform>` environment on the first activate for each platform (after you confirm). Run `skenv activate _pre-skenv-copilot` to restore them. These envs are protected from deletion.

**Q: What does `deactivate` do?**
With no flag, it deactivates all active environments. Use `--claude` or `--copilot` to deactivate only one platform. Deactivating removes all skills from the platform's discovery directory.

**Q: Can I have both a Claude and Copilot env active at the same time?**
Yes. Each platform has its own active slot. Activating a copilot env doesn't affect the active claude env, and vice versa.

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
