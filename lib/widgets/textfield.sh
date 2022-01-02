# A text input field.
#
# Input attributes:
#
#   label=     - The text label for the field. Default is empty, meaning no labels.
#
#   type=text  - Type of the text field.
#
#   value=     - The initial text to be shown in the field. Default is empty.
#
#   multiline  - If present, the input field becomes a text area able
#                to contain multi-line inputs.
#
textfield () {
    local -A attrs; args-to-attrs "$@" || err-return

    : id=${attrs[id]:=w$((++NEXT_WID))}
    : type=${attrs[type]:=text}

    local label=${attrs[label]:-}
    local multiline=${attrs[multiline]+x}
    local with_block=${attrs[with]:-}
    unset attrs\[{label,multiline,with}\]

    # Allow setting ws-send=no to disable ws-send
    [[ ${attrs[ws-send]:-} == no ]] && unset 'attrs[ws-send]' || attrs[ws-send]=

    # Keep track of widget state
    local name=${attrs[name]:-}
    [[ $name && -v "val_$name" ]] && name=val_$name && attrs[value]=${!name}

    if [[ $multiline ]]; then
        attrs[" "]=${attrs[value]}
        unset 'attrs[value]'
    fi

    local args=(); attrs-to-args || err-return

    div/ class="w-textfield"
        if [[ $label ]]; then
            label/ for="${attrs[id]}" ="$label"
        fi
        if [[ ! $multiline ]]; then
            input/ "${args[@]}"
        else
            textarea/ "${args[@]}"; /textarea
        fi
        [[ ! $with_block ]] || "$with_block"
    /div
}
