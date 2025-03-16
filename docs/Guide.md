## Quickstart

1. Clone the repo and make sure you have the required dependencies installed and in `PATH`.
2. Add the `baguette` repo directory to `PATH`.
3. Save the following single file app as `myapp`:
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
4. Run it:
```bash
$ chmod +x ./myapp
$ ./myapp
websocketd --address 0.0.0.0 --port 8080 --staticdir /home/ubuntu/work/baguette/public --cgidir /home/ubuntu/work/baguette/cgi-bin --passenv PATH,BGT_HOME,WSD_ADDR,WSD_PORT,WSD_SCRIPT_DIR,WSD_PUBLIC_DIR /home/ubuntu/work/baguette/myapp

You can access the Baguette app at http://127.0.0.1:8080/index.html

Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving using application   : /home/ubuntu/work/baguette/myapp 
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving static content from : /home/ubuntu/work/baguette/public
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving CGI scripts from    : /home/ubuntu/work/baguette/cgi-bin
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Starting WebSocket server   : ws://0.0.0.0:8080/
Wed, 12 Feb 2025 23:17:45 +0000 | INFO   | server     |  | Serving CGI or static files : http://0.0.0.0:8080/
```
5. Visit the URL to see the app. You can use the browser's inspector / dev tool to see the HTML your app returned.
   You should also switch to the websocket section of the browser's dev tool and see what's sent and received over
   the websocket when you interact with the app.


## How a Baguette app works

When you run `myapp`, it starts `websocketd` configured to serve your app over websockets.
The entrypoint to your app is actually served by [a CGI script](../cgi-bin/index.html)
that renders the template `index.html` file provided by your app. In this case, the
app is only a single file, so it falls back to the default [index.html](../index.html) in Baguette.

The HTML returned by the CGI script, once loaded, causes the browser to establish a
new websocket connection between a new process of your app on the server and the
browser. The `@main` *render function* is called after the connection in order to return
the HTML that represents the app.

User interactions with HTML elements marked with `ws-send` attribute could trigger
an event that is sent, through the connection, to the application process, and invokes
a *render function*, which will send some HTML response back and updates the page.
Such update is done via htmx's [OOB swap](https://htmx.org/attributes/hx-swap-oob/).

In order to control what `input` `value`'s get sent to the app process, as well as,
which *render function* to call on the server when such send-back is triggered,
Baguette follows the following rules:

  - From the triggering element, the closest ancestor element with an `id` *and*
    a `data-scope` attribute establishes the boundary within which all `input`'s
    and `button`'s with the `name` attributes will be included for their `value`'s
    to be sent back. Additionally, any `data-*` attributes on the triggering
    element will also be included, and if the name of the triggering event
    starts with `@`, then the event's `detail` object will also be included.

  - The *render function* to call is, by default, the function named after the `id`
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
When the user clicks on the `div` (`Click me`), because the default [hx-trigger]
is the `click` event for `div`'s, and because the element is marked with `ws-send`,
htmx will trigger the event and send some JSON data over the websocket connection
to our app on the server, and besides some htmx headers that are always included
in the JSON, what's also included is determined by `hx-include` and `hx-vals`,
which Baguette sets up to behave according to the rules described above. So, in
this case, both `input`'s `value`'s will be included, and the *render function* to be
called is `@A`.

[hx-trigger]: https://htmx.org/attributes/hx-trigger/
[hx-include]: https://htmx.org/attributes/hx-include/
[hx-vals]: https://htmx.org/attributes/hx-vals/


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
- Don't use the `${...?...}` form of parameter expansions (e.g., `${var?}` or
  `${var:?}`) in order to preserve stack traces.
- A *render function* should output zero or more complete HTML elements that have
  the `id` attributes. htmx will replace the elements in the page with the
  returned elements that have matching `id`'s. This is simply how htmx's [websocket 
  extension] works. If you expect your element to be swapped but it's not, check
  if it has an id and it's not returned as a child of another element.

[websocket extension]: https://v1.htmx.org/extensions/web-sockets/


## Introduction to Bos

[Bos] is a single-source-file library implemented in Bash to facilitate
Object-Oriented Programming. An object in [Bos] is simply a dynamically allocated
Bash associative array, where its object ID (`oid`) is stored as the `0`-th
element (i.e., with `0` as the key). Several functions are provided by [Bos]
for working with objects. Let's take a look at an example:

[Bos]: ../lib/bos.sh

```bash

# Use 'class' to declare a class. E.g.,
class Person
```

Above registers 'Person' as a class in Bos and also generates a function
named after the class for creating object instances of the class. E.g., a
person object can be created with:
```bash

declare p1
Person p1 name="John Doe"
```

This creates a `Person` object with a `name` attribute set to "John Doe", and assigns
its `oid` to the variable, `p1`.

When you instantiate an object using a class, Bos sends the `init` message to the
object, passing it the remaining arguments (`name="John Doe"`, in this case) that
come after the variable name (`p1`).

Methods of a class are defined with a prefix that is the name of its class, like this:
```bash

Person/init () {  # first_name=... last_name=... gender=<M|F> birth_date=<yyyy-mm-dd>

    # Call the default init (Object/init) to assign named arguments as object attributes.
    msg $self ../init "$@"

    # 'self' is also the associative array representing the object's state
    # So, within a method, you can use it to set and get the object's attributes.

    # Validate object attributes
    [[ ${self[first_name]:-} ]] || err-return
    [[ ${self[last_name]:-} ]] || err-return
    [[ ${self[gender]:-} == @(M|F) ]] || err-return

    local d='[0-9]'; local date_regex="$d$d$d$d-$d$d-$d$d"
    [[ ${self[birth_date]:-} =~ ^$date_regex$ ]] || err-return
    date -d "${self[birth_date]:-}" >/dev/null || err-return
    msg $self age || err-return
}
```
Within a method, the `self` variable is automatically available, and it expands
to the `oid` of the object receiving the message. Here we use the `msg` function
to send a message to the object itself. `$1` is the receiver, and the rest of the
arguments will become the arguments to the method identified by the message.

When using the `msg` function, the `../` prefix to a message name causes the
message resolution to start from the *parent* class of the object instead.

`Object` is the root of all classes in [Bos], and its `init` method simply assigns
its named arguments (in the form of `name=value`) as the object's attributes. So,
here we are actually calling the `Object/init` method to assign attributes from
the named arguments passed during the object's creation (i.e., when `Person` is
called).

```bash

Person/name () {
    # In Bos, the convention is to return a value by setting the RESULT global
    # variable. To return multiple values, you can set it to an array.
    RESULT="${self[first_name]} ${self[last_name]}"
}

Person/age () {
    local today; today=$(date +%Y-%m-%d) || err-return
    local year_now=${today%%-*} year_then=${self[birth_date]%%-*}
    local age=$(( year_now - year_then ))
    [[ $age -ge 0 ]] || err-return

    local d1=${today#*-} d2=${self[birth_date]#*-}
    local d=$( (echo $d1; echo $d2) | sort -V | head -n1)
    if [[ $age -gt 0 ]]; then
        if [[ $d != "$d2" ]]; then (( age-- )); fi
    fi

    RESULT=$age
}

Test-Person () {
    local p1
    Person p1 \
        first_name=John \
        last_name=Doe   \
        gender=M \
        birth_date=2001-03-21

    msg $p1 name; local p1_name=$RESULT
    msg $p1 age; local p1_age=$RESULT

    echo "The person is the $p1_age year-old '$p1_name'"

    # Free the allocated object; $p1 would be unset after this.
    msg $p1 delete
}

Test-Person
```
