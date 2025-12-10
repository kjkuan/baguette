#!/usr/bin/env bash
#
set -e

source baguette.sh

declare -A STATES

@main () {
    main/ id=${FUNCNAME#@} data-scope
        h2/ ="Welcome to Baguette"

        : ${STATES[username]:=${val_name:-}}

        if [[ ! ${STATES[username]:-} ]]; then
            textfield name=name label="What's your name?" placeholder="First Last" ws-send=no
            button label=Submit
        else
            markdown "_Hello ${STATES[username]:-World}!_"
        fi

        local label
        for label in one two three; do
            checkbox =${label^}  name=$label value=${label^}
        done

        local checked=(${val_one:-} ${val_two:-} ${val_three})
        markdown "You checked: **${checked[*]}**"
    /main
}

baguette
