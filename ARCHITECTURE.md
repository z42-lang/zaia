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
  CLIENT (describe → render → assemble)          SERVER / SHARED

  ┌────────────────────┐                     ┌───────────────┐
  │      zaia.ui       │  describe           │   zaia.core   │  routing/result/DI
  │ Component · VNode  │                     └───┬───────┬───┘
  │ H · State · UiDisp │                    ┌────┘       └────┐
  └─────────┬──────────┘             ┌──────▼────────┐ ┌──────▼───────┐
  ┌─────────▼──────────┐             │  zaia.server  │ │ zaia.shared  │
  │   zaia.renderer    │  render     │ WebApp·Router │ │ ApiContract  │
  │ RenderBackend ·    │             │ Middleware    │ │ (server⇄     │
  │ Renderer · Html    │             │ → z42.net.Http│ │  client)     │
  │ Backend (SSR)      │             │ → z42.json    │ │ → z42.json   │
  └─────────┬──────────┘             └───────────────┘ └──────────────┘
  ┌─────────▼──────────┐
  │     zaia.web       │  DomBackend : RenderBackend → VM __dom_* builtins
  └─────────┬──────────┘
  ┌─────────▼──────────┐
  │     zaia.app       │  assemble — App.Mount: backend + change→render loop + lifecycle
  └────────────────────┘
```

| Package | Runs on | Depends on | Public seams | Status |
|---------|---------|-----------|--------------|--------|
| `zaia.core` | any | — | `RoutePattern` · `Result<T>` · `ServiceContainer` (DI) | 🟢 builds |
| `zaia.ui` | any | — | `Component` · `VNode` (attrs + events) · `H` · `State<T>` · `UiDispatch`/`ChangeListener` | 🟢 builds |
| `zaia.renderer` | any | `zaia.ui` | `RenderBackend` · `Renderer` · `HtmlBackend` | 🟢 builds (incl. a working `HtmlBackend`) |
| `zaia.web` | wasm | `zaia.renderer`, **VM DOM builtins** | `DomBackend : RenderBackend` | 🟢 builds; `DomBackend` stubbed until primitives land |
| `zaia.app` | wasm / client | `zaia.core`, `zaia.ui`, `zaia.renderer`, `zaia.web` | `App` · `AppBuilder` · `Router`/`RouteHandler` | 🟢 builds |
| `zaia.server` | native | `zaia.core`, `z42.net`, `z42.json` | `WebApp` · `RequestContext` · `Middleware` · `Endpoint` | 🟢 builds |
| `zaia.shared` | any | `zaia.core`, `z42.net`, `z42.json` | `ApiContract` (convention) · `ApiClient` (typed caller) | 🟢 builds |
| `zaia.paint` | any | — | `DrawList` · `Painter` · `DrawCmd` · `DrawBackend` · `TextDrawBackend` · `InputState` · `Style` | 🟢 builds + runs |
| `zaia.widgets` | any | `zaia.paint` | `Widget` · `Label`/`Button`/`Checkbox`/`Slider` · `Row`/`Column`/`Panel` · `Gui` | 🟢 builds + runs |

Every seam above is **frozen** (this pass settled the abstraction layer before building
features on it). Concrete behavior is filled behind these seams incrementally; the two
still-stubbed bodies are `DomBackend` and `CanvasBackend`, gated on their VM primitives.

### Two front-ends, backend-agnostic rendering

zaia has **two UI front-ends** sharing the "render through a seam" philosophy:

- **Declarative** (`zaia.ui` → `zaia.renderer`): React/Blazor-style. `Component.Render()`
  builds a retained `VNode` tree; `RenderBackend` mutates DOM nodes (`HtmlBackend` runs SSR
  today; `DomBackend` awaits DOM primitives). Best for content/document UIs.
- **Canvas widgets** (`zaia.paint` → `zaia.widgets`): a **retained widget toolkit** painted
  through a **draw-command list**. `Gui` lays out persistent widget objects, hit-tests them
  against `InputState`, and emits a `DrawList` to a `DrawBackend` (`TextDrawBackend` runs
  today; `CanvasBackend` awaits VM `__canvas_*`). Best for tools/dashboards. See
  [docs/paint.md](docs/paint.md) · [docs/widgets.md](docs/widgets.md).

### Design lineage

The seams deliberately mirror proven frameworks so they read as familiar, not invented:
`Component`/`VNode`/`H` follow **React / hyperscript**; `RenderBackend` follows **Blazor's
renderer abstraction** (a minimal imperative mutation API a diff can target, not the DOM
API itself); `ServiceContainer` follows **ASP.NET Core `IServiceProvider`**; `WebApp`
follows **ASP.NET Minimal APIs**; `Router` follows **ASP.NET routing**; the `ApiContract` +
typed `ApiClient` seam follows **tRPC / Refit-style** typed clients over a shared DTO. The
`zaia.paint` layer borrows **egui**'s `Painter`/`epaint` and **nuklear**'s tagged
command-buffer + `nk_input`/`nk_style`; `zaia.widgets` keeps their paint/input/style
abstractions but is **retained** (persistent widget objects, callbacks) rather than
immediate-mode — a deliberate divergence so it composes with zaia's retained model.

All seven compile today with the **nightly** z42 SDK. The only thing not yet *runnable* on
the client is the DOM output — the `DomBackend` throws until the VM DOM primitives ship
(the description, the reconciler, and the `HtmlBackend` all run today). See
[docs/dom-interop.md](docs/dom-interop.md).

### The client is three layers: describe → render → assemble

The client stack is split by a single question — *whose job is this?*

- **`zaia.ui` — describe.** `Component` (override `Render() -> VNode`), the `H` element
  factory, and `State<T>`, the data-update primitive: mutate a `State` and it fires a
  change signal through `UiDispatch`. This layer **only describes** the UI and how data
  updates; it has no renderer, no DOM, and no idea what happens when data changes.
  Full design: [docs/description.md](docs/description.md).
- **`zaia.renderer` — render.** The `RenderBackend` seam + the `Renderer` reconciler +
  `HtmlBackend`. It takes a description's `VNode` tree and materializes it through a
  backend. It renders; it does not assemble or react. Full design:
  [docs/rendering.md](docs/rendering.md).
- **`zaia.app` — assemble.** The composition root. `App.Mount("#app", root)` picks a
  backend (`DomBackend`), wires the reactive loop (registers a `ChangeListener` on
  `UiDispatch` that re-renders), and owns process lifetime. It's the only place that knows
  all three layers. Full design: [docs/app-host.md](docs/app-host.md).

The seam between describe and assemble is a nominal `ChangeListener` (registered on
`UiDispatch`), not a delegate — so the description signals a change without ever importing
the renderer, and a named class crosses the zpkg boundary cleanly.

## Server — the shape

Minimal-API style, a thin layer over `HttpServer.ServeThreaded(Action<HttpServerContext>)`:

```z42
using Zaia.Server;

