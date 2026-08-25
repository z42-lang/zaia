# zaia

**A full-stack framework for the [z42](https://z42-lang.github.io/) language.**

Build the server, the web client, and the shared code of an application in one
language, one repo, one mental model — HTTP APIs and interactive web UIs in z42,
sharing models and route contracts end-to-end. Think *ASP.NET Core Minimal APIs +
Blazor*, reimagined for z42.

> Status: **early**. The server stack is buildable today on the z42 standard library;
> the browser/client stack is gated on the VM's DOM primitives (in progress). See
> [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full design and roadmap.

## The shape of it

**Server** — a thin, ergonomic layer over `z42.net.Http`:

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

**Web** — Blazor-like components (renderer lands with the DOM primitives):

```z42
using Zaia.Web;

class Counter : Component {
    int _count = 0;
    override VNode Render() =>
        H.Div(
            H.H1("Count: " + _count.ToString()),
            H.Button("Increment").OnClick(() => { _count = _count + 1; StateChanged(); })
        );
}

void Main() { App.Mount("#app", new Counter()); }
```

**Shared** — one contract, implemented by the server, called typed by the client. Rename a
DTO field and both ends fail to compile *together*, not at runtime.

## Packages

| Package | Role | Status |
|---------|------|--------|
| [`zaia.core`](packages/zaia.core) | platform-agnostic kernel: routing, result, pipeline, DI | 🟢 |
| [`zaia.server`](packages/zaia.server) | `WebApp`, router, middleware, request context | 🟢 |
| [`zaia.shared`](packages/zaia.shared) | end-to-end API contracts + typed client calls | 🟢 |
| [`zaia.web`](packages/zaia.web) | components, virtual DOM, renderer | ⏳ needs VM DOM primitives |

## Getting started

You need the **nightly** z42 SDK (`curl -fsSL https://z42-lang.github.io/install.sh | sh -s -- --version nightly`).

Build the framework — the four packages compile as a **workspace** so their
inter-dependencies (`server`/`web`/`shared` → `core`) resolve automatically:

```sh
cd packages && z42 build --workspace --release
# → packages/dist/dist/zaia.{core,shared,web,server}.zpkg   ✓ all four build green
```

> The `examples/hello-server` app is written against this API; wiring it as a
> workspace member so it builds and runs end-to-end is the current milestone (M1).
> See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the roadmap.

## Layout

```
packages/   zaia.core · zaia.server · zaia.web · zaia.shared   (the framework)
examples/   hello-server · counter-web · todo-fullstack        (runnable samples)
templates/  project scaffolds for `z42 new`
scripts/    build.z42 — compiles packages in dependency order
```

Built entirely in z42 — no other framework. See [`ARCHITECTURE.md`](ARCHITECTURE.md).
