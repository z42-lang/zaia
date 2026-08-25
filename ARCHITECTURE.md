# zaia — architecture

**zaia** is a full-stack framework for the [z42](https://z42-lang.github.io/) language:
build the **server**, the **web client**, and the **shared** code of an application in
one language, one repo, one mental model. Think *ASP.NET Core Minimal APIs + Blazor*,
reimagined for z42 — HTTP APIs and interactive web UIs, sharing models and route
contracts end-to-end.

> Name: **z**42 + **a**pp/**i**nteractive/**a**rchitecture. Pronounced "zai-a".

## Design goals

1. **One language across the stack.** The same z42 types flow from database to server
   to browser. No serialization mismatch between a TypeScript client and a C# server.
2. **Minimal ceremony.** A server is `WebApp.Create().MapGet(...).Run()`. A component is
   a class with a `Render()`. Progressive complexity — reach for DI, middleware, and
   contracts only when you need them.
3. **Layered, not monolithic.** Four packages with a strict dependency direction, so you
   can take just the server, just the client, or the whole thing.
4. **Built on the z42 standard library.** The server is a thin, ergonomic layer over
   `z42.net.Http`; serialization is `z42.json`; the client renders through the VM's DOM
   builtins. zaia adds structure, not a parallel runtime.

## Layers

```
                 ┌─────────────────────────────────────────┐
                 │              zaia.core                   │  platform-agnostic kernel
                 │  RoutePattern · Result · Pipeline · DI   │  (no net, no DOM)
                 └───────────────┬──────────────┬──────────┘
                     ┌───────────┘              └───────────┐
          ┌──────────▼──────────┐            ┌──────────────▼─────────────┐
          │     zaia.server     │            │          zaia.web          │
          │  WebApp · Router ·  │            │  Component · VNode · render │
          │  Middleware · Ctx   │            │  · client Router · state    │
          │  → z42.net.Http     │            │  → VM DOM builtins (wasm)   │
          │  → z42.json         │            │  → z42.json                 │
          └──────────┬──────────┘            └──────────────┬─────────────┘
                     └───────────┐              ┌───────────┘
                          ┌──────▼──────────────▼──────┐
                          │        zaia.shared         │  full-stack glue
                          │  ApiContract · DTOs · Link  │  (route + req/resp types,
                          │  → z42.json                 │   implemented by server,
                          └────────────────────────────┘   called typed by client)
```

**Dependency direction is strict:** `core` depends on nothing (in the framework);
`server`, `web`, `shared` depend on `core`; `shared` is consumed by both `server` and
`web`. Nothing depends on `server` or `web` — they are leaves. This keeps the client
bundle free of server code and vice-versa.

| Package | Runs on | Depends on | Status |
|---------|---------|-----------|--------|
| `zaia.core` | any (native + wasm) | — | 🟢 buildable now |
| `zaia.server` | native | `zaia.core`, `z42.net`, `z42.json` | 🟢 buildable now (stdlib HTTP is complete) |
| `zaia.shared` | any | `zaia.core`, `z42.json` | 🟢 buildable now |
| `zaia.web` | wasm / browser | `zaia.core`, `z42.json`, **VM DOM builtins** | ⏳ blocked on DOM primitives (see below) |

### Why the client is blocked (and the server is not)

The server sits on `z42.net.Http.HttpServer`, which already exists and works. The client
needs the VM to expose **DOM primitives** (`__dom_create_element`, `__dom_add_event_listener`,
event re-entry into the interpreter) — those are being added in the z42 language repo
(change `add-wasm-dom-poc`) and will ship in a nightly SDK. Until then, `zaia.web` is a
**specified skeleton**: the component/VNode API is fixed here so shared code and examples
can compile against it, but the renderer is stubbed until the primitives land.

## Server — the shape

Minimal-API style, a thin layer over `HttpServer.ServeThreaded(Action<HttpServerContext>)`:

```z42
using Zaia.Server;

void Main() {
    var app = WebApp.Create();

    app.Use(Middleware.Logger());               // cross-cutting: logging, auth, cors…

    app.MapGet("/",            ctx => ctx.Text(200, "Hello from zaia"));
    app.MapGet("/users/{id}",  ctx => ctx.Json(200, Users.Find(ctx.Route("id"))));
    app.MapPost("/users",      ctx => {
        User u = ctx.Body<User>();              // JSON body → typed (z42.json)
        Users.Add(u);
        ctx.Json(201, u);
    });

    app.Run("0.0.0.0", 8080);                   // blocks; serves on a thread pool
}
```

- **`WebApp`** — the builder + host. `MapGet/MapPost/MapPut/MapDelete(pattern, handler)`,
  `Use(middleware)`, `Run(host, port)`.
- **`Router`** — matches `(method, path)` to an endpoint using `RoutePattern` (`/users/{id}`
  captures `id`). From `zaia.core`.
- **`Middleware`** — `Action<RequestContext, Action>` `(ctx, next)`; composed into a
  pipeline that wraps the matched handler. Structural func type → crosses packages cleanly.
- **`RequestContext`** — wraps `HttpServerContext`: `Route(name)` / `Query(name)` /
  `Header(name)` / `Body<T>()` in; `Text` / `Json` / `Status` / `Bytes` / `Redirect` out.

Handlers are `Action<RequestContext>` — no custom named delegates (keeps cross-package
references clean, per the z42 delegate rule).

## Web — the shape (skeleton until DOM primitives land)

Blazor-like components; `Render()` returns a virtual node tree that the renderer diffs
against the live DOM:

```z42
using Zaia.Web;

class Counter : Component {
    int _count = 0;

    override VNode Render() {
        return H.Div(
            H.H1("Count: " + _count.ToString()),
            H.Button("Increment").OnClick(() => { _count = _count + 1; StateChanged(); })
        );
    }
}

void Main() {
    App.Mount("#app", new Counter());   // boots the VM-resident render loop
}
```

- **`Component`** — base class; `Render() -> VNode`; `StateChanged()` schedules a re-render.
- **`VNode`** — immutable virtual node (tag, attrs, children, event handlers). `H` is the
  element factory (`H.Div`, `H.Button`, `H.Text`, …).
- **`Renderer`** — diffs the new VNode tree against the last and patches the real DOM via
  the VM DOM builtins. Event handlers are non-capturing at first (PoC constraint), growing
  to captured closures once GC-rooted handlers land.
- **`App.Mount`** — fetches `#app`, does the first render, and leaves the VM resident so
  DOM events re-enter z42.

## Shared — end-to-end typing

Define an endpoint's contract once; the server implements it, the client calls it typed:

```z42
using Zaia.Shared;

// contracts (compiled into both server and client)
class GetUser : ApiContract {
    public static string Method = "GET";
    public static string Path   = "/users/{id}";
    // request: route param id; response:
    public class Response { public string Id; public string Name; }
}
```

- Server: `app.Map(GetUser, ctx => ...)` — the router pattern comes from the contract.
- Client: `Api.Call(GetUser, id).Then(resp => ...)` — over `z42.net.Http.HttpClient`,
  request/response shapes checked against the contract, JSON via `z42.json`.

This is the payoff of one-language full-stack: rename a field on the DTO and both ends
fail to compile together, not at runtime.

## Repo layout

```
zaia/
  packages/
    zaia.core/     z42.toml + src/   RoutePattern, Result, Pipeline, ServiceCollection
    zaia.server/   z42.toml + src/   WebApp, Router, Middleware, RequestContext
    zaia.web/      z42.toml + src/   Component, VNode, H, Renderer, App   (skeleton)
    zaia.shared/   z42.toml + src/   ApiContract, Api                     (skeleton)
  examples/
    hello-server/  a runnable HTTP server (buildable today)
    counter-web/   a client component (pending DOM primitives)
    todo-fullstack/ server + client sharing contracts                    (later)
  templates/       project templates for `z42 new --template …`          (later)
  scripts/build.z42  builds each package to a local libs dir, in dep order
  docs/            deeper design notes
  ARCHITECTURE.md  this file
```

## Build & consume

zaia packages are ordinary z42 libraries, compiled together as a **z42 workspace**
(`packages/z42.workspace.toml`, `members = ["*"]`). Workspace discovery is what makes the
inter-package dependencies resolve — `server`/`web`/`shared` find `core`'s compiled `dist/`
automatically, which a flat `Z42_LIBS` does *not* do for custom packages:

```sh
cd packages && z42 build --workspace --release   # → packages/dist/dist/zaia.*.zpkg
```

Each package manifest is the **named** form `<name>.z42.toml` (e.g. `zaia.core.z42.toml`) —
workspace member discovery requires it. Everything builds with the **nightly** z42 SDK (the
client layer additionally *requires* the nightly that carries the DOM builtins).

> **Open build item (M1):** a z42 workspace only accepts direct-child members, so an app in
> `examples/` can't join the `packages/` workspace as-is, and a flat `Z42_LIBS` doesn't
> resolve custom cross-package types at compile time. Wiring examples to consume the built
> framework zpkgs (a single-workspace layout, or a package-install step once z42 grows one)
> is the finishing step of M1. The four framework packages themselves build green today.

## Roadmap

| Milestone | Contents | Gate |
|-----------|----------|------|
| **M1 — server spine** | `zaia.core` + `zaia.server` + `hello-server` runnable | stdlib HTTP (done) |
| **M2 — shared contracts** | `zaia.shared` + typed `HttpClient` calls + a two-endpoint demo | z42.json (done) |
| **M3 — web PoC** | `zaia.web` real renderer over DOM builtins + `counter-web` | `add-wasm-dom-poc` in nightly |
| **M4 — full-stack demo** | `todo-fullstack` sharing contracts across server + browser | M1–M3 |
| **M5 — tooling** | `z42 new --template` scaffolds, dev server with live reload | M1–M4 |

M1 and M2 are unblocked today. M3 is gated on the DOM primitives; its API is already
frozen here so M1/M2 code and examples stay stable when the renderer lands.
