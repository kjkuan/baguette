# A "File Explorer" widget that displays a file tree rooted at a given directrory.
#
# Directories can be expanded / collapsed to show / hide the files inside, and the
# state (expanded / collapsed) will be remembered as well.
#
# To use it, you need to create an object to be used by the widget as its "model":
#
#     local mydir; FileExplorerModel mydir root="$PWD"
#
# The `root` attribute should be set to the directory that will be used as the root
# of the file tree.
#
# Next, you should wrap the widget in a render function. E.g.,
#
#     @render-fs-tree () { file-explorer "$@"; }
#
# And then, you pass the model object created earlier to it for rendering:
#
#     @render-fs-tree $mydir
#
#

declare -g FE_LS_OPTS=(
    --group-directories-first

    # ------- mandatory options -----
    -aAp  # show .* but don't show . and ..; append '/' to a directory
    --color=never
    --quoting-style=shell-escape
    # This makes sure each entry is a single line and also allows for special characters.
)
declare -g FE_NEXT_PATH_ID=0


class FileExplorerModel
#
# NOTE: potentially, one can subclass it to provide a different model for the tree to be
# created by the widget.

FileExplorerModel/init () {
    msg $self ../init "$@"
    [[ -d ${self[root]:-} ]] || err-return
    self[root]=$(realpath -e "${self[root]}") || err-return
}

# Given a relative path (below the root dir of the model), return an
# unique node id for referencing it later.
#
# The returned node id will be prefixed with the model's oid and is of this form:
#
#   <oid>-<N><'f'|'d'>
#
# where oid is the object ID of the model object; N is a positive int, and
# the last character is either 'f', if it's a normal file, or 'd', if it's a
# directory.
#
# NOTE: This method is used internally by the model, and might also be useful for apps
# using the widget; however, it is not relied upon by the widget except for the format of
# a node id.
#
FileExplorerModel/path-id () {  # <relative-path-below-the-model-root>
    local relpath; relpath=$(
        realpath --relative-base="${self[root]}" -e "${self[root]}/${1:-}"
    ) || err-return
    [[ $relpath != /* ]] || err-return

    if [[ ${self[/$relpath]:-} ]]; then
        RESULT=${self[/$relpath]}; return
    fi
    [[ $1 == */ || $relpath == . ]] && local t=d || local t=f
    local id=$self-$((FE_NEXT_PATH_ID++))$t
    self[$id]=$relpath
    self[/$relpath]=$id
    RESULT=$id
}

# Given a node-id, return the file path to the node.
# The path returned is relative to the root of the model.
#
# NOTE: This method is for apps using the widget; it is not relied upon by the widget.
#
FileExplorerModel/id-path () {  # <node-id>
    [[ ${1:-} == "$self"-* ]] || err-return
    [[ ${self[$1]:-} ]] || err-return
    RESULT=${self[$1]}
}

# Return the node id for the root of the tree.
FileExplorerModel/root-id () { msg $self path-id .; }

