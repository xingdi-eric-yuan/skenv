# --- Skill metadata tracking ---
#
# Each installed skill gets a .skenv-meta file recording its source path,
# install timestamp, install mode (copy/link), and a content hash.
# For symlinked skills, meta is stored alongside as <name>.skenv-meta.

_write_meta() {
    local skill_dir="$1"
    local source_path="$2"
    local install_mode="${3:-copy}"

    local meta_file
    if [[ -L "$skill_dir" ]]; then
        meta_file="${skill_dir}.skenv-meta"
    else
        meta_file="$skill_dir/.skenv-meta"
    fi

    local hash=""
    if [[ -d "$source_path" ]]; then
        hash=$(find "$source_path" -type f -exec cat {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    fi

    cat > "$meta_file" <<EOF
source=$source_path
installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mode=$install_mode
hash=$hash
EOF
}

_read_meta() {
    local skill_dir="$1"
    local key="$2"
    local meta_file

    if [[ -L "$skill_dir" ]]; then
        meta_file="${skill_dir}.skenv-meta"
    else
        meta_file="$skill_dir/.skenv-meta"
    fi

    if [[ -f "$meta_file" ]]; then
        grep "^${key}=" "$meta_file" 2>/dev/null | cut -d= -f2-
    fi
}

_read_meta_summary() {
    local skill_dir="$1"
    local source
    source=$(_read_meta "$skill_dir" "source")
    if [[ -n "$source" ]]; then
        echo -e " ${YELLOW}← ${source}${NC}"
    fi
}

_is_skill_outdated() {
    local skill_dir="$1"
    local stored_hash source current_hash
    stored_hash=$(_read_meta "$skill_dir" "hash")
    source=$(_read_meta "$skill_dir" "source")

    [[ -z "$stored_hash" || -z "$source" || ! -d "$source" ]] && return 1

    current_hash=$(find "$source" -type f -exec cat {} + 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    [[ "$stored_hash" != "$current_hash" ]]
}
