#!/usr/bin/env bash
#
# A simple Markdown preview app to preview entered Markdown text as one types.
#
set -eo pipefail

source baguette.sh

@main () {
    main/ id=main
        div/ class=InputPane
            div/ id="markdown-editor"; /div
            input/ id=markdown-input name=markdown_text type=hidden \
                   hx-trigger="change" data-scope ws-send

            script/ ="$(cat <<'EOF'
                const editor = ace.edit("markdown-editor");
                editor.session.setMode("ace/mode/markdown");
                editor.session.on("change", debounce(function () {
                    const elt = document.getElementById("markdown-input");
                    elt.value = editor.getValue();
                    elt.dispatchEvent(new Event("change"));
                }, 70));
EOF
            )"
        /div
        div/ class=OutputPane
            div/ id=markdown-preview class=markdown-body; /div
        /div
        script/ ="$(cat <<'EOF'
            htmx.onLoad(function(elt) {
                if (elt.parentElement.id === "markdown-preview") {
                    const blocks = elt.querySelectorAll("pre code");
                    blocks.forEach(hljs.highlightElement);
                }
            });
EOF
        )"
    /main
}

@markdown-input () {
    div/ id=markdown-preview hx-swap-oob=innerHTML
        markdown "$val_markdown_text"
        # NOTE: The cmark-gfm tool needs to be pre-installed.
    /div
}

baguette