# Return the node name of the given id.
FileExplorerModel/id-name () {
    [[ ${1:-} == "$self"-* ]] || err-return
    local path=${self[$1]:-}; [[ $path ]] || err-return
    RESULT=${path##*/}
}

# Given a node id, return the child nodes in the form of an array of:
#
#   "$node_id $name_name"
#
FileExplorerModel/list () {  # <node-id>
    msg $self id-path "${1:-}" || err-return
    local path=$RESULT

    local files; files=$(ls "${FE_LS_OPTS[@]}" "${self[root]}/$path") || err-return
    #FIXME: stat the files to get ctime and mtime and show them as
    #       titles / tool-tips when mouse hovered

    local name id results=()
    while read -r name; do
        [[ $name ]] || continue
        [[ $name != \'* ]] || eval printf -v name %s "$name" || err-return
        msg $self path-id "$path/$name" || err-return; id=$RESULT
        results+=("$id ${name%/}")
    done <<<"$files"
    RESULT=("${results[@]}")
}

FileExplorerModel/remove-id () {
    [[ ${1:-} ]] || err-return
    msg $self id-path $1 || err-return; local path=$RESULT
    unset -v "self[/$path]" "self[$1]"
}


file-explorer () {   # [fe-model-oid|node-id]
    local model=${1:-} path_id user_clicked is_root

    if [[ ! $model ]]; then  # triggered by user click
        local tid; get-hx-tid || err-return
        path_id=$tid model=${tid%%-*}
        user_clicked=x

        # Toggle the expand / collapse state of this path
        local state=0
        if [[ $path_id == *d ]]; then
            msg $model get "$path_id@state=0"; state=$((!RESULT))
            msg $model set "$path_id@state=$state"

            local folder; msg $model id-name "$path_id"; folder=$RESULT
            if [[ $state == 0 ]]; then  # we should collapse the li
                -fe-folder-li "$path_id" "${folder##*/}" + selected
            else
                -fe-folder-li "$path_id" "${folder##*/}" - selected
                file-explorer "$path_id"
            fi
            /li
        fi
        return

    elif [[ $model == *-* ]]; then # triggered by a direct or recursive call
        path_id=$model model=${model%%-*}

    else  # initial case; start from root
        msg $model root-id; path_id=$RESULT
        is_root=x
    fi

    [[ $path_id == *d ]] || return 0

    ul/ ${is_root:+id=$path_id} class=FE-Folder \
        ${is_root:+ws-send hx-trigger="@fe-handle-item-move-overwrite, @fe-handle-refresh"}

        msg $model list "$path_id" || err-return
        set -- "${RESULT[@]}"
        local id name
        while (( $# )); do
            id=${1%% *} name=${1#* }; shift
            if [[ $id == *d ]]; then
                msg $model get "$id@state=0"
                if [[ $RESULT == 1 ]]; then
                    -fe-folder-li "$id" "$name" -
                    file-explorer "$id"
                else
                    -fe-folder-li "$id" "$name"
                fi
            else
                li/ id=$id class=FE-File data-scope=${FUNCNAME#@} ws-send \
                    hx-trigger="click, fe-handle-item-move" \
                    hx-on:click="$(-fe-onclick-js)"
                    div/ class=FE-Label ="$name"
            fi
            /li
        done
    /ul
}

-fe-folder-li () {
    local classes=(FE-FileFolder)
    [[ $3 == - ]] && classes+=(FE-FileFolder-open)   \
                  || classes+=(FE-FileFolder-closed)

    [[ ${4:-} == selected ]] && classes+=(selected)

    li/ id="$1" class="${classes[*]}" \
        data-scope=${FUNCNAME[1]#@} ws-send \
        hx-on:click="$(-fe-onclick-js)" \
        hx-trigger="click, fe-handle-item-move"
        sp; span/ class=FE-Label style="display: inline-block" ${user_clicked:+autofocus} ="$2"

    [[ $3 == - ]] || { ul/ class=FE-Folder; /ul; }
    # NOTE: needed so files can be dropped into the folder when it is closed.
}

FE_JS__UNSELECT_ALL='
    let selected = document.querySelectorAll(".FE-File.selected, .FE-FileFolder.selected");
    for (var i=0; i < selected.length; i++) {
        htmx.removeClass(selected[i], "selected");
    }
'

-fe-onclick-js () {
    cat <<EOF
event.stopPropagation();
(function () {
    $FE_JS__UNSELECT_ALL
    htmx.addClass(event.currentTarget, "selected");
})();
EOF
}

# Helper to unselect all and select the specified path-id, expanding
# its parent directory if necessary.
#
fe-navigate-to-path () {  # <path-id> <path>
    local model=${1%%-*}
    if [[ $1 != *d ]]; then
        local dir; dir=$(dirname "$2")
        msg $model path-id "$dir"; local path_id=$RESULT
    else
        local path_id=$1
    fi
    msg $model root-id; local root_id=$RESULT
    if [[ $path_id != "$root_id" ]]; then
        msg $model set "$path_id@state=0"
        HX[Trigger]=$path_id   # fake the click trigger
        file-explorer
    else
        file-explorer "$model"
    fi
    script/ id=script-from-server ="$(cat <<EOF
        setTimeout(function() {
            $FE_JS__UNSELECT_ALL
            htmx.addClass(document.getElementById('$1'), 'selected');
        }, 10);
EOF
    )"  # NOTE: The delay here works around a race condition that seems to manifest
        #       when the folder containing the path is already expanded.
}


