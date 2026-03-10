# --- Shell hook (auto-activate + prompt) ---

cmd_hook() {
    local shell_type="${1:-zsh}"
    case "$shell_type" in
        bash|zsh)
            cat <<'HOOK'
# skenv shell hook — add to your .bashrc or .zshrc:
#   eval "$(skenv hook zsh)"  # or bash

_skenv_auto_activate() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.skenv" ]]; then
            local env_name
            env_name=$(cat "$dir/.skenv" | tr -d '[:space:]')
            local skenv_home="${SKENV_HOME:-$HOME/.skenv}"
            # Read env's platform
            local platform="claude"
            if [[ -f "$skenv_home/$env_name/.platform" ]]; then
                platform=$(cat "$skenv_home/$env_name/.platform")
            fi
            local active_file="$skenv_home/.active-$platform"
            local current=""
            [[ -f "$active_file" ]] && current=$(cat "$active_file")
            if [[ -n "$env_name" && "$env_name" != "$current" ]]; then
                # Don't retry a failed activation
                if [[ "${_skenv_last_failed:-}" == "$env_name" ]]; then
                    return
                fi
                if ! skenv activate "$env_name" 2>&1; then
                    _skenv_last_failed="$env_name"
                else
                    _skenv_last_failed=""
                fi
            fi
            return
        fi
        dir=$(dirname "$dir")
    done
    _skenv_last_failed=""
}

_skenv_prompt() {
    local skenv_home="${SKENV_HOME:-$HOME/.skenv}"
    local parts=""
    for p in claude copilot; do
        local af="$skenv_home/.active-$p"
        if [[ -f "$af" ]]; then
            local val
            val=$(cat "$af")
            if [[ -n "$val" ]]; then
                if [[ -n "$parts" ]]; then
                    parts="$parts $p:$val"
                else
                    parts="$p:$val"
                fi
            fi
        fi
    done
    if [[ -n "$parts" ]]; then
        echo "[skenv:${parts}] "
    fi
}

# Auto-activate on directory change
if [[ -n "$ZSH_VERSION" ]]; then
    autoload -U add-zsh-hook
    add-zsh-hook chpwd _skenv_auto_activate
    # Prompt: add $(_skenv_prompt) to your PROMPT, e.g.:
    #   PROMPT='$(_skenv_prompt)%~ %# '
else
    _skenv_prompt_command() {
        _skenv_auto_activate
    }
    PROMPT_COMMAND="_skenv_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    # Prompt: add $(_skenv_prompt) to your PS1, e.g.:
    #   PS1='$(_skenv_prompt)\u@\h:\w\$ '
fi

# Run once on shell startup
_skenv_auto_activate
HOOK
            ;;
        *)
            _error "Unsupported shell: $shell_type (use bash or zsh)"
            exit 1
            ;;
    esac
}

# --- Tab completion ---

cmd_completion() {
    local shell_type="${1:-zsh}"
    case "$shell_type" in
        bash)
            cat <<'COMP'
_skenv_completions() {
    local cur prev commands
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="create activate deactivate install install-package uninstall list ls status clone delete base diff freeze init inherit run hooks registry hook completion help"

    case "$prev" in
        skenv)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        activate|delete|ls|inherit|run)
            local envs=$(ls -1 "${SKENV_HOME:-$HOME/.skenv}/" 2>/dev/null | grep -v '^\.')
            COMPREPLY=($(compgen -W "$envs --claude --copilot" -- "$cur"))
            ;;
        clone|diff)
            local envs=$(ls -1 "${SKENV_HOME:-$HOME/.skenv}/" 2>/dev/null | grep -v '^\.')
            COMPREPLY=($(compgen -W "$envs" -- "$cur"))
            ;;
        uninstall)
            local skenv_home="${SKENV_HOME:-$HOME/.skenv}"
            local active=""
            for p in claude copilot; do
                [[ -f "$skenv_home/.active-$p" ]] && active=$(cat "$skenv_home/.active-$p") && break
            done
            if [[ -n "$active" ]]; then
                local skills=$(ls -1 "$skenv_home/$active/" 2>/dev/null)
                COMPREPLY=($(compgen -W "$skills" -- "$cur"))
            fi
            ;;
        create)
            COMPREPLY=($(compgen -W "--claude --copilot --from" -- "$cur"))
            ;;
        deactivate)
            COMPREPLY=($(compgen -W "--claude --copilot" -- "$cur"))
            ;;
        base)
            COMPREPLY=($(compgen -W "install uninstall ls" -- "$cur"))
            ;;
        registry)
            COMPREPLY=($(compgen -W "add remove list" -- "$cur"))
            ;;
        hooks)
            COMPREPLY=($(compgen -W "apply remove list" -- "$cur"))
            ;;
        install-package)
            COMPREPLY=($(compgen -d -- "$cur"))
            ;;
        hook|completion)
            COMPREPLY=($(compgen -W "bash zsh" -- "$cur"))
            ;;
        install)
            COMPREPLY=($(compgen -d -- "$cur"))
            if [[ -f "${SKENV_HOME:-$HOME/.skenv}/.registry" ]]; then
                local names=$(cut -d'|' -f1 "${SKENV_HOME:-$HOME/.skenv}/.registry" 2>/dev/null)
                COMPREPLY+=($(compgen -W "$names" -- "$cur"))
            fi
            ;;
    esac
}
complete -F _skenv_completions skenv
COMP
            ;;
        zsh)
            cat <<'COMP'
