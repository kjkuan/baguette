# Bos is a simple Bash Object System
#
# Despite being included with Baguette, this script works as a standalone
# module that can be sourced alone by other scripts.
#
# NOTE: Some Bos functions or methods accept variable names as arguments;
# the user is responsible for making sure the names supplied are valid
# Bash variable names without unwanted $(command-substitution) to prevent
# code injection attacks.
#

[[ ! ${BOS_SOURCED:-} ]] || return 0

declare -ig OID=0         # An object ID in Bos is of this form: "_bos_${class_name}__$((++OID))"
declare -Ag IS_A=()       # Class -> Parent_Class
declare -Ag METHOD_CACHE  # method-name -> actual function name
declare -ig AID=0

if ! declare -F err-trace >/dev/null 2>&1; then
    # Assumming this script has been sourced not as part of Baguette, let's define
    # a simplified version of 'err-trace' as a function in order to make Bos work.
    err-trace () {
        local rc=${2:-$?}
        [[ ! ${1:-} ]] || printf "Error: %s\n" "$1"
        return $rc
    } >&2
    shopt -s expand_aliases
    alias err-return='{ err-trace; return; }'
fi

# Allocate an instance given a class, and assign it to the specified variable
#
new () {  # <class-name> <obj_var_name>
    [[ ${1:-} && ${2:-} ]] || err-return
    local _class=$1 _var_name=$2; shift 2
    [[ ${IS_A[$_class]+x} ]] || {
        err-trace "Class $_class not found in the system!"
        return
    }
    local _oid=_bos_${_class}__$((++OID))
    declare -Ag "$_oid=()"
    printf -v "$_var_name" "%s" "$_oid" || err-return
    printf -v "$_oid[0]" "%s" "$_oid" || err-return
}