void Main() {
    var app = WebApp.Create();
    app.Services.Register(new UserStore());          // DI: resolved via ctx.Resolve<T>()
    app.Use(Middleware.Logger());
    app.MapGet("/",           ctx => ctx.Text(200, "Hello from zaia"));
    app.MapGet("/users/{id}", ctx => ctx.Json(200, ctx.Resolve<UserStore>().Find(ctx.Route("id"))));
    app.MapPost("/users",     ctx => { User u = ctx.Body<User>(); ctx.Resolve<UserStore>().Add(u); ctx.Json(201, u); });
    app.Run("0.0.0.0", 8080);
}
```

Handlers stay **imperative** — `ctx.Json(...)` / `ctx.Text(...)` — sidestepping z42's
block-lambda→`Func` inference wall. `Result<T>` (in `zaia.core`) is for your own logic, not
the handler return type. A shared contract binds with `app.MapContract(C.Verb, C.Path, …)`.

## Web — the shape

Blazor-like components; `Render()` returns a VNode tree the renderer materializes through
a backend:

```z42
using Zaia.Ui;
using Zaia.App;

class Counter : Component {
    State<int> _count = new State<int>(0);              // data-update primitive
    override VNode Render() =>
        H.Div(
            H.H1("Count: " + _count.Get().ToString()),
            H.Button("Increment").OnClick(() => _count.Set(_count.Get() + 1))
        );
}

