# Rendering (`zaia.renderer`)

The rendering layer takes a **description** (a `Component`'s `VNode` tree, from
[`zaia.ui`](description.md)) and materializes it through a `RenderBackend`. It renders;
it does not describe data or assemble the reactive loop. Because it targets the backend
seam and never the DOM, one reconciler drives the browser, a server-side HTML string, or
a test harness.

## Pieces

| Type | Role |
|------|------|
| `RenderBackend` | The seam. Abstract ops on opaque **int node handles**: `Root`, `CreateElement`, `CreateText`, `SetText`, `SetAttribute`, `AppendChild`, `Clear`, `On`. |
| `Renderer` | Backend-agnostic reconciler: renders the root `Component` to a `VNode` tree (from `zaia.ui`) and materializes it through a backend. `Rerender()` clears the root and rebuilds after a change. |
| `HtmlBackend` | A backend that produces an HTML string — SSR, and proof the reconciler needs no DOM. |

## The seam

Modeled after **Blazor's renderer abstraction**: a minimal imperative mutation API a diff
can target, not the DOM API itself. The op set is exactly what a keyed-diff patcher needs.

```z42
public abstract class RenderBackend {
    public abstract int  Root(string selector);
    public abstract int  CreateElement(string tag);
    public abstract int  CreateText(string text);
    public abstract void SetText(int node, string text);
    public abstract void SetAttribute(int node, string name, string value);
    public abstract void AppendChild(int parent, int child);
    public abstract void Clear(int node);                      // remove all children
    public abstract void On(int node, string eventName, Action handler);
}
```

Nodes are **integer handles**, not backend objects — the browser backend keeps a
`handle → web_sys::Node` table, the HTML backend keeps parallel arrays, a test backend
keeps a tree. Nothing above the seam knows which.

## Backends

- **`HtmlBackend`** (in `zaia.renderer`) — materializes the tree as an HTML string.
  Needs no DOM, so it runs **today**: server-side rendering, and proof the reconciler is
  backend-agnostic.

  ```z42
  HtmlBackend b = new HtmlBackend();
  new Renderer(b).Mount("#app", new Counter());
  Console.WriteLine(b.ToHtml(0));
  // <div><h1>Count: 0</h1><button>Increment</button></div>
  ```

- **`DomBackend`** (in `zaia.web`) — the live browser DOM, over the VM `__dom_*` builtins.
  Compiles today with stubbed ops; real once the DOM primitives ship
  ([dom-interop.md](dom-interop.md)).

- **A test backend** — an in-memory tree for assertions; a few lines.

## Reconciliation

PoC scope is a **full (re)build** on each render: `Renderer._render()` calls
`root.Render()`, walks the `VNode` tree, and issues `CreateElement` / `SetText` /
`SetAttribute` / `On` / `AppendChild` against the backend. `Rerender()` first calls
`Clear(root)` so a re-render replaces rather than appends. A data change signals through
`zaia.ui`'s `UiDispatch`; the app registers a `ChangeListener` that forwards to `Rerender()`
(see [app-host.md](app-host.md)).

**Future — diffing.** Keyed tree-diffing (compare the new `VNode` tree to the last and
patch only the delta) is a drop-in optimization: the `RenderBackend` seam already exposes
the mutation ops a patcher needs (`SetAttribute`/`Clear` landed; it will grow a
finer-grained `RemoveChild`). The component and backend APIs do **not** change when diffing
lands.

## Why this shape

- **SSR + hydration** fall out of one abstraction: render on the server with
  `HtmlBackend`, ship the HTML, then attach a `DomBackend` on the client over the same
  tree.
- **Testability**: assert on a component's `VNode` output (or an in-memory backend) with
  no browser.
- **Portability**: a future native or canvas backend is just another `RenderBackend`.