# Send a message to the specified object
#
msg () {  # <obj_id> <msg_name> [args ...]
    [[ ${1:-} && ${2:-} ]] || err-return
    local oid=$1 msg_name=$2; shift 2
    [[ $oid == _bos_* ]] || {
        err-trace "String '$oid' doesn't look like an object ID!"
        return
    }

    # Trailing comma after the object id, or colon after the message name, is optional
    oid=${oid%,}
    msg_name=${msg_name%:}

    local class=${oid#_bos_}; class=${class%__*}
    if [[ $msg_name == ../* ]]; then
        [[ ${FUNCNAME[1]:-} == */* ]] || {
            err-trace "Message prefixed with ../ should only be sent from a method!"
            return
        }
        class=${IS_A[${FUNCNAME[1]%%/*}]:-}
    fi
    msg_name=${msg_name#../}
    local method=$class/$msg_name
    local -n self=$oid || err-return

    if [[ ${METHOD_CACHE["$method"]:-} ]]; then
        "${METHOD_CACHE["$method"]}" "$@"
        return
    fi

    while true; do
        [[ $class ]] || { err-trace "Method not found: $msg_name" 127; return; }
        declare -F "$class/$msg_name" >/dev/null || {
            class=${IS_A[$class]:-}
            continue
        }
        break
    done

    METHOD_CACHE["$method"]=$class/$msg_name
    "$class/$msg_name" "$@"
}

# Define a class' relationship in the system as well as its default constructor implementation.
#
class () {  # <name> [isa=Object]
    [[ ${1:-} ]] || err-return
    local parent=${2:-isa=Object}
    [[ $parent == isa=* ]] || err-return
    parent=${parent#isa=}

    IS_A[$1]=$parent

    eval "$(cat <<EOF
$1 () {
    [[ \${1:-} ]] || err-return
    new $1 "\$1";
    local -n self=\${!1} || err-return
    $1/init "\${@:2}"
}

$1/init () { msg "\$self" ../init "\$@"; }
EOF
    )" || err-return
}

# Define the root of all classes -- the 'Object' class.
class Object; IS_A[Object]=


# Add functions to the specified class as methods.
#
mix () {  # <class> [function-names ...]
    [[ ${1:-} ]] || err-return
    local klass=$1; shift
    [[ ${IS_A[$klass]+x} ]] ||
        err-trace "Class $klass not found in the system!"
    local func fdef
    for func in "$@"; do
        fdef=$(declare -pf "$func") || err-return
        eval \
"
$klass/${func#*/} ()
${fdef#*$'\n'}
"       || err-return
    done
}

# Make the default constructor useful for assigning attributes at object creation time.
#
# NOTE: "0" is not allowed as an attribute name since it's used internally to hold the
#       object id.
#
Object/init () {  # [attr_name1=value1 ...]
    local arg
    for arg in "$@"; do
        self[${arg%%=*}]=${arg#*=}
    done
}

# This method returns the class name of the object.
Object/classname () {
    local class_name=${self#_bos_}
    RESULT=${class_name%__*}
}

# Check if an instance is of a specific class
Object/isa () { # <classname>
    [[ ${1:-} ]] || err-return
    local class=$1
    msg $self classname
    until [[ $RESULT == "$class" ]]; do
        RESULT=${IS_A[$RESULT]:-}
        [[ $RESULT ]] || return
    done
}

# Fetch the named object attributes and place them in the RESULT var.
#
# A default value can be supplied for an attribute to be returned instead,
# in case the attribute is not found. E.g.,
#
#     msg $obj get attr1 attr2=value
#
Object/get () { # [attr1 attr2 ...]
    RESULT=(); local attr
    while (( $# )); do
        attr=${1%%=*}; [[ $attr ]] || err-return
        if [[ -v "self[$attr]" ]]; then
            RESULT+=("${self[$attr]}")
        elif [[ $1 == *=* ]]; then
            RESULT+=("${1#*=}")
        else
            err-trace "Attribute not found: $1"
            return
        fi
        shift
    done
}

# Set the named attributes (attr1=value2 attr2=value2 ...)
Object/set () { Object/init "$@"; }

# Print the object states.
Object/print () {
    local key class_name=${self#_bos_}; class_name=${class_name%__*}
    echo "$self"
    for key in "${!self[@]}"; do
        [[ $key != 0 ]] || continue
        printf "    %s=%q\n" "$key" "${self[$key]}"
    done \
         |
        sort -t= -k1,1
}

# Print the object attributes as JSON.
#
# This is done non-recursively; however, for attributes that are objects
# or arrays, one can serialize them to JSON, and pass them as named json arguments
# to have them merged with the result of this method. E.g..,
#
#     msg $self to-json --argjson id "$self" --argjson attr_x "{...}"
#
# NOTE: The object id (i.e., under the "0" key in the object) is not part of the output.
#
Object/to-json () {
    jq -n "$@" --args '
      [ $ARGS.positional as $args
         | range(0; ($args|length); 2) as $i
         | $args[$i]   as $key
         | $args[$i+1] as $value
         | if $key != "0" then {$key: $value} else empty end
      ]  | (reduce .[] as $item ({}; . + $item)) + $ARGS.named
    ' "${self[@]@k}"
}

# Make a shallow copy of an object; assign the object ID to the specified variable.
#
Object/copy () { # <varname>
    [[ ${1:-} ]] || err-return
    local _decl; _decl=$(declare -p $self) || err-return
    msg $self classname; local _class=$RESULT

    # Create a temporary object, mainly to get its oid.
    local _copy_oid; Object _copy_oid
    local _tmp_oid=$_copy_oid

    # Replace the classname embedded in the oid
    _copy_oid=_bos_${_class}__${_copy_oid#*__}

    # Set the object state (associative array) to a copy of the current object.
    eval "declare -Ag $_copy_oid=${_decl#*=}" || err-return

    # Delete the temporary object.
    unset -v "$_tmp_oid"

    # Fix the oid embedded within the object
    local -n _copy=$_copy_oid
    _copy[0]=$_copy_oid

    printf -v "$1" %s "$_copy_oid" || err-return
}

# Delete the object itself. A sub-class probably wants to override this method
# to delete any dynamically allocated values (e.g., arrays) within the object
# (associative array).
#
Object/delete () { unset -v $self; }


# Dynamically allocate an array and assign it to the specified variable
#
# NOTE: I decided to not make an Array object since it's easier to just
#       work with the array variable directly.
#
new-array () { # <var_name>
    local _aid=_bos_array__$((++AID))
    declare -ag "$_aid=()"
    printf -v "$1" %s $_aid || err-return
}

BOS_SOURCED=x
