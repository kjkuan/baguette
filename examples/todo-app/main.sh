#!/usr/bin/env bash
#
# An example Todo-list management app modeled after https://www.getminimalist.com
# and https://todomvc.com/
#
# Currently, it is a local, single-user app that saves your todo lists as JSON objects
# in the filesystem (in the app's directory).
#

set -eo pipefail

source baguette.sh

cd "$WSD_SCRIPT_DIR"
# NOTE: Todo lists will be saved in the current directory.

source model.sh

#FIXME:
#   - Allow setting a deadline for a todo item.

TodoListManager TODO_MANAGER

# Save the current todo list
save-todo-list () { msg $TODO_MANAGER save-list $TODO_LIST; }

msg $TODO_MANAGER load-lists
msg $TODO_MANAGER get-lists
if [[ $RESULT ]]; then
    TODO_LIST=${RESULT%%$'\n'*}  # i.e., the first list, which should be "Inbox",  in the results.
else
    msg $TODO_MANAGER new-list Inbox; TODO_LIST=$RESULT
    save-todo-list
fi

# Inbox is the built-in, default, todo-list. It can't be deleted nor renamed.
declare -r INBOX=$TODO_LIST

# A todo item to be rendered for its new item UI in order to take user input.
NEW_ITEM=; TodoItem NEW_ITEM

# Name of the current filter in effect.
ITEM_FILTER=all  # One of: all, acitve, or completed

