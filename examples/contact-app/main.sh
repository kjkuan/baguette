#!/usr/bin/env bash
#
set -eo pipefail

source baguette.sh

cd "$WSD_SCRIPT_DIR"

source model.sh

Contact/load-db

@main () {
    local tid=${1:-}; [[ $tid ]] || get-hx-tid
    if [[ $tid == ContactsTable-deleteLink-* ]]; then
        tid=${tid#*-deleteLink-}
        Contact/find "$tid"
        msg "$RESULT" delete
        tr/ id="ContactsTable-row-$tid" hx-swap-oob=delete; /tr
        return
    fi
    main/ id=main data-scope
        case ${tid:-} in 
            ContactsTable-editLink-*|ContactView-editLink-*)
                @contact-edit "${tid#*-editLink-}"
                ;;
            ContactsTable-viewLink-*)
                -contact-view "${tid#*-viewLink-}"
                ;;
            ContactsTable-newLink)
                @contact-new
                ;;
            *)  @archive-ui
                -contacts-table
                ;;
        esac
    /main
}

-contacts-table () {
    div/ class="tool-bar"
        textfield label="Search Term" name="q" id="search" \
                  hx-trigger="@contacts-tbody" \
                  hx-indicator="#spinner1"
        img/ style="height: 20px" id="spinner1" class="htmx-indicator" src="/static/img/spinning-circles.svg"
        # NOTE: hx-indicator doesn't work with ws-send in htmx 1.8

        button label="Search" id="ContactsSearch-submitBtn"
        script/ ="
            const search_input = document.getElementById('search');
            search_input.addEventListener('keyup',
                debounce(function() {
                    if (search_input.dataset['value'] !== search_input.value) {
                        htmx.trigger(search_input, '@contacts-tbody');
                    }
                    search_input.dataset['value'] = search_input.value;
                }, 200)
            );
        "
    /div
    div/ x-data="{ selected: [] }"
        template/ x-if="selected.length > 0"
            div/ class="box info tool-bar flxed top"
                slot/ x-text="selected.length"; /slot
                text " contacts selected"; sp

                button/ ="Delete" class="bad bg color border" \
                       id="ContactsTable-deleteContactsBtn-interactive" \
                       x-on:click='
                           if (confirm(`Delete ${selected.length} contacts?`)) {
                               document.getElementById("ContactsTable-deleteContactsBtn").click();
                           }
                       '

                hr/ aria-orientation="vertical"
                button label="Cancel" x-on:click="selected = []"
            /div
        /template
        table/
            thead/
            tr/
                th/ = # checkbox
                th/ =First
                th/ =Last
                th/ =Phone
                th/ =Email
                th/ = # Options
            /tr
            /thead
            @contacts-tbody
        /table

        button id="ContactsTable-deleteContactsBtn" label="Delete Selected Contacts" \
               data-render="@ContactsTable-tbody" hx-include='#ContactsTable-tbody'
    /div

    p/
        a/ id=ContactsTable-newLink ="Add Contact" ws-send data-scope=main; sp

        #FIXME: 'revealed' doesn't seem to work with ws-send?
        # span/ hx-trigger="revealed" ws-send id="contacts-count" data-scope
        #     img/ style="height: 20px" class="htmx-indicator" src="/static/img/spinning-circles.svg"
        # /span
        #
        # Workaround:
        img/ style="height: 20px" src="/static/img/spinning-circles.svg" \
             id="contacts-count" data-scope hx-trigger="@contacts-count" ws-send
        script/ ="htmx.trigger('#contacts-count', '@contacts-count')"
    /p
}

@contacts-count () {
    Contact/count
    span/ id="contacts-count" ="($RESULT total Contacts)"
}

