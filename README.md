# zaia

**A full-stack framework for the [z42](https://github.com/z42-lang/z42) language.**

Build an application's server, its web client, and the code they share in one
language — with one route table both ends resolve, and one component tree that
renders to HTML on the server and to the DOM in the browser.

```z42
// shared: a URL means one thing
PageTable pages = new PageTable()
    .Add("/",            new HomeFactory())
    .Add("/docs/{slug}", new DocFactory(store));

// server                                    // browser
PageMatch m = pages.Resolve(ctx.Path);        Router.Start(pages, "#app");
ctx.Html(200, Ssr.Render(m.Page));
```

```z42
// a component, rendered by either end
class Counter : Component {
    private State<int> _count = new State<int>(0);

    public override VNode Render() {
        return H.Div(
            H.H1(H.Text("Count: " + this._count.Get().ToString())),
            H.Button(H.Text("+")).OnClick(() => this._count.Set(this._count.Get() + 1))
        );
    }
}
```

## Status

**Seams first.** Every interface compiles and every example runs today; two
bodies are deliberately incomplete and say so in
[ARCHITECTURE.md](ARCHITECTURE.md#what-is-not-done) — the reconciler rebuilds
rather than diffs, and the browser backend waits on VM builtins that do not
exist yet.

The server half is real: routing, route captures, query strings, DI,
middleware and server-side rendering are verified against a live server.

## Build

```sh
./scripts/build.sh
```

Building by hand needs `rm -rf artifacts && z42c build --workspace --release
--no-incremental` — all three parts load-bearing, for reasons in
[docs/workflow/build.md](docs/workflow/build.md).

## Why it exists

Two jobs, which check each other:

1. **Build the z42 site and playground.** They are the framework's first users,
   and nothing goes in that they do not need.
2. **Find out what z42 cannot do yet.** A framework leans on generics,
   interfaces, delegates and cross-package types harder than a test suite does.
   Fourteen findings so far — three of which changed a design — are recorded in
   [docs/design/language-surface.md](docs/design/language-surface.md).

## Documentation

| | |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, the two seams that matter, what is not done |
| [docs/design/language-surface.md](docs/design/language-surface.md) | What z42 could not do, and what it cost |
| [docs/design/dom-interop.md](docs/design/dom-interop.md) | The VM contract the browser client needs |
| [docs/workflow/build.md](docs/workflow/build.md) | How to build, and why the flags |
| [docs/roadmap.md](docs/roadmap.md) | What is next, and the language work it pulls |

## License

[MIT](LICENSE)
