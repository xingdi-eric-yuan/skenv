#!/usr/bin/env bash
#
# Build skenv from source modules into a single distributable script.
#
# Usage: ./build.sh
#
# Source files in src/ are concatenated in filename order.
# The first file (1-header.sh) provides the shebang and set -euo pipefail.
# Subsequent files have their leading comments preserved as section markers.
# The output `skenv` is the single-file distributable that users install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/skenv"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Error: src/ directory not found." >&2
    exit 1
fi

# Concatenate source files in order
{
    first=1
    for src_file in "$SRC_DIR"/*.sh; do
        if [[ $first -eq 1 ]]; then
            # First file: include everything (has the shebang)
            cat "$src_file"
            first=0
        else
            # Subsequent files: add a blank line separator, then the content
            echo ""
            cat "$src_file"
        fi
    done
} > "$OUTPUT"

chmod +x "$OUTPUT"

# Verify syntax
if bash -n "$OUTPUT"; then
    lines=$(wc -l < "$OUTPUT" | tr -d ' ')
    echo "✓ Built skenv ($lines lines) from $(ls -1 "$SRC_DIR"/*.sh | wc -l | tr -d ' ') source files."
else
    echo "✗ Syntax error in built script." >&2
    exit 1
fi