void Main() { App.Mount("#app", new Counter()); }   // client
// — or, server-side rendering, today (no DOM primitives needed):
//   using Zaia.Renderer;
//   var b = new HtmlBackend(); new Renderer(b).Mount("#app", new Counter());
//   Console.WriteLine(b.ToHtml(0));   // → "<div><h1>Count: 0</h1><button>Increment</button></div>"
```

## Shared — end-to-end typing

Define an endpoint's contract once; the server implements it, the client calls it typed.
Rename a shared DTO field and both ends fail to compile together, not at runtime.

```z42
// shared: the contract (static Verb/Path + nested DTOs — the z42-friendly convention)
public class GetUser : ApiContract {
    public static string Verb = "GET";
    public static string Path = "/users/{id}";
    public class Response { public string Id; public string Name; }
}

// server: implement it            app.MapContract(GetUser.Verb, GetUser.Path, ctx => …);
// client: call it typed
var api = new ApiClient("http://localhost:8080");
GetUser.Response u = api.Get<GetUser.Response>("/users/" + id);
```

## Repo layout

```
zaia/
  packages/                       ← the z42 workspace (framework libs + example exes)
    zaia.core/      RoutePattern, Result, ServiceContainer  (routing · result · DI)
    zaia.ui/        Component, VNode, H, State, UiDispatch   (describe)
    zaia.renderer/  RenderBackend, Renderer, HtmlBackend     (render)
    zaia.web/       DomBackend (→ VM DOM builtins)
    zaia.app/       App, AppBuilder, Router                  (assemble)
    zaia.server/    WebApp, RequestContext, Middleware, Endpoint
    zaia.shared/    ApiContract, ApiClient
    zaia.paint/     DrawList, Painter, DrawCmd, DrawBackend, InputState, Style  (egui/nuklear-borrowed)
    zaia.widgets/   Widget, Label/Button/Checkbox/Slider, Row/Column/Panel, Gui  (retained toolkit)
    example-counter-ssr/   exe · Component → HtmlBackend → HTML string (runs today)
    example-hello-server/  exe · WebApp over z42.net.Http
    example-widgets/       exe · Panel of widgets → TextDrawBackend dump (runs today)
    z42.workspace.toml
  docs/             description.md · rendering.md · app-host.md · dom-interop.md
  scripts/build.sh · scripts/run-example.sh
  ARCHITECTURE.md
```

## Build

Everything compiles together as **one z42 workspace** — framework libraries *and* example
exes are all direct-child members of `packages/`. Workspace discovery is what resolves the
inter-package types (`web → renderer`, an example `→ ui + renderer`, …); a flat `Z42_LIBS`
does **not** resolve custom-package types, so the single workspace is the mechanism. Member
manifests use the **named** form `<name>.z42.toml`.

```sh
cd packages && z42 build --workspace --release   # → packages/dist/dist/*.zpkg (9 members green)

# run the SSR example (Z42_LIBS = the SDK's stdlib; siblings resolve from the dist dir):
Z42_LIBS="$(dirname "$(z42 which)")/../libs" z42vm packages/dist/dist/counter-ssr.zpkg
# → <div class="counter"><h1>Count: 0</h1><button>Increment</button></div>
```

> **M1 layout note:** a z42 workspace only accepts direct-child members (`members = ["*"]`),
> so examples live *inside* the workspace (`packages/example-*`) rather than a sibling
> `examples/` tree — that's what lets them consume the framework via workspace discovery
> instead of a flat lib path. This was M1's finishing step; it is done.

## Roadmap

| Milestone | Contents | Gate |
|-----------|----------|------|
| **M1 — server + SSR spine** ✅ | `core`+`server`+`renderer`(HtmlBackend) build & example runs (`counter-ssr` renders HTML) | stdlib HTTP (done) |
| **M2 — shared contracts** | `shared` + typed `HttpClient` calls | z42.json (done) |
| **M3 — client render** | `web`.`DomBackend` real over DOM builtins + `counter-web` | `add-wasm-dom-poc` in nightly |
| **M4 — full-stack demo** | server + browser sharing contracts; SSR + hydration | M1–M3 |
| **M5 — tooling** | `z42 new --template`, dev server with live reload | M1–M4 |

M1 is done — the SSR example runs today. M2 is unblocked; M3 is gated on the DOM primitives,
whose contract is frozen in [docs/dom-interop.md](docs/dom-interop.md) so the layers above
stay stable when it lands.
