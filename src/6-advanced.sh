# --- Base layer ---

cmd_base() {
    local subcmd="${1:?Usage: skenv base install <path> | uninstall <name> | ls}"
    shift

    case "$subcmd" in
        install)
            local skill_path="${1:?Usage: skenv base install <skill-path>}"
            shift
            local link_mode=0
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --link) link_mode=1; shift ;;
                    *) _error "Unknown option: $1"; exit 1 ;;
                esac
            done

            skill_path=$(realpath "$skill_path" 2>/dev/null || echo "$skill_path")
            if [[ ! -d "$skill_path" ]]; then
                _error "Skill path '$skill_path' is not a directory."
                exit 1
            fi

            mkdir -p "$BASE_DIR"
            local skill_name
            skill_name=$(basename "$skill_path")
            local dest="$BASE_DIR/$skill_name"

            if [[ -e "$dest" ]]; then
                _warn "Base skill '$skill_name' already exists. Replacing."
                rm -rf "$dest"
            fi

            if [[ $link_mode -eq 1 ]]; then
                ln -sf "$skill_path" "$dest"
                _write_meta "$dest" "$skill_path" "link"
            else
                cp -r "$skill_path" "$dest"
                _write_meta "$dest" "$skill_path" "copy"
            fi
            _info "Installed ${BOLD}$skill_name${NC} into ${BOLD}base layer${NC}"

            local current
            current=$(_get_active)
            if [[ -n "$current" ]]; then
                _sync_skills "$current"
                _hint "Active environment updated."
            fi
            ;;
        uninstall)
            local skill_name="${1:?Usage: skenv base uninstall <skill-name>}"
            local target="$BASE_DIR/$skill_name"
            if [[ ! -e "$target" && ! -L "$target" ]]; then
                _error "Skill '$skill_name' not found in base layer."
                exit 1
            fi
            rm -rf "$target"
            _info "Uninstalled ${BOLD}$skill_name${NC} from ${BOLD}base layer${NC}"

            local current
            current=$(_get_active)
            if [[ -n "$current" ]]; then
                _sync_skills "$current"
                _hint "Active environment updated."
            fi
            ;;
        ls)
            echo -e "${BOLD}Base layer skills (always active):${NC}"
            if [[ ! -d "$BASE_DIR" ]] || [[ -z "$(ls -A "$BASE_DIR" 2>/dev/null)" ]]; then
                _warn "No base skills installed."
                _hint "Run: skenv base install <skill-path>"
                return 0
            fi
            for skill in "$BASE_DIR"/*; do
                [[ -e "$skill" || -L "$skill" ]] || continue
                local skill_name
                skill_name=$(basename "$skill")
                [[ "$skill_name" == .* || "$skill_name" == *.skenv-meta ]] && continue
                local meta_line=""
                meta_line=$(_read_meta_summary "$skill")
                if [[ -L "$skill" ]]; then
                    echo -e "  ${BLUE}•${NC} ${BOLD}$skill_name${NC} ${CYAN}(linked)${NC}${meta_line}"
                else
                    echo -e "  ${BLUE}•${NC} ${BOLD}$skill_name${NC}${meta_line}"
                fi
            done
            ;;
        *)
            _error "Unknown base subcommand: $subcmd"
            _hint "Usage: skenv base install <path> | uninstall <name> | ls"
            exit 1
            ;;
    esac
}

# --- Diff ---

cmd_diff() {
    local env_a="${1:?Usage: skenv diff <env-a> <env-b>}"
    local env_b="${2:?Usage: skenv diff <env-a> <env-b>}"
    _require_env_exists "$env_a"
    _require_env_exists "$env_b"

    local dir_a dir_b
    dir_a=$(_env_dir "$env_a")
    dir_b=$(_env_dir "$env_b")

    local -a skills_a=() skills_b=()
    for s in "$dir_a"/*; do
        [[ -e "$s" || -L "$s" ]] || continue
        local bn; bn=$(basename "$s")
        [[ "$bn" == .* || "$bn" == *.skenv-meta ]] && continue
        skills_a+=("$bn")
    done
    for s in "$dir_b"/*; do
        [[ -e "$s" || -L "$s" ]] || continue
        local bn; bn=$(basename "$s")
        [[ "$bn" == .* || "$bn" == *.skenv-meta ]] && continue
        skills_b+=("$bn")
    done

    local only_a=() only_b=() common=()
    for s in "${skills_a[@]+"${skills_a[@]}"}"; do
        if printf '%s\n' "${skills_b[@]+"${skills_b[@]}"}" | grep -qxF "$s"; then
            common+=("$s")
        else
            only_a+=("$s")
        fi
    done
    for s in "${skills_b[@]+"${skills_b[@]}"}"; do
        printf '%s\n' "${skills_a[@]+"${skills_a[@]}"}" | grep -qxF "$s" || only_b+=("$s")
    done

    echo -e "${BOLD}Diff: $env_a ↔ $env_b${NC}"
    echo ""
    if [[ ${#only_a[@]} -gt 0 ]]; then
        echo -e "  ${RED}Only in $env_a:${NC}"
        for s in "${only_a[@]}"; do echo -e "    ${RED}-${NC} $s"; done
    fi
    if [[ ${#only_b[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Only in $env_b:${NC}"
        for s in "${only_b[@]}"; do echo -e "    ${GREEN}+${NC} $s"; done
    fi
    if [[ ${#common[@]} -gt 0 ]]; then
        echo -e "  ${BLUE}Common:${NC}"
        for s in "${common[@]}"; do echo -e "    ${BLUE}=${NC} $s"; done
    fi
    if [[ ${#only_a[@]} -eq 0 && ${#only_b[@]} -eq 0 ]]; then
        _info "Environments are identical."
    fi
}

# --- Freeze / Init ---

cmd_freeze() {
    local env_name="${1:-}"
    if [[ -z "$env_name" ]]; then
        env_name=$(_require_active)
    fi
    _require_env_exists "$env_name"

    local env_dir
    env_dir=$(_env_dir "$env_name")

    echo "# skenv manifest for: $env_name"
    echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    for skill in "$env_dir"/*; do
        [[ -e "$skill" || -L "$skill" ]] || continue
        local skill_name source mode
        skill_name=$(basename "$skill")
        [[ "$skill_name" == .* || "$skill_name" == *.skenv-meta ]] && continue
        source=$(_read_meta "$skill" "source")
        mode=$(_read_meta "$skill" "mode")

        if [[ -n "$source" ]]; then
            echo "${skill_name}|${source}|${mode:-copy}"
        else
            echo "${skill_name}||copy"
        fi
    done

    if [[ -d "$BASE_DIR" ]]; then
        for skill in "$BASE_DIR"/*; do
            [[ -e "$skill" || -L "$skill" ]] || continue
            local skill_name source mode
            skill_name=$(basename "$skill")
            [[ "$skill_name" == .* || "$skill_name" == *.skenv-meta ]] && continue
            source=$(_read_meta "$skill" "source")
            mode=$(_read_meta "$skill" "mode")
            echo "@base:${skill_name}|${source:-}|${mode:-copy}"
        done
    fi
}

cmd_init() {
    local name="${1:?Usage: skenv init <name> --from <manifest>}"
    shift

    local manifest=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) manifest="$2"; shift 2 ;;
            *) _error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$manifest" ]]; then
        _error "No manifest specified."
        _hint "Usage: skenv init <name> --from <manifest-file>"
        exit 1
    fi

    if [[ ! -f "$manifest" ]]; then
        _error "Manifest file '$manifest' not found."
        exit 1
    fi

    cmd_create "$name"

    local env_dir
    env_dir=$(_env_dir "$name")

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        local is_base=0
        if [[ "$line" == @base:* ]]; then
            is_base=1
            line="${line#@base:}"
        fi

        IFS='|' read -r skill_name source mode <<< "$line"

        if [[ -z "$source" || ! -d "$source" ]]; then
            _warn "Skipping '$skill_name' — source not found: ${source:-<none>}"
            continue
        fi

        local dest
        if [[ $is_base -eq 1 ]]; then
            mkdir -p "$BASE_DIR"
            dest="$BASE_DIR/$skill_name"
        else
            dest="$env_dir/$skill_name"
        fi

        if [[ "$mode" == "link" ]]; then
            ln -sf "$source" "$dest"
        else
            cp -r "$source" "$dest"
        fi
        _write_meta "$dest" "$source" "$mode"

        local target_label="$name"
        [[ $is_base -eq 1 ]] && target_label="base"
        _info "Restored ${BOLD}$skill_name${NC} into ${BOLD}$target_label${NC}"
    done < "$manifest"
}

# --- Inheritance ---

cmd_inherit() {
    local child="${1:?Usage: skenv inherit <child-env> <parent-env>}"
    local parent="${2:?Usage: skenv inherit <child-env> <parent-env>}"
    _require_env_exists "$child"
    _require_env_exists "$parent"

    if [[ "$child" == "$parent" ]]; then
        _error "An environment cannot inherit from itself."
        exit 1
    fi

    # Validate no cycles BEFORE writing .parent
    local parent_file="$(_env_dir "$child")/.parent"
    local old_parent=""
    [[ -f "$parent_file" ]] && old_parent=$(cat "$parent_file")

    echo "$parent" > "$parent_file"
    # Test the chain — _resolve_env_chain exits 1 on cycle (runs in subshell)
    local chain_test=""
    chain_test=$(_resolve_env_chain "$child" 2>/dev/null) || {
        # Restore old state on cycle detection
        if [[ -n "$old_parent" ]]; then
            echo "$old_parent" > "$parent_file"
        else
            rm -f "$parent_file"
        fi
        _error "Inheritance cycle detected: $child → $parent creates a loop."
        exit 1
    }

    _info "${BOLD}$child${NC} now inherits from ${BOLD}$parent${NC}"

    local current
    current=$(_get_active)
    if [[ "$current" == "$child" ]]; then
        _sync_skills "$child"
        _hint "Active environment updated."
    fi
}

# --- Run with temporary env ---

cmd_run() {
    local env_name="${1:?Usage: skenv run <env> -- <command...>}"
    shift
    _require_env_exists "$env_name"

    if [[ "${1:-}" != "--" ]]; then
        _error "Expected '--' before command."
        _hint "Usage: skenv run <env> -- <command...>"
        exit 1
    fi
    shift

    if [[ $# -eq 0 ]]; then
        _error "No command specified."
        exit 1
    fi

    local previous
    previous=$(_get_active)

    _ensure_home

    # Trap to restore state on signals
    _cmd_run_restore() {
        if [[ -n "$previous" ]]; then
            echo "$previous" > "$ACTIVE_FILE"
            _sync_skills "$previous"
        else
            rm -f "$ACTIVE_FILE"
            for skills_dir in "${SKILLS_DIRS[@]}"; do
                _wipe_skills_dir "$skills_dir"
            done
        fi
    }
    trap _cmd_run_restore EXIT

    echo "$env_name" > "$ACTIVE_FILE"
    _sync_skills "$env_name"

    local exit_code=0
    "$@" || exit_code=$?

    _cmd_run_restore
    trap - EXIT

    return $exit_code
}

# --- Skill registry ---

cmd_registry() {
    local subcmd="${1:?Usage: skenv registry add <name> <path> | remove <name> | list}"
    shift

    case "$subcmd" in
        add)
            local name="${1:?Usage: skenv registry add <name> <path>}"
            local path="${2:?Usage: skenv registry add <name> <path>}"
            path=$(realpath "$path")
            if [[ ! -d "$path" ]]; then
                _error "Path '$path' is not a directory."
                exit 1
            fi
            _ensure_home
            if [[ -f "$REGISTRY_FILE" ]]; then
                awk -F'|' -v n="$name" '$1 != n' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" || true
                mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
            fi
            echo "${name}|${path}" >> "$REGISTRY_FILE"
            _info "Registered ${BOLD}$name${NC} → $path"
            ;;
        remove)
            local name="${1:?Usage: skenv registry remove <name>}"
            if [[ ! -f "$REGISTRY_FILE" ]]; then
                _error "Registry is empty."
                exit 1
            fi
            if ! awk -F'|' -v n="$name" '$1 == n { found=1 } END { exit !found }' "$REGISTRY_FILE"; then
                _error "Skill '$name' not found in registry."
                exit 1
            fi
            awk -F'|' -v n="$name" '$1 != n' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" || true
            mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
            _info "Removed ${BOLD}$name${NC} from registry."
            ;;
        list)
            if [[ ! -f "$REGISTRY_FILE" || ! -s "$REGISTRY_FILE" ]]; then
                _warn "Registry is empty."
                _hint "Run: skenv registry add <name> <path>"
                return 0
            fi
            echo -e "${BOLD}Skill registry:${NC}"
            while IFS='|' read -r name path; do
                if [[ -d "$path" ]]; then
                    echo -e "  ${BLUE}•${NC} ${BOLD}$name${NC} → $path"
                else
                    echo -e "  ${BLUE}•${NC} ${BOLD}$name${NC} → $path ${RED}(missing)${NC}"
                fi
            done < "$REGISTRY_FILE"
            ;;
        *)
            _error "Unknown registry subcommand: $subcmd"
            _hint "Usage: skenv registry add <name> <path> | remove <name> | list"
            exit 1
            ;;
    esac
}

_resolve_install_path() {
    local arg="$1"
    if [[ -d "$arg" ]]; then
        echo "$arg"
        return 0
    fi
    if [[ -f "$REGISTRY_FILE" ]]; then
        local path
        path=$(awk -F'|' -v n="$arg" '$1 == n { print $2; exit }' "$REGISTRY_FILE" || true)
        if [[ -n "$path" && -d "$path" ]]; then
            echo "$path"
            return 0
        fi
    fi
    echo "$arg"
}