@contacts-tbody () {
    local search tid; get-hx-tid
    if [[ $tid == ContactsTable-deleteContactsBtn* ]]; then
        local id
        for id in "${val_selected_contact_ids[@]}"; do
            Contact/find "$id"
            msg "$RESULT" delete
        done
        flash msg="Deleted Contacts!"

    elif [[ $tid == @(search|ContactsSearch-submitBtn) && ${val_q:-} ]]; then
        Contact/search "$val_q"
        search=x
    fi
    [[ ${search:-} ]] || Contact/all 1

    tbody/ id="ContactsTable-tbody" data-scope x-init='selected = []'
        local contact cid
        for contact in "${RESULT[@]}"; do
            msg "$contact" get id first= last= phone= email
            cid=$RESULT
            tr/ id="ContactsTable-row-$cid"
                td/; input/ type="checkbox" name="selected_contact_ids" \
                            value="$cid" x-model="selected"
                /td
                td/ ="${RESULT[1]}"
                td/ ="${RESULT[2]}"
                td/ ="${RESULT[3]}"
                td/ ="${RESULT[4]}"
                td/
                    div/ data-overflow-menu
                        button/ type="button" \
                                aria-haspopup="menu" \
                                aria-controls="contact-menu-$cid" \
                                ="Options"
                        div/ role="menu" hidden id="contact-menu-$cid"
                            a/ id="ContactsTable-editLink-$cid" role="menuitem" href="#" ="Edit" ws-send data-scope=main
                            a/ id="ContactsTable-viewLink-$cid" role="menuitem" href="#" ="View" ws-send data-scope=main
                            a/ id="ContactsTable-deleteLink-$cid" role="menuitem" href="#" ="Delete" ws-send data-scope=main \
                            hx-on::ws-before-send="
                                if (!confirm('Are you sure you want to delete this contact?'))
                                    event.preventDefault();
                            "
                        /div
                    /div
                /td
            /tr
        done
    /tbody
}

-contact-view () {  # [cid]
    local cid=${1:-0}
    Contact/find "$cid"
    msg "$RESULT" get first= last= phone= email id
    h1/ ="${RESULT[0]} ${RESULT[1]}"
    div/
        div/ ="Phone: ${RESULT[2]}"
        div/ ="Email: ${RESULT[3]}"
    /div
    p/
        a/ id="ContactView-editLink-${RESULT[4]}" href="#" ="Edit" ws-send; sp
        a/ href="#" ="Back" ws-send data-render=main data-scope
    /p
}

