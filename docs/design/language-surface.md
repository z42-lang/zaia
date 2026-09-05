# The z42 surface zaia is written against

zaia exists to build the z42 site and playground, and to **find out what z42
cannot do yet** by trying to build something real with it. This page is the
second output: everything the framework hit, what it cost, and what the
workaround is.

Each entry is a candidate issue for the z42 repo. None of them were worked
around by abandoning a design — where the language pushed back, the note says
whether the design bent or the code did.

> Verified against the SDK in `z42/.z42/` on 2026-09-05.

## Language

### 1. Expression-bodied properties are not accepted

```z42
public bool IsOk => this._error == null;         // E0443: undefined type: =>
public bool IsOk { get { return this._error == null; } }   // OK
```

Expression-bodied *methods* (`public int Double(int x) => x * 2;`) work. Only
the property form fails. Roadmap has this on the 0.4.1 S stream
(`init` + 表达式体属性); it has not landed.

**Cost:** cosmetic, pervasive. Every property in the framework is a `get` block.

### 2. Postfix `!` (null-forgiving) is not accepted

```z42
return this._value!;    // E0201: unexpected token in expression
```

**Cost:** none, and arguably an improvement — `Result<T>` now stores `T` with
`default(T)` in the error case instead of `T?`, so there is nothing to forgive.

### 3. `default` is not accepted in argument position

```z42
new Result<T>(default, why)      // parsed as a type; cascades
new Result<T>(default(T), why)   // OK
```

`return default;` works. Only the bare form as a call argument fails.

### 4. A block lambda cannot be assigned to a delegate **field**

```z42
sig.OnFire = (string x) => { Console.WriteLine(x); };
// E0402: cannot assign Func<String, <unknown>> to Action<String>
```

The same lambda is fine as a **method argument** and as a **local declaration**:

```z42
reg.On("click", (string x) => { Console.WriteLine(x); });   // OK
Action<string> h = (string x) => { Console.WriteLine(x); }; // OK
```

So target typing flows through parameters and local declarations but not
through field assignment, and only for the block-bodied form — an expression
lambda assigns to a field fine.

**Cost: this one shaped the API.** Every handler-taking surface in zaia is a
*method* rather than a settable field — `node.OnClick(h)`, `app.MapGet(p, h)`,
`app.Use(m)` — so the gap never reaches a caller. That is a better fluent API
anyway, which is why the design did not bend, but it was not a free choice.

### 5. A delegate field cannot be invoked through `this.`

```z42
this.OnFire(s);                                  // E0401: no method `OnFire` on `Sig`
Action<string> h = this.OnFire; if (h != null) h(s);   // OK
```

**Cost:** small and local. `WebApp.Dispatch` and `Router` copy to a local first.

### 6. `String.IndexOf(char)` mis-dispatches at runtime

`String` declares both `IndexOf(string)` and `IndexOf(char)`. Calling the char
overload compiles, then fails at runtime inside the string one:

```z42
url.IndexOf('?');   // __str_to_chars: arg 0 expected string, got Char('?')
url.IndexOf("?");   // OK
```

This is the only defect found that produces a **runtime** failure from
type-correct code, which makes it the most serious entry here.

**Cost:** `RequestContext` uses the string form throughout, with a comment.

## Generics and packages

### 7. A generic method's return type is not substituted across a zpkg boundary

```z42
Greeter g = c.Services.Resolve<Greeter>();          // E0402: cannot assign T to Greeter
Greeter g = (Greeter)c.Services.Resolve<Greeter>(); // OK
```

Within one package the same call needs no cast. Roadmap 0.4.x G stream
(generic instantiation) is partially landed — `Activator.CreateInstance<T>` and
JSON `Deserialize<T>` ship — so this looks like a remaining gap rather than a
missing feature.

**Cost:** an explicit cast at every `Resolve<T>` and `ApiClient.Get<T>` call
site. Ugly in exactly the two places a framework most wants to be invisible.

### 8. `string` and `String` do not unify as generic type arguments across packages

