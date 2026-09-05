# Building zaia

```sh
./scripts/build.sh
```

That is the supported path. If you build by hand, use exactly this:

```sh
rm -rf artifacts
cd src && z42c build --workspace --release --no-incremental
```

All three parts are load-bearing. A plain `z42c build --workspace` fails, and
it fails with messages that point at your source instead of at the build.

## Why each flag

### `rm -rf artifacts` — a stale dist breaks the layering

With a previously-built `zaia.app.zpkg` sitting in the flat libs dir, building
`zaia.ui` fails:

```
zaia.ui/src/UiDispatch.z42(1,1): E0436: namespace `Zaia.App` is used but not
imported in this file; add `using Zaia.App;`
```

Do **not** add that import. `zaia.ui` importing `zaia.app` is exactly the cycle
the layering exists to prevent. The analyzer is seeing `App` — an
`IChangeListener` implementor from a downstream package — through the flat libs
dir and concluding the interface's own file needs it. Clearing `artifacts/`
resolves it.

### `--release` — debug zpkgs do not run

`[project].pack` defaults to `false` for debug, which emits an *indexed* zpkg:
a package that references scattered `.zbc` files beside it rather than
containing them. Relocate or copy that `.zpkg` and every method call into it
fails at runtime with

```
VCall: no implementation of `Get` found in hierarchy of `Zaia.Ui.State`
```

which reads like a generic-dispatch bug and is a packaging one. `--release`
emits packed, self-contained zpkgs.

### `--no-incremental` — incremental workspace builds report phantom errors

An incremental `--workspace` build reports `undefined type` for types that
plainly exist in a sibling package, and the failure **moves between members**
on successive runs — build twice and a different member fails. Clean plus
`--no-incremental` converges in a single run, every time.

## Running an example

The runtime needs both the SDK's stdlib and zaia's own dist on its lib path:

```sh
Z42_LIBS="$Z42_SDK/libs:$PWD/artifacts/dist" \
  z42vm artifacts/dist/example-isomorphic.zpkg
```

`scripts/build.sh` does this for each example after a successful build.

## Adding a package

1. Create `src/<name>/` with `<name>.z42.toml` and `src/**/*.z42`.
   The directory must be a **direct child** of `src/` — nested member globs
   (`members = ["libs/*"]`) discover nothing.
2. Spell `version` and `license` out literally. `version.workspace = true`
   inheritance is unimplemented and throws `TomlException: expected string, got
   table`.
3. In `[dependencies]`, declare **workspace siblings only**. Naming an SDK
   standard-library package there (`"z42.text" = "0.1.0"`) makes z42c stop
   resolving your siblings — `using Zaia.Ui;` starts reporting `undefined type:
   VNode`. The standard library is reachable through `using` alone.

Full detail and the rest of the findings:
[../design/language-surface.md](../design/language-surface.md).
