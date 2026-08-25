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

`App.Mount` is deliberately tiny today:

```z42
public static void Mount(string selector, Component root) {
    Renderer r = new Renderer(new DomBackend());
    r.Mount(selector, root);
}
```

It is the seam where **lifecycle and composition** grow:

- **Resident loop.** After `Mount` returns, the VM stays alive (the client host does not
  dispose it) so DOM events re-enter z42 and drive re-renders.
- **Configuration & DI.** An `AppBuilder` will carry configuration and a service
  container (from `zaia.core`) so components can resolve services without globals.
- **Routing.** A client `Router` (reusing `zaia.core.RoutePattern`) will map the URL to a
  root component for single-page navigation.
- **SSR + hydration.** The server renders a component with `HtmlBackend` and ships the
  HTML; the client host attaches a `DomBackend` to the same component tree instead of
  rebuilding it.

## Why a separate layer

Keeping the host out of `zaia.renderer` keeps the renderer pure (no DOM, no browser
lifecycle) and lets the **same renderer** serve the client host, the server's SSR path,
and tests. The host is the only place that picks a concrete backend and owns process
lifetime — so swapping backends or adding startup logic never touches component code.
