# Description (`zaia.ui`)

The description layer is where you write your UI. It answers one question —
*what is on screen, and how does it change with data?* — and nothing else. It has
no renderer, no DOM, no lifecycle. That purity is what lets the same description
run in the browser, on the server (SSR), or in a test.

## Pieces

| Type | Role |
|------|------|
| `Component` | The unit of UI. Override `Render() -> VNode` to describe the view. |
| `VNode` | Node description: `Tag`, `Text`, `Children`, a string **`Attributes`** bag, and an **`Events`** bag (event name → `Action`). Fluent `Attr`/`Class`/`Id`/`On`/`OnClick`/`OnInput`/`Add`. `H` builds them. |
| `H` | Element factory — `El`/`Leaf`/`Text` primitives + sugars (`Div`, `Span`, `P`, `Ul`, `Li`, `H1..3`, `Button`, `A(href,text)`, `Input(type,ph)`, …). |
| `State<T>` | The **data-update** primitive. A cell you read in `Render()` and mutate to update the view. |
| `UiDispatch` / `ChangeListener` | The change-signal seam: the description fires; the app listens. |

Modeled after **React / hyperscript**: `Render()` returns a pure `VNode` tree from the
component's data, `H` is the element factory, and nodes carry attributes + event handlers.

## Describe the view

```z42
using Zaia.Ui;

class Counter : Component {
    State<int> _count = new State<int>(0);

    override VNode Render() {
        return H.Div(
            H.H1("Count: " + _count.Get().ToString()),
            H.Button("Increment").OnClick(() => _count.Set(_count.Get() + 1))
        );
    }
}
```

`Render()` is a pure function of the component's data: given the current `State`
values, it returns a `VNode` tree. It never touches the screen — it just describes
what the screen should be.

## Describe data updates

`State<T>` is the seam between "data" and "view":

```z42
public class State<T> {
    public State(T initial);
    public T Get();              // read in Render()
    public void Set(T value);    // mutate → fires a change signal
}
```

Calling `Set` updates the value and fires `UiDispatch.NotifyChanged`. That is the
**entire** contract the description makes with the outside world: "my data changed."
It does not re-render, it does not know a renderer exists. (You can also signal
manually with `Component.StateChanged()` if you mutate a plain field.)

## The change-signal seam

```z42
public abstract class ChangeListener { public abstract void OnChanged(); }

public static class UiDispatch {
    public static ChangeListener Listener;             // registered by the app
    public static void NotifyChanged(Component c);      // fired by State / StateChanged
}
```

The app registers a `ChangeListener` that re-renders (see [app-host.md](app-host.md)).
The seam is a **nominal class**, not a delegate, for two reasons: a named type crosses
the zpkg boundary cleanly (a structural func type does not), and it keeps the
description layer importing nothing from the renderer.

## Why keep description separate

- **One description, many targets.** The same `Component` renders to the DOM, to an
  HTML string (SSR), or to a test backend — because it only describes.
- **Testable in isolation.** Assert on the `VNode` a component returns for given
  `State`; no renderer, no browser.
- **Stable API.** When the renderer grows tree-diffing, or a new backend appears, the
  description layer — the code app authors actually write — does not change.
