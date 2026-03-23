# --- Package installation ---
#
# A "package" is a directory containing skills/ and optionally hooks/ and agent-context.md:
#   my-package/
#   ├── skills/            # each subdirectory is a skill (with SKILL.md)
#   ├── hooks/             # optional: hook configs + scripts
#   │   ├── *.json         # hook definitions (platform-specific format)
#   │   └── scripts/       # hook scripts referenced by the JSON
#   └── agent-context.md   # optional: always-on context injected into project instructions

cmd_install_package() {
    local pkg_path=""
    local env_name=""
    local link_mode=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                [[ $# -lt 2 ]] && { _error "--env requires an environment name"; exit 1; }
                env_name="$2"; shift 2 ;;
            --link) link_mode=1; shift ;;
            -*)  _error "Unknown flag: $1"; exit 1 ;;
            *)
                if [[ -z "$pkg_path" ]]; then
                    pkg_path="$1"; shift
                else
                    _error "Unexpected argument: $1"; exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$pkg_path" ]]; then
        _error "Usage: skenv install-package <path> [--env <name>] [--link]"
        exit 1
    fi

    pkg_path=$(realpath "$pkg_path" 2>/dev/null || echo "$pkg_path")

    if [[ ! -d "$pkg_path" ]]; then
        _error "Package path '$pkg_path' is not a directory."
        exit 1
    fi

    local pkg_name
    pkg_name=$(basename "$pkg_path")

    local has_skills=0 has_hooks=0 has_context=0
    [[ -d "$pkg_path/skills" ]] && has_skills=1
    [[ -d "$pkg_path/hooks" ]] && has_hooks=1
    [[ -f "$pkg_path/agent-context.md" ]] && has_context=1

    if [[ $has_skills -eq 0 && $has_hooks -eq 0 && $has_context -eq 0 ]]; then
        _error "Package '$pkg_name' has no skills/, hooks/, or agent-context.md."
        _hint "A package should contain skills/, hooks/, and/or agent-context.md."
        exit 1
    fi

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    local env_dir
    env_dir=$(_env_dir "$env_name")

    # --- Install skills ---
    local skill_count=0
    if [[ $has_skills -eq 1 ]]; then
        for skill_dir in "$pkg_path"/skills/*/; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name
            skill_name=$(basename "$skill_dir")
            local dest="$env_dir/$skill_name"

            if [[ -e "$dest" || -L "$dest" ]]; then
                _warn "Skill '$skill_name' already exists in '$env_name'. Replacing."
                rm -rf "$dest"
                rm -f "${dest}.skenv-meta"
            fi

            if [[ $link_mode -eq 1 ]]; then
                ln -sf "$skill_dir" "$dest"
                _write_meta "$dest" "$skill_dir" "link"
            else
                cp -r "$skill_dir" "$dest"
                _write_meta "$dest" "$skill_dir" "copy"
            fi
            skill_count=$((skill_count + 1))
        done
    fi

    # --- Store hooks and agent-context ---
    local hook_count=0
    if [[ $has_hooks -eq 1 || $has_context -eq 1 ]]; then
        local hooks_store="$env_dir/.hooks/$pkg_name"
        rm -rf "$hooks_store"
        mkdir -p "$hooks_store"

        # Store hooks
        if [[ $has_hooks -eq 1 ]]; then
            if [[ $link_mode -eq 1 ]]; then
                for item in "$pkg_path"/hooks/*; do
                    [[ -e "$item" ]] || continue
                    ln -sf "$item" "$hooks_store/$(basename "$item")"
                done
            else
                cp -r "$pkg_path"/hooks/* "$hooks_store/"
            fi

            # Count hook events
            hook_count=$(python3 -c "
import json, glob, sys
count = 0
for f in glob.glob('$hooks_store/*.json'):
    try:
        data = json.load(open(f))
        hooks = data.get('hooks', {})
        for event, entries in hooks.items():
            count += len(entries)
    except: pass
print(count)
" 2>/dev/null || echo "0")
        fi

        # Store agent-context.md
        if [[ $has_context -eq 1 ]]; then
            if [[ $link_mode -eq 1 ]]; then
                ln -sf "$pkg_path/agent-context.md" "$hooks_store/agent-context.md"
            else
                cp "$pkg_path/agent-context.md" "$hooks_store/agent-context.md"
            fi
        fi

        # Store package metadata
        cat > "$hooks_store/.package-meta" <<EOF
source=$pkg_path
installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mode=$([ $link_mode -eq 1 ] && echo "link" || echo "copy")
EOF
    fi

    # --- Report ---
    local parts=""
    [[ $skill_count -gt 0 ]] && parts="$skill_count skill(s)"
    if [[ $hook_count -gt 0 ]]; then
        [[ -n "$parts" ]] && parts="$parts, "
        parts="${parts}$hook_count hook(s)"
    fi
    if [[ $has_context -eq 1 ]]; then
        [[ -n "$parts" ]] && parts="$parts, "
        parts="${parts}agent-context"
    fi

    _info "Installed package ${BOLD}$pkg_name${NC} into ${BOLD}$env_name${NC} ($parts)"

    # Re-sync if this is the active env
    local platform
    platform=$(_platform_for_env "$env_name")
    local current
    current=$(_get_active "$platform")
    if [[ "$current" == "$env_name" && $skill_count -gt 0 ]]; then
        _sync_skills "$env_name"
        _hint "Active environment updated."
    fi

    if [[ $hook_count -gt 0 || $has_context -eq 1 ]]; then
        _hint "Run 'skenv hooks apply' in your project to activate hooks and context."
    fi
}

# --- Hooks management ---

cmd_hooks() {
    local subcmd="${1:?Usage: skenv hooks apply|remove|list [options]}"
    shift

    case "$subcmd" in
        apply)  _hooks_apply "$@" ;;
        remove) _hooks_remove "$@" ;;
        list)   _hooks_list "$@" ;;
        *)
            _error "Unknown hooks subcommand: $subcmd"
            _hint "Usage: skenv hooks apply|remove|list"
            exit 1
            ;;
    esac
}

_hooks_apply() {
    local project_dir=""
    local pkg_filter=""
    local env_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -lt 2 ]] && { _error "--project requires a directory"; exit 1; }
                project_dir="$2"; shift 2 ;;
            --env)
                [[ $# -lt 2 ]] && { _error "--env requires an environment name"; exit 1; }
                env_name="$2"; shift 2 ;;
            -*)  _error "Unknown flag: $1"; exit 1 ;;
            *)   pkg_filter="$1"; shift ;;
        esac
    done

    [[ -z "$project_dir" ]] && project_dir="$PWD"
    project_dir=$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    local env_dir
    env_dir=$(_env_dir "$env_name")
    local platform
    platform=$(_platform_for_env "$env_name")

    local hooks_base="$env_dir/.hooks"
    if [[ ! -d "$hooks_base" ]]; then
        _warn "No hook packages installed in '$env_name'."
        return 0
    fi

    local applied=0
    for pkg_dir in "$hooks_base"/*/; do
        [[ -d "$pkg_dir" ]] || continue
        local pkg_name
        pkg_name=$(basename "$pkg_dir")
        [[ "$pkg_name" == .* ]] && continue

        # Filter if specific package requested
        if [[ -n "$pkg_filter" && "$pkg_name" != "$pkg_filter" ]]; then
            continue
        fi

        _hooks_apply_package "$pkg_name" "$pkg_dir" "$project_dir" "$platform"
        applied=$((applied + 1))
    done

    if [[ $applied -eq 0 ]]; then
        if [[ -n "$pkg_filter" ]]; then
            _error "Hook package '$pkg_filter' not found in '$env_name'."
        else
            _warn "No hook packages to apply."
        fi
    fi
}