#compdef skenv

_skenv() {
    local -a commands envs skills
    commands=(
        'create:Create a new skill environment'
        'activate:Activate an environment'
        'deactivate:Deactivate the current environment'
        'install:Install a skill into an environment'
        'install-package:Install a skill package (skills + hooks)'
        'uninstall:Remove a skill from an environment'
        'list:List all environments'
        'ls:List skills in an environment'
        'status:Show current active environment'
        'clone:Clone an environment'
        'delete:Delete an environment'
        'base:Manage base layer skills'
        'diff:Compare two environments'
        'freeze:Export env as manifest'
        'init:Create env from manifest'
        'inherit:Set env inheritance'
        'run:Run command with temporary env'
        'hooks:Manage project-level hooks'
        'registry:Manage skill registry'
        'hook:Print shell hook'
        'completion:Print shell completions'
        'help:Show help'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' commands
    elif (( CURRENT >= 3 )); then
        local skenv_home="${SKENV_HOME:-$HOME/.skenv}"
        case "${words[2]}" in
            create)
                local -a flags=('--claude' '--copilot' '--from')
                _describe 'flag' flags
                ;;
            activate|delete|ls|inherit|run|diff)
                envs=($(ls -1 "$skenv_home/" 2>/dev/null | grep -v '^\.'))
                _describe 'environment' envs
                ;;
            clone)
                envs=($(ls -1 "$skenv_home/" 2>/dev/null | grep -v '^\.'))
                _describe 'environment' envs
                ;;
            deactivate)
                local -a flags=('--claude' '--copilot')
                _describe 'flag' flags
                ;;
            uninstall)
                local active=""
                for p in claude copilot; do
                    [[ -f "$skenv_home/.active-$p" ]] && active=$(cat "$skenv_home/.active-$p") && break
                done
                if [[ -n "$active" ]]; then
                    skills=($(ls -1 "$skenv_home/$active/" 2>/dev/null))
                    _describe 'skill' skills
                fi
                ;;
            install)
                _files -/
                if [[ -f "$skenv_home/.registry" ]]; then
                    local -a regnames
                    regnames=($(cut -d'|' -f1 "$skenv_home/.registry" 2>/dev/null))
                    _describe 'registry skill' regnames
                fi
                ;;
            install-package)
                _files -/
                ;;
            hooks)
                if (( CURRENT == 3 )); then
                    local -a subcmds=('apply' 'remove' 'list')
                    _describe 'subcommand' subcmds
                fi
                ;;
            base)
                if (( CURRENT == 3 )); then
                    local -a subcmds=('install' 'uninstall' 'ls')
                    _describe 'subcommand' subcmds
                fi
                ;;
            registry)
                if (( CURRENT == 3 )); then
                    local -a subcmds=('add' 'remove' 'list')
                    _describe 'subcommand' subcmds
                fi
                ;;
            hook|completion)
                local -a shells=('bash' 'zsh')
                _describe 'shell' shells
                ;;
        esac
    fi
}

_skenv "$@"

compdef _skenv skenv
COMP
            ;;
        *)
            _error "Unsupported shell: $shell_type (use bash or zsh)"
            exit 1
            ;;
    esac
}
