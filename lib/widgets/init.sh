[[ ! ${BGT_WIDGETS_SOURCED:-} ]] || return 0

NEXT_WID=0

_bgt-init-built-in-widgets () {
    local widgets=(
        markdown.sh
        button.sh
        textfield.sh
        checkbox.sh
        radio.sh
        selectbox.sh
        file-upload.sh
        flash.sh
        file-explorer.sh
    )
    local widget
    for widget in "${widgets[@]}"; do
        source "$BGT_HOME/lib/widgets/$widget"
    done

    install-tags \
        title base link meta style \
        article section nav aside h{1..6} hgroup header footer address \
        p hr pre blockquote ol ul menu li dl dt dd figure figcaption main search div \
        a em strong small s dfn abbr data time code var samp kbd sub sup i b mark span br \
        ins del \
        picture source img iframe embed object video audio track \
        table caption colgroup col tbody thead tfoot tr td th \
        form label input button select datalist optgroup option textarea output progress meter fieldset legend \
        details summary dialog \
        script noscript template slot

    # Re-define the script tag to correctly handle inline contents specified with ="...."
    script/ () {
        local args=() contents
        while (( $# )); do
            if [[ $1 == =* ]]; then
                contents+=${1#=}
            else
                args+=("$1")
            fi
            shift
        done
        local js=()
        if [[ ${contents:-} ]]; then
            js=(
                'eval('
                "\"$(text "$contents")\""
                '.replace(/&amp;/g, "&")'
                '.replace(/&lt;/g, "<")'
                '.replace(/&gt;/g, ">")'
                '.replace(/&quot;/g, "\"")'
                ".replace(/&#39;/g, \"'\")"
                '.replace(/&#10;/g, "\n")'
                ');'
            )  # The replace()'s here reverse the effect of escape-html() in utils.sh.
        fi
        print-tag script "${args[@]}"
        print "${js[*]}"
        print "</script>"
    }
}
_bgt-init-built-in-widgets

BGT_WIDGETS_SOURCED=x
