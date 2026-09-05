# DOM interop — the contract `zaia.web` depends on

`zaia.web`'s `DomBackend` is a thin adapter: it maps the eleven-operation
`IRenderBackend` seam onto a handful of **VM builtins** that let z42 code,
running in WebAssembly, touch the real browser DOM.

Those builtins are a **z42 VM change, not framework code**. This page is the
framework side of the contract; the implementation belongs in the language repo.

The contract is not only described here — it is **declared in code**, in
[`src/zaia.web/src/DomNative.z42`](../../src/zaia.web/src/DomNative.z42), as
`[Native(...)] extern` signatures. An extern to an absent builtin compiles
(it is a link-time concern, not a compile-time one), so the contract type-checks
against its consumer and cannot drift from it.

## Why builtins and not the JS facade

This is the decision the whole client story rests on, so it is worth stating
precisely.

The wasm **facade** (`@z42/wasm`, the JS ↔ VM boundary) marshals only:

```ts
export type Z42VMValue = null | boolean | number | bigint;
```

No strings. No objects. z42's own playground entry point works around this by
passing source in through a virtual filesystem and output back through
`Console` → `stdoutHandler` as bytes — `Std.Scripting.Playground` says so in as
many words: *不跨 facade 传字符串（facade 暂无 string 编组）*.

A UI framework cannot live inside that. Every DOM operation is string-shaped —
tag names, attribute names, attribute values, text content.

**A builtin is on the other side of that boundary.** It is called from inside
the VM and receives a z42 `Value::Str` directly; nothing is marshalled across
the facade at all. So the DOM path needs no facade change, and does not wait on
one.

## What the VM must provide

Interp-only on wasm (the sandbox forbids runtime code generation), each
implemented for `wasm32` and stubbed elsewhere so the runtime keeps building on
every platform.

| Builtin | Seam operation |
|---------|----------------|
| `__dom_get_element_by_id` | `Root(selector)` → handle, 0 when absent |
| `__dom_create_element` | `CreateElement(tag)` |
| `__dom_create_text` | `CreateText(text)` |
| `__dom_set_text` | `SetText(node, text)` |
| `__dom_set_attribute` | `SetAttribute(node, name, value)` |
| `__dom_remove_attribute` | `RemoveAttribute(node, name)` |
| `__dom_append_child` | `AppendChild(parent, child)` |
| `__dom_insert_before` | `InsertBefore(parent, child, before)` |
| `__dom_remove_child` | `RemoveChild(parent, child)` |
| `__dom_clear` | `Clear(node)` |
| `__dom_add_event_listener` | `On(node, eventName, handler)` |

**Node handles are integers** indexing a wasm-side node table. `web_sys` objects
never become z42 values — that is what keeps this eleven functions instead of a
DOM binding.

## The one hard part: event re-entry

A click fires **outside** any `invoke`. The listener builtin must store the
handler and, when the event arrives:

1. re-acquire the resident VM (the host is a process-global singleton and stays
   alive after `Main` returns);
2. **re-establish the ambient GC heap** from the persisted `VmContext`;
3. run the handler.

Step 2 is the real risk: the ambient heap is set up around a normal `invoke`,
not around a cold event re-entry. So the VM change should be **spike-first** —
prove "click → z42 `Console.WriteLine`" end to end before building on it. If
the heap cannot be re-established cleanly, that is a stop-and-design point.

### Non-capturing handlers only

The first cut accepts a plain method group or a lambda that closes over nothing,
because a capturing closure needs its environment GC-rooted across event turns.

This restriction is invisible in the signature and very visible at a call site,
so it is stated on `IRenderBackend.On` and again on `DomNative.AddEventListener`.
It is also the one that will hurt: `H.Button(...).OnClick(() => this._count.Set(...))`
captures `this`. Until rooting lands, a component's handlers have to be method
groups on the component itself.

## Two smaller contracts, not yet specified

- **`__history_*`** — `location.pathname` and `pushState`, behind
  `Zaia.App.ILocation`. Only `MemoryLocation` exists today, which is enough to
  test the router and to run it server-side.
- **a `fetch` builtin** — `ApiClient` uses `Std.Net.Http`, which is sockets, so
  it is native-only. A browser client needs its requests to leave through
  `fetch`.

Both are the same shape as the DOM contract: a small set of builtins behind an
interface that already exists.

## How zaia consumes it

When the builtins ship in a nightly SDK, **nothing changes in zaia**.
`DomNative`'s externs start resolving, `DomBackend` starts working, and
`App.Mount` starts working in the browser. `Renderer`, `Component`, `H` and
`App` are already written against the seam.

That is the whole point of the backend abstraction: the client turns on when the
primitive lands.
