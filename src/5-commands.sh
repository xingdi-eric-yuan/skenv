# --- Environment lifecycle commands ---

cmd_create() {
    local name=""
    local from_env=""
    local platform=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_env="${2:?--from requires an environment name}"; shift 2 ;;
            --claude) platform="$PLATFORM_CLAUDE"; shift ;;
            --copilot) platform="$PLATFORM_COPILOT"; shift ;;
            -*) _error "Unknown flag: $1"; exit 1 ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"; shift
                else
                    _error "Unexpected argument: $1"; exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        _error "Usage: skenv create <name> [--claude|--copilot] [--from <env>]"
        exit 1
    fi

    if [[ "$name" == _* ]]; then
        _error "Environment names starting with '_' are reserved for skenv internals."
        exit 1
    fi

    if [[ "$name" =~ [[:space:]] ]]; then
        _error "Environment names cannot contain whitespace."
        exit 1
    fi

    _ensure_home
    local env_dir
    env_dir=$(_env_dir "$name")

    if [[ -d "$env_dir" ]]; then
        _error "Environment '$name' already exists."
        exit 1
    fi

    if [[ -n "$from_env" ]]; then
        _require_env_exists "$from_env"
        # If no platform specified, inherit from source env
        if [[ -z "$platform" ]]; then
            platform=$(_platform_for_env "$from_env")
        fi
        local src_dir
        src_dir=$(_env_dir "$from_env")
        cp -r "$src_dir" "$env_dir"
        # Remove metadata files from the copy
        find "$env_dir" -maxdepth 1 -name '*.skenv-meta' -delete 2>/dev/null
        find "$env_dir" -maxdepth 2 -name '.skenv-meta' -delete 2>/dev/null
        # Set the platform (may differ from source if overridden)
        echo "${platform:-$DEFAULT_PLATFORM}" > "$env_dir/.platform"
        local count
        count=$(find "$env_dir" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -not -name '.*' -not -name '*.skenv-meta' 2>/dev/null | wc -l | tr -d ' ')
        _info "Created ${BOLD}$name${NC} [${platform:-$DEFAULT_PLATFORM}] from ${BOLD}$from_env${NC} ($count skill(s) copied)"
    else
        mkdir -p "$env_dir"
        echo "${platform:-$DEFAULT_PLATFORM}" > "$env_dir/.platform"
        _info "Created skill environment: ${BOLD}$name${NC} [${platform:-$DEFAULT_PLATFORM}]"
    fi
    _hint "Activate it with: skenv activate $name"
}

cmd_activate() {
    local yes_flag=0
    while [[ "${1:-}" == -* ]]; do
        case "$1" in
            -y|--yes) yes_flag=1; shift ;;
            *) _error "Unknown flag: $1"; exit 1 ;;
        esac
    done
    local name="${1:?Usage: skenv activate [-y|--yes] <name>}"
    _ensure_home
    _require_env_exists "$name"

    local platform
    platform=$(_platform_for_env "$name")
    local active_file
    active_file=$(_active_file_for_platform "$platform")

    local current=""
    [[ -f "$active_file" ]] && current=$(cat "$active_file")

    if [[ "$current" == "$name" ]]; then
        _warn "Environment '$name' is already active."
        return 0
    fi

    _auto_import "$yes_flag" "$name"

    if [[ -n "$current" ]]; then
        _warn "Switching $platform from: $current"
    fi

    echo "$name" > "$active_file"
    _sync_skills "$name"

    local count
    count=$(find "$(_env_dir "$name")" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -not -name '.*' -not -name '*.skenv-meta' 2>/dev/null | wc -l | tr -d ' ')
    local skills_dir
    skills_dir=$(_skills_dir_for_platform "$platform")
    _info "Activated ${BOLD}$name${NC} [$platform] ($count skill(s) linked to $skills_dir)"
}

