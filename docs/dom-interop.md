# DOM interop — the contract `zaia.web` depends on

`zaia.web`'s `DomBackend` is a thin adapter: it maps the `RenderBackend` seam onto a
handful of **VM DOM builtins** that let z42 code, running in WebAssembly, touch the real
browser DOM. Those builtins are a **z42 language / VM change** (`add-wasm-dom-poc`, in the
z42 repo) — not framework code. This page is the contract zaia builds on and the plan for
landing it, so the framework's design story lives in one place.

> Authoritative implementation + spec of the VM change live in the z42 language repo; this
> doc is the framework-side design and the frozen interface `zaia.web` targets.

## The vision

Like .NET Blazor WebAssembly: the browser downloads the z42 VM, and z42 code creates DOM
nodes and handles events to build interactive UIs client-side. zaia's `renderer` + `web` +
`app` layers are that UI framework; this contract is the last missing primitive underneath.

## What the VM must provide

A small set of builtins (interp-only on wasm — no JIT), each `wasm32` real / native `bail!`
stub so the runtime keeps building on every platform:

| Builtin | `RenderBackend` op | Notes |
|---------|--------------------|-------|
| `__dom_get_element_by_id` | `Root(selector)` | returns an int node handle |
| `__dom_create_element` | `CreateElement(tag)` | `document.createElement`; returns handle |
| `__dom_create_text` | `CreateText(text)` | text node |
| `__dom_set_text` | `SetText(node, text)` | `textContent` |
| `__dom_set_attribute` | `SetAttribute(node, name, value)` | `setAttribute` (class / id / href / value / …) |
| `__dom_append_child` | `AppendChild(parent, child)` | |
| `__dom_clear` | `Clear(node)` | remove all children (reconciler's rebuild reset) |
| `__dom_add_event_listener` | `On(node, eventName, handler)` | stores a non-capturing handler + re-enters the VM on the event; `eventName` = "click" / "input" / … |

Node handles are integers indexing a wasm-side `thread_local Vec<web_sys::Node>` — web_sys
objects never cross into z42 values.

## The one hard part: event re-entry

A click fires **outside** any `invoke`. The listener builtin stores the handler as a z42
`FuncRef` (a non-capturing method-group / lambda — a plain name, no GC-rooting problem) and
creates a `wasm_bindgen` `Closure` that, on the event:

1. re-acquires the resident VM (`Host` is a process-global singleton — it stays alive after
   `Main` returns);
2. **re-establishes the ambient GC heap** from the persisted `VmContext`;
3. runs the handler via `interp::run_returning` (the proven pattern used by reflection
   attribute factories).

Step 2 is the **only real risk** — the ambient heap is set up around a normal `invoke` but
not around a cold event re-entry. So the change is **spike-first**: prove "click → z42
`Console.WriteLine`" end-to-end before building anything else. If the heap can't be
re-established cleanly, that's a stop-and-design point (it may pull the heap-scope out of
`host/ops`).

## PoC boundary (frozen here)

- **Non-capturing handlers only** (`Action` / method-group → `FuncRef`). Capturing closures
  need a GC-rooted env across event turns — deferred. `zaia.renderer`'s `On(node, eventName,
  Action)` already reflects this.
- **Imperative build, no diffing** at the VM level — the renderer does the reconciliation.
- **Ships a pre-built app `.zbc`** loaded via the handle API (`loadZbc` → `resolveEntry` →
  `invoke`, no `dispose` so the VM stays resident). In-browser *compilation* is a separate
  track (the playground / `add-wasm-vfs-backend`).
- **No rich JS↔z42 marshaling** — the builtins take z42 `Value::Str` directly.

## How zaia consumes it

Once the builtins ship in a nightly SDK, `zaia.web.DomBackend` replaces its stubs with
`[Native("__dom_*")]` extern calls. **Nothing above `DomBackend` changes** — `Renderer`,
`Component`, `H`, `App` are already written against the seam. `App.Mount` starts working in
the browser; `HtmlBackend` keeps serving SSR. That is the whole point of the backend
abstraction: the client "just turns on" when the primitive lands.

## Status

- Contract + PoC plan: **frozen** (this doc).
- VM change `add-wasm-dom-poc`: spec written, **spike pending** (z42 repo).
- `zaia.web.DomBackend`: compiles with stubs today; wire to externs when the nightly carries
  the builtins.
