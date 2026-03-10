# --- Core engine ---
#
# These functions implement the central mechanism: wiping skill directories
# and re-symlinking from the active environment, respecting the layering
# order: base -> parent envs -> active env.

_wipe_skills_dir() {
    local skills_dir="$1"
    if [[ -d "$skills_dir" ]]; then
        find "$skills_dir" -maxdepth 1 -mindepth 1 \( -type l -o -type d \) -exec rm -rf {} +
    fi
}

_link_skills_from() {
    # Symlink all skills from a source dir into a target skills dir.
    # Overwrites existing entries (later layer wins).
    local src_dir="$1"
    local target_dir="$2"

    for skill in "$src_dir"/*; do
        [[ -e "$skill" || -L "$skill" ]] || continue
        local skill_name
        skill_name=$(basename "$skill")
        [[ "$skill_name" == *.skenv-meta || "$skill_name" == .* ]] && continue
        rm -rf "$target_dir/$skill_name"
        ln -sf "$skill" "$target_dir/$skill_name"
    done
}

_resolve_env_chain() {
    # Walk the .parent chain for an env, returning parent-first order.
    # The env itself is appended last (highest priority). Detects cycles.
    local env_name="$1"
    local -a chain=()
    local -a visited=()
    local current="$env_name"

    while [[ -n "$current" ]]; do
        for v in "${visited[@]+"${visited[@]}"}"; do
            if [[ "$v" == "$current" ]]; then
                _error "Inheritance cycle detected involving '$current'."
                exit 1
            fi
        done
        visited+=("$current")

        local parent_file="$(_env_dir "$current")/.parent"
        if [[ -f "$parent_file" ]]; then
            local parent
            parent=$(cat "$parent_file")
            if [[ -n "$parent" && -d "$(_env_dir "$parent")" ]]; then
                chain=("$parent" "${chain[@]+"${chain[@]}"}")
                current="$parent"
            else
                current=""
            fi
        else
            current=""
        fi
    done

    chain+=("$env_name")
    # Use pipe delimiter to handle env names safely
    local IFS='|'
    echo "${chain[*]}"
}

_sync_skills() {
    # Clean wipe-and-replace: true venv-style isolation.
    # Layering: base -> parent envs (if inherited) -> active env.
    # Now targets a single platform dir based on env's platform.
    local env_name="$1"

    local platform
    platform=$(_platform_for_env "$env_name")
    local skills_dir
    skills_dir=$(_skills_dir_for_platform "$platform")

    local chain_str
    chain_str=$(_resolve_env_chain "$env_name")
    local -a chain=()
    IFS='|' read -ra chain <<< "$chain_str"

    mkdir -p "$skills_dir"
    _wipe_skills_dir "$skills_dir"

    # Base layer (always present)
    if [[ -d "$BASE_DIR" ]]; then
        _link_skills_from "$BASE_DIR" "$skills_dir"
    fi

    # Inheritance chain (parent first, child last = child wins)
    for link_env in "${chain[@]}"; do
        local link_dir
        link_dir=$(_env_dir "$link_env")
        if [[ -d "$link_dir" ]]; then
            _link_skills_from "$link_dir" "$skills_dir"
        fi
    done
}

_auto_import() {
    local skip_confirm="${1:-0}"
    local target_env="${2:-}"
    # On first use per platform, snapshot existing skills into _pre-skenv-<platform>.
    # Preserves symlinks as symlinks so external references stay linked.

    local platform="$PLATFORM_CLAUDE"
    if [[ -n "$target_env" ]]; then
        platform=$(_platform_for_env "$target_env")
    fi

    local pre_name
    pre_name=$(_pre_skenv_for_platform "$platform")
    local pre_dir
    pre_dir=$(_env_dir "$pre_name")
    [[ -d "$pre_dir" ]] && return 0

    local skills_dir
    skills_dir=$(_skills_dir_for_platform "$platform")

    # Check if there are existing skills to protect
    local has_skills=0
    if [[ -d "$skills_dir" ]] && [[ -n "$(ls -A "$skills_dir" 2>/dev/null)" ]]; then
        has_skills=1
    fi

    if [[ $has_skills -eq 1 ]] && [[ "$skip_confirm" -ne 1 ]] && [[ "${SKENV_YES:-}" != "1" ]]; then
        echo ""
        _warn "${BOLD}First-time setup for $platform — please read carefully.${NC}"
        echo ""
        echo -e "  skenv will manage this skill directory:"
        local count=0
        [[ -d "$skills_dir" ]] && count=$(find "$skills_dir" -maxdepth 1 -mindepth 1 \( -type l -o -type d \) 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${CYAN}$skills_dir${NC}  ($count skills)"
        echo ""
        echo -e "  On activate, skenv ${RED}replaces all contents${NC} of this directory"
        echo -e "  with symlinks to the active environment."
        echo ""
        echo -e "  skenv will snapshot your current skills into a ${BOLD}$pre_name${NC} environment,"
        echo -e "  but we strongly recommend you back them up yourself first."
        echo ""
        echo -n -e "  ${BOLD}Have you backed up your skills? [y/N]${NC} "

        local answer
        read -r answer
        case "$answer" in
            [yY]|[yY][eE][sS])
                ;;
            *)
                _error "Aborting. Please back up your skills first, then try again."
                _hint "Example: cp -r $skills_dir ~/skills-backup-$platform"
                exit 1
                ;;
        esac
    fi

    local imported=0
    mkdir -p "$pre_dir"
    # Tag the backup env with its platform
    echo "$platform" > "$pre_dir/.platform"

    if [[ -d "$skills_dir" ]]; then
        for item in "$skills_dir"/*; do
            [[ -e "$item" || -L "$item" ]] || continue
            local name
            name=$(basename "$item")
            [[ -e "$pre_dir/$name" || -L "$pre_dir/$name" ]] && continue

            if [[ -L "$item" ]]; then
                local target
                target=$(readlink "$item")
                # Resolve relative symlinks to absolute paths
                if [[ "$target" != /* ]]; then
                    target="$(cd "$(dirname "$item")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
                fi
                ln -s "$target" "$pre_dir/$name"
            else
                cp -r "$item" "$pre_dir/$name"
            fi
            imported=$((imported + 1))
        done
    fi

    if [[ $imported -gt 0 ]]; then
        _info "Imported $imported existing $platform skill(s) into ${BOLD}$pre_name${NC} environment."
        _hint "Run 'skenv activate $pre_name' anytime to restore your original $platform skills."

        # Offer to copy existing skills into the target environment
        if [[ -n "$target_env" ]] && [[ "$target_env" != "$pre_name" ]]; then
            local target_dir
            target_dir=$(_env_dir "$target_env")
            local do_import=0
            if [[ "$skip_confirm" -eq 1 ]] || [[ "${SKENV_YES:-}" == "1" ]]; then
                : # non-interactive mode: don't import unless explicitly asked
            else
                echo ""
                echo -n -e "  ${BOLD}Import these skills into '$target_env'? [y/N]${NC} "
                local import_answer
                read -r import_answer
                case "$import_answer" in
                    [yY]|[yY][eE][sS]) do_import=1 ;;
                esac
            fi
            if [[ $do_import -eq 1 ]]; then
                for item in "$pre_dir"/*; do
                    [[ -e "$item" || -L "$item" ]] || continue
                    local skill_name
                    skill_name=$(basename "$item")
                    [[ "$skill_name" == *.skenv-meta ]] && continue
                    [[ "$skill_name" == .* ]] && continue
                    # Skip if target already has this skill
                    [[ -e "$target_dir/$skill_name" || -L "$target_dir/$skill_name" ]] && continue
                    if [[ -L "$item" ]]; then
                        local link_target
                        link_target=$(readlink "$item")
                        ln -s "$link_target" "$target_dir/$skill_name"
                    else
                        cp -r "$item" "$target_dir/$skill_name"
                    fi
                done
                _info "Copied $imported skill(s) into ${BOLD}$target_env${NC}."
            fi
        fi
    fi
}
