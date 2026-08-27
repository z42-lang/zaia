# Application host (`zaia.app`)

The **app** layer is the composition root — the single entry point a program calls to
turn framework pieces into a running application. zaia has two hosts that mirror each
other across the stack:

| Host | Package | Entry | Wires |
|------|---------|-------|-------|
| **Client** | `zaia.app` | `App.Mount(selector, root)` | a `DomBackend` into a `Renderer`, mounts the root component, leaves the VM resident |
| **Server** | `zaia.server` | `WebApp.Create()…Run(host, port)` | the router + middleware pipeline over `HttpServer` |

## Client host

```z42
using Zaia.Renderer;
using Zaia.App;

void Main() { App.Mount("#app", new Counter()); }
```

`App.Mount` is the one-liner entry; it delegates to `AppBuilder`, the configurable
composition root (ASP.NET `WebApplicationBuilder` / Blazor `WebAssemblyHostBuilder` shape):

```z42
public static void Mount(string selector, Component root) {
    AppBuilder.Create().Root(selector, root).Run();
}

// AppBuilder.Run(): pick the backend, wire the reactive loop, mount, stay resident.
AppBuilder.Create()
    .Root("#app", new Counter())
    .Run();
```

The host is where **lifecycle and composition** grow — the seams now defined:

- **Resident loop.** ✅ After `Run` returns, the VM stays alive (the client host does not
  dispose it) so DOM events re-enter z42 and drive re-renders through the `ChangeListener`.
- **Configuration & DI.** ✅ `AppBuilder.Services` is a `zaia.core.ServiceContainer` — the
  registration seam. Wiring an ambient provider components resolve from is the next step and
  does not change this API.
- **Routing.** ✅ `Router` (reusing `zaia.core.RoutePattern`) maps a URL path to a root
  `Component` via a nominal `RouteHandler`. Resolve logic is testable today; binding it to
  browser history/`popstate` needs the DOM primitives.
- **SSR + hydration.** The server renders a component with `HtmlBackend` and ships the
  HTML; the client host attaches a `DomBackend` to the same component tree instead of
  rebuilding it. (Planned — needs the DOM primitives.)

## Why a separate layer

Keeping the host out of `zaia.renderer` keeps the renderer pure (no DOM, no browser
lifecycle) and lets the **same renderer** serve the client host, the server's SSR path,
and tests. The host is the only place that picks a concrete backend and owns process
lifetime — so swapping backends or adding startup logic never touches component code.