# The entry point to a Baguette app; rendering starts here.
@main () {
    @list-of-todo-lists
    main/ id=${FUNCNAME#@} data-scope
        @todo-list
    /main
}

@list-of-todo-lists () {
    local tid; get-hx-tid
    if [[ $tid == new-list-link ]]; then
        msg $TODO_MANAGER new-list "$val_name"
        msg $TODO_MANAGER save-list $RESULT
        @switch-todo-list $RESULT

    elif [[ $tid == delete_* ]]; then
        tid=${tid#delete_}; [[ $tid != "$INBOX" ]] || err-return
        msg $TODO_MANAGER delete-list $tid
        li/ id=$tid hx-swap-oob=delete; /li
        if [[ $tid == "$TODO_LIST" ]]; then
            @switch-todo-list $INBOX
        fi
    fi
    nav/ id=todo-lists class=TodoListManager data-scope=$FUNCNAME
        ol/
            local todo_list
            msg $TODO_MANAGER get-lists
            for todo_list in $RESULT; do
                msg $todo_list get name
                li/ id=$todo_list
                    a/ id=select_$todo_list ="$RESULT" ws-send data-render=@switch-todo-list
                    if [[ $todo_list != "$INBOX" ]]; then
                        a/ id=delete_$todo_list class=TodoListManager-deleteLink =X \
                           ws-send hx-on::ws-before-send="
                               if (!confirm('Are you sure you want to delete $RESULT?'))
                                   event.preventDefault();
                           "
                           # NOTE: It's done this way because 'hx-confirm' doesn't work with 'ws-send'
                    fi
                /li
            done
        /ol
        div/ class=TodoListManager-ops
            a/ id=new-list-link ="(+) Create todo list" onclick="return false;" ws-send
            # See new_list_prompt() in app.js
        /div
    /nav
}

@switch-todo-list () { # [list]
    if [[ ${1:-} ]]; then
        TODO_LIST=$1
    else
        local tid; get-hx-tid
        TODO_LIST=${tid#select_}
    fi
    @todo-list
}

@new-item-button () {
    # If the button was clicked
    if [[ -v val_new_item_btn ]]; then
        # Delete the button
        div/ id=${FUNCNAME#@} hidden; /div

        # Add an empty todo item at the end of the todo-list UI to handle user input.
        ol/ hx-swap-oob="beforeend:#todo-list"
            @todo-item $NEW_ITEM appending
        /ol
    else
        div/ id=${FUNCNAME#@} data-scope
            button name=new_item_btn label="(+) Add todo item"
        /div
    fi
}

@todo-list () {
    msg $TODO_LIST get name
    local is_inbox; [[ $TODO_LIST == "$INBOX" ]] && is_inbox=x

    local filter=$ITEM_FILTER
    local tid; get-hx-tid
    if [[ $tid == filter_* ]]; then
        filter=${tid#filter_}
    fi

    ol/ id=todo-list class="TodoList sortable" ws-send data-scope \
        hx-trigger="@handle-item-reordering, @handle-todo-list-title-update"

        # Show name of the todo list
        h2/ class=TodoList-title title="$RESULT" ${is_inbox:-contenteditable} ="$RESULT"

        # Show the filter links with the current filter applied.
        @todo-item-filters "$filter"

        # Show the todo items with the current filter applied.
        local item; msg $TODO_LIST get-items "$filter"
        for item in "${RESULT[@]}"; do
            @todo-item $item
        done
        ITEM_FILTER=$filter
    /ol
    @new-item-button
}

@todo-item-filters () {
    local filter=${1:-$ITEM_FILTER}

    msg $TODO_LIST count
    local completed=${RESULT% *} all=${RESULT#* }
    local active=$(( all - completed ))

    div/ id=todo-item-filters
        local name style
        for name in all active completed; do
            [[ $name == "$filter" ]] && style='style=text-decoration: underline' || style=
            a/ id=filter_$name ${style:+"$style"} href="#" ="${name^} (${!name:-0})" ws-send
            [[ $name == completed ]] || { sp; text \|; sp; }
        done
    /div
}

@handle-todo-list-title-update () {
    [[ ${val_title:-} ]] || err-return
    [[ $TODO_LIST != "$INBOX" ]] || err-return
    msg $TODO_LIST set name="${val_title}"
    save-todo-list
    @list-of-todo-lists
}

# See how the event is triggered and its details in app.js
@handle-item-reordering () {
    msg $TODO_LIST remove-item "${val_movedItem}"
    if [[ ${val_beforeItem:-} ]]; then
        msg $TODO_LIST insert-item "$val_beforeItem" "$val_movedItem"
    else
        msg $TODO_LIST insert-after "$val_afterItem" "$val_movedItem"
    fi
    save-todo-list
}

@todo-item () {  # [item | <item 'appending'|'inserted'>]
    local item=${1:-} mode=${2:-}
    local item_text checked=

    if [[ ! ${item:-} ]]; then # it's from ws-send; we'll figure out the item oid from the HX-Trigger header
        local tid; get-hx-tid
        if [[ $tid == delete_link_* ]]; then
            item=${tid#delete_link_}
            msg $TODO_LIST remove-item $item; msg $item delete
            save-todo-list
            li/ id="$item" hx-swap-oob=delete; /li
            @todo-item-filters
            return
        fi
    fi

    msg $item get text; item_text=$RESULT

    local appending=
    if [[ $mode == appending ]]; then
        appending=data-appending=x
    fi

    li/ id="$item" class=TodoItem $appending \
        data-scope=$FUNCNAME ws-send \
        hx-trigger="@handle-item-text-update, @handle-new-item-insert"
        div/
            span/ class="TodoItem-dragHandle${appending:+ appending}"
                print "&vellip;&vellip;"
            /span; sp

            if [[ ! $appending ]]; then
                msg $item is-checked && checked=x
            fi
            @todo-checkbox $item ${checked:+checked}

            div/ class=TodoItem-text contenteditable ${mode:+autofocus}
                text "$item_text"
                br/  # See https://stackoverflow.com/a/27949928
            /div

            if [[ ! $appending ]]; then
                div/ class=TodoItem-controls
                    a/ id=delete_link_$item ="X" ws-send
                /div
            fi
        /div
    /li
}

@todo-checkbox () {
    local item=${1:-} checked updating=
    if [[ $item ]]; then
        checked=${2:-}
    else
        updating=x  # i.e., we are reacting to user clicking on the checkbox of an existing item
        local tname; get-hx-tname
        item=${tname#checkbox_}
        if [[ -v val_$tname ]]; then
            checked=x
            msg $item set checkedAt="$(date)"
        else
            checked=
            msg $item set checkedAt=
        fi
        save-todo-list
    fi

    if [[ $updating ]]; then
        [[ $checked ]] && local want=completed || local want=active
        if [[ $ITEM_FILTER != all && $ITEM_FILTER != $want ]]; then
            li/ id=$item hx-swap-oob=delete; /li
            @todo-item-filters
        fi
    else
        [[ $item == "$NEW_ITEM" ]] && local is_new=x || local is_new=
        span/ id="checkbox_$item" data-scope=$FUNCNAME
            input/ name=checkbox_$item type=checkbox ${checked:+checked} \
                   ws-send ${is_new:+disabled}
        /span
    fi
}

# See how the event is triggered and its details in app.js
@handle-item-text-update () {
    local tid; get-hx-tid

    if [[ -v val_appending ]]; then
        li/ id=$tid hx-swap-oob=delete; /li

        if [[ ${val_text:-} ]]; then
            local valname=val_checkbox_$NEW_ITEM
            msg $TODO_LIST append text="$val_text" ${!valname+"checkedAt=$(date)"}
            save-todo-list
            if [[ $ITEM_FILTER != completed ]]; then
                ol/ hx-swap-oob="beforeend:#todo-list"
                    @todo-item $RESULT
                /ol
            fi
        fi
        @new-item-button
        @todo-item-filters
    else
        msg $tid set text="$val_text"
        save-todo-list
        msg $tid is-checked && local want=completed || local want=active
        if [[ $ITEM_FILTER != all && $ITEM_FILTER != $want ]]; then
            li/ id=$tid hx-swap-oob=delete; /li
            @todo-item-filters
        fi
    fi
}

# See how the event is triggered and its details in app.js
@handle-new-item-insert () {
    local tid; get-hx-tid
    if [[ $tid == "$NEW_ITEM" ]]; then
        # It was triggered by the new-item (+) button to append the
        # item at the end of the list.
        msg $TODO_LIST _get-item -1
        tid=$RESULT
    fi
    local new_item; TodoItem new_item 
    msg $TODO_LIST insert-after $tid $new_item
    ol/ hx-swap-oob="afterend:#$tid"
        @todo-item $new_item inserted
    /ol

    @todo-item-filters
}


baguette

