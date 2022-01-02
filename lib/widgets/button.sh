# A button widget.
#
# Input attributes:
#
#   label=OK       - Text to be shown on the button.
#
#   value=clicked  - Value to be set when the button is clicked.
#
#   type=button    - Type of the button. Default is a normal 'button' type.
#                    Set it to 'submit' explicitly if you wish it to act as the
#                    submit button when used inside a form.
#
button () {
    local -A attrs; args-to-attrs "$@" || err-return

    : type=${attrs[type]:-button}
    : value=${attrs[value]=clicked}

    local label=${attrs[label]-OK}
    unset 'attrs[label]'

    [[ ${attrs[ws-send]:-} == no ]] && unset 'attrs[ws-send]' || attrs[ws-send]=

    attrs[class]+=" w-button"

    local args=(); attrs-to-args || err-return

    button/ "${args[@]}" ="$label"
}
