# A checkbox.
#
# Input attributes:
#
#   label=    - The text label for the checkbox.
#
#   value     - The value to be set for the checkbox when it's checked. Default is 'on'.
#
#   checked   - The checkbox is checked if this attribute is present.
#
checkbox () {
    local -A attrs; args-to-attrs "$@" || err-return

    : id=${attrs[id]:=w$((++NEXT_WID))}

    local label=${attrs[label]:-}
    local with_block=${attrs[with]:-}
    unset attrs\[{label,with}\]

    attrs[type]=checkbox

    # Allow setting ws-send=no to disable ws-send
    [[ ${attrs[ws-send]:-} == no ]] && unset 'attrs[ws-send]' || attrs[ws-send]=

    # Keep track of widget state
    local name=${attrs[name]:-}
    [[ $name && -v "val_$name" ]] && attrs[checked]=

    local args=(); attrs-to-args || err-return

    div/ class="w-checkbox"
        input/ "${args[@]}"
        if [[ $label ]]; then
            label/ for="${attrs[id]}" ="$label"
        fi
        [[ ! $with_block ]] || "$with_block"
        #FIXME: allow passing some attribute to determine the relative location from
        #       which the with_block is called?
    /div
}
