/** Stolen from https://dev.to/yanagisawahidetoshi/boost-your-javascript-performance-with-the-debounce-technique-497i */
function debounce(func, wait) {
    let timeout;
    return function(...args) {
        const context = this;
        clearTimeout(timeout);
        timeout = setTimeout(
            () => { func.apply(context, args) },
            wait
        );
    }
}

/** Base64-encode the file loaded by the file input element along with some file metadata. */
async function upload_file(evt) {
    const elt = evt.target;
    const id = elt.id;
    const file = elt.files[0];
    const bytes = await file.bytes();
    const info = {}
    info[`${id}`] = bytes.toBase64();
    info[`${id}_filename`] = file.name;
    info[`${id}_filesize`] = file.size;
    info[`${id}_filetype`] = file.type;
    info['render'] = get_default_renderer(evt);
    htmx.addClass(htmx.find(`#${id}-indicator`), htmx.config.requestClass);
    htmx.trigger(elt, '@file-ready', info);
}

function get_default_renderer (evt) {
    const c = htmx.closest(evt.target, "[data-scope]");
    return c.dataset.scope || c.id;
}

htmx.onLoad(function (elt) {
    if (elt !== document.body) return;
    const body = document.body;
    body.setAttribute("hx-ext", "ws");
    if (!body.getAttribute("ws-connect")){
        body.setAttribute("ws-connect", "127.0.0.1:8080/");
    }
    body.setAttribute("hx-headers", "js:{'HX-Trigger-Event': event.type}");
    body.setAttribute("hx-include", "closest *[data-scope]");
    body.setAttribute("hx-vals", `js:{
        "render": get_default_renderer(event),
        ...event.target.dataset,
        ...(function () {
                if (event.type.startsWith("@")) {
                    let { elt: _, ...detail } = event.detail;
                    if (!detail.render)
                        detail.render = event.type;
                    return detail;
                }
           })(),

    }`);
    htmx.process(body);
});

// Prompt the user if navigating away from the page
window.onbeforeunload = function () { return true; }
