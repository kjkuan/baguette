[[ ! ${BGT_SOURCED:-} ]] || return 0

BGT_HOME=$(cd "$(dirname "$BASH_SOURCE")" && pwd) || return
export BGT_HOME

BGT_STARTING_DIR=$PWD

# --- Options for websocketd ------------------------------------
: ${WSD_ADDR:=0.0.0.0}
: ${WSD_PORT:=8080}

[[ ${WSD_SCRIPT_DIR:-} ]] || {
    WSD_SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || return
}
[[ ${WSD_CGI_DIR:-} ]] || WSD_CGI_DIR=$WSD_SCRIPT_DIR/cgi-bin
[[ ${WSD_PUBLIC_DIR:-} ]] || WSD_PUBLIC_DIR=$WSD_SCRIPT_DIR/public

# If no public/, then use the default one in Baguette.
[[ -d $WSD_PUBLIC_DIR ]] || WSD_PUBLIC_DIR=$BGT_HOME/public

# If no cgi-bin/, then use the default one in Baguette.
[[ -d $WSD_CGI_DIR ]] || WSD_CGI_DIR=$BGT_HOME/cgi-bin

export WSD_ADDR WSD_PORT WSD_SCRIPT_DIR WSD_PUBLIC_DIR

# Array for additional options that overrides the websocketd launch command
WSD_OPTS=()

# --------------------------------------------------------------

# For logging execution trace (set -x) and stderr; empty means no tracing.
BGT_TRACE_FILE=; # E.g., BGT_TRACE_FILE=bgt.xtrace

# For logging stderr and the last stack trace
: ${BGT_STACK_TRACE_FILE="${0##*/}.strace"}

# Set this to non-empty if you wish to flash any outputs to STDERR
# Default is yes if errexit (set -e) is enabled.
#
if [[ ! -v BGT_FLASH_STDERR && $- == *e* ]]; then
    BGT_FLASH_STDERR=x
fi

# Commands to be executed after rendering the html response.
#
BGT_POST_RENDER_QUEUE=()

