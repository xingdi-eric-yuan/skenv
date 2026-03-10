# --- Output helpers ---

_info()  { echo -e "${GREEN}✓${NC} $*"; }
_warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
_error() { echo -e "${RED}✗${NC} $*" >&2; }
_hint()  { echo -e "  ${CYAN}→${NC} $*"; }

# --- Path and state helpers ---

_ensure_home() {
    mkdir -p "$SKENV_HOME"
}

_get_active() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        cat "$ACTIVE_FILE"
    else
        echo ""
    fi
}

_require_active() {
    local active
    active=$(_get_active)
    if [[ -z "$active" ]]; then
        _error "No active skill environment."
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