```z42
// RouteMatch.Params is Dictionary<string, string>, declared in zaia.core
ctx.RouteValues = m.Params;
// E0402: cannot assign Dictionary<string, string> to Dictionary<String, String>
```

The alias and the class name survive as distinct spellings in zpkg metadata, so
the two instantiations are different types across a package boundary.

**Cost: this one changed a design.** `RequestContext` holds the whole nominal
`RouteMatch` instead of its parameter dictionary. The result is better — no
per-request copy — but it was forced, and any framework API that hands a
`Dictionary<string, ...>` across a package boundary will hit it.

## Toolchain

### 9. Workspace members must be direct children

`members = ["libs/*", "apps/*"]` discovers **zero** members; only
`members = ["*"]` works. Note that `z42/examples/workspace-full/` uses the
nested form and therefore does not build.

**Cost: this one changed the repo layout.** `src/framework/*` + `src/apps/*`
was the intended tree; everything is flat under `src/` instead, with naming
(`zaia.*`, `example-*`) carrying the grouping.

### 10. `version.workspace = true` inheritance is unimplemented

```toml
version.workspace = true
# Std.TomlException: expected string, got table
#   at ManifestLoader._parseProject
```

Every member spells `version` and `license` out literally.

### 11. Declaring an SDK stdlib package in `[dependencies]` breaks sibling resolution

Adding `"z42.text" = "0.1.0"` to a member manifest makes z42c stop resolving
that member's **workspace siblings** — `using Zaia.Ui;` starts failing with
`undefined type: VNode`. Removing the stdlib entry fixes it; the stdlib is
still reachable through `using` alone.

**Cost:** a rule nobody would guess. Member manifests declare workspace
siblings only, with a comment saying why.

### 12. Incremental workspace builds produce spurious cross-member failures

A `--workspace` build after a source change reports `undefined type` for types
that plainly exist in a sibling, and the failure **oscillates** between members
across successive runs. `--no-incremental` on a clean `artifacts/` converges in
one run, every time.

### 13. Debug builds emit *indexed* zpkgs that do not run standalone

`[project].pack` defaults to `false` (indexed) for debug and `true` (packed) for
release. An indexed zpkg references scattered `.zbc` files next to it, so
copying or relocating the `.zpkg` yields:

```
VCall: no implementation of `Get` found in hierarchy of `GX.Plain`
```

— a *runtime* error that reads like a dispatch bug and is actually a packaging
one. Building `--release` fixes it.

**Cost:** an hour, chasing a phantom generic-dispatch failure. The error message
is the problem: nothing in it points at packaging.

### 14. A stale dist makes the analyzer demand a circular import

With a previously-built `zaia.app.zpkg` present in the flat libs dir, building
`zaia.ui` fails:

```
zaia.ui/src/UiDispatch.z42(1,1): E0436: namespace `Zaia.App` is used but not
imported in this file; add `using Zaia.App;`
```

`zaia.ui` must never import `zaia.app` — that is the dependency inversion the
whole layering rests on. The analyzer is seeing `App`, an `IChangeListener`
implementor from another package, through the flat libs dir and concluding the
interface's own file needs the import.

**Cost:** the framework must be built from a clean `artifacts/`. `scripts/build.sh`
removes it every time, which is why the build is slower than it should be.

## What this adds up to

Nothing here blocked the framework. Eight of the fourteen are cosmetic or
one-line workarounds; three (#4, #8, #9) changed a design or a layout; two
(#6, #13) cost real debugging time because the failure surfaced far from the
cause; and the toolchain group (#11, #12, #14) together mean **a clean
`--release --no-incremental` build is the only reliable one**.

The two worth fixing first, by cost-to-discover rather than frequency:

1. **#6** — type-correct code failing at runtime is the worst failure mode here.
2. **#13** — the error message points at dispatch and the cause is packaging.

And the one worth fixing for the framework's sake is **#7**: an explicit cast on
every `Resolve<T>` is the single most visible wart in zaia's public API.