# Commands to be executed on EXIT trap.
BGT_EXIT_CMDS=(); trap '
    set +e
    for ((i=$(( ${#BGT_EXIT_CMDS[*]} -1)); i >= 0; i--)); do
        eval "${BGT_EXIT_CMDS[i]}"
    done
' EXIT

[[ $- == *e* ]] || { no_errexit=x; set -e; }

# Load helper functions and aliases
source "$BGT_HOME/lib/utils.sh"

# Load object system for modeling
source "$BGT_HOME/lib/bos.sh"

# Load the built-in widgets
source "$BGT_HOME/lib/widgets/init.sh"


if [[ ${no_errexit:-} ]]; then set +e; unset -v no_errexit; fi

# If errexit is set then set up error handling to return / flash the stack trace
# before exiting.
#
if [[ $- == *e* ]]; then
    set -E
    trap '
        # Dump and save the stack trace
        BGT_FROM_ERR_TRAP="ERR trap" err-trace >> "$BGT_STACK_TRACE_FILE" 2>&1 || true

        # Send back any, potentially incomplete, html first
        echo

        # Flash an error message immediately
        compose _flash msg="Oops! Something went wrong ..."; with () {

            [[ ${BGT_ENV:-} != prod ]] || return 0

            details/
              summary/ ="Stack trace"
              pre/
                text "$(<"$BGT_STACK_TRACE_FILE")"
              /pre
            /details
        }; end
        echo
    ' ERR
fi


# Run a Buguette app and start the event loop.
#
_baguette () {
    @main; echo

    local json_line request_context handler
    local -A HX # htmx request headers without the "HX-" prefix

    while true; do
        HX=(); unset -v ${!val_*}

        read -r json_line || continue
        request_context=$(
            jq -re '
                def toval: . // "" | tostring;

                (.HEADERS | to_entries | map((
                    (.key|ltrimstr("HX-")), .value | toval) | @sh
                )) as $headers
                    |
                del(.HEADERS) | to_entries | map(
                    "val_\(.key|gsub("-"; "_"))=\(
                        if (.value|type) == "array" then
                          "(" + ([.value[] | toval | @sh] | join(" ")) + ")"
                        else
                          .value | toval | @sh
                        end
                    )"
                ) as $values
                    |
                "HX=(  \($headers|join(" ")) )",
                "local \($values |join(" "))  "
            ' <<<"$json_line"
        ) || err-return

        eval "$request_context" || err-return

        # **WARNING**
        #
        # To avoid remote code execution, DO NOT use these user input variables
        # (i.e., ${HX[...]} or $val_*), either directly or indirectly, in any
        # arithmetic contexts without validating they are numbers first!
        #

        local flashed

        handler=${val_render:-}
        if [[ $handler ]] && handler=@${handler#@} &&
           declare -F -- "$handler" >/dev/null 2>&1
        then
            "$handler"
            if [[ ${BGT_FLASH_STDERR:-} && -s $BGT_STACK_TRACE_FILE && ${BGT_ENV:-} != prod ]]; then
                #FIXME: this logic should also be in the ERR trap?

                compose _flash msg="Found error outputs!"; with () {
                    details/
                    summary/ ="STDERR"
                    pre/
                        text "$(<"$BGT_STACK_TRACE_FILE")"
                    /pre
                    /details
                }; end

                flashed=directly

                cp "$BGT_STACK_TRACE_FILE"{,.flashed}
                : >"$BGT_STACK_TRACE_FILE"
            fi
        else
            flash msg="Unknown render function: $handler"
        fi

        [[ ${flashed:-} == x ]] && { flash-clear; flashed=; }

        local cmd
        for cmd in "${BGT_POST_RENDER_QUEUE[@]}"; do
            eval "$cmd"
            if [[ $cmd == "_flash "* ]]; then flashed=x; fi
        done
        echo
        BGT_POST_RENDER_QUEUE=()

        if [[ $flashed == directly ]]; then flashed=x; fi
    done
}

baguette () {
    local logfile
    for logfile in BGT_{STACK_,}TRACE_FILE; do
        if [[ ${!logfile:-} ]]; then
            mkdir -p "$(dirname "${!logfile}")" || err-return
            printf -v "$logfile" "%s.$$" "$(realpath "${!logfile}")" || err-return
        fi
    done

    if [[ ${GATEWAY_INTERFACE:-} == websocketd* ]]; then
        # We are invoked by websocketd
        if [[ ${BGT_TRACE_FILE:-} ]]; then
            PS4='+ \t|${BASH_SOURCE##*/}>$FUNCNAME:$LINENO: '
            exec {BASH_XTRACEFD}>"$BGT_TRACE_FILE" || err-return
            exec 2> >(tee -a "$BGT_STACK_TRACE_FILE" >&$BASH_XTRACEFD) || err-return
            set -x
        else
            exec 2>>"$BGT_STACK_TRACE_FILE" || err-return
        fi
        BGT_EXIT_CMDS+=('[[ -s $BGT_STACK_TRACE_FILE ]] || rm "$BGT_STACK_TRACE_FILE"')
        _baguette "$@"
    else
        # We are sourced by a Baguette app / script
        local cmd=(
            websocketd
            --address "$WSD_ADDR"
            --port "$WSD_PORT"
            --staticdir "$WSD_PUBLIC_DIR"
            --cgidir "$WSD_CGI_DIR"
            --passenv PATH,BGT_HOME,WSD_ADDR,WSD_PORT,WSD_SCRIPT_DIR,WSD_PUBLIC_DIR
            "${WSD_OPTS[@]}"
            "$WSD_SCRIPT_DIR/${0##*/}" "$@"
        )
        echo "${cmd[@]}"
        echo
        local ip=$WSD_ADDR; [[ $ip != 0.0.0.0 ]] || ip=127.0.0.1
        echo "You can access the Baguette app at http://$ip:$WSD_PORT/index.html"
        echo
        exec "${cmd[@]}"
    fi
}


BGT_SOURCED=x