_hooks_apply_package() {
    local pkg_name="$1"
    local pkg_dir="$2"
    local project_dir="$3"
    local platform="$4"

    case "$platform" in
        copilot) _hooks_apply_copilot "$pkg_name" "$pkg_dir" "$project_dir" ;;
        claude)  _hooks_apply_claude "$pkg_name" "$pkg_dir" "$project_dir" ;;
    esac

    # Apply agent context if present
    _context_apply "$pkg_name" "$pkg_dir" "$project_dir" "$platform"
}

_hooks_apply_copilot() {
    local pkg_name="$1"
    local pkg_dir="$2"
    local project_dir="$3"

    local target_dir="$project_dir/.github/hooks"
    local target_file="$target_dir/hooks.json"
    local target_scripts="$target_dir/scripts"

    mkdir -p "$target_dir"
    mkdir -p "$target_scripts"

    # Symlink scripts
    local scripts_dir="$pkg_dir/scripts"
    if [[ -d "$scripts_dir" ]]; then
        # Resolve symlink if scripts dir is itself a symlink
        local real_scripts
        real_scripts=$(realpath "$scripts_dir" 2>/dev/null || echo "$scripts_dir")
        for script in "$real_scripts"/*; do
            [[ -f "$script" ]] || continue
            local script_name
            script_name=$(basename "$script")
            local dest="$target_scripts/$script_name"
            rm -f "$dest"
            ln -sf "$script" "$dest"
        done
    fi

    # Merge hook entries into hooks.json
    # If target is a symlink, replace with real file
    if [[ -L "$target_file" ]]; then
        local old_target
        old_target=$(readlink "$target_file")
        rm -f "$target_file"
        _warn "Replaced symlink $target_file (was → $old_target)"
    fi

    # Find all .json hook configs in the package
    local hook_files=()
    for f in "$pkg_dir"/*.json; do
        [[ -f "$f" ]] || continue
        # Resolve symlinks
        local real_f
        real_f=$(realpath "$f" 2>/dev/null || echo "$f")
        hook_files+=("$real_f")
    done

    if [[ ${#hook_files[@]} -eq 0 ]]; then
        _warn "No hook config files found in package '$pkg_name'."
        return
    fi

    python3 << PYEOF
import json, sys, os

target_file = "$target_file"
pkg_name = "$pkg_name"
hook_files = ${hook_files[@]+"$(printf '"%s",' "${hook_files[@]}" | sed 's/,$//')"}

# Wrap in list
if isinstance(hook_files, str):
    hook_files = [hook_files]

# Read existing target
existing = {"version": 1, "hooks": {}}
if os.path.exists(target_file):
    try:
        with open(target_file) as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

# Remove old entries from this package
for event in list(existing.get("hooks", {}).keys()):
    existing["hooks"][event] = [
        e for e in existing["hooks"][event]
        if e.get("_skenv_package") != pkg_name
    ]
    if not existing["hooks"][event]:
        del existing["hooks"][event]

# Add new entries from all hook files
for hf in hook_files:
    try:
        with open(hf) as f:
            pkg_hooks = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue
    for event, entries in pkg_hooks.get("hooks", {}).items():
        if event not in existing.get("hooks", {}):
            existing.setdefault("hooks", {})[event] = []
        for entry in entries:
            entry["_skenv_package"] = pkg_name
            existing["hooks"][event].append(entry)

existing.setdefault("version", 1)

with open(target_file, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
PYEOF

    if [[ $? -ne 0 ]]; then
        _error "Failed to merge hooks for '$pkg_name'."
        return 1
    fi

    local event_count
    event_count=$(python3 -c "
import json
with open('$target_file') as f:
    data = json.load(f)
count = sum(1 for e, entries in data.get('hooks', {}).items()
            for entry in entries if entry.get('_skenv_package') == '$pkg_name')
print(count)
" 2>/dev/null || echo "?")
    _info "Applied ${BOLD}$pkg_name${NC} hooks to $project_dir ($event_count hook(s))"
}

_hooks_apply_claude() {
    local pkg_name="$1"
    local pkg_dir="$2"
    local project_dir="$3"

    local target_file="$project_dir/.claude/settings.json"

    # Find hook config files
    local hook_files=()
    for f in "$pkg_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local real_f
        real_f=$(realpath "$f" 2>/dev/null || echo "$f")
        hook_files+=("$real_f")
    done

    if [[ ${#hook_files[@]} -eq 0 ]]; then
        _warn "No hook config files found in package '$pkg_name'."
        return
    fi

    # Resolve script paths to absolute for Claude (uses command, not relative paths)
    local scripts_dir="$pkg_dir/scripts"
    local real_scripts=""
    if [[ -d "$scripts_dir" ]]; then
        real_scripts=$(realpath "$scripts_dir" 2>/dev/null || echo "$scripts_dir")
    fi

    mkdir -p "$(dirname "$target_file")"

    python3 << PYEOF
import json, sys, os, re

target_file = "$target_file"
pkg_name = "$pkg_name"
scripts_dir = "$real_scripts"
hook_files = ${hook_files[@]+"$(printf '"%s",' "${hook_files[@]}" | sed 's/,$//')"}

if isinstance(hook_files, str):
    hook_files = [hook_files]

# Event name mapping: copilot (camelCase) -> claude (PascalCase)
EVENT_MAP = {
    "sessionStart": "SessionStart",
    "sessionEnd": "SessionEnd",
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "userPromptSubmit": "UserPromptSubmit",
    "notification": "Notification",
    "stop": "Stop",
}

# Read existing settings
existing = {}
if os.path.exists(target_file):
    try:
        with open(target_file) as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

# Remove old entries from this package
for event in list(existing.get("hooks", {}).keys()):
    existing["hooks"][event] = [
        e for e in existing["hooks"][event]
        if e.get("_skenv_package") != pkg_name
    ]
    if not existing["hooks"][event]:
        del existing["hooks"][event]

# Add new entries, converting format
for hf in hook_files:
    try:
        with open(hf) as f:
            pkg_hooks = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue
    for event, entries in pkg_hooks.get("hooks", {}).items():
        claude_event = EVENT_MAP.get(event, event)
        if claude_event not in existing.get("hooks", {}):
            existing.setdefault("hooks", {})[claude_event] = []
        for entry in entries:
            # Convert copilot format to claude format
            bash_cmd = entry.get("bash", entry.get("command", ""))
            # Resolve relative script path to absolute
            if scripts_dir and not os.path.isabs(bash_cmd):
                script_name = os.path.basename(bash_cmd)
                abs_path = os.path.join(scripts_dir, script_name)
                if os.path.exists(abs_path):
                    bash_cmd = abs_path
            claude_entry = {
                "_skenv_package": pkg_name,
                "hooks": [{"type": "command", "command": bash_cmd}]
            }
            existing["hooks"][claude_event].append(claude_entry)

with open(target_file, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
PYEOF

    if [[ $? -ne 0 ]]; then
        _error "Failed to merge hooks for '$pkg_name'."
        return 1
    fi

    _info "Applied ${BOLD}$pkg_name${NC} hooks to $target_file"
}

# --- Hooks remove ---

_hooks_remove() {
    local pkg_name=""
    local project_dir=""
    local env_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -lt 2 ]] && { _error "--project requires a directory"; exit 1; }
                project_dir="$2"; shift 2 ;;
            --env)
                [[ $# -lt 2 ]] && { _error "--env requires an environment name"; exit 1; }
                env_name="$2"; shift 2 ;;
            -*)  _error "Unknown flag: $1"; exit 1 ;;
            *)   pkg_name="$1"; shift ;;
        esac
    done

    if [[ -z "$pkg_name" ]]; then
        _error "Usage: skenv hooks remove <package> [--project <dir>]"
        exit 1
    fi

    [[ -z "$project_dir" ]] && project_dir="$PWD"
    project_dir=$(realpath "$project_dir" 2>/dev/null || echo "$project_dir")

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi

    local platform
    platform=$(_platform_for_env "$env_name")

    case "$platform" in
        copilot) _hooks_remove_copilot "$pkg_name" "$project_dir" "$env_name" ;;
        claude)  _hooks_remove_claude "$pkg_name" "$project_dir" "$env_name" ;;
    esac
}

_hooks_remove_copilot() {
    local pkg_name="$1"
    local project_dir="$2"
    local env_name="$3"

    local target_file="$project_dir/.github/hooks/hooks.json"
    local target_scripts="$project_dir/.github/hooks/scripts"

    if [[ ! -f "$target_file" ]]; then
        _warn "No hooks.json found at $target_file"
        return 0
    fi

    # Remove hook entries
    python3 << PYEOF
import json, os

target_file = "$target_file"
pkg_name = "$pkg_name"

with open(target_file) as f:
    data = json.load(f)

removed = 0
for event in list(data.get("hooks", {}).keys()):
    before = len(data["hooks"][event])
    data["hooks"][event] = [
        e for e in data["hooks"][event]
        if e.get("_skenv_package") != pkg_name
    ]
    removed += before - len(data["hooks"][event])
    if not data["hooks"][event]:
        del data["hooks"][event]

with open(target_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print(removed)
PYEOF

    # Remove symlinked scripts from this package
    local env_dir
    env_dir=$(_env_dir "$env_name")
    local pkg_scripts="$env_dir/.hooks/$pkg_name/scripts"
    if [[ -d "$pkg_scripts" ]]; then
        local real_pkg_scripts
        real_pkg_scripts=$(realpath "$pkg_scripts" 2>/dev/null || echo "$pkg_scripts")
        if [[ -d "$target_scripts" ]]; then
            for link in "$target_scripts"/*; do
                [[ -L "$link" ]] || continue
                local link_target
                link_target=$(realpath "$link" 2>/dev/null || echo "")
                # Remove if it points into the package's scripts dir
                if [[ "$link_target" == "$real_pkg_scripts"/* ]]; then
                    rm -f "$link"
                fi
            done
        fi
    fi

    _info "Removed ${BOLD}$pkg_name${NC} hooks from $project_dir"

    # Remove agent context
    _context_remove "$pkg_name" "$project_dir" "copilot"
}

_hooks_remove_claude() {
    local pkg_name="$1"
    local project_dir="$2"
    local env_name="$3"

    local target_file="$project_dir/.claude/settings.json"

    if [[ ! -f "$target_file" ]]; then
        _warn "No settings.json found at $target_file"
        return 0
    fi

    python3 << PYEOF
import json

target_file = "$target_file"
pkg_name = "$pkg_name"

with open(target_file) as f:
    data = json.load(f)

for event in list(data.get("hooks", {}).keys()):
    data["hooks"][event] = [
        e for e in data["hooks"][event]
        if e.get("_skenv_package") != pkg_name
    ]
    if not data["hooks"][event]:
        del data["hooks"][event]

with open(target_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF

    _info "Removed ${BOLD}$pkg_name${NC} hooks from $target_file"

    # Remove agent context
    _context_remove "$pkg_name" "$project_dir" "claude"
}
#
# Injects/removes agent-context.md content into project instruction files.
# Copilot: .github/copilot-instructions.md
# Claude:  claude.md (preferred) or AGENTS.md

_detect_instructions_file() {
    local project_dir="$1"
    local platform="$2"

    case "$platform" in
        copilot)
            echo "$project_dir/.github/copilot-instructions.md"
            ;;
        claude)
            if [[ -f "$project_dir/claude.md" ]]; then
                echo "$project_dir/claude.md"
            elif [[ -f "$project_dir/AGENTS.md" ]]; then
                echo "$project_dir/AGENTS.md"
            else
                echo "$project_dir/claude.md"
            fi
            ;;
    esac
}

_context_apply() {
    local pkg_name="$1"
    local pkg_dir="$2"
    local project_dir="$3"
    local platform="$4"

    # Find agent-context.md (resolve symlinks)
    local context_file="$pkg_dir/agent-context.md"
    if [[ -L "$context_file" ]]; then
        context_file=$(realpath "$context_file" 2>/dev/null || echo "$context_file")
    fi
    [[ -f "$context_file" ]] || return 0

    local instructions_file
    instructions_file=$(_detect_instructions_file "$project_dir" "$platform")

    # Ensure parent directory exists
    mkdir -p "$(dirname "$instructions_file")"

    # Read the context content
    local context_content
    context_content=$(cat "$context_file")

    local marker_start="<!-- skenv:${pkg_name} -->"
    local marker_end="<!-- /skenv:${pkg_name} -->"

    if [[ -f "$instructions_file" ]]; then
        # Remove existing block if present (idempotent re-apply)
        local tmp_file
        tmp_file=$(mktemp)
        python3 -c "
import sys
marker_start = '$marker_start'
marker_end = '$marker_end'
with open('$instructions_file') as f:
    content = f.read()
# Remove existing block (including markers and surrounding blank lines)
import re
pattern = r'\n*' + re.escape(marker_start) + r'.*?' + re.escape(marker_end) + r'\n*'
content = re.sub(pattern, '\n', content, flags=re.DOTALL)
content = content.strip()
with open('$tmp_file', 'w') as f:
    f.write(content)
    f.write('\n')
" 2>/dev/null
        mv "$tmp_file" "$instructions_file"
    fi

    # Append the marked block
    {
        [[ -f "$instructions_file" && -s "$instructions_file" ]] && echo ""
        echo "$marker_start"
        echo "$context_content"
        echo "$marker_end"
    } >> "$instructions_file"

    _info "Injected ${BOLD}$pkg_name${NC} context into $(basename "$instructions_file")"
}

_context_remove() {
    local pkg_name="$1"
    local project_dir="$2"
    local platform="$3"

    local instructions_file
    instructions_file=$(_detect_instructions_file "$project_dir" "$platform")

    [[ -f "$instructions_file" ]] || return 0

    local marker_start="<!-- skenv:${pkg_name} -->"
    local marker_end="<!-- /skenv:${pkg_name} -->"

    # Check if markers exist
    if ! grep -qF "$marker_start" "$instructions_file" 2>/dev/null; then
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp)
    python3 -c "
import re
marker_start = '$marker_start'
marker_end = '$marker_end'
with open('$instructions_file') as f:
    content = f.read()
pattern = r'\n*' + re.escape(marker_start) + r'.*?' + re.escape(marker_end) + r'\n*'
content = re.sub(pattern, '\n', content, flags=re.DOTALL)
content = content.strip()
with open('$tmp_file', 'w') as f:
    f.write(content)
    f.write('\n')
" 2>/dev/null
    mv "$tmp_file" "$instructions_file"

    _info "Removed ${BOLD}$pkg_name${NC} context from $(basename "$instructions_file")"
}

# --- Hooks list ---

_hooks_list() {
    local env_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                [[ $# -lt 2 ]] && { _error "--env requires an environment name"; exit 1; }
                env_name="$2"; shift 2 ;;
            *) _error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    local env_dir
    env_dir=$(_env_dir "$env_name")
    local hooks_base="$env_dir/.hooks"

    echo -e "${BOLD}Hook packages in '$env_name':${NC}"

    if [[ ! -d "$hooks_base" ]]; then
        _warn "No hook packages installed."
        _hint "Run: skenv install-package <path>"
        return 0
    fi

    local found=0
    for pkg_dir in "$hooks_base"/*/; do
        [[ -d "$pkg_dir" ]] || continue
        local pkg_name
        pkg_name=$(basename "$pkg_dir")
        [[ "$pkg_name" == .* ]] && continue
        found=1

        local source=""
        [[ -f "$pkg_dir/.package-meta" ]] && source=$(grep "^source=" "$pkg_dir/.package-meta" 2>/dev/null | cut -d= -f2-)

        # List events from hook JSON files
        local events
        events=$(python3 -c "
import json, glob
events = set()
for f in glob.glob('$(realpath "$pkg_dir" 2>/dev/null || echo "$pkg_dir")/*.json'):
    try:
        data = json.load(open(f))
        events.update(data.get('hooks', {}).keys())
    except: pass
print(', '.join(sorted(events)) if events else 'none')
" 2>/dev/null || echo "unknown")

        echo -e "  ${BLUE}•${NC} ${BOLD}$pkg_name${NC}"
        echo -e "    Events: ${CYAN}$events${NC}"
        if [[ -f "$pkg_dir/agent-context.md" ]] || [[ -L "$pkg_dir/agent-context.md" ]]; then
            echo -e "    Context: ${GREEN}agent-context.md${NC}"
        fi
        [[ -n "$source" ]] && echo -e "    Source: ${YELLOW}$source${NC}"
    done

    if [[ $found -eq 0 ]]; then
        _warn "No hook packages installed."
        _hint "Run: skenv install-package <path>"
    fi
}