@contact-edit () { # [cid]
    local cid=${1:-0} contact

    local tid; get-hx-tid
    if [[ $tid == ContactEdit-saveBtn ]]; then
        cid=$val_cid
        Contact/find "$cid"; contact=$RESULT
        msg "$contact" update \
            ${val_email+email="$val_email"} \
            ${val_first_name+first="$val_first_name"} \
            ${val_last_name+last="$val_last_name"} \
            ${val_phone+phone="$val_phone"} 

        if msg "$contact" save; then
            flash msg="Updated Contact!"
            @main "ContactsTable-viewLink-$cid"
            return
        fi
    elif [[ $tid == ContactEdit-deleteBtn ]]; then
        cid=$val_cid
        Contact/find "$cid"; contact=$RESULT
        msg "$contact" delete
        flash msg="Deleted Contact!"
        @main; return
    fi

    if [[ ! ${contact:-} ]]; then
        Contact/find "$cid"; contact=$RESULT
    fi
    msg "$contact" get id email first= last= phone= errors

    local id=$RESULT email=${RESULT[1]} first=${RESULT[2]} last=${RESULT[3]} phone=${RESULT[4]}
    local -n errors=${RESULT[5]}

    div/ id=${FUNCNAME#@} data-scope
        fieldset/ 
            legend/ ="Contact Values"
            div/ class="table rows"
                p/

                    label/ for="email" ="Email"
                    input/ name="email" id="email" type="email" placeholder="Email" value="$email" \
                           hx-trigger="@validate-contact-email" ws-send
                    span/ id="email-error" class="error" ="${errors[email]:-}"
                /p
                p/
                    label/ for="first_name" ="First Name"
                    input/ name="first_name" id="first_name" type="text" placeholder="First Name" value="$first"
                    span/ class="error" ="${errors[first]:-}"
                /p
                p/
                    label/ for="last_name" ="Last Name"
                    input/ name="last_name" id="last_name" type="text" placeholder="Last Name" value="$last"
                    span/ class="error" ="${errors[last]:-}"
                /p
                p/
                    label/ for="phone" ="Phone"
                    input/ name="phone" id="phone" type="text" placeholder="Phone" value="$phone"
                    span/ class="error" ="${errors[phone]:-}"
                /p
            /div
            input/ type=hidden name=cid value="$cid"
            button label="Save" id="ContactEdit-saveBtn"
        /fieldset

        script/ ="
            const email_input = document.getElementById('email');
            email_input.addEventListener('keyup',
                debounce(function() {
                    if (email_input.dataset['value'] !== email_input.value) {
                        htmx.trigger(email_input, '@validate-contact-email');
                    }
                    email_input.dataset['value'] = email_input.value;
                }, 200)
            );
        "

        button label="Delete Contact" id="ContactEdit-deleteBtn" \
            hx-on::ws-before-send="
                if (!confirm('Are you sure you want to delete this contact?'))
                    event.preventDefault();
            " \
            data-render=$FUNCNAME
        sp
        a/ href="#" ="Back" ws-send data-render=main data-scope
    /div
}

@validate-contact-email () {
    local cid=${1:-${val_cid:-}}
    Contact/find "$cid"; local -n contact=$RESULT

    local orig_email=${contact[email]}
    contact[email]=${val_email:-}
    msg "$contact" validate || true
    contact[email]=$orig_email
    # ^^^ Fixes the bug similar to - https://github.com/bigskysoftware/contact-app/issues/20

    msg "$contact" get errors
    local -n errors=$RESULT
    span/ id="email-error" class="error" ="${errors[email]:-}"
}


@contact-new () {
    local contact tid; get-hx-tid
    if [[ $tid == ContactNew-saveBtn ]]; then
        Contact contact \
            email="$val_email"      \
            first="$val_first_name" \
            last="$val_last_name"   \
            phone="$val_phone"

        if msg $contact save; then
            flash msg="Created New Contact!"
            @main; return
        else
            msg $contact get errors
            local -n errors=$RESULT
        fi
    else
        local -A errors=()
    fi

    div/ id=${FUNCNAME#@} data-scope
        fieldset/
            legend/ ="Contact Values"
            div/ class="table rows"
                p/
                    label/ for="email" ="Email"
                    input/ name="email" id="email" type="email" placeholder="Email"
                    span/ id="email-error" class="error" ="${errors[email]:-}"
                /p
                p/
                    label/ for="first_name" ="First Name"
                    input/ name="first_name" id="first_name" type="text" placeholder="First Name"
                    span/ class="error" ="${errors[first]:-}"
                /p
                p/
                    label/ for="last_name" ="Last Name"
                    input/ name="last_name" id="last_name" type="text" placeholder="Last Name"
                    span/ class="error" ="${errors[last]:-}"
                /p
                p/
                    label/ for="phone" ="Phone"
                    input/ name="phone" id="phone" type="text" placeholder="Phone"
                    span/ class="error" ="${errors[phone]:-}"
                /p
            /div
            button label="Save" id="ContactNew-saveBtn"
        /fieldset
        p/
            a/ href="#" ="Back" ws-send data-render=main data-scope
        /p
    /div

    if [[ ${contact:-} ]]; then
        msg $contact delete  # because the save must have failed.
    fi
}

@archive-ui () {
    Archiver/get; local archiver=$RESULT
    local tid; get-hx-tid
    if [[ $tid == Archiver-downloadBtn ]]; then
        msg $archiver run &

    elif [[ $tid == Archiver-clearBtn ]]; then
        msg $archiver reset
    fi

    div/ id="archive-ui" data-scope
        msg $archiver status; local status=$RESULT

        if [[ $status == Waiting ]]; then
            button id="Archiver-downloadBtn" label="Download Contact Archive"

        elif [[ $status == Running ]]; then
            div/ hx-trigger="@archive-ui" ws-send id="progress-div"
                text "Creating Archive..."
                div/ class="progress"; msg $archiver progress
                    div/ id="archive-progress" class="progress-bar" style="width: ${RESULT}%"; /div
                /div
            /div

        elif [[ $status == Complete ]]; then
            msg $archiver archive-file 
            generate-download-script cgi-bin "$RESULT" archive.json
            BGT_EXIT_CMDS+=("rm -f $(printf %q "$PWD/cgi-bin/$RESULT")")
            a/ href="/$RESULT" ="Archive Downloading! Click here if the download does not start" \
               target=_blank  _="on load click() me"
            button id="Archiver-clearBtn" label="Clear Download"
        fi
    /div
}


#BGT_TRACE_FILE=./x.out
baguette

