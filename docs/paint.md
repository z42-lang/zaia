# Paint layer (`zaia.paint`)

The paint layer is a **backend-agnostic drawing abstraction**: widgets (or any code)
emit a list of draw commands through a `Painter`, and a `DrawBackend` rasterizes that
list to a real target. It's borrowed almost directly from the immediate-mode GUI
libraries [egui](https://github.com/emilk/egui) (its `Painter` / `epaint::Shape`) and
[nuklear](https://github.com/immediate-mode-ui/nuklear) (its tagged `nk_command`
buffer + `nk_input` / `nk_style`) — the parts of those libraries that are *paradigm-
neutral* and reusable regardless of whether the UI on top is immediate or retained.

## Pieces

| Type | Role |
|------|------|
| `Vec2` · `Rect` · `Color` · `Stroke` | geometry & color value types (egui `emath`/`ecolor`, nuklear `nk_vec2`/`nk_rect`/`nk_color`) |
| `DrawCmd` → `RectCmd`·`TextCmd`·`LineCmd`·`CircleCmd`·`ClipCmd` | one draw command; a class tree with an int `Kind` tag (z42 has no enums; nuklear tags `nk_command` the same way) |
| `DrawList` | an ordered buffer of `DrawCmd`s for one frame |
| `Painter` | ergonomic helpers that append the right command (`Rect`/`Text`/`Line`/`Circle`/`PushClip`) — egui's `Painter` |
| `DrawBackend` | the seam: `Begin` / `Submit(DrawList)` / `End` |
| `TextDrawBackend` | a reference backend that serializes commands to text — runs **today** |
| `InputState` | per-frame input snapshot (pointer, button edges, scroll, `Dt`) — egui `RawInput` / nuklear `nk_input` |
| `Style` | colors + metrics for theming — egui `Visuals` / nuklear `nk_style` |

## The seam

```z42
public abstract class DrawBackend {
    public abstract void Begin(int width, int height);
    public abstract void Submit(DrawList list);   // rasterize the frame's commands
    public abstract void End();
}
```

Commands are **data**, not calls — a `DrawList` is produced independently of any target,
then handed to a backend. Backends switch on `DrawCmd.Kind`:

- **`TextDrawBackend`** (in `zaia.paint`) — serializes each command to a line of text.
  Needs no GPU/canvas, so it runs today for tests, goldens, and proving the widget layer
  composes (the paint-layer analog of `zaia.renderer`'s `HtmlBackend`).

  ```
  rect 0,0 360x220 fill=#2a2a30ff round=4
  text 8,6 "Demo" #e6e6ebff size=14
  rect 8,66 344x26 fill=#4e4e58ff round=4
  ...
  ```

- **`CanvasBackend`** (in `zaia.web`) — the live browser target: maps each command to an
  HTML5 Canvas 2D call via VM `__canvas_*` builtins (`fillRect`, `fillText`, `stroke`,
  `clip`). Those primitives are a z42 VM change (sibling to `add-wasm-dom-poc`, and
  simpler — draw calls, no node graph). Compiles today with stubbed ops; real once they
  ship. **Nothing above the backend changes** when it lands.

- **A GPU backend** (future) — tessellate + upload, like eframe's glow/wgpu integration.

## Why a command list

- **One description, many targets** — the same `DrawList` drives text (test), canvas
  (browser), or GPU. The producer never knows which.
- **Testable today** — assert on the serialized commands with no canvas or browser, which
  is how `example-widgets` runs now.
- **Unblocks interactive UI without the DOM primitives** — a canvas needs only draw calls,
  a separate and simpler VM change than the DOM node graph the declarative client waits on.
