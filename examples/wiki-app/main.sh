#!/usr/bin/env bash
#
# A simple personal wiki app based on Markdown
#
# TODO:
#  - Allow tagging a document
#    - Use this syntax in the doc:  [//]: # (tag tag1 tag2 tag3 ...)
#    - the same mechanism can be used for embedding other metadata. E.g.
#      - [//]: # (title "Document Title")
#      - [//]: # (author "First Last")
#
#  - Allow incremental searching
#  - Generate backlinks
#  - Use github's markdown stylesheet
#
#  - Generate knowledge graph
#  - Allow generating htmls for publishing as a static website
#    - Generate a ToC
#  - Allow transclusion
#  - Implement group operations?
#    - allow selecting multiple files
set -eo pipefail

source baguette.sh

FE_LS_OPTS+=(--ignore=.*)
FE_MODEL=  # to be created later

WIKI_HOME=${WIKI_HOME:-$WSD_SCRIPT_DIR/wiki}

CURRENT_NODE=  # path-id of the current node being viewed
CURRENT_CONTENTS=

# a stack of path-id's that lead to the currently selected page being viewed;
# ${LINK_STACK[-1]} is the top.
#
LINK_STACK=("")

class WikiFEModel isa=FileExplorerModel

# Hide the .md extension when listing files
WikiFEModel/list () {
    msg $self ../list "$@"
    local i
    for ((i=0; i < ${#RESULT[*]}; i++)); do
        RESULT[i]=${RESULT[i]%.md}
    done
}
WikiFEModel/has-path-id () { [[ ${1:-} ]] && [[ ${self[$1]:-} ]]; }

[[ -d $WIKI_HOME ]] || {
    mkdir -p "$WIKI_HOME"; (
        cd "$WIKI_HOME"

        git init -b main
        git config user.email "baguette+wiki@localhost"
        git config user.name "Baguette Wiki-App"

        cp "$WSD_SCRIPT_DIR/Index.md" .
        echo ".gitkeep" > .gitignore
        git add Index.md .gitignore
        git commit -m "New WIKI_HOME created; added default Index.md."
    )
}
WikiFEModel FE_MODEL root="$WIKI_HOME"

git-tracked () { git ls-files --error-unmatch -- "${1:?}" >/dev/null 2>&1; }


@main () {
    main/ id=main data-scope
        div/ id="file-explorer-panel"

            small/ style="float: right; margin-right: 5px"
                a/ id=$FE_MODEL-new-note   data-scope=file-explorer ws-send href=# ="+Note"; sp
                a/ id=$FE_MODEL-new-folder data-scope=file-explorer ws-send href=# ="+Folder"
            /small
            @file-explorer $FE_MODEL

            div/ id=fe-context-menu class=ContextMenu \
                 hx-trigger="@handle-file-deletes, @handle-file-rename" ws-send
                ul/
                    li/ ="Delete" hx-on:click="delete_selected_files()"
                    li/ ="Rename" hx-on:click="rename_selected_file()"
                /ul
            /div
        /div
        div/ id=file-viewer; /div
    /main
}

@handle-file-deletes () {
    [[ ${val_path_ids:-} ]] || return 0
    local path_id paths=()
    for path_id in "${val_path_ids[@]}"; do
        msg $FE_MODEL id-path $path_id; paths+=("$RESULT")
        msg $FE_MODEL remove-id $path_id
    done
    (cd "$WIKI_HOME"
     rm -rf -- "${paths[@]}"
     git rm -r --ignore-unmatch -- "${paths[@]}"
     if git status --porcelain -- "${paths[@]}" | grep -q ^D; then
         git commit -m "Delete files"$'\n'$'\n'"$(
             IFS=$'\n'; sed -e 's/^/    /' <<<"${paths[*]}"
         )"
     fi
    )
    for path_id in "${val_path_ids[@]}"; do
        li/ id=$path_id hx-swap-oob=delete; /li
    done

    if [[ " $CURRENT_NODE " == *" ${val_path_ids[*]} "* ]]; then
        # clear the file-viewer
        div/ id=file-viewer; /div
    fi
}

@handle-file-rename () {
    local model=${val_path_id%%-*}
    msg $model id-path $val_path_id; local path=$RESULT

    val_old_name+=.md
    val_new_name+=.md
    [[ $val_old_name == "${path##*/}" ]] # sanity check

    if [[ $path == */* ]]; then
        local new_path=${path%/*}/$val_new_name
    else
        local new_path=$val_new_name
    fi
    {
      [[ ${val_new_name:-} && $val_new_name != */* ]] &&
      [[ ! -e "$WIKI_HOME/$new_path" ]]
    } || {
        flash msg="Invalid or duplicate name: $val_new_name"

        # Restore the old name
        li/ id="$val_path_id" hx-swap-oob="textContent: #$val_path_id .FE-Label"
            text "${val_old_name%.md}"
        /li
        return 0
    }

    (cd "$WIKI_HOME"
     if git-tracked "$path"; then
         git mv -k -- "$path" "$new_path"
         git commit -m "Rename $path to $new_path"
     else
         # file is not tracked by git yet; this can happen when a new file is just
         # created but not yet saved.
         mv "$path" "$new_path"
     fi
    )

    # Remove the old path-id
    msg $model remove-id "$val_path_id"

    msg $FE_MODEL path-id "$new_path"; local new_path_id=$RESULT
    fe-navigate-to-path $new_path_id
    @file-viewer $new_path_id  # needed to keep the tree and the view in-sync


    # FIXME: need to fix all backlinks
}

create-untitled () (  # <file|folder>
    [[ ${1:-} == @(file|folder) ]]

    [[ $1 == file ]] && local ext=md || local ext=
    cd "$WIKI_HOME"; local name
    for name in Untitled Untitled-{1..100}; do
        if [[ ! -e "$name${ext:+.$ext}"  ]]; then
            if [[ $1 == file ]]; then
                touch "$name.$ext"
            else
                mkdir "$name"
                touch "$name/.gitkeep"
            fi
            return
        fi
    done
    return 1  # oops, too many untitiled files!
)

@file-explorer () {
    local model=${1:-} path
    if [[ ! $model ]]; then
        local tid; get-hx-tid
        model=${tid%%-*}

        if [[ $tid == *-new-note ]]; then
            create-untitled file
            set -- "$model"  # so that 'file-explorer "$@"' would do a full refresh.

        elif [[ $tid == *-new-folder ]]; then
            create-untitled folder
            set -- "$model"

        elif [[ ${HX[Trigger-Event]:-} == fe-handle-item-move ]]; then

            # For some reason, the event gets triggered twice for a move;
            # once by the dragged LI; another by the destination UL, even
            # though the htmx triggering element is the same.
            #
            # We only need one event, so this is how we can make sure.
            [[ $tid == "$val_fromItemId" ]] || return 0

            local src dst
            msg $model id-path "$val_fromItemId"; src=$WIKI_HOME/$RESULT
            msg $model id-path "$val_toItemId"; dst=$WIKI_HOME/$RESULT

            local out
            if ! out=$(mv --no-clobber -- "$src" "$dst" 2>&1); then
                if [[ $out == "mv: not replacing "* ]]; then
                    msg $model root-id; local root_id=$RESULT
                    src=${src##*/} dst=${dst#$WIKI_HOME/}/
                    script/ id=script-from-server ="$(cat <<EOF
                        if (confirm("Overwrite '$src' in '$dst' ?")) {
                            htmx.trigger("#$root_id", "@fe-handle-item-move-overwrite", {
                                fromItemId: "$val_fromItemId",
                                toItemId: "$val_toItemId",
                            });
                        } else {
                            htmx.trigger("#$root_id", "@fe-handle-refresh");
                        }
EOF
                    )"
                    return
                else
                    # e.g., permission issue, or moving a directory to a non-directory
                    flash msg="Failed moving $src to $dst !"
                fi
            else
                -git-mv "${src#$WIKI_HOME/}" "${dst#$WIKI_HOME/}"

                # Remove the moved item because it will get a new id when
                # listed from its new directory later
                msg $model remove-id "$tid"
            fi

            set -- "$model"

        elif [[ $tid == *f ]]; then  # an item was clicked
            @file-viewer "$tid"
        fi

    fi
    file-explorer "$@"
}

-git-mv () (
    cd "$WIKI_HOME" || err-return
    local src=$1 dst=$2 tracked

    git-tracked "$src" && {
        git rm "$src" || err-return
        tracked=x
    }
    if [[ -d $dst ]]; then
        [[ $tracked ]] && { git add "$dst/${src##*/}" || err-return; }

    elif git-tracked "$dst"; then
        git add "$dst" || err-return
        tracked=x
    fi
    if [[ ${tracked:-} ]]; then
        git commit -m "Move $src to $dst" || err-return
    fi
)

@fe-handle-item-move-overwrite () {
    local src dst tid; get-hx-tid
    local model=${tid%%-*}
    msg $model id-path "$val_fromItemId"; src=$WIKI_HOME/$RESULT
    msg $model id-path "$val_toItemId"; dst=$WIKI_HOME/$RESULT

    mv -- "$src" "$dst"
    -git-mv "${src#$WIKI_HOME/}" "${dst#$WIKI_HOME/}"

    li/ id=$val_fromItemId hx-swap-oob=delete; /li
    msg $model remove-id "$val_fromItemId"
}

@fe-handle-refresh () {
    local tid; get-hx-tid
    model=${tid%%-*}
    file-explorer "$model"
}


@file-viewer () {  # <path-id> ['view'|'edit']
    local path_id=${1:-${val_path_id:-}} path
    local mode=${2:-${val_btn_mode:-}}; [[ $mode ]] || mode=view
    local model=${path_id%%-*}

    local tid; get-hx-tid
    if [[ $tid == back-btn ]]; then

        # This check is needed because the node might have been moved or deleted
        if msg $model has-path-id "$val_back_btn_link"; then
            path_id=$val_back_btn_link
            msg $model id-path "$path_id"; path=$RESULT
            fe-navigate-to-path "$path_id" "$path"
        fi
        (( ${#LINK_STACK[*]} > 1 )) && unset -v "LINK_STACK[-1]"

    elif [[ ${val_link:-} ]]; then
        # user clicked on a link in view / preview mode
        [[ ${LINK_STACK[-1]:-} != "$val_path_id" ]] &&
            LINK_STACK+=("$val_path_id")

    elif [[ ! ${val_path_id:-} ]]; then
        # user clicked on a file node in the file explorer
        [[ $CURRENT_NODE && ${LINK_STACK[-1]:-} != "$CURRENT_NODE" ]] &&
            LINK_STACK+=("$CURRENT_NODE")
    fi

    if [[ ${val_link:-} ]]; then  # user clicked on a link
        val_link=${val_link%.md}.md

        path=$(realpath --relative-base="$WIKI_HOME" -m "$WIKI_HOME/$val_link")
        [[ $path != /* && $path != . ]] || {
            flash msg="Invalid link: $val_link"
            return
        }
        if [[ ! -e "$WIKI_HOME/$path" ]]; then
            (cd "$WIKI_HOME" && d=$(dirname "$path") && mkdir -p "$d" && touch "$d/.gitkeep")
            touch "$WIKI_HOME/$path"
            mode=edit
        fi

        # Get the path id in order to navigate to it later
        if msg "$model" path-id "$val_link"; then
            path_id=$RESULT
        else # This shouldn't be possible but just in case ...
            flash msg="Invalid link: $val_link"
            return
        fi

        fe-navigate-to-path "$path_id" "$val_link"

        #FIXME: If the current page has been changed, prompt and ask the user if he/she
        #       wants to save the current page.
    fi

    [[ ${path:-} ]] || { msg "$model" id-path "$path_id"; path=$RESULT; }
    path=$WIKI_HOME/$path

    CURRENT_NODE=$path_id

    if [[ -v val_contents ]]; then
        CURRENT_CONTENTS=$val_contents
    fi

    if [[ -v val_btn_save ]]; then
        printf -- %s "$CURRENT_CONTENTS" > "$path"
        (cd "$WIKI_HOME"
         git add -- "${path#$WIKI_HOME/}"
         git commit -m "Add or update ${path#$WIKI_HOME/}"
        )
        [[ $val_btn_save == edit ]] && mode=view

    elif [[ -v val_btn_cancel ]]; then
        CURRENT_CONTENTS=$(cat "$path")
        mode=view

    elif [[ ! -v val_btn_mode ]]; then
        CURRENT_CONTENTS=$(cat "$path")
    fi

    div/ id=${FUNCNAME#@} data-scope
        input/ name=path_id type=hidden value=$path_id
        div/ class=FileViewer-controls
            if (( ${#LINK_STACK[*]} > 1 )); then
                button id=back-btn name=back_btn_link label=Back value=${LINK_STACK[-1]}; sp
            else
                button label=Back disabled; sp
            fi
            # QUESTION: Do we want a Forward button?

            case $mode in
                edit) local btn_mode=view ;;
                view) local btn_mode=edit ;;
                *) err-return ;;
            esac
            button name=btn_mode label=${btn_mode^} value=$btn_mode; sp
            if [[ $mode == @(view|edit) ]]; then
                button name=btn_save label=Save value=$mode; sp
                button name=btn_cancel label=Cancel
            else
                button label=Save disabled; sp
                button label=Cancel disabled
            fi
        /div
        if [[ $mode == view ]]; then
            div/ class="FileViewer-contents preview"
                markdown "$CURRENT_CONTENTS" | post-process-html
            /div
        else # edit mode
            textfield class=FileViewer-contents name=contents value="$CURRENT_CONTENTS" \
                      multiline ws-send=no
            #FIXME: this should be below the buttons
        fi
    /div
}

post-process-html () {
    local html; html=$(cat); [[ $html ]] || return 0
    xmlstarlet tr --html <(cat <<'EOF'
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

    <xsl:template match="node()|@*">
        <xsl:copy>
            <xsl:apply-templates select="node()|@*"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template name="get-href">
        <xsl:param name="href" select="current()"/>
        <xsl:choose>
            <xsl:when test="$href = ''">
                <xsl:value-of select="$href/../text()"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$href"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template match="//a/@href">
        <xsl:attribute name="href">
            <xsl:call-template name="get-href"/>
        </xsl:attribute>
    </xsl:template>

    <xsl:template match="//a[@href]">
        <xsl:copy>
            <xsl:choose>
                <xsl:when test="not(contains(@href, '://'))">
                    <xsl:attribute name="ws-send"/>
                    <xsl:attribute name="data-link">
                        <xsl:call-template name="get-href">
                            <xsl:with-param name="href" select="@href"/>
                        </xsl:call-template>
                    </xsl:attribute>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:attribute name="target">_blank</xsl:attribute>
                </xsl:otherwise>
            </xsl:choose>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

</xsl:stylesheet>
EOF
    ) <<<"$html" \
    |
   sed -e 's|<html><body>||; s|</body></html>||' \
    |
   while read -r line; do
       printf "%s&#10;" "$line"
   done
}




#BGT_TRACE_FILE=./x.out
baguette
