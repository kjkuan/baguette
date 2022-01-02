class Contact
class Errors

PAGE_SIZE=100
declare -A CONTACTS_DB=()  # Contact id -> Contact oid

Contact/init () {  # [id=...] [first=...] [last=...] [phone=...] [email=...]
    msg $self ../init "$@"
    Errors 'self[errors]'
    # NOTE: Here we are using a Bos object (of the Errors class) as an associative array.
    # The downside of this is that we need to be aware that key '0' is the object id.
}

Contact/to-json () {  # This is our Contact.__str__
    local errors; errors=$(msg ${self[errors]} to-json)  || err-return
    msg $self ../to-json --argjson errors "$errors" \
     |
    jq -e '
        .id = (.id | tonumber)
        | .first = .first
        | .last  = .last
        | .phone = .phone
    '
    # NOTE: This ensure that id is convert back to a number and that any missing
    # optional attributes are set to null's (although if updating via the UI, they
    # can only be set to empty strings anyway).
}

Contact/update () {  # <first> <last> <phone> <email>
    #msg $self set first="$1" last="$2" phone="$3" email="$4"
    msg $self set "$@"
}

Contact/validate () {
    local -n errors=${self[errors]}
    if [[ ! ${self[email]:-} ]]; then
        errors[email]="Email Required"
    fi

    local contact
    for contact in "${CONTACTS_DB[@]}"; do
        msg $contact get id email || err-return
        if [[ ${RESULT[0]} != "${self[id]:-}" && ${RESULT[1]} == "${self[email]:-}" ]]; then
            errors[email]="Email Must Be Unique"
            break
        fi
    done
    (( ${#errors[*]} == 1 ))  # at least 1 because of the object id at key 0
}

Contact/save () {
    msg $self validate || return
    if [[ ! -v 'self[id]' ]]; then
        if (( ${#CONTACTS_DB[*]} == 0 )); then
            local max_id=1
        else
            local contact max_id=0
            for contact in "${CONTACTS_DB[@]}"; do
                msg $contact get id || err-return
                (( RESULT > max_id )) && max_id=$RESULT
            done
        fi
        self[id]=$(( max_id + 1 ))
        CONTACTS_DB[${self[id]}]=$self
    fi
    Contact/save-db
}

Contact/delete () {
    unset -v "CONTACTS_DB[${self[id]}]"
    msg ${self[errors]} delete
    msg $self ../delete
    Contact/save-db
}

# The rest methods of this class are either "classmethod" or "staticmethod"; neither
# of which exist in Bos, so I just added them as instance method. When we use these methods,
# We'll invoke them directly (i.e., without using 'msg ...') using their function names
# to distinguish them from instance methods.
# -------------------------------------------------------------------------------------
Contact/count () { sleep 2; RESULT=${#CONTACTS_DB[*]}; }
Contact/all () {
    local page=${1:-}; is-int "$page" || err-return
    local start=$(( (page - 1) * PAGE_SIZE ))
    local end=$(( start + PAGE_SIZE ))
    RESULT=($(
        IFS=$'\n'
        echo "${CONTACTS_DB[*]}" | sort | sed -n "$((start + 1)),$((end - 1))p"
    ))
}
Contact/search () {
    local text=${1:-}; [[ $text ]] || err-return
    local contact first=0 last=1 email=2 phone=3
    local results=()
    for contact in "${CONTACTS_DB[@]}"; do
        msg $contact get first= last= email phone= || err-return
        if    [[ ${RESULT[first]} == *"$text"* ]] \
           || [[ ${RESULT[last]}  == *"$text"* ]] \
           || [[ ${RESULT[email]} == *"$text"* ]] \
           || [[ ${RESULT[phone]} == *"$text"* ]]
        then
            results+=($contact)
        fi
    done
    RESULT=("${results[@]}")
}
Contact/load-db () {
    CONTACTS_DB=()
    local c code; code="$(
        jq -r '.[] |
            [ @sh "id=\(.id // halt_error)",
              @sh "email=\(.email // halt_error)",
              if .first then @sh "first=\(.first)" else empty end,
              if .last  then @sh "last=\(.last)"   else empty end,
              if .phone then @sh "phone=\(.phone)" else empty end
            ] as $args
            | (
              "Contact c \($args|join(" "))",
              @sh "CONTACTS_DB[\(.id)]=$c"
            )
        ' contacts.json
    )" || err-return
    eval "$code"
}
Contact/save-db () {
    local contact file=contacts.json
    for contact in "${CONTACTS_DB[@]}"; do
        msg $contact to-json || err-return
    done | jq -s . > $file.tmp || err-return
    mv $file.tmp $file
}

Contact/find () {
    local id=${1:-}; is-int "$id" || err-return
    local contact=${CONTACTS_DB[$id]:-}
    if [[ $contact ]]; then
        msg $contact get errors
        local -n errors=$RESULT
        errors=([0]="$RESULT")
    fi
    RESULT=$contact
}
# -------------------------------------------------------------------------------------

class Archiver

_ARCHIVER=
Archiver/get () {
    if [[ $_ARCHIVER ]]; then
        RESULT=$_ARCHIVER
    else
        Archiver _ARCHIVER
        RESULT=$_ARCHIVER
    fi
}

Archiver/init () {
    self[status]=/dev/shm/archiver-status.$$
    self[progress]=/dev/shm/archiver-progress.$$
    echo Waiting > "${self[status]}"
    echo 0 > "${self[progress]}"
    BGT_EXIT_CMDS+=("rm -f ${self[status]} ${self[progress]}")
}
Archiver/status () {
    local count=3
    while (( count-- )); do
        RESULT=$(<"${self[status]}")
        case $status in Waiting|Running|Complete) break ;; esac
        sleep 0.2
    done
}
Archiver/progress () { RESULT=$(<"${self[progress]}"); }

# This method is meant to be run as a background process.
Archiver/run () {
    if [[ $(<"${self[status]}") == Waiting ]]; then
        echo Running > "${self[status]}"
        echo 0 > "${self[progress]}"
        local i
        for i in {1..10}; do
            sleep 0.$RANDOM
            [[ $(<"${self[status]}") == Running ]] || return 0
            echo $(( i * 10 )) > "${self[progress]}"
            #echo "Here... $(<"${self[progress]}")" >&2
        done
        sleep 1
        [[ $(<"${self[status]}") == Running ]] || return 0
        echo Complete > "${self[status]}"
    fi
}
Archiver/archive-file () { RESULT=contacts.json; }
Archiver/reset () { echo Waiting > "${self[status]}"; }
