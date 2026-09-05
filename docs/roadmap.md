# zaia roadmap

The framework's first two users are the **z42 site** and the **playground**.
Everything here is ordered by what those two need, and each milestone names the
z42-side work it waits on — the framework is meant to *pull* language work, not
route around it.

> The playground's compile-and-run **engine** is not zaia's job. The z42 repo
> builds it (`add-wasm-vfs-backend` proved in-browser compilation: DepScan over
> an in-memory VFS resolved 43 namespaces / 374 modules, matching disk), and its
> own proposal states the website lives in another repo. zaia builds the site
> and the playground's **UI** on top of that engine.

## M0 — seams ✅

Every interface settled and compiling; the render path proven end to end with no
browser.

- `zaia.core` · `zaia.ui` · `zaia.renderer` · `zaia.web` · `zaia.server` ·
  `zaia.shared` · `zaia.app` all build
- `example-counter-ssr` — a stateful component renders to HTML
- `example-hello-server` — routing, captures, query, DI, middleware, 404, SSR,
  all verified against a live server
- `example-isomorphic` — every route rendered through **both** the server path
  and the client `Router`, compared byte for byte

## M1 — the site

A static-ish content site is the smallest thing that exercises the whole spine,
and it is the thing z42 most needs.

- Markdown → `VNode` (a `Std`-only renderer; no new dependency)
- Static asset serving in `zaia.server` — `MapStatic(prefix, dir)` with content
  types and caching headers
- A layout/slot convention so pages share a shell
- `example-site` → the real `app-site`

**Waits on:** nothing. All of this is buildable today.

## M2 — a client that runs

The first milestone that needs the language to move.

- `__dom_*` builtins land → `DomBackend` stops throwing
  ([docs/design/dom-interop.md](design/dom-interop.md))
- `__history_*` → `BrowserLocation : ILocation`
- `example-counter-web` — the same `Counter` from `example-counter-ssr`, in a
  browser, with no source change

**Waits on:** `add-wasm-dom-poc` in the z42 repo, spike-first on GC-heap
re-entry. Also the capturing-handler restriction — until closure environments
are GC-rooted across event turns, a component's handlers must be method groups.

## M3 — hydration and a real reconciler

The two incomplete bodies, which are the same piece of work.

- Keyed diffing in `Renderer.Update` (`VNode.Key` already carries the identity)
- `Router` adopts the server's DOM instead of remounting it
- Focus and scroll survive a re-render

**Waits on:** nothing but M2 being real enough to test against.

## M4 — the playground UI

- Editor pane, run button, output pane, shareable-link state
- Drives the z42 repo's wasm engine (`Z42VM.mountFile` → `Std.Scripting`)
- Console output arrives as bytes through `stdoutHandler` — the one place zaia
  touches the facade directly, because that is what the facade is for

**Waits on:** M2, and the engine's JS entry point stabilizing.

## M5 — end-to-end typing

- `ApiContract` used for real across the site's own API
- A `fetch` builtin so `ApiClient` works in a browser

**Waits on:** a `fetch` builtin contract, not yet specified.

## Language work this pulls

Ordered by what it costs the framework today, not by size. Full detail in
[docs/design/language-surface.md](design/language-surface.md).

| | Why it matters here |
|---|---|
| `String.IndexOf(char)` mis-dispatch (#6) | Type-correct code failing at runtime — the worst failure mode found |
| Indexed-zpkg error message (#13) | Says "no implementation of `Get`", means "packaging" |
| Generic return type across zpkg (#7) | Forces a cast on every `Resolve<T>` — the most visible wart in zaia's API |
| Clean-build-only toolchain (#11, #12, #14) | Every build is a full rebuild |
| `string`/`String` in generic args (#8) | Any API handing a `Dictionary<string, …>` across a package hits it |
| Expression-bodied properties (#1) | Cosmetic, but touches every property in the framework |
| Block lambda → delegate field (#4) | Shaped the whole handler API into methods |

Async is not on this list. `async`/`await` is 0.8.x, and a worker pool over
blocking handlers is the honest shape until then — not a workaround to be
unwound later.
