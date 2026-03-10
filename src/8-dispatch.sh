# --- Help ---

cmd_help() {
    cat <<'EOF'
skenv — virtualenv-style skill environment manager for Claude Code & Copilot CLI

USAGE:
  skenv <command> [arguments]

COMMANDS:
  create <name> [opts]         Create a new skill environment
                               --claude (default) or --copilot to set platform
                               --from <env> to copy from existing env
  activate [-y] <name>         Activate env (symlinks into platform's skills dir)
  deactivate [--claude|--copilot]  Deactivate env(s) (no flag = deactivate all)
  install <path> [opts]        Install a skill (--env N, --link)
  uninstall <name> [opts]      Remove a skill (--env N)
  list                         List all environments (* = active, shows platform)
  ls [name]                    List skills in an environment (default: active)
  status                       Show active environment(s) per platform
  clone <src> <dst>            Clone an environment (preserves platform)
  delete <name>                Delete an environment
  base install|uninstall|ls    Manage base layer (always-on skills, all platforms)
  diff <env-a> <env-b>         Compare two environments
  freeze [name]                Export env as manifest (pipe to file)
  init <name> --from <file>    Recreate env from manifest (--claude|--copilot)
  inherit <child> <parent>     Set env inheritance (same platform only)
  run <env> -- <cmd...>        Run command with temporary env
  registry add|remove|list     Manage skill registry
  hook [bash|zsh]              Print shell hook (auto-activate + prompt)
  completion [bash|zsh]        Print tab completion script
  help                         Show this help

PLATFORMS:
  Each environment targets exactly one platform:
    --claude   → manages ~/.claude/skills/   (default)
    --copilot  → manages ~/.copilot/skills/

  You can have one active env per platform simultaneously.

ENVIRONMENT VARIABLES:
  SKENV_HOME            Base directory for envs (default: ~/.skenv)

SETUP:
  # Add to your .zshrc or .bashrc:
  eval "$(skenv hook zsh)"            # auto-activate + prompt
  eval "$(skenv completion zsh)"      # tab completion

EXAMPLES:
  skenv create research                   # claude env (default)
  skenv create copilot-dev --copilot      # copilot env
  skenv activate research                 # activates in ~/.claude/skills/
  skenv activate copilot-dev              # activates in ~/.copilot/skills/
  skenv status                            # shows both active envs

  skenv install ~/my-skills/python-research --link
  skenv base install ~/my-skills/always-on-skill
  skenv ls

  skenv deactivate --claude               # deactivate only claude
  skenv deactivate                        # deactivate all

  skenv freeze > research.manifest        # export (includes platform)
  skenv init research-v2 --from research.manifest  # recreate

  skenv inherit research-v2 research      # must be same platform
  skenv run research -- claude            # temporary activation
  skenv diff research webdev              # compare two envs
EOF
}

# --- Main dispatch ---

command="${1:-help}"
shift || true

case "$command" in
    create)     cmd_create "$@" ;;
    activate)   cmd_activate "$@" ;;
    deactivate) cmd_deactivate "$@" ;;
    install)
        if [[ $# -gt 0 ]]; then
            resolved=$(_resolve_install_path "$1")
            shift
            cmd_install "$resolved" "$@"
        else
            cmd_install "$@"
        fi
        ;;
    uninstall)  cmd_uninstall "$@" ;;
    list)       cmd_list "$@" ;;
    ls)         cmd_ls "$@" ;;
    status)     cmd_status "$@" ;;
    delete)     cmd_delete "$@" ;;
    clone)      cmd_clone "$@" ;;
    base)       cmd_base "$@" ;;
    diff)       cmd_diff "$@" ;;
    freeze)     cmd_freeze "$@" ;;
    init)       cmd_init "$@" ;;
    inherit)    cmd_inherit "$@" ;;
    run)        cmd_run "$@" ;;
    registry)   cmd_registry "$@" ;;
    hook)       cmd_hook "$@" ;;
    completion) cmd_completion "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
        _error "Unknown command: $command"
        _hint "Run: skenv help"
        exit 1
        ;;
esac
