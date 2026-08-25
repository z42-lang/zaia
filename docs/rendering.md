# Rendering (`zaia.renderer`)

The rendering layer separates **what** a UI is from **where** it goes. A `Component`
produces an immutable `VNode` tree; a `Renderer` reconciles that tree against a
`RenderBackend`. The renderer never mentions the DOM — so one reconciler drives the
browser, a server-side HTML string, or a test harness.

## Pieces

| Type | Role |
|------|------|
| `VNode` | Immutable virtual node: `Tag`, `Text`, `Children`, `OnClickHandler`. `Tag == ""` is a text node. |
| `H` | Element factory — `H.Div(H.H1("hi"), H.Button("go"))` reads like the markup it builds. |
| `Component` | Base class; override `Render() -> VNode`. `StateChanged()` schedules a re-render. |
| `RenderBackend` | The seam. Abstract ops on opaque **int node handles**: `Root`, `CreateElement`, `CreateText`, `SetText`, `AppendChild`, `OnClick`. |
| `Renderer` | Backend-agnostic reconciler: renders the root component to a `VNode` tree and materializes it through a backend. |

## The seam

```z42
public abstract class RenderBackend {
    public abstract int  Root(string selector);
    public abstract int  CreateElement(string tag);
    public abstract int  CreateText(string text);
    public abstract void SetText(int node, string text);
    public abstract void AppendChild(int parent, int child);
    public abstract void OnClick(int node, Action handler);
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
`AppendChild` / `OnClick` against the backend. `Component.StateChanged()` reaches the
active renderer (`Renderer.Active`) and reschedules.

**Future — diffing.** Keyed tree-diffing (compare the new `VNode` tree to the last and
patch only the delta) is a drop-in optimization: the `RenderBackend` seam already exposes
the mutation ops a patcher needs (it will grow `RemoveChild` / `SetAttribute`). The
component and backend APIs do **not** change when diffing lands.

## Why this shape

- **SSR + hydration** fall out of one abstraction: render on the server with
  `HtmlBackend`, ship the HTML, then attach a `DomBackend` on the client over the same
  tree.
- **Testability**: assert on a component's `VNode` output (or an in-memory backend) with
  no browser.
- **Portability**: a future native or canvas backend is just another `RenderBackend`.
