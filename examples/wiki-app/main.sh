#!/usr/bin/env bash
#
# A simple personal wiki app based on Markdown
#
# TODO:
#  - Use git for versioning the wiki files
#  - Allow tagging a document
#  - Allow incremental searching
#  - Generate backlinks
#  - Generate knowledge graph
#  - Allow generating htmls for publishing as a static website
#    - Generate a ToC
#  - Allow transclusion
#  - Implement group operations?
#
set -eo pipefail

source baguette.sh

cd "$WSD_SCRIPT_DIR"

WIKI_HOME=$PWD/wiki

[[ -d $WIKI_HOME ]] || {
    mkdir -p "$WIKI_HOME"
    cat > "$WIKI_HOME/Index.md" <<'EOF'
# Wiki

This is the default starting page of the wiki. You can edit it or create a new page.
To link to a new or existing page, simply use the link syntax in Markdown, like:

```markdown
    This is a [link](relative-path-to-another-file) to another page.
```

Which, in preview-mode, would look like:

>    This is a [link](relative-path-to-another-file) to another page.

If the link URL is omitted in the parentheses (`()`) then it defaults to the display name
specified in the square brackets (`[...]`).

Clicking on a link navigates to the page (view) if it exists. If the page doesn't already exists,
it gets created and the app lets you edit it right then.

When editing a page, you may click the `Preview` button anytime to see how it will be rendered;
clicking the `Save` button to save the page and return to the page view mode.

Clicking on a link with an external URL will open the page in a separate window.

You can drag and drop files or directories in the file explorer panel on the left to
organize your pages. Right clicking on the panel opens a context menu that allows you
to delete and rename selected files.
EOF
}

declare -g FE_MODEL
FileExplorerModel FE_MODEL root="$WIKI_HOME"


@main () {
    main/ id=main data-scope

        div/ id="file-explorer-panel"

            a/ id=$FE_MODEL-new-note   data-scope=file-explorer ws-send href=# ="+ Note"; sp
            a/ id=$FE_MODEL-new-folder data-scope=file-explorer ws-send href=# ="+ Folder"
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
    (cd "$WIKI_HOME" && rm -rf -- "${paths[@]}")
    for path_id in "${val_path_ids[@]}"; do
        li/ id=$path_id hx-swap-oob=delete; /li
    done
}

@handle-file-rename () {
    msg $FE_MODEL id-path $val_path_id; local path=$RESULT
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
            text "$val_old_name"
        /li
        return 0
    }

    (cd "$WIKI_HOME" && mv "$path" "$new_path")

    # Remove old path-id and re-render from the parent directory
    msg $FE_MODEL remove-id "$val_path_id"
    if [[ $new_path == */* ]]; then
        msg $FE_MODEL path-id ${new_path%/*}
    else
        RESULT=$FE_MODEL
    fi
    file-explorer "$RESULT"
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
                    flash msg="Failed moving $src to $dst !"
                fi
            else
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

@fe-handle-item-move-overwrite () {
    local src dst tid; get-hx-tid
    local model=${tid%%-*}
    msg $model id-path "$val_fromItemId"; src=$WIKI_HOME/$RESULT
    msg $model id-path "$val_toItemId"; dst=$WIKI_HOME/$RESULT
    mv -- "$src" "$dst"
    li/ id=$val_fromItemId hx-swap-oob=delete; /li
    msg $model remove-id "$val_fromItemId"
}

@fe-handle-refresh () {
    local tid; get-hx-tid
    model=${tid%%-*}
    file-explorer "$model"
}

CURRENT_NODE=  # path-id of the current node being viewed
CURRENT_CONTENTS=

# a stack of path-id's that lead to the currently selected page being viewed;
# ${LINK_STACK[-1]} is the top.
#
LINK_STACK=("")


@file-viewer () {  # <path-id> ['view'|'edit']
    local path_id=${1:-${val_path_id:-}} path
    local mode=${2:-${val_btn_mode:-}}; [[ $mode ]] || mode=view
    local model=${path_id%%-*}

    local tid; get-hx-tid
    if [[ $tid == back-btn ]]; then
        path_id=$val_back_btn_link
        msg $model id-path "$path_id"; path=$RESULT
        fe-navigate-to-path "$path_id" "$path" "$val_path_id"
        (( ${#LINK_STACK[*]} > 1 )) && unset -v "LINK_STACK[-1]"

    elif [[ ${val_link:-} ]]; then
        # user clicked on a link in view / preview mode
        [[ ${LINK_STACK[-1]:-} != "$val_path_id" ]] &&
            LINK_STACK+=("$val_path_id")

    elif [[ ! ${val_path_id:-} ]]; then
        # user clicekd on a file node in the file explorer
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
            (cd "$WIKI_HOME" && mkdir -p "$(dirname "$path")")
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

        fe-navigate-to-path "$path_id" "$val_link" "$val_path_id"

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
            case $mode in
                edit) local btn_mode=view ;;
                view) local btn_mode=edit ;;
                *) err-return ;;
            esac
            button name=btn_mode label=${btn_mode^} value=$btn_mode; sp
            if [[ -v val_btn_mode ]]; then
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
