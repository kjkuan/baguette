class TodoItem

TodoItem/init () {
    msg $self ../init "$@"
    : ${self[text]=}
    : ${self[createdAt]:=$(date)}
    : ${self[checkedAt]=}
}
TodoItem/is-checked () { [[ ${self[checkedAt]} ]]; }
TodoItem/to-json () {
    jq -n --arg text      "${self[text]}"      \
          --arg createdAt "${self[createdAt]}" \
          --arg checkedAt   "${self[checkedAt]}" '
        { $text, $createdAt, $checkedAt }
    '
}


class TodoList
class ItemIndexMap

TodoList/init () {  # <name>
    [[ ${1:-} ]] || err-return
    self[name]=$1
    new-array 'self[items]'         # array to keep the todo items in a specific order.
    ItemIndexMap 'self[index_map]'  # obj_id -> array index
}

# Count the items in the list and return the number of checked items and the total.
#
TodoList/count () {
    local -n items=${self[items]}
    local -i checked
    local item
    for item in "${items[@]}"; do
        msg $item is-checked && (( ++checked ))
    done
    RESULT="$checked ${#items[*]}"
}

# Append the specified TodoItem at the end of the list.
#
TodoList/append-item () {  # <item-id>
    local -n items=${self[items]}
    local -n index_map=${self[index_map]}

    # The item to be appended shouldn't be already in the list otherwise
    # it will mess up the operation.
    [[ ! ${index_map[$1]:-} ]] || err-return

    if (( ! ${#items[*]} )); then
        index_map[$1]=0
    else
        local i=${index_map[${items[-1]}]:-}; [[ $i ]] || err-return
        index_map[$1]=$(( i + 1 ))
    fi
    items+=("$1")
}

# Append a new item at the end of the list.
#
TodoList/append () {
    local item; TodoItem item "$@"
    msg $self append-item $item
    RESULT=$item
}

# Remove a specified TodoItem; potentially, leaving a "hole" in the list.
#
TodoList/remove-item () {  # <item-id>
    [[ ${1:-} ]] || err-return
    local -n index_map=${self[index_map]}
    local index=${index_map[$1]:-}; [[ $index ]] || err-return
    local -n items=${self[items]}
    unset -v "items[$index]" "index_map[$1]"
}

# Insert the specified TodoItem before another one in the list.
#
TodoList/insert-item () { # <before-item-id> <item-id>
    [[ ${1:-} && ${2:-} ]] || err-return
    local -n items=${self[items]}
    local -n index_map=${self[index_map]}

    # The item to be inserted shouldn't be already in the list otherwise
    # it will mess up the operation.
    [[ ! ${index_map[$2]:-} ]] || err-return

    local index=${index_map[$1]:-} item i; [[ $index ]] || err-return
    for item in "$2" "${items[@]:index}"; do
        i=${index_map[$item]:-}

        # If the index of the item we are currently shifting (1 index to the right)
        # is not the same as the previous index which we just assigned to the previous
        # item.
        if [[ $i ]] && (( i != index - 1 )); then unset -v "items[$i]"; fi
#        if [[ ${items[i]} == $item ]]; then unset -v "items[$i]"; fi

        items[index]=$item
        index_map[$item]=$((index++))
    done
}

# Insert the specified TodoItem after another one in the list.
#
TodoList/insert-after () {  # <after-item-id> <item-id>
    [[ ${1:-} && ${2:-} ]] || err-return
    local -n items=${self[items]}
    local -n index_map=${self[index_map]}

    if [[ $1 == "${items[-1]}" ]]; then
        msg $self append-item "$2"
    else
        local index=${index_map[$1]:-}; [[ $index ]] || err-return
        index=${items[@]:index:2}
        index=${index#* }
        msg $self insert-item $index $2
    fi
}

# Insert a new item before an existing item.
#
TodoList/insert () {
    local id=${1:-}; [[ $id ]] || err-return; shift
    local item; TodoItem item "$@"
    msg $self insert-item "$id" $item
    RESULT=$item
}

TodoList/get-items () {  # [all|active|completed]
    local filter=${1:-all}
    [[ $filter == @(all|active|completed) ]] || err-return

    local -n items=${self[items]}
    if [[ $filter == all ]]; then
        RESULT=("${items[@]}")
        return
    fi
    RESULT=()
    case $filter in
        active) local -n active=RESULT ;;
        completed) local -n completed=RESULT ;;
    esac
    local item
    for item in "${items[@]}"; do
        if msg $item is-checked; then
            completed+=("$item")
        else
            active+=("$item")
        fi
    done
}

TodoList/_get-item () {  # <item_index>
    local -n items=${self[items]}
    RESULT=${items[$1]}
}

TodoList/clear () {
    local -n items=${self[items]}
    local item; for item in "${items[@]}"; do msg $item delete; done
    items=()
    msg ${self[index_map]} delete
    ItemIndexMap 'self[index_map]'
}

TodoList/to-json-objects () {
    jq -n --arg name "${self[name]:-N/A}" '{ $name }'
    local -n items=${self[items]}
    local item
    for item in "${items[@]}"; do
        msg $item to-json
    done
}

TodoList/load () {
    local commands; commands=$(jq -res '
        (@sh "self[name]=\(.[0].name)"),
        (.[1:][]
         | @sh "msg $self append text=\(.text) createdAt=\(.createdAt) checkedAt=\(.checkedAt)"
        )
    ')
    msg $self clear
    eval "$commands"
}

shopt -s nullglob

class TodoListManager

TodoListManager/new-list () {  # <todo-list-name>
    [[ ${1:-} ]] || err-return
    local list; TodoList list "$1"
    local guid=$(get-guid)
    self[$list]=$guid
    RESULT=$list
}

TodoListManager/save-list () { # <todo-list>
    [[ ${1:-} ]] || err-return
    local guid=${self[$1]:-}; [[ $guid ]] || err-return
    msg $1 to-json-objects > "$guid.todos"
}

TodoListManager/load-lists () {
    local files=(*.todos)
    (( ${#files[*]} )) || return 0

    local oid; local -A guid2oid
    for oid in "${!self[@]}"; do
        [[ $oid != 0 ]] || continue
        guid2oid[${self[$oid]}]=$oid
    done

    # Sort the todo files by creation time
    local sorted_files; sorted_files=$(
        stat -c "%W,%n" "${files[@]}" | sort -t, -k1,1 | cut -d, -f2
    )

    # Load the todo files in order so that their oid's would reflect
    # this ordering, which is assumed by 'get-lists', too.
    #
    local file guid list
    for file in $sorted_files; do
        guid=${file%.todos}
        [[ ${guid2oid[$guid]:-} ]] || {
            TodoList list "name"
            self[$list]=$guid
            guid2oid[$guid]=$list
        }
        msg "${guid2oid[$guid]:-}" load < "$file"
    done
}

TodoListManager/get-lists () {
    RESULT=$(
        for oid in "${!self[@]}"; do
            [[ $oid != 0 ]] || continue
            echo ${oid##*_} $oid
        done | sort -nk1,1 | cut -d' ' -f2
    )
}

TodoListManager/delete-list () {
    [[ ${1:-} ]] || err-return
    rm -f "${self[$1]}.todos"
    unset -v "self[$1]"
    msg "$1" delete
    unset -v "$1"
}

