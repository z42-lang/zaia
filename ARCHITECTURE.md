# zaia — architecture

**zaia** is a full-stack framework for the [z42](https://github.com/z42-lang/z42)
language: build an application's **server**, its **web client**, and the code
they **share** in one language, one repo, one mental model.

It has two jobs, and they check each other:

1. **Build the z42 site and playground.** Those are the framework's first real
   users, and nothing goes in that they do not need.
2. **Find out what z42 cannot do yet.** A framework leans on generics,
   interfaces, delegates and cross-package types harder than any test suite
   does. Everything it hits is recorded in
   [docs/design/language-surface.md](docs/design/language-surface.md) — fourteen
   findings so far, three of which changed a design.

> **Status: seams first.** Every interface below compiles and every example runs
> today. Two bodies are deliberately incomplete and say so: `Renderer.Update`
> rebuilds rather than diffs, and `DomBackend` calls VM builtins that do not
> exist yet.

## Design goals

1. **One language across the stack.** The same z42 type flows from the server to
   the browser. No hand-maintained TypeScript mirror of a server DTO.
2. **A URL means one thing.** The server and the client resolve routes from the
   *same table*, so a server-rendered page and its client takeover cannot drift.
3. **Backend-agnostic rendering.** Components render to a seam, never to the DOM.
   The same component tree drives the browser, server-side HTML, and a test.
4. **Built on the z42 standard library.** The server is a thin layer over
   `Std.Net.Http`; serialization is `Std.Json`. zaia adds structure, not a
   parallel runtime.

## Layers

```
   CLIENT                                    SHARED                SERVER

  ┌──────────────────┐                  ┌──────────────┐      ┌──────────────┐
  │     zaia.ui      │ describe         │  zaia.core   │      │ zaia.server  │
  │ Component·VNode  │                  │ RoutePattern │◄─────┤ WebApp       │
  │ H·State          │                  │ Result       │      │ RequestContext│
  │ UiDispatch       │                  │ ServiceContainer│   │ IMiddleware  │
  └────────┬─────────┘                  └──────┬───────┘      └──────┬───────┘
           │                                   │                     │
  ┌────────▼─────────┐                  ┌──────▼───────┐             │
  │  zaia.renderer   │ render           │ zaia.shared  │             │
  │ IRenderBackend ◄─┼── the seam       │ PageTable    │─────────────┘
  │ Renderer         │                  │ ApiContract  │   the server renders
  │ HtmlBackend      │──── SSR          │ ApiClient    │   from the same table
  └────────┬─────────┘                  └──────┬───────┘
           │                                   │
  ┌────────▼─────────┐                  ┌──────▼───────┐
  │    zaia.web      │ wasm             │  zaia.app    │ assemble
  │ DomBackend       │─── __dom_*       │ App·Router   │
  └──────────────────┘                  └──────────────┘
```

| Package | Runs on | Depends on | Public seams |
|---------|---------|-----------|--------------|
| `zaia.core` | any | — | `RoutePattern`/`RouteMatch` · `Result<T>` · `ServiceContainer` · `HttpVerb` |
| `zaia.ui` | any | — | `Component` · `VNode`/`VEvent` · `H` · `State<T>` · `UiDispatch`/`IChangeListener` |
| `zaia.renderer` | any | `zaia.ui` | **`IRenderBackend`** · `Renderer` · `HtmlBackend` |
| `zaia.web` | wasm | `zaia.renderer` | `DomBackend` · `DomNative` (the frozen VM contract) |
| `zaia.server` | native | `zaia.core` | `WebApp` · `RequestContext` · `IMiddleware` · `Endpoint` |
| `zaia.shared` | any | `zaia.core`, `zaia.ui` | **`PageTable`**/`IPageFactory` · `ApiContract` · `ApiClient` |
| `zaia.app` | wasm / any | core, ui, renderer, web, shared | `App` · `Router` · `ILocation` |

## The two seams that matter

Everything else is plumbing. These two carry the design.

### `IRenderBackend` — one tree, three hosts

Eleven imperative operations that a diff can target. Not the DOM API, not a
rendering API: create a node, set an attribute, append a child, bind an event.

`Component`, `H`, `VNode` and `Renderer` are written against those eleven
operations and nothing else, so **a new host is a new implementation of one
file**. Three exist or are planned:

- `HtmlBackend` (`zaia.renderer`) — an in-memory tree serialized to HTML. This
  is server-side rendering, and it is also the seam's proof: a complete backend
  with no browser, no DOM and no event loop.
- `DomBackend` (`zaia.web`) — the real browser DOM.
- a test backend — records the op stream for assertions.

Node handles are opaque `int`s, never host objects. That is what keeps the
contract at eleven functions instead of a DOM binding.

### `PageTable` — a URL means one thing

```z42
PageTable pages = new PageTable()
    .Add("/",            new HomeFactory())
    .Add("/docs/{slug}", new DocFactory(store));
```

The server resolves an incoming request against this table and renders the
component to HTML. The browser resolves a history entry against **the same
table** and mounts the component. One declaration, two consumers, no way to
drift — which is what makes hydration a *takeover* rather than a second
implementation kept in sync by hand.

`example-isomorphic` asserts exactly this: it renders every route through both
paths and compares the HTML byte for byte.

## The client is three layers: describe → render → assemble

Split by one question — *whose job is this?*

- **`zaia.ui` — describe.** `Component.Render()` returns a `VNode` tree;
  `State<T>` announces changes. This layer has no renderer, no DOM, and no idea
  what happens when data changes.
- **`zaia.renderer` — render.** Takes a tree, materializes it through an
  `IRenderBackend`. It renders; it does not assemble or react.
- **`zaia.app` — assemble.** The composition root, and the only place that knows
  all three. `App.Mount` picks a backend, subscribes to `UiDispatch`, and owns
  lifetime.

The seam between *describe* and *assemble* is `IChangeListener`, a **nominal
interface rather than a delegate**, for two reasons: it keeps `zaia.ui` from
ever importing a renderer, and a named type crosses a zpkg boundary more
cleanly than a delegate value. (`IMiddleware` and `IPageFactory` are nominal for
the same reason.)

## Server — the shape

A thin layer over `Std.Net.Http.HttpServer.ServeWithPool`:

```z42
void Main() {
    WebApp app = WebApp.Create();
    app.Services.Register<Greeter>(new Greeter("Hello"));
    app.Use(new LoggerMiddleware());

    app.MapGet("/health", (RequestContext c) => { c.Text(200, "ok"); });
    app.MapGet("/hello/{name}", (RequestContext c) => {
        Greeter g = (Greeter)c.Services.Resolve<Greeter>();
        c.Text(200, g.Greet(c.Route("name")));
    });

    app.Run("127.0.0.1", 8080);
}
```

Two shapes here are forced by the language, not chosen:

- **Handlers answer imperatively** (`c.Text(...)`) instead of returning a
  response, because z42 does not infer a return type through a block lambda, so
  a response-returning handler would not type-check at the call site.
- **`Resolve<T>` needs a cast**, because a generic method's return type is not
  substituted across a package boundary yet
  ([#7](docs/design/language-surface.md)).

Both are the single most visible warts in the API, and both disappear without a
source change when the language closes the gap.

**Threading.** Handlers run on a worker pool concurrently. There is no async
story because z42 has no `async`/`await` until 0.8.x; a worker pool over
blocking handlers is the honest shape until then.

## Client — the shape

```z42
class Counter : Component {
    private State<int> _count = new State<int>(0);

    public override VNode Render() {
        return H.Div(
            H.H1(H.Text("Count: " + this._count.Get().ToString())),
            H.Button(H.Text("+")).OnClick(() => this._count.Set(this._count.Get() + 1))
        );
    }
}

void Main() { App.Mount("#app", new Counter()); }              // browser
```

The same component, server-rendered, today:

```z42
HtmlBackend b = new HtmlBackend();
new Renderer(b).Mount("#app", new Counter().Render());
Console.WriteLine(b.ToHtml());
// <div><h1>Count: 0</h1><button>+</button></div>
```

## What is not done

Stated plainly, because the seams are frozen and the bodies are not:

| | Status | Blocked on |
|---|---|---|
| `Renderer.Update` | **Rebuilds**, does not diff. Correct, but drops focus and scroll. | Nothing — it is work. `VNode.Key` already carries the identity a keyed diff needs. |
| Hydration | `Router` remounts rather than adopting the server's DOM. | Same work as keyed diffing. |
| `DomBackend` | Compiles; every call throws. | `__dom_*` VM builtins — see [docs/design/dom-interop.md](docs/design/dom-interop.md). |
| `ILocation` in a browser | Only `MemoryLocation` exists. | `__history_*` builtins. |
| `ApiClient` in a browser | Native only — it uses sockets. | A `fetch` builtin contract. |

Nothing above the backends changes when any of these land. That is the point of
the seams, and it is why they were settled first.

## Repo layout

```
zaia/
├── ARCHITECTURE.md          ← this file
├── docs/
│   ├── design/
│   │   ├── dom-interop.md        the VM contract zaia.web depends on
│   │   └── language-surface.md   what z42 could not do, and what it cost
│   ├── workflow/build.md         how to build and run (read before building)
│   └── roadmap.md
├── src/                     ← the z42 workspace; members are direct children
│   ├── z42.workspace.toml
│   ├── zaia.core/  zaia.ui/  zaia.renderer/  zaia.web/
│   ├── zaia.server/  zaia.shared/  zaia.app/
│   ├── example-counter-ssr/      component → HTML, no browser
│   ├── example-hello-server/     WebApp: routing, DI, middleware, SSR
│   └── example-isomorphic/       one PageTable, both ends, compared
└── scripts/build.sh
```

The flat layout under `src/` is a toolchain constraint, not a preference:
z42c's workspace discovery only globs direct children
([#9](docs/design/language-surface.md)).

## Build

```sh
./scripts/build.sh              # clean --release --no-incremental, then run the examples
```

Read [docs/workflow/build.md](docs/workflow/build.md) before building by hand —
three separate toolchain gotchas make a naive `z42c build --workspace` fail in
ways that look like source errors.
