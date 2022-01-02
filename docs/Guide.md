0. Clone the repo and make sure you have the required dependencies installed and in `PATH`.
1. Add the `baguette` repo directory to `PATH`.
2. Save the following single file app as `myapp`:
```bash
#!/usr/bin/env bash
#
set -e

source baguette.sh

@main () {
    main/ id=main data-scope
        textfield name=name label="Your name:" placeholder="First Last" ws-send=no
        button label=Submit

        local label
        for label in one two three; do
            checkbox =${label^}  name=$label value=${label^}
        done

        h1/ class=greeting ="Hello ${val_name:-World}"
        markdown "This is a geeting from **Baguette**!"

        local checked=(${val_one:-} ${val_two:-} ${val_three})
        p/ ="You checked: ${checked[*]}"
    /main
}

baguette
```
3. Run it:
```bash
ubuntu@b3905ccfd545:~/work/baguette$ chmod +x ./myapp
ubuntu@b3905ccfd545:~/work/baguette$ ./myapp
websocketd --address 0.0.0.0 --port 8080 --staticdir /home/ubuntu/work/baguette/public --cgidir /home/ubuntu/work/baguette/cgi-bin --passenv PATH,BGT_HOME,WSD_ADDR,WSD_PORT,WSD_SCRIPT_DIR,WSD_PUBLIC_DIR /home/ubuntu/work/baguette/myapp

You can access the Baguette app at http://127.0.0.1:8080/index.html

Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving using application   : /home/ubuntu/work/baguette/myapp 
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving static content from : /home/ubuntu/work/baguette/public
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving CGI scripts from    : /home/ubuntu/work/baguette/cgi-bin
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Starting WebSocket server   : ws://0.0.0.0:8080/
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving CGI or static files : http://0.0.0.0:8080/
```
4. Visit the URL to see the app. You can use the browser's inspector / dev tool to see the HTML your app returned.
   You should also switch to the websocket section of the browser's dev tool and see what's sent and received over
   the websocket when you interact with the app.


## How a Baguette app works

When you run `myapp`, it starts `websocketd` configured to serve your app over websockets.
The entrypoint to your app is actually served by [a CGI script](../cgi-bin/index.html)
that renders the template `index.html` file provided by your app. In this case, the
app is only a single file, so it falls back to the default [index.html](../index.html) in Baguette.

The HTML returned by the CGI script, once loaded, causes the browser to establish a
new websocket connection between a new process of your app on the server and the
browser. The `@main` render function is called after the connection in order to return
the HTML that represents the app.

User interactions with HTML elements marked with `ws-send` could trigger an event
that is sent, through the connection, to the application process, and invokes
a render function, which will send some HTML response back and updates the page.

In order to control what `input` `value`'s get sent to the app process, as well as,
which render function to call on the server when such send-back is triggered,
Baguette follows the following rules:

  - From the triggering element, the closest ancestor element with an `id` and
    a `data-scope` attribute establishes the boundary within which all `input`'s
    and `button`'s with the `name` attributes will be included for their `value`'s
    to be sent back. Additionally, any `data-*` attributes on the triggering
    element will also be included, and if the name of the triggering event
    starts with `@`, then the event's `detail` object will also be included.

  - The render function to call is, by default, the function named after the `id`
    of such ancestor element; however, it can be overridden by the value of the
    `data-scope` attribute specified on the same element, or, it can be overridden
    by the triggering element's `data-render` attribute, and lastly, it can be
    overridden by the `render` attribute of the triggering event's `detail` object.

For the exact logic, you can check out the code [here](../public/baguette.js).

It's probably easier to go through a few examples to see how it works. Given:
```bash
div/ id=A data-scope   # establishes the value include scope
    input/ name=key1 value=value1
    div/
        input/ name=key2 value=value2
    /div
    div/ ="Click me" ws-send
/div
```
When the user clicks on the `div` (`Click me`), because the default `hx-trigger`
is the `click` event for `div`'s, and because the element is marked with `ws-send`,
htmx will trigger the event and send some JSON data over websocket to our app
on the server. Besides some htmx headers that are always included in the JSON,
what's also included is determined by `hx-include` and `hx-vals`, which Baguette
sets up to behave according to the rules described above. So, in this case,
both `input`'s `value`'s will be included, and the render function to be
called is `@A`.


## Rules to follow when writing a Baguette app:

- Don't use the `hx-include` or `hx-vals` attributes on your elements since
  Baguette relies on both to work, unless you know what you are doing.

- Don't output to `STDOUT` either directly or indirectly from your app.
  `STDOUT` is reserved for HTML responses from your app.

- Don't output to `STDERR` either directly or indirectly unless it's really
  an error. By default, Baguette, shows any errors written to `STDERR` at the
  top of your app if `BGT_ENV` is not `prod`. This can be disabled by setting
  `BGT_FLASH_STDERR` to empty.

  - Use the HTML tag functions like `div/` (opening tag) and `/div` (closing tag)
    to generate the HTML response. Attributes can be set on a tag via the
    `name=value` arguments to the opening tag function. E.g., `input/ type=text name=age value=42`

- Don't navigate away from the page. Doing so will disconnect the page from the app
  process, causing it to be terminated, and lose all the application states. For
  example, when generating an anchor element, it should either be marked with
  `ws-send`, or, it should have `target=_blank`.

- A render function should output one or more complete HTML elements that have
  the `id` attributes. htmx will replace the elements in the page with the
  returned elements that have matching `id`'s. This is simply how htmx's websocket 
  extension works. If you expect your element to be swapped but it's not, check
  if it has an id and it's not returned as a child of another element.
