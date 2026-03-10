# --- Help ---

cmd_help() {
    cat <<'EOF'
skenv — virtualenv-style skill environment manager for Claude Code & Copilot CLI

USAGE:
  skenv <command> [arguments]

COMMANDS:
  create <name> [--from <env>] Create a new skill environment (optionally from existing)
  activate [-y] <name>      Activate env (clean swap into ~/.claude/skills/ & ~/.copilot/skills/)
  deactivate                 Deactivate (removes all skills from discovery dirs)
  install <path> [opts]      Install a skill (--env N, --link)
  uninstall <name> [opts]    Remove a skill (--env N)
  list                       List all environments (* = active)
  ls [name]                  List skills in an environment (default: active)
  status                     Show current active environment
  clone <src> <dst>          Clone an environment
  delete <name>              Delete an environment
  base install|uninstall|ls  Manage base layer (always-on skills)
  diff <env-a> <env-b>       Compare two environments
  freeze [name]              Export env as manifest (pipe to file)
  init <name> --from <file>  Recreate env from manifest
  inherit <child> <parent>   Set env inheritance
  run <env> -- <cmd...>      Run command with temporary env
  registry add|remove|list   Manage skill registry
  hook [bash|zsh]            Print shell hook (auto-activate + prompt)
  completion [bash|zsh]      Print tab completion script
  help                       Show this help

ENVIRONMENT VARIABLES:
  SKENV_HOME            Base directory for envs (default: ~/.skenv)

SETUP:
  # Add to your .zshrc or .bashrc:
  eval "$(skenv hook zsh)"            # auto-activate + prompt
  eval "$(skenv completion zsh)"      # tab completion

EXAMPLES:
  skenv create research
  skenv activate research
  skenv install ~/my-skills/zsh-shell
  skenv install ~/my-skills/python-research --link
  skenv base install ~/my-skills/always-on-skill
  skenv ls

  skenv create webdev
  skenv activate webdev               # clean switch — only webdev skills
  skenv install react-patterns        # install from registry

  skenv freeze > research.manifest    # export
  skenv init research-v2 --from research.manifest  # recreate

  skenv inherit research-v2 research  # research-v2 extends research
  skenv run research -- claude        # temporary activation

  skenv list                          # shows all envs, * marks active
  skenv diff research webdev          # compare two envs
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