cmd_deactivate() {
    local platform="${1:-}"

    if [[ -n "$platform" ]]; then
        # Deactivate specific platform
        case "$platform" in
            --claude) platform="$PLATFORM_CLAUDE" ;;
            --copilot) platform="$PLATFORM_COPILOT" ;;
            *) _error "Usage: skenv deactivate [--claude|--copilot]"; exit 1 ;;
        esac
        local active_file
        active_file=$(_active_file_for_platform "$platform")
        if [[ ! -f "$active_file" ]]; then
            _warn "No active $platform environment to deactivate."
            return 0
        fi
        local current
        current=$(cat "$active_file")
        local skills_dir
        skills_dir=$(_skills_dir_for_platform "$platform")
        _wipe_skills_dir "$skills_dir"
        rm -f "$active_file"
        _info "Deactivated $platform environment: ${BOLD}$current${NC}"
    else
        # Deactivate all platforms
        local deactivated=0
        for p in "$PLATFORM_CLAUDE" "$PLATFORM_COPILOT"; do
            local af
            af=$(_active_file_for_platform "$p")
            if [[ -f "$af" ]]; then
                local cur
                cur=$(cat "$af")
                local sd
                sd=$(_skills_dir_for_platform "$p")
                _wipe_skills_dir "$sd"
                rm -f "$af"
                _info "Deactivated $p environment: ${BOLD}$cur${NC}"
                deactivated=1
            fi
        done
        if [[ $deactivated -eq 0 ]]; then
            _warn "No active environment to deactivate."
        fi
    fi
}

# --- Skill management commands ---

cmd_install() {
    local skill_path="${1:?Usage: skenv install <skill-path> [--env <name>] [--link]}"
    shift

    local env_name="" link_mode=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                [[ $# -lt 2 ]] && { _error "--env requires an environment name"; exit 1; }
                env_name="$2"; shift 2 ;;
            --link) link_mode=1; shift ;;
            *) _error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    skill_path=$(realpath "$skill_path" 2>/dev/null || echo "$skill_path")

    if [[ ! -d "$skill_path" ]]; then
        _error "Skill path '$skill_path' is not a directory."
        _hint "A skill should be a directory containing a SKILL.md file."
        exit 1
    fi

    if [[ ! -f "$skill_path/SKILL.md" ]]; then
        _warn "No SKILL.md found in '$skill_path'. Installing anyway."
    fi

    local skill_name
    skill_name=$(basename "$skill_path")
    local env_dir
    env_dir=$(_env_dir "$env_name")
    local dest="$env_dir/$skill_name"

    if [[ -e "$dest" || -L "$dest" ]]; then
        _warn "Skill '$skill_name' already exists in '$env_name'. Replacing."
        rm -rf "$dest"
        rm -f "${dest}.skenv-meta"
    fi

    if [[ $link_mode -eq 1 ]]; then
        ln -sf "$skill_path" "$dest"
        _write_meta "$dest" "$skill_path" "link"
        _info "Linked ${BOLD}$skill_name${NC} into ${BOLD}$env_name${NC} (→ $skill_path)"
    else
        cp -r "$skill_path" "$dest"
        _write_meta "$dest" "$skill_path" "copy"
        _info "Installed ${BOLD}$skill_name${NC} into ${BOLD}$env_name${NC}"
    fi

    local current
    current=$(_get_active)
    if [[ "$current" == "$env_name" ]]; then
        _sync_skills "$env_name"
        _hint "Active environment updated."
    fi
}

cmd_uninstall() {
    local skill_name="${1:?Usage: skenv uninstall <skill-name> [--env <name>]}"
    shift

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
    local target="$env_dir/$skill_name"

    if [[ ! -e "$target" ]]; then
        _error "Skill '$skill_name' not found in environment '$env_name'."
        exit 1
    fi

    rm -rf "$target"
    rm -f "${target}.skenv-meta"
    _info "Uninstalled ${BOLD}$skill_name${NC} from ${BOLD}$env_name${NC}"

    local current
    current=$(_get_active)
    if [[ "$current" == "$env_name" ]]; then
        _sync_skills "$env_name"
        _hint "Active environment updated."
    fi
}

# --- Listing and status commands ---

