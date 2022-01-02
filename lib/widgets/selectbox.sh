# A drop-down list of options.
#
# Usage: selectbox id=ID ... <option-groups>
#
# where <option-groups> is one or more arguments of this form:
#
#   < -- | --group ...> <option=...> [value=...] [selected]
#
# NOTE: Use '--' to start options outside of an option group; use '--group G' to
#       start an option group, G, for the following options (option=... value=...).
#
# Input attributes:
#
#   label   - Text label for the widget.
#
# Option attributes:
#
#   option   - The option text.
#
#   value    - Value to be set when the option is selected
#              Default is the value of the 'option' attribute.
#
#   selected - Select the option by default if this attribute is present.
#
#   NOTE: One should make sure the values of options are unique within
#         the selectbox widget; otherwise, wrong options might be selected.
#
# Example:
#
#     selectbox name=fruit label="Some fruits" \
#         -- \
#           option=Banana     value=banannanana \
#           option=Strawberry value=bbbbberry   \
#            \
#         --group "Group 1" \
#           option="Honey Crisp" value=apple selected \
#           option=Orange   \
#            \
#         --group "Group 2" \
#           option=Grape    \
#           option=Pear     \
#         -- \
#           option=Pineapple value=pppineable
#
#
selectbox () {
    # Extract the name=value args that come before the group option args (--* ...)
    local named_args=()
    while (( $# )); do
        if [[ $1 == --* ]]; then break; fi
        named_args+=("$1")
        shift
    done
    local -A attrs; args-to-attrs "${named_args[@]}" || err-return

    local name=${attrs[name]:-}
    local label=${attrs[label]:-}
    unset 'attrs[label]'

    [[ ${attrs[ws-send]:-} == no ]] && unset 'attrs[ws-send]' || attrs[ws-send]=
    local args=(); attrs-to-args || err-return

    # Keep track of widget state
    declare -A state=()
    if [[ $name && -v "val_$name" ]]; then
        local val; local -n vals=val_$name
        for val in "${vals[@]}"; do state[$val]=selected; done
    fi

    div/ class="w-selectbox"
        if [[ $label ]]; then
            label/; text "$label"
        fi
        select/ "${args[@]}"
            local group option value selected
            while (( $# )); do
                if [[ $1 == @(--|--group) ]]; then
                    # Close previous open group if there was one and we are opening new one
                    if [[ $group ]] && [[ $1 == -- || ${2:-} != "$group" ]]; then
                        /optgroup
                    fi
                    [[ $1 == -- ]] && group= || { group=${2:-}; shift; }
                    shift || err-return  # missing expected group name

                    if [[ $group ]]; then optgroup/ label="$group"; fi

                elif [[ $1 == option=* ]]; then
                    option=${1#option=}; shift
                    [[ $option ]] || err-return  # empty option not allowed
                    value= selected=
                    if (( $# )); then
                        for _ in 1 2; do
                            case $1 in
                              value=*)
                                  value=${1#value=}; shift
                                  [[ $value ]] || err-return  # empty value not allowed
                                  ;;
                              selected)
                                  selected=x; shift
                                  ;;
                              option=*|--*|'')
                                  break
                                  ;;
                              *) err-trace "Unexpected token ($1) after an 'option=...'" 1
                                 return
                                  ;;
                            esac
                        done
                    fi
                    # if there's a state then we don't want the default selected attribute
                    (( ${#state[*]} )) && selected=
                    option/ ="$option" value="${value:-$option}" \
                            ${state[${value:-$option}]:-} ${selected:+selected}
                else
                    err-trace "Unexpected token ($1) before the start of an option or group!" 1
                    return
                fi
            done
            if [[ $group ]]; then /optgroup; fi
        /select
        [[ $label ]] && /label
    /div
}
