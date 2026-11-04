import Foundation

/// Shell integration comes in through start arguments and environment variables.
/// The user's `.zshrc` and `.bashrc` stay untouched.
public enum ShellIntegration {
    public static var directory: URL { EntermPaths.support.appendingPathComponent("shell", isDirectory: true) }

    public static func install() {
        let zsh = directory.appendingPathComponent("zsh", isDirectory: true)
        try? FileManager.default.createDirectory(at: zsh, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? zshEnv.write(to: zsh.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
        try? zshIntegration.write(to: directory.appendingPathComponent("integration.zsh"), atomically: true, encoding: .utf8)
        try? bashInit.write(to: directory.appendingPathComponent("init.bash"), atomically: true, encoding: .utf8)
    }

    /// Returns argv and environment changes for the user's login shell.
    public static func shellCommand(shell: String, environment: [String: String]) -> (path: String, argv: [String], env: [String: String]) {
        let name = URL(fileURLWithPath: shell).lastPathComponent
        var env: [String: String] = [:]
        switch name {
        case "zsh":
            if let current = environment["ZDOTDIR"], !current.isEmpty { env["ENTERM_USER_ZDOTDIR"] = current }
            env["ZDOTDIR"] = directory.appendingPathComponent("zsh").path
            return (shell, ["-zsh"], env)
        case "bash":
            return (shell, ["bash", "--init-file", directory.appendingPathComponent("init.bash").path], env)
        default:
            return (shell, ["-\(name)"], env)
        }
    }

    static let zshEnv = #"""
    # Enterm: restores the user's ZDOTDIR, reads the user's own files, then adds the integration.
    ENTERM_INTEGRATION_DIR="${ZDOTDIR:h}"
    if [[ -n "${ENTERM_USER_ZDOTDIR-}" ]]; then
      ZDOTDIR="$ENTERM_USER_ZDOTDIR"
    else
      unset ZDOTDIR
    fi
    unset ENTERM_USER_ZDOTDIR
    [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"
    [[ -o interactive && -r "$ENTERM_INTEGRATION_DIR/integration.zsh" ]] && source "$ENTERM_INTEGRATION_DIR/integration.zsh"
    """#

    static let zshIntegration = #"""
    # Enterm: runs after the user's .zshrc through the first prompt hook.
    autoload -Uz add-zsh-hook

    _enterm_cwd() { printf '\e]7;file://%s%s\a' "${HOST:-localhost}" "${PWD// /%20}" }

    _enterm_install() {
      add-zsh-hook -d precmd _enterm_install
      add-zsh-hook precmd _enterm_cwd
      _enterm_cwd
      (( ${+functions[command_not_found_handler]} )) && functions[_enterm_prior_cnf]=$functions[command_not_found_handler]
      command_not_found_handler() {
        case "$1" in
          claude|codex|agy|gemini) [[ -n "$ENTERM_CLI" ]] && "$ENTERM_CLI" event cnf "$1" >/dev/null 2>&1 ;;
        esac
        if (( ${+functions[_enterm_prior_cnf]} )); then _enterm_prior_cnf "$@"; return $?; fi
        print -u2 -r -- "zsh: command not found: $1"
        return 127
      }
      local tool
      for tool in claude codex agy; do
        (( ${+aliases[$tool]} )) && continue
        eval "$tool() { if builtin whence -p $tool >/dev/null; then if [[ ! -x \"\$ENTERM_CLI\" ]]; then command $tool \"\$@\"; return \$?; fi; \"\$ENTERM_CLI\" event launch $tool; \"\$ENTERM_CLI\" wrap $tool \"\$@\"; local code=\$?; \"\$ENTERM_CLI\" event launchEnd $tool; return \$code; else command_not_found_handler $tool \"\$@\"; fi }"
      done
      if [[ -n "${ENTERM_STARTUP-}" ]]; then
        (( ${+widgets[zle-line-init]} )) && zle -A zle-line-init _enterm_prior_line_init
        _enterm_startup_widget() {
          (( ${+widgets[_enterm_prior_line_init]} )) && zle _enterm_prior_line_init
          if [[ -n "${ENTERM_STARTUP-}" ]]; then
            BUFFER="$ENTERM_STARTUP"
            unset ENTERM_STARTUP
            zle accept-line
          fi
        }
        zle -N zle-line-init _enterm_startup_widget
      fi
    }
    add-zsh-hook precmd _enterm_install
    """#

    static let bashInit = #"""
    # Enterm: reads the user's files as a login shell would, then adds the integration.
    [ -r /etc/profile ] && source /etc/profile
    if [ -r "$HOME/.bash_profile" ]; then source "$HOME/.bash_profile"
    elif [ -r "$HOME/.bash_login" ]; then source "$HOME/.bash_login"
    elif [ -r "$HOME/.profile" ]; then source "$HOME/.profile"
    elif [ -r "$HOME/.bashrc" ]; then source "$HOME/.bashrc"; fi

    _enterm_prompt() {
      local code=$?
      printf '\e]7;file://%s%s\a' "${HOSTNAME:-localhost}" "${PWD// /%20}"
      if [ "$code" = 127 ]; then
        local word
        word=$(HISTTIMEFORMAT= builtin history 1 | awk '{print $2}')
        case "$word" in
          claude|codex|agy|gemini) [ -n "$ENTERM_CLI" ] && "$ENTERM_CLI" event cnf "$word" >/dev/null 2>&1 ;;
        esac
      fi
      if [ -n "${ENTERM_STARTUP-}" ]; then
        local startup="$ENTERM_STARTUP"
        unset ENTERM_STARTUP
        printf '%s\n' "$startup"
        eval "$startup"
      fi
    }
    PROMPT_COMMAND="_enterm_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    for _enterm_tool in claude codex agy; do
      eval "$_enterm_tool() { if type -P $_enterm_tool >/dev/null; then if [ ! -x \"\$ENTERM_CLI\" ]; then command $_enterm_tool \"\$@\"; return \$?; fi; \"\$ENTERM_CLI\" event launch $_enterm_tool; \"\$ENTERM_CLI\" wrap $_enterm_tool \"\$@\"; local code=\$?; \"\$ENTERM_CLI\" event launchEnd $_enterm_tool; return \$code; else [ -n \"\$ENTERM_CLI\" ] && \"\$ENTERM_CLI\" event cnf $_enterm_tool >/dev/null 2>&1; echo \"bash: $_enterm_tool: command not found\" >&2; return 127; fi; }"
    done
    unset _enterm_tool
    """#
}

/// A service outlives its window, so the app can move while the service still knows the old place.
public enum CompanionPath {
    /// The service's own companion while it exists, otherwise the one the window reported.
    public static func choose(own: String, reported: String?,
                              isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String {
        if isExecutable(own) { return own }
        guard let reported, URL(fileURLWithPath: reported).lastPathComponent == "enterm", isExecutable(reported) else { return own }
        return reported
    }
}