cmd_list() {
    _ensure_home

    local active_claude
    active_claude=$(_get_active "$PLATFORM_CLAUDE")
    local active_copilot
    active_copilot=$(_get_active "$PLATFORM_COPILOT")

    local found=0
    for env_dir in "$SKENV_HOME"/*/; do
        [[ -d "$env_dir" ]] || continue
        found=1
        local name
        name=$(basename "$env_dir")
        local count
        count=$(find "$env_dir" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -not -name '.*' -not -name '*.skenv-meta' 2>/dev/null | wc -l | tr -d ' ')
        local platform
        platform=$(_platform_for_env "$name")
        local ptag="[$platform]"

        if [[ "$name" == "$active_claude" || "$name" == "$active_copilot" ]]; then
            echo -e "  ${GREEN}*${NC} ${BOLD}$name${NC}  ${CYAN}$ptag${NC}  ($count skills)"
        else
            echo -e "    $name  ${CYAN}$ptag${NC}  ($count skills)"
        fi
    done

    if [[ $found -eq 0 ]]; then
        _warn "No skill environments found."
        _hint "Run: skenv create <name>"
    fi
}

cmd_ls() {
    local env_name="${1:-}"

    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    local env_dir
    env_dir=$(_env_dir "$env_name")

    local parent_file="$env_dir/.parent"
    if [[ -f "$parent_file" ]]; then
        echo -e "${BOLD}Skills in '$env_name'${NC} ${CYAN}(inherits from: $(cat "$parent_file"))${NC}${BOLD}:${NC}"
    else
        echo -e "${BOLD}Skills in '$env_name':${NC}"
    fi

    local found=0
    for skill in "$env_dir"/*; do
        [[ -e "$skill" || -L "$skill" ]] || continue
        local skill_name
        skill_name=$(basename "$skill")
        [[ "$skill_name" == ".parent" || "$skill_name" == .* || "$skill_name" == *.skenv-meta ]] && continue
        found=1

        local mode_tag=""
        local mode
        mode=$(_read_meta "$skill" "mode")
        [[ "$mode" == "link" ]] && mode_tag=" ${CYAN}(linked)${NC}"

        local outdated_tag=""
        if _is_skill_outdated "$skill"; then
            outdated_tag=" ${RED}(outdated)${NC}"
        fi

        local meta_line=""
        meta_line=$(_read_meta_summary "$skill")

        local skill_resolved="$skill"
        [[ -L "$skill" ]] && skill_resolved=$(readlink -f "$skill" 2>/dev/null || echo "$skill")

        if [[ -f "$skill_resolved/SKILL.md" ]]; then
            local desc
            desc=$(sed -n '/^---$/,/^---$/{ /^description:/s/^description: *//p; }' "$skill_resolved/SKILL.md" 2>/dev/null | head -1)
            if [[ -n "$desc" ]]; then
                if [[ ${#desc} -gt 72 ]]; then
                    desc="${desc:0:69}..."
                fi
                echo -e "  ${BLUE}•${NC} ${BOLD}$skill_name${NC}${mode_tag}${outdated_tag}"
                echo -e "    ${desc}"
            else
                echo -e "  ${BLUE}•${NC} ${BOLD}$skill_name${NC}${mode_tag}${outdated_tag}"
            fi
        else
            echo -e "  ${BLUE}•${NC} $skill_name ${YELLOW}(no SKILL.md)${NC}${mode_tag}${outdated_tag}"
        fi
    done

    if [[ $found -eq 0 ]]; then
        _warn "No skills installed."
        _hint "Run: skenv install <skill-path>"
    fi
}

cmd_status() {
    local shown=0
    for p in "$PLATFORM_CLAUDE" "$PLATFORM_COPILOT"; do
        local current
        current=$(_get_active "$p")
        if [[ -n "$current" ]]; then
            local count
            count=$(find "$(_env_dir "$current")" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) -not -name '.*' -not -name '*.skenv-meta' 2>/dev/null | wc -l | tr -d ' ')
            echo -e "Active ${CYAN}[$p]${NC}: ${BOLD}${GREEN}$current${NC} ($count skills)"
            shown=1
        fi
    done
    if [[ $shown -eq 0 ]]; then
        echo -e "No active skill environment."
    fi
}

cmd_delete() {
    local name="${1:?Usage: skenv delete <name>}"

    local name_lower
    name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if [[ "$name_lower" == _pre-skenv-* ]]; then
        _error "Cannot delete '$name' — it contains your original skills backup."
        _hint "Use 'skenv clone $name <newname>' to copy it, or force with: rm -rf \$SKENV_HOME/$name"
        exit 1
    fi

    _require_env_exists "$name"

    local platform
    platform=$(_platform_for_env "$name")
    local current
    current=$(_get_active "$platform")

    if [[ "$current" == "$name" ]]; then
        _warn "Deactivating '$name' before deletion."
        local skills_dir
        skills_dir=$(_skills_dir_for_platform "$platform")
        _wipe_skills_dir "$skills_dir"
        rm -f "$(_active_file_for_platform "$platform")"
    fi

    rm -rf "$(_env_dir "$name")"
    _info "Deleted environment: ${BOLD}$name${NC}"
}

cmd_clone() {
    local src="${1:?Usage: skenv clone <source> <destination>}"
    local dst="${2:?Usage: skenv clone <source> <destination>}"

    _require_env_exists "$src"
    _ensure_home

    local dst_dir
    dst_dir=$(_env_dir "$dst")
    if [[ -d "$dst_dir" ]]; then
        _error "Environment '$dst' already exists."
        exit 1
    fi

    cp -r "$(_env_dir "$src")" "$dst_dir"
    _info "Cloned ${BOLD}$src${NC} → ${BOLD}$dst${NC}"
}
