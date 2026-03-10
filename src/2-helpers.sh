# --- Output helpers ---

_info()  { echo -e "${GREEN}✓${NC} $*"; }
_warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
_error() { echo -e "${RED}✗${NC} $*" >&2; }
_hint()  { echo -e "  ${CYAN}→${NC} $*"; }

# --- Path and state helpers ---

_ensure_home() {
    mkdir -p "$SKENV_HOME"
}

_skills_dir_for_platform() {
    local platform="$1"
    case "$platform" in
        claude)  echo "$HOME/.claude/skills" ;;
        copilot) echo "$HOME/.copilot/skills" ;;
        *) _error "Unknown platform: $platform"; exit 1 ;;
    esac
}

_active_file_for_platform() {
    echo "$SKENV_HOME/.active-$1"
}

_pre_skenv_for_platform() {
    echo "_pre-skenv-$1"
}

_platform_for_env() {
    local env_name="$1"
    local pfile="$(_env_dir "$env_name")/.platform"
    if [[ -f "$pfile" ]]; then
        cat "$pfile"
    else
        echo "$DEFAULT_PLATFORM"
    fi
}

_get_active() {
    # With arg: return active env for that platform
    # Without arg: return first active env found (claude then copilot)
    local platform="${1:-}"
    if [[ -n "$platform" ]]; then
        local af
        af=$(_active_file_for_platform "$platform")
        if [[ -f "$af" ]]; then
            cat "$af"
        else
            echo ""
        fi
    else
        for p in "$PLATFORM_CLAUDE" "$PLATFORM_COPILOT"; do
            local af
            af=$(_active_file_for_platform "$p")
            if [[ -f "$af" ]]; then
                local val
                val=$(cat "$af")
                if [[ -n "$val" ]]; then
                    echo "$val"
                    return 0
                fi
            fi
        done
        echo ""
    fi
}

_require_active() {
    local platform="${1:-}"
    local active
    active=$(_get_active "$platform")
    if [[ -z "$active" ]]; then
        if [[ -n "$platform" ]]; then
            _error "No active $platform skill environment."
        else
            _error "No active skill environment."
        fi
        _hint "Run: skenv activate <name>"
        exit 1
    fi
    echo "$active"
}

_env_dir() {
    echo "$SKENV_HOME/$1"
}

_require_env_exists() {
    local env_dir
    env_dir=$(_env_dir "$1")
    if [[ ! -d "$env_dir" ]]; then
        _error "Environment '$1' does not exist."
        _hint "Run: skenv create $1"
        exit 1
    fi
}
