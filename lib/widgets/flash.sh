# Command to flash a message and/or html in the #bgt-flash-area at the end of
# the current app response.
#
# Input attributes:
#
#   msg=   - Text to be shown in the flash message area.
#
# This isn't strictly a UI "widget" and it requires an element with the id,
# 'bgt-flash-area', already defined in the document.
#

flash () { BGT_POST_RENDER_QUEUE+=("_flash $(printf '%q ' "$@")"); }
flash-clear () { div/ id="bgt-flash-area"; /div; }

_flash () {  # msg=...
    local -A attrs; args-to-attrs "$@" || err-return

    local msg=${attrs[msg]}
    local class=${attrs[class]:-}
    local with_block=${attrs[with]:-}

    unset attrs\[{class,msg,with}\]
    local args=(); attrs-to-args || err-return

    div/ hx-swap-oob="afterbegin:#bgt-flash-area"
        div/ class="w-flash $class" "${args[@]}"
            span/ ="$msg"
            [[ ! $with_block ]] || "$with_block"
        /div
    /div
    #FIXME: add a close button to allow dismissing the message
}
