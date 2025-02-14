shopt -s expand_aliases

alias err-return='{ err-trace; return; }'
alias err-exit='{ err-trace; exit; }'

# These Void elements can't have end tags.
#
declare -A VOID_ELEMENTS=()
for name in area base br col embed hr img input link meta param source track wbr; do
    VOID_ELEMENTS[$name]=x
done
unset -v name

print () { printf %s "$*"; }
escape-html () {  # <varname>
    local -n _s=$1 || err-return
    _s=${_s//\&/\&amp;}
    _s=${_s//\</\&lt;}
    _s=${_s//\>/\&gt;}
    _s=${_s//\"/\&quot;}
    _s=${_s//\'/\&#39;}
    _s=${_s//$'\n'/\&#10;}
}
text () { local text="$*"; escape-html text; print "$text"; }
is-int () { [[ ${1:-} ]] && printf %d "$1" >/dev/null 2>&1; }

is-safe () { [[ ${1:-} =~ [_a-zA-Z]*[_a-zA-Z0-9]+ ]]; }
# NOTE: No array element reference allowed, to guard against command injections.


# Generate a random hexadecimal id with low probability of collisions.
get-guid () {
    od -N 16 -t x -A n /dev/urandom | tr -d ' '
    [[ $PIPESTATUS ]] || err-return
}


# Write a HTML element to STDOUT.
#
# If an attribute argument has an empty name (i.e., "=value") then the
# value of the argument is taken to be the body of the element, and in which
# case the element will also be closed (i.e., end tag added after the element
# body) automatically. Lastly, a repeated attribute name that come later in
# the argument list will be ignored.
#
# NOTE: No validation is done for the element name nor any of its
#       attributes and contents!
#
print-tag () { #  <tag-name> [attr1=value1 attr2=value2 ...]
    [[ ${1:-} ]] || err-return
    local elem=$1; shift
    local attr name body
    local -A seen
    printf "<%s" "$elem"
    for attr in "$@"; do
        name=${attr%%=*}; name=${name,,}
        [[ $attr == *=* ]] && attr=${attr#*=} || attr=
        [[ $attr ]] && escape-html attr
        if [[ $name ]]; then
            [[ ${seen[$name]:-} ]] && continue || seen[$name]=x
            printf ' %s="%s"' "$name" "$attr"
        else
            body+=$attr
        fi
    done
    if [[ -v body ]]; then
        printf ">%s</%s>" "$body" "$elem"
    else
        print '>'
    fi
}

# Create convenient functions that call 'print-tag' to generate
# the open and close tags of the given HTML elements.
#
# Unless a specific function name is provided, it's assumed to be the same as
# the element name plus a trailing '/'. A second function that starts with '/'
# followed by the element name is also generated for each opening tag function.
#
# Example:
#
#   install-tags i bold/=b
#   i/; print "Italic"; /i
#   bold/; print "Bold"; /bold
#
install-tags () {  # [[funcname=]<element-name> ...]
    local tag
    for tag in "$@"; do
        local funcname=
        if [[ $tag == *=* ]]; then
            funcname=${tag%=*}
            tag=${tag##*=}
        else
            funcname=$tag/
        fi
        [[ $tag =~ ^[a-zA-Z][a-zA-Z0-9]*$ ]] || err-return
        eval "$funcname () {
            print-tag '$tag' \"\$@\"
        }" || err-return

        if [[ ! ${VOID_ELEMENTS[$tag]:-} ]]; then
            eval "/${funcname%/} () {
                printf '</%s>' '$tag'
            }" || err-return
        fi
    done
}

# Output a whitespace.
sp () { echo -n ' '; }
nbsp () { echo -n '&nbsp;'; }


# 'compose' delays the invocation of a command until the 'end' comman is called,
# at which point it will invoke the command with a 'with=...' argument, passing
# it the name of the function to be called in the scope of the command's
# execution.
#
# Example / the intended use case:
#
#     compose mycmd arg1 arg2 arg3; with () {
#       ...
#     }; end
#
# Above, 'mycmd' will be invoked by 'end', passing it the 'with' function just
# defined after the 'compose' command. 'mycmd' will get a "with=..." argument,
# which contains the name of the function defined via the current 'with' alias.
# It is up to 'mycmd' to invoke the renamed function when and wherever needed.
# 
# Alternatively, one can also use a function named other than 'with' by passing
# its name to the 'end' command, like so:
#
#     compose mycmd a b c; with-block () {
#       ...
#     }; end with-block
#
# As long as the function (with-block) is uniquely named, it won't cause any
# problems. This also has the advantage of not re-defining the function over and
# over when used within a loop, and additionally it also works when used from a
# subshell.
#
WITH_BLOCK_ID=0
alias with="_with_block_$WITH_BLOCK_ID"
compose () { COMPOSE_CMD=("$@"); }
end () {
    (( ${#COMPOSE_CMD[*]} )) || err-return
    local _block_func
    if [[ ${1:-} ]]; then
        _block_func=$1
    else
        _block_func=_with_block_$WITH_BLOCK_ID
        alias with="${_block_func%_*}_$((++WITH_BLOCK_ID))"
        # NOTE: this trick won't work if called from a subshell though :(
    fi
    "${COMPOSE_CMD[@]}" with=$_block_func; local rc=$?
    COMPOSE_CMD=()
    return $rc
}


# Parse "$@" of the form: "name1=value1" "name2=value2" ...
# to an associative array named 'attrs', which should be local to the caller.
#
args-to-attrs () {
    local param name
    for param in "$@"; do
        name=${param%%=*}
        if [[ $name ]]; then
            [[ $name =~ ^[a-zA-Z][a-zA-Z0-9.:_-]*$ ]] || err-return
        else
            name=' '  # The "=value" argument will be stored under a key
                      # that's a single space.
        fi

        if [[ $param == *=* ]]; then
            if [[ $name == id ]]; then
                [[ ${param#*=} =~ ^[a-zA-Z][a-zA-Z0-9.:_-]+$ ]] || err-return
            fi
            attrs[$name]=${param#*=}
        else
            attrs[$name]=
        fi
    done
}

# Copy the items of an associative array named, 'attrs', into a positional
# array named, 'args'. Elements in 'args' will be of the form: "key=value".
# Both 'attrs' and 'args' should be declared ahead of time in the caller.
#
attrs-to-args () {
    local name value
    for name in "${!attrs[@]}"; do
        value=${attrs[$name]}
        if [[ $name == ' ' ]]; then name=; fi
        if [[ $value ]]; then
            args+=("$name=$value")
        else
            args+=("$name")
        fi
    done
}

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
        echo "$(mapfile -tn1 -s $((lineno - 1)) l < "$file"; echo "  $l")"
    done
}



get-hx-tid () {
    local id=${HX[Trigger]:-}
    if [[ $id ]]; then
        is-safe "$id" || err-return
        tid=$id
    fi
}
get-hx-tname () {
    local name=${HX[Trigger-Name]:-}
    if [[ $name ]]; then
        is-safe "$name" || err-return
        tname=$name
    fi
}


generate-download-script () {  # <dir-for-the-script> <file-for-download> [as-name]
    local dir=${1:-} file=${2:-} download_name=${3:-}
    [[ -d $dir && -f $file ]] || err-return
    file=$(realpath -e "$file")

    local id; id=$(get-guid) || err-return
    local code; code="$(cat <<EOF
#!/usr/bin/env bash

CRLF=\$'\r\n'
nl () { printf %s "\$CRLF"; }
print () { printf %s "\$@"; }

print "Content-Type: application/octet-stream"; nl
print "Content-Disposition: attachment; filename=${download_name:-${file##*/}}"; nl
nl
cat $(printf %q "$file")
EOF
    )" || err-return

    file=$dir/$id
    printf "%s\n" "$code" > "$file" || err-return
    chmod +x "$file" || err-return
    RESULT=$id
}

