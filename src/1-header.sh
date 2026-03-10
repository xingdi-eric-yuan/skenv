#!/usr/bin/env bash
#
# skenv — virtualenv-style skill environment manager for Claude Code & Copilot CLI
#
# Usage: skenv <command> [arguments]
#
# Run `skenv help` for full command listing, or see README.md.
#

set -euo pipefail

# --- Configuration ---

SKENV_HOME="${SKENV_HOME:-$HOME/.skenv}"
ACTIVE_FILE="$SKENV_HOME/.active"
BASE_DIR="$SKENV_HOME/.base"
REGISTRY_FILE="$SKENV_HOME/.registry"
PRE_SKENV="_pre-skenv"

# Skill directories to sync — supports both Claude Code and Copilot CLI
SKILLS_DIRS=(
    "$HOME/.claude/skills"
    "$HOME/.copilot/skills"
)

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
