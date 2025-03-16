
/** Make the tree nodes draggable for moving. */
htmx.onLoad(function(elt) {
    let uls;
    if (elt.id === "main" ||
        elt.classList.contains("FE-FileFolder") ||
        elt.classList.contains("FE-Folder")
    ) {
        uls = elt.querySelectorAll("ul.FE-Folder");
        if (elt.id !== "main")
            uls = [elt, ...uls];

        for (var i=0; i < uls.length; i++) {
            let ul = uls[i];
            new Sortable(ul, {
                group: "fe-folder",
                animation: 150,
                fallbackOnBody: true,
                draggable: "li",
                sort: false,
                emptyInsertThreshold: 10,
                onRemove: function (evt) {
                    // console.log(`from-folder-id: ${evt.from.id}`);
                    // console.log(`from-item-id: ${evt.item.id}`);
                    // console.log(`to-item-id: ${evt.to.id ? evt.to.id : evt.to.parentElement.id}`);
                    evt.item.dataset.fromFolderId = evt.from.id;
                    evt.item.dataset.fromItemId = evt.item.id;
                    evt.item.dataset.toItemId = (evt.to.id ? evt.to.id : evt.to.parentElement.id);

                    htmx.trigger(evt.item, 'fe-handle-item-move');
                },
                /*
                onMove: function (evt) {
                    console.log(evt.related);
                    console.log(`willInsertAfter: ${evt.willInsertAfter}`);
                }
                */
            });
        }
    }
});

/** Syntax highlight code snippets in Markdown when viewed **/
htmx.onLoad(function(elt) {
    if (elt.id === "file-viewer") {
        let preview_elts = elt.querySelectorAll(".preview");
        if (preview_elts.length > 0) {
            hljs.highlightAll();
        }
    }
});

htmx.onLoad(function(elt) {
    if (elt.id === "main") {
        const fe_panel = document.getElementById("file-explorer-panel");
        const contextMenu = document.getElementById("fe-context-menu");
        fe_panel.addEventListener("contextmenu", (event) => {
            event.preventDefault();
            contextMenu.style.top = `${event.clientY}px`;
            contextMenu.style.left = `${event.clientX}px`;
            contextMenu.style.display = "block";
        });
        document.addEventListener("click", () => {
            contextMenu.style.display = "none";
        });
    }
});


function delete_selected_files() {
    let selected = document.querySelectorAll(".selected");
    if (selected.length) {
        let path_ids = [];
        selected.forEach((elt) => { path_ids.push(elt.id) });
        if (confirm("Delete the currently selected files?")) {
            htmx.trigger("#fe-context-menu", "@handle-file-deletes", {
                path_ids: path_ids
            });
        }
    }
}

function rename_selected_file() {
    let selected = document.querySelector(".selected > .FE-Label");
    if (selected) {
        let old_name = selected.textContent;
        const rename_event_trigger = function(evt) {
            selected.contentEditable = false;
            let new_name = evt.target.textContent;
            if (new_name !== old_name) {
                htmx.trigger("#fe-context-menu", "@handle-file-rename", {
                    path_id: selected.parentNode.id,
                    old_name: old_name,
                    new_name: new_name,
                });
            }
        };
        selected.removeEventListener('focusout', rename_event_trigger);
        selected.addEventListener('focusout', rename_event_trigger);
        selected.contentEditable = true;
        selected.focus();
    }
}

