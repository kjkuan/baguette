## Baguette

Baguette is a Bash server-side web framework geared towards internal tooling,
or, for making reactive web forms with shell scripts. It's developed on top of
[htmx] and uses [websocketd] for browser and server app communication.

It is still a work in progress, and some knowledge of [htmx] is required to use
it effectively; however, any feedback, ideas, or contributions are welcomed.
Please take a look at the issues page if you'd like to participate in its development.

> **NOTE:** While it's possible to build a public-facing "web app" with
> Baguette, its main use case is for building reactive form-based UIs to
> existing tools / commands that are meant for internal consumptions within a
> secure private network.

[htmx]: https://htmx.org
[websocketd]: https://github.com/joewalnes/websocketd


## Features

- Websocket makes it easy to write stateful and reactive web applications.
- Built-in support for OOP and modeling via [Bos](lib/bos.sh).
- Built-in UI widgets / components (Experimental).
- Error reporting (when `set -e` is used) with stack traces to help with app development.


## Limitations

- A Baguette app is not RESTful; it exposes no HTTP endpoints, so you can't,
  for example, bookmark the state of your app via an URL, and you can't interact
  with it via HTTP requests (you can use CGI, but then it's a separate process).

- It's slow and not scalable to high number of users. Though, depends on your use
  case, it might be fast enough; or, it might be good for prototyping.


## Sample Baguette App

Here's what a simple, single-page app in Baguette looks like:

```bash
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
```

Please see [Guide](docs/Guide.md) for a getting-started guide.


## Dependencies

- [websocketd](https://github.com/matvore/websocketd) (this is a fork that fixed the issue with `--passenv` for CGI scripts)
- [htmx] (>= 2.0)
- [jq](https://github.com/jqlang/jq)
- GNU Coreutils
- Bash (>= 4.3; preferably >= 5)

You can take a look at [the examples](examples) to get an idea on what a
Baguette app looks like. Currently, a [Dockerfile](Dockerfile) is provided for building
an image with the dependencies needed to run the examples.

```Bash
$ cd baguette
$ docker build -t localhost/baguette .

$ d=/home/baguette/baguette image=localhost/baguette
$ opts=(--rm -v "$PWD:${d:?}" -e WSD_PORT=5000 -p 5000:5000)

# Pick one to try: (ctrl-c to exit)
$ docker run "${opts[@]}" -w "$d/examples/todo-app" $image ./main.sh
$ docker run "${opts[@]}" -w "$d/examples/markdown-app" $image ./main.sh
$ docker run "${opts[@]}" -w "$d/examples/contact-app" $image ./main.sh
$ docker run "${opts[@]}" -w "$d/examples/wiki-app" $image ./main.sh

# NOTE: The path to /index.html is required for the URL of these apps.
```


## Other similar projects:

- [Streamlit](https://github.com/streamlit/streamlit) (original inspiration)
- [PyWebIO](https://github.com/pywebio/PyWebIO)
- [Reflex](https://reflex.dev)
