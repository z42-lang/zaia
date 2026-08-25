# zaia — architecture

**zaia** is a full-stack framework for the [z42](https://z42-lang.github.io/) language:
build the **server**, the **web client**, and the **shared** code of an application in
one language, one repo, one mental model. Think *ASP.NET Core Minimal APIs + Blazor*,
reimagined for z42 — HTTP APIs and interactive web UIs, sharing models and route
contracts end-to-end.

Deeper design notes live in [`docs/`](docs/): [rendering](docs/rendering.md) ·
[app host](docs/app-host.md) · [DOM interop](docs/dom-interop.md).

## Design goals

1. **One language across the stack.** The same z42 types flow from database to server
   to browser. No serialization mismatch between a TypeScript client and a C# server.
2. **Minimal ceremony.** A server is `WebApp.Create().MapGet(...).Run()`. A component is
   a class with a `Render()`. Progressive complexity — reach for DI, middleware, and
   contracts only when you need them.
3. **Backend-agnostic rendering.** Components render to a `RenderBackend` seam, not to the
   DOM directly — so the same component tree drives the browser, server-side HTML, or a
   test harness.
4. **Built on the z42 standard library.** The server is a thin layer over `z42.net.Http`;
   serialization is `z42.json`; the browser renders through the VM's DOM builtins. zaia
   adds structure, not a parallel runtime.

## Layers

Six packages, strict dependency direction (arrows point to dependencies):

```
                        ┌───────────────┐
                        │   zaia.core   │   kernel: routing, result, DI
                        └───┬───────┬───┘   (no net, no DOM)
              ┌─────────────┘       └──────────────┬───────────────┐
   ┌──────────▼─────────┐              ┌────────────▼────┐  ┌───────▼────────┐
   │   zaia.renderer    │              │   zaia.server   │  │  zaia.shared   │
   │ VNode · Component  │              │ WebApp · Router │  │  ApiContract   │
   │ RenderBackend ·    │              │ Middleware · Ctx│  │  (server⇄client│
   │ Renderer · Html    │              │ → z42.net.Http  │  │   contracts)   │
   │ Backend (SSR)      │              │ → z42.json      │  │  → z42.json    │
   └───────┬────────────┘              └─────────────────┘  └────────────────┘
     ┌─────▼──────────┐
     │   zaia.web     │  DomBackend : RenderBackend  → VM __dom_* builtins
     └─────┬──────────┘
     ┌─────▼──────────┐
     │   zaia.app     │  App.Mount — client host: wires DomBackend into Renderer
     └────────────────┘
```

| Package | Runs on | Depends on | Status |
|---------|---------|-----------|--------|
| `zaia.core` | any | — | 🟢 builds |
| `zaia.renderer` | any | — | 🟢 builds (incl. a working `HtmlBackend`) |
| `zaia.web` | wasm | `zaia.renderer`, **VM DOM builtins** | 🟢 builds; `DomBackend` stubbed until primitives land |
| `zaia.app` | wasm / client | `zaia.renderer`, `zaia.web` | 🟢 builds |
| `zaia.server` | native | `zaia.core`, `z42.net`, `z42.json` | 🟢 builds |
| `zaia.shared` | any | `zaia.core`, `z42.json` | 🟢 builds |

All six compile today with the **nightly** z42 SDK. The only thing not yet *runnable* on
the client is the DOM output — the `DomBackend` throws until the VM DOM primitives ship
(the reconciler above it, and the `HtmlBackend`, run today). See
[docs/dom-interop.md](docs/dom-interop.md).

### The two new abstractions: renderer and app

- **`zaia.renderer`** separates *what* a UI is (a `Component` producing a `VNode` tree)
  from *where* it goes (a `RenderBackend`). The `Renderer` reconciles the tree against a
  backend and never mentions the DOM. Two backends exist: `HtmlBackend` (a string — SSR,
  runs today) and, in `zaia.web`, `DomBackend` (the live browser DOM). A test backend is
  trivial to add. Full design: [docs/rendering.md](docs/rendering.md).
- **`zaia.app`** is the client application host — the composition root a browser program
  calls. `App.Mount("#app", root)` wires a `DomBackend` into a `Renderer` and starts the
  resident render loop. It mirrors the server's `WebApp` host on the other side of the
  stack. Full design: [docs/app-host.md](docs/app-host.md).

## Server — the shape

Minimal-API style, a thin layer over `HttpServer.ServeThreaded(Action<HttpServerContext>)`:

```z42
using Zaia.Server;

void Main() {
    var app = WebApp.Create();
    app.Use(Middleware.Logger());
    app.MapGet("/",           ctx => ctx.Text(200, "Hello from zaia"));
    app.MapGet("/users/{id}", ctx => ctx.Json(200, Users.Find(ctx.Route("id"))));
    app.MapPost("/users",     ctx => { User u = ctx.Body<User>(); Users.Add(u); ctx.Json(201, u); });
    app.Run("0.0.0.0", 8080);
}
```

## Web — the shape

Blazor-like components; `Render()` returns a VNode tree the renderer materializes through
a backend:

```z42
using Zaia.Renderer;
using Zaia.App;

class Counter : Component {
    int _count = 0;
    override VNode Render() =>
        H.Div(
            H.H1("Count: " + _count.ToString()),
            H.Button("Increment").OnClick(() => { _count = _count + 1; StateChanged(); })
        );
}

void Main() { App.Mount("#app", new Counter()); }   // client
// — or, server-side rendering, today:
//   var b = new HtmlBackend(); new Renderer(b).Mount("#app", new Counter());
//   Console.WriteLine(b.ToHtml(0));   // → "<div><h1>Count: 0</h1><button>Increment</button></div>"
```

## Shared — end-to-end typing

Define an endpoint's contract once; the server implements it, the client calls it typed.
Rename a DTO field and both ends fail to compile together, not at runtime.

## Repo layout

```
zaia/
  packages/
    zaia.core/      routing, result, DI
    zaia.renderer/  VNode, Component, H, RenderBackend, Renderer, HtmlBackend
    zaia.web/       DomBackend (→ VM DOM builtins)
    zaia.app/       App.Mount (client host)
    zaia.server/    WebApp, Router, Middleware, RequestContext
    zaia.shared/    ApiContract
    z42.workspace.toml
  examples/         hello-server (server) · counter-web (client)
  docs/             rendering.md · app-host.md · dom-interop.md
  scripts/build.sh
  ARCHITECTURE.md
```

## Build

The packages compile together as a **z42 workspace** (workspace discovery is what resolves
`web → renderer`, `app → renderer+web`, etc. — a flat `Z42_LIBS` does not, for custom
packages). Member manifests use the **named** form `<name>.z42.toml`.

```sh
cd packages && z42 build --workspace --release   # → packages/dist/dist/zaia.*.zpkg  (all six green)
```

> **Open build item (M1):** a z42 workspace only accepts direct-child members, so an app in
> `examples/` can't join the `packages/` workspace as-is. Wiring examples to consume the
> built framework zpkgs (a single-workspace layout, or a package-install step once z42 grows
> one) is the finishing step of M1. The framework packages themselves build green today.

## Roadmap

| Milestone | Contents | Gate |
|-----------|----------|------|
| **M1 — server + SSR spine** | `core`+`server`+`renderer`(HtmlBackend) build & example runs | stdlib HTTP (done) |
| **M2 — shared contracts** | `shared` + typed `HttpClient` calls | z42.json (done) |
| **M3 — client render** | `web`.`DomBackend` real over DOM builtins + `counter-web` | `add-wasm-dom-poc` in nightly |
| **M4 — full-stack demo** | server + browser sharing contracts; SSR + hydration | M1–M3 |
| **M5 — tooling** | `z42 new --template`, dev server with live reload | M1–M4 |

M1/M2 are unblocked today; M3 is gated on the DOM primitives, whose contract is frozen in
[docs/dom-interop.md](docs/dom-interop.md) so the layers above stay stable when it lands.
