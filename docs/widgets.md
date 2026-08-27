# Widget toolkit (`zaia.widgets`)

A **retained widget toolkit** painted through the [paint layer](paint.md). It gives you
buttons, checkboxes, sliders, and panels that lay out, hit-test input, and draw
themselves — targeting a `DrawBackend` (text today, canvas next), not the DOM.

## Retained, not immediate — the deliberate divergence

egui and nuklear, which this borrows from, are **immediate-mode**: every frame your code
re-calls `ui.button("x")`, which both draws and returns "was I clicked." zaia.widgets keeps
their **paint / input / style** abstractions (see [paint.md](paint.md)) but flips the widget
model to **retained**, to compose with the rest of zaia:

- Widgets are **persistent objects** you build once (`new Button("Go")`), not re-emitted
  each frame.
- Interaction is wired with **callbacks** and public state fields (`button.OnClicked(fn)`,
  `checkbox.Checked`) — there is **no** immediate `Ui`/`Response`.
- It's closer to **Flutter/Qt** (retained tree + a paint layer) than to egui.

## Pieces

| Type | Role |
|------|------|
| `Widget` | base: `Measure(Style)` · `Layout(bounds, Style)` · `HandleInput(InputState, Style)` · `Paint(Painter, Style)`, with a `Rect Bounds` |
| `Label` | non-interactive text |
| `Button` | clickable surface; `OnClicked(Action)` fires on release inside |
| `Checkbox` | toggles `Checked`; `OnToggled(Action)` |
| `Slider` | drag to set `Value` in `[Min,Max]`; `OnMoved(Action)` |
| `Row` · `Column` · `Panel` | containers: equal-share row / vertical stack / titled surface (layout math borrowed from nuklear rows + egui cursor stacking) |
| `Gui` | the retained root: `Layout(w,h)` → `Update(InputState)` → `Paint(DrawBackend)` |

## The per-frame loop

```z42
using Zaia.Paint;
using Zaia.Widgets;

Button go = new Button("Increment");
Action onClick = () => { Console.WriteLine("clicked"); };   // block lambda → bind via Action local
go.OnClicked(onClick);                                       // set through a method (cross-zpkg delegate rule)

Panel panel = new Panel("Demo");
panel.Add(new Label("Hello")).Add(go).Add(new Checkbox("On", true)).Add(new Slider(0.0, 100.0, 42.0));

Gui gui = new Gui(panel);
gui.Layout(360, 220);                                        // assign bounds top-down
gui.Update(InputState.At(px, py, false, false, true));      // dispatch a click → hit-test → callback
gui.Paint(new TextDrawBackend());                            // emit the frame's DrawList
```

`Gui` is the retained counterpart to egui's `Context::run`, but the widget objects persist
across frames instead of being rebuilt. `example-widgets` runs exactly this today and dumps
the frame's draw commands through `TextDrawBackend`.

## z42 adaptations (why some shapes differ from egui)

- **No enums** → `DrawCmd` is a class tree with a `Kind` tag (nuklear-style).
- **No `&mut` refs** → `checkbox(&mut bool)` becomes a `Checkbox` object with a public
  `Checked` field + an `OnToggled` callback.
- **Cross-zpkg delegates** → callbacks are set through methods (`OnClicked(Action)`) so the
  delegate crosses as a method argument, never a field assignment (same rule as
  `zaia.ui`'s `VNode.OnClick`); a block-body lambda is bound through an explicit `Action`
  local first (it otherwise infers as `Func<unknown>`).
- **Field/type name clashes** → a field may not share a type's name (a `Style Style` field
  would shadow the `Style` type and break `Style.Dark()`); `Gui` names it `Theme`.

## Status

Builds and **runs today** through `TextDrawBackend`; the live browser path turns on when
`zaia.web`'s `CanvasBackend` gets its VM `__canvas_*` primitives — with no change above the
backend seam.
