function new_list_prompt(evt) {
    let value;
    while (true) {
        value = window.prompt("Create a list");
        if (value === null) break;     // user cancelled
        if (value=value.trim()) break; // non-empty string
    }
    if (!value) { // value === undefined, i.e., user cancelled
        evt.preventDefault();
    } else {
        evt.detail.parameters["name"] = value;
    }
}

htmx.onLoad(function(elt) {
    /** Make each todo list item draggable for reordering. */
    var todo_list;
    if (elt.id === "main") {  // the initial swap that contains the rendered todo-list
        todo_list = elt.querySelector("#todo-list");
    } else if (elt.id === "todo-list") {
        todo_list = elt;
    }
    if (todo_list) {
        var sortable = new Sortable(todo_list, {
            animation: 150,
            handle: ".TodoItem-dragHandle",
            forceFallback: true,
            onEnd: function (evt) {
                if (evt.newIndex === evt.oldIndex) return;
                //console.log(`old=${evt.oldIndex} new=${evt.newIndex} length=${todo_list.children.length}`);
                const is_last = evt.newIndex === todo_list.children.length - 1;
                htmx.trigger("#todo-list", "@handle-item-reordering", {
                    movedItem: todo_list.children[evt.newIndex].id,
                    beforeItem: is_last ? "" : todo_list.children[evt.newIndex + 1].id,
                    afterItem: is_last ? todo_list.children[evt.newIndex - 1].id : "",
                });
            }
        });
    }

    /** Handle keyboard events for editing the todo-list */
    function addTodoItemListener(item) {
        const item_text = item.querySelector(".TodoItem-text");

        /** Make each todo item trigger an update event on focus out */
        item.addEventListener("focusout", function () {
            if (item.dataset.text !== item_text.textContent) {
                item.dataset.text = item_text.textContent;
                htmx.trigger(item, "@handle-item-text-update");
            }
        });

        item_text.addEventListener("keydown", function (evt) {
            if (evt.key === "Enter") {
                evt.preventDefault();
                item_text.blur();
                htmx.trigger(item, "@handle-new-item-insert");

            } else if (evt.key === "ArrowUp") {
                item.previousElementSibling?.querySelector(".TodoItem-text").focus();

            } else if (evt.key === "ArrowDown") {
                item.nextElementSibling?.querySelector(".TodoItem-text").focus();
            }
        });
    }
    if (todo_list) {
        todo_list.querySelector(".TodoList-title").addEventListener("focusout", function () {
            if (todo_list.dataset.title !== this.textContent) {
                if (!this.textContent) {
                    this.textContent = this.title;
                } else {
                    todo_list.dataset.title = this.textContent;
                    htmx.trigger(todo_list, "@handle-todo-list-title-update");
                }
            }
        });
        var todo_items = todo_list.querySelectorAll(".TodoItem");
        for (var i=0; i < todo_items.length; i++) {
            addTodoItemListener(todo_items[i]);
        }
    } else if (elt.classList.contains("TodoItem")) {
        addTodoItemListener(elt);
    }

    /** Handle todo-list creation on the client side. I.e., prompting for the name of the list. */
    const new_list_link = document.getElementById("new-list-link");
    if (new_list_link) {
        new_list_link.removeEventListener("htmx:wsConfigSend", new_list_prompt);
        new_list_link.addEventListener("htmx:wsConfigSend", new_list_prompt);
    }
    // NOTE: We can't use hx-prompt due to the bug: https://github.com/bigskysoftware/htmx/issues/2470

});



