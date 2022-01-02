# A file upload widget.
#
# Input attributes:
#
#   id      - An unique id for the widget; required.
#
#   label=  - The text label for the file-upload widget. Default is empty, meaning no labels.
#
# The selected file is uploaded to the server immediately. The val_$id variable will contain
# the base64 encoded string value of the uploaded file. A few other vals containing metadata
# for the file will also be set:
#
#   val_${id}_filename   - name of the file selected by the user.
#   val_${id}_filesize   - size (in bytes) of the file selected by the user.
#
# NOTE: Only single file selection is supported; however, one can dynamically
#       add more instances of this widget in order for the user to upload more
#       files.
#
# NOTE: Currently, this widget base64 encode the file and keep it in-memory;
#       therefore, the upload performance would be slow, and memory consumption
#       would be high, for large files.
#
# Example:
#
#  upload_file=
#  @handle-file-upload () {
#      if [[ ! -e $upload_file ]]; then
#          upload_file=$(mktemp) || err-return
#          trap 'rm -f "$upload_file"' EXIT
#      fi
#      if [[ $val_myfile_filename ]]; then
#          base64 -d <<<"$val_myfile_file" > "$upload_file" || err-return
#      fi
#      file-upload id='myfile' label="Upload" data-scope=$FUNCNAME
#  }
#
#
#
file-upload () {
    local -A attrs; args-to-attrs "$@" || err-return

    local id=${attrs[id]:-}; [[ $id ]] || err-return
    local name=${attrs[name]:-$id}

    [[ ! -v 'attrs[multiple]' ]] || err-return

    local label=${attrs[label]:-}
    unset attrs\[{id,name,label,type}\]

    local args=(); attrs-to-args || err-return

    local -n uploaded_filename=val_${id}_filename
    local -n uploaded_filesize=val_${id}_filesize
    local -n uploaded_filetype=val_${id}_filetype

    span/ id="w-$id" class="w-file-upload"
        if [[ $label ]]; then
            label/ for="$id" ="$label"
        fi
        input/ id="$id" name="$name" type=file "${args[@]}" \
               hx-on:change="upload_file(event)" \
               hx-trigger='@file-ready' ws-send \
               hx-indicator="#$id-indicator"

        img/ id="$id-indicator" class=htmx-indicator src=/images/upload.gif \
             alt="Uploading ..." width=16 height=16

        if [[ ${uploaded_filename:-} ]]; then
            small/
                text "Uploaded: $uploaded_filename (approx. $(( (uploaded_filesize+1023)/1024 ))Kb)"
            /small
            input/ name="${id}_filename" type=hidden value=$uploaded_filename
            input/ name="${id}_filesize" type=hidden value=$uploaded_filesize
            input/ name="${id}_filetype" type=hidden value=$uploaded_filetype
        fi
    /span
}
