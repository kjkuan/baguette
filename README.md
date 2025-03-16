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


## Dependencies

- [websocketd](https://github.com/matvore/websocketd) (this is a fork that fixed the issue with `--passenv` for CGI scripts)
- [htmx] (>= 2.0)
- [jq](https://github.com/jqlang/jq)
- GNU Coreutils
- Bash (>= 4.3; preferably >= 5)

You can take a look at [the examples](examples) to get an idea on what a
Baguette app looks like. Currently, a [Dockerfile](Dockerfile) is provided for building
an image with the dependencies needed to run the examples (replace `podman`
with `docker` if that's what you use):

```Bash
$ cd baguette
$ podman build -t baguette .

$ d=/home/baguette/baguette image=localhost/baguette
$ opts=(--rm --userns keep-id -v "$PWD:${d:?}" -e WSD_PORT=5000 -p 5000:5000)

# Pick one to try: (ctrl-c to exit)
$ podman run "${opts[@]}" -w "$d/examples/todo-app" $image ./main.sh
$ podman run "${opts[@]}" -w "$d/examples/markdown-app" $image ./main.sh
$ podman run "${opts[@]}" -w "$d/examples/contact-app" $image ./main.sh

# NOTE: The path to /index.html is required for the URL of these apps.
```


## Other similar projects:

- [Streamlit](https://github.com/streamlit/streamlit) (original inspiration)
- [PyWebIO](https://github.com/pywebio/PyWebIO)
- [Reflex](https://reflex.dev)
