# A group of radio buttons.
#
# Usage: radio id=ID ... -- <label=...> [[value=...] [checked]] ...
#
# Input attributes:
#
#   id      - Optional, but one must be provided if the widget needs to be
#             directly swappable by htmx.
#
#   name    - Optional, but required for the transfering and tracking the radio
#             button states. Default to the same as the 'id' attribute.
#
#   label   - Required. Text label for a radio button.
#
#   value   - Required. Value to be set if the radio button is on.
#             Default is the value of the 'label' attribute.
#
#   checked - The radio button is "on" if this attribute is present.
#
#   NOTE: For ease of implementation, value can't be an empty string.
#
#   NOTE: One should make sure the values of radio buttons are unique within
#         the group; otherwise, the wrong button might be turned on, and the
#         widget won't be able to determine its state correctly.
#
# Examples:
#
#    radio name=my_color -- \
#        label="Red"   \
#        label="Green" \
#        label="Blue"  \
#
#    radio name=my_color -- \
#        label="Red"    value="#ff0000" \
#        label="Green"  value="#00ff00" \
#        label="Blue"   value="#0000ff"
#
#    radio name=my_color -- \
#        label="Red"   checked \
#        label="Green" value="#3cb371" \
#        label="Blue"  value="jazz"
#
#
radio () {
    # Extract name=value args into attrs
    local named_args=()
    while (( $# )); do
        if [[ $1 == -- ]]; then shift; break; fi
        named_args+=("$1")
        shift
    done
    local -A attrs; args-to-attrs "${named_args[@]}" || err-return
    (( $# )) || err-return
    #
    # The rest of the args should be multiples of this form:
    #
    #   <label=...> [[value=...] [checked]]
    #

    local id=${attrs[id]:-}
    local name=${attrs[name]:-$id}
    unset attrs\[{id,name}\]

    [[ ${attrs[ws-send]:-} == no ]] && unset 'attrs[ws-send]' || attrs[ws-send]=

    attrs[class]+=" w-radio"
    local args=(); attrs-to-args || err-return

    # Keep track of widget state
    local -A state=()
    if [[ $name && -v "val_$name" ]]; then
        local valname=val_$name
        state[${!valname}]=checked
    fi

    div/ ${id:+id="$id"} "${args[@]}"
        local label value checked
        while (( $# )); do
            if [[ $1 == label=* ]]; then
                label=${1#label=}; shift
                [[ $label ]] || err-return  # empty label not allowed
                value= checked=
                if (( $# )); then  # For the next two args after label=...
                    for _ in 1 2; do
                        case $1 in
                            value=*)
                                value=${1#value=}; shift
                                [[ $value ]] || err-return # empty value not allowed
                                ;;
                            checked|checked=*)
                                checked=x; shift
                                ;;
                            label=*|'')
                                # End of the radio button arguments, or the start of the next
                                # radio button's attributes.
                                break
                                ;;
                            *) err-trace "Unexpected token ($1) after a label ($label)!" 1
                               return
                                ;;
                        esac
                    done
                fi
                # if there's a state then we don't want the default checked attribute
                (( ${#state[*]} )) && checked=
                div/
                    label/
                        input/ ${name:+name="$name"} type=radio value="${value:-$label}" \
                               ${state[${value:-$label}]:-} ${checked:+checked};
                        text " $label"
                    /label
                /div
            else
                err-trace "Unexpected token ($1); was expecting a 'label=...' instead!" 1
                return
            fi
        done
    /div
}
