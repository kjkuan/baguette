# Stack-trace-preserving error handling for Bash.
#
# Despite being included with Baguette, this script works as a standalone
# module that can be sourced alone by other scripts.
#
# **IMPORTANT**
#
# 'err-return' and 'err-exit' are aliases, and aliases are expanded at *parse*
# time; therefore, this file must be sourced *before* any code that uses them
# is parsed -- i.e., source it at the top level, first, and never from within
# a function. Getting this wrong is silent: an unexpanded 'err-return' is just
# a "command not found", and because it's used on the right-hand side of '||',
# the error it was meant to report gets swallowed instead.
#
# **NOTE**
#
# Stack traces are rendered by reading each frame's source line off disk, so
# the '.sh' files of the running script and of any library it sources must stay
# on disk, at the paths they were sourced from, for as long as the process runs.
#
[[ ! ${ERRTRACE_SOURCED:-} ]] || return 0

shopt -s expand_aliases

# Frames that 'caller' reports with a relative path are resolved against this.
# It has to be the directory the process started in, so capture it before the
# script has a chance to 'cd' anywhere.
#
: ${BGT_STARTING_DIR:=$PWD}

alias err-return='{ err-trace; return; }'
alias err-exit='{ err-trace; exit; }'

# Show an optional error message and return the last / or the specified
# exit status while printing the stack trace to STDERR.
#
# This function is meant to replace the use of '|| return' idiom, in order to
# preserve the complete stack trace from the point where the error was raised.
#
# It can also be used as the ERR trap in conjunction with the 'errtrace' (set -E)
# shell option; it works with or without 'errexit' (set -e); however, the
# 'nounset' (set -u) shell option and the use of ${var?} or ${var:?} type of
# parameter expansion should be avoided to preserve stack trace.
#
err-trace () {  # [error-message [status]]
    local rc=${2:-$?}; local opts=$-; set +x
    [[ ! ${1:-} ]] || printf "Error: %s\n" "$1"

    local new_trace=$(while caller $((i++)); do :; done | tac)
    if [[ ${BGT_LAST_TRACE:-} != "$new_trace"* ]]; then
        # NOTE: this checks avoids printing duplicated sub traces as Bash
        # unwinds the stack of calls.

        local caller=${BGT_FROM_ERR_TRAP:-"${FUNCNAME[1]}()"}
        echo
        echo "Stack trace of pid $BASHPID from $caller (most recent first):"
        echo -----------------------------------------------------------------------
        echo "$new_trace" | tac | _print_stacktrace
        echo -----------------------------------------------------------------------

        BGT_LAST_TRACE=$new_trace
    fi
    [[ $opts == *x* ]] && set -x
    return $rc
} >&2

_print_stacktrace () {
    while read -r lineno func file; do
        echo "File $file, line $lineno${func:+", in $func ()"}:"
        [[ $file == /* ]] || file=$BGT_STARTING_DIR/$file
        echo "$(mapfile -tn1 -s $((lineno - 1)) l < "$file"; echo "  $l")"
    done
}

ERRTRACE_SOURCED=x
