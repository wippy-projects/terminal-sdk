# CLAUDE.md — Terminal UI Toolkit (butschster/tui)

## Project Overview

A **pure Lua** Terminal UI toolkit for the [Wippy](https://wippy.ai) platform. Inspired by Go's [Lip Gloss](https://github.com/charmbracelet/lipgloss), it provides an immutable style builder, layout primitives, ANSI rendering, interactive components, and a CLI SDK. No Go-side runtime changes required — works on any `terminal.host` process using the `io` module.

**Organization:** `butschster` | **Module namespace:** `wippy.tui` | **License:** MIT

## Repository Structure

```
terminal-sdk/
├── wippy.yaml          # Module manifest (org, module name, description, keywords)
├── wippy.lock          # Lock file (directories config: modules → .wippy, src → ./src)
├── README.md           # Full API reference and usage examples
├── CLAUDE.md           # This file
└── src/
    ├── _index.yaml     # Entry registry — declares all libraries, their imports, and modules
    ├── ansi.lua        # Low-level ANSI escape sequences, string measurement, cursor/screen ops
    ├── color.lua       # Color system: named, ANSI16, ANSI256, hex, RGB, adaptive, profile-aware
    ├── border.lua      # Border character sets (normal, rounded, thick, double, block, etc.)
    ├── style.lua       # Immutable style builder with box model, colors, borders, alignment
    ├── layout.lua      # Layout primitives: horizontal/vertical joins, placement, table
    ├── app.lua         # Elm Architecture (MVU) app runtime with event loop & frame diffing
    ├── theme.lua       # Theme system: 8 built-in themes + custom registration
    ├── components/
    │   ├── spinner.lua        # Animated spinner (14 presets)
    │   ├── progress.lua       # Progress bar (solid/gradient fill)
    │   ├── textinput.lua      # Single-line text input with cursor
    │   ├── textarea.lua       # Multi-line text editor with undo
    │   ├── viewport.lua       # Scrollable content pane with scrollbar
    │   ├── help.lua           # Key binding display (short/full modes)
    │   ├── list.lua           # Item browser with fuzzy filtering & pagination
    │   ├── table_view.lua     # Navigable data table with row selection
    │   ├── tabs.lua           # Tabbed navigation
    │   ├── paginator.lua      # Page indicator (dot/numeric/arabic)
    │   ├── timer.lua          # Countdown/stopwatch component
    │   ├── multi_progress.lua # Cross-process progress aggregator
    │   └── filepicker.lua     # Placeholder — pending filesystem API (Stage 6)
    └── cli/
        ├── args.lua           # CLI argument/option parser with auto --help
        ├── output.lua         # Structured output: table, panel, definitions, tree, rule
        ├── prompt.lua         # Interactive prompts: text, password, confirm, select, multiselect
        ├── cli_progress.lua   # Line-based progress bar, spinner, multi-bar
        └── completion.lua     # Shell completion generator (bash, zsh, fish)
```

## Wippy Module System

### Key Files

- **`wippy.yaml`** — Module manifest declaring the organization (`butschster`), module name (`tui`), description, license, and keywords.
- **`wippy.lock`** — Specifies directory layout: modules download to `.wippy/`, source lives in `./src/`.
- **`src/_index.yaml`** — The entry registry. Every library in the module is declared here with its `kind`, `source`, `modules` (runtime dependencies like `io`, `time`), and `imports` (other `wippy.tui:*` libraries).

### How Imports Work

Libraries declare dependencies via `imports` in `_index.yaml`. At runtime, each library uses `require()` with the import name:

```yaml
# In _index.yaml
- name: style
  kind: library.lua
  source: file://style.lua
  imports:
    ansi: wippy.tui:ansi        # require("ansi")
    color: wippy.tui:color      # require("color")
    border_defs: wippy.tui:border  # require("border_defs")
```

```lua
-- In style.lua
local ansi = require("ansi")
local color_mod = require("color")
local border_defs = require("border_defs")
```

### Consumer Usage

Consumers add a `ns.dependency` entry in their own `_index.yaml`, then import specific libraries:

```yaml
entries:
  - name: dep.tui
    kind: ns.dependency
    component: butschster/tui
    version: "*"
  - name: my_app
    kind: process.lua
    source: file://app.lua
    method: main
    modules: [ io ]
    imports:
      style: wippy.tui:style
      color: wippy.tui:color
```

## Language & Runtime

- **Language:** Lua (Wippy's embedded Lua runtime)
- **Type annotations:** Lua-style inline type hints (e.g., `function foo(n: integer): string`)
- **Concurrency:** Coroutines via `coroutine.spawn()`, channels via `channel.new()` / `channel.select()`
- **Runtime modules:** `io` (terminal I/O), `time` (timers), `process` (spawn, events, inbox)
- **No external dependencies** — all functionality is self-contained within this module

## Architecture & Design Patterns

### Immutable Builder Pattern (style.lua)

Every style method returns a **new** style object. The original is never mutated. This makes styles safe to share, inherit, and compose:

```lua
local base = style.new():bold():foreground("#fafafa")
local title = base:inherit():background("#7b2fff"):padding(0, 1)
-- `base` is unchanged
```

Internally, each method calls `clone(self)`, modifies the clone, and returns it.

### Composable Sub-Model Pattern (components)

All components follow the Elm Architecture sub-model pattern:
- `new(opts)` — create a component model
- `update(model, msg)` — handle messages, return updated model
- `view(model)` — render to string

Components are embedded in a parent `app.run()` model and messages are delegated:

```lua
update = function(model, msg)
    model.spin = spinner.update(model.spin, msg)
    return model
end
```

### Elm Architecture App Runtime (app.lua)

The app runtime manages: init → event loop → update → view → frame diff → render.

- **Event sources:** terminal input, commands (`app.cmd`), ticks (`app.tick`), process inbox, process events
- **Frame diffing:** Line-level diff against previous frame for minimal terminal output
- **Side effects:** `app.cmd(fn)` runs async functions via coroutine; results delivered as messages
- **One-shot ticks:** `app.tick(duration)` delivers `{kind = "tick"}`; must be re-called to repeat

### Color Profile System (color.lua)

Colors auto-downsample based on the active profile:
- `truecolor` → full RGB
- `256` → ANSI 256-palette approximation
- `16` → basic ANSI colors
- `none` → no color output

Adaptive colors (`color.adaptive(light, dark)`) select based on `color._dark_background`.

### Theme System (theme.lua)

8 built-in themes with semantic color slots: `bg`, `fg`, `primary`, `secondary`, `accent`, `muted`, `border`, `success`, `warning`, `error`, `info`, `highlight`, `surface`. Custom themes via `theme.register()`.

## Code Conventions

### Naming
- **snake_case** for all function names, variable names, and table keys
- **UPPER_CASE** for constants (e.g., `ansi.BOLD`, `spinner.DOTS`, `color.PROFILE_TRUECOLOR`)
- **Private fields** prefixed with underscore (e.g., `self._bold`, `self._fg`, `_quit_requested`)
- **Module-local functions** use `local function name()` (not added to the module table)

### Module Structure
Each `.lua` file follows this pattern:
1. Doc comment block (`---` comments) describing the module and usage
2. `require()` statements for dependencies
3. Module table creation: `local mod = {}`
4. Constants section
5. Internal/private helpers as `local function`
6. Public API as `function mod.name()`
7. Metatable methods as `function MT:name()` (for OOP-style APIs)
8. `return mod`

### Documentation
- **LuaDoc-style** triple-dash comments (`---`) for public functions
- Section headers using horizontal rule comment blocks:
  ```lua
  ---------------------------------------------------------------------------
  -- Section Name
  ---------------------------------------------------------------------------
  ```
- Type annotations in function signatures: `function foo(x: string, y: integer?): boolean`

### Error Handling
- Functions return `value, err` pairs for fallible operations (e.g., `args.parse()`)
- `assert()` for required configuration (e.g., `app.run` requires `init`, `update`, `view`)
- `pcall()` wrapping for user-provided callbacks in the app runtime

### Immutability
- Style objects are immutable — every setter clones before modifying
- Component models are treated as values — `update()` returns a new/modified model
- Arrays are shallow-copied when cloning (`shallow_copy_array`)

## Dependency Graph

```
ansi (no deps)
  ├── color → ansi
  ├── layout → ansi
  ├── app → ansi, io, time
  ├── viewport → ansi
  ├── help → ansi
  └── output → ansi, color, border
border (no deps)
  └── style → ansi, color, border
theme (no deps)
spinner, progress, textinput, list, table_view, textarea, timer,
  multi_progress, tabs, paginator (no deps — standalone components)
args, prompt, cli_progress (no deps — CLI SDK standalone)
completion (no deps)
```

## Key Libraries Quick Reference

| Library | Import | Key Functions |
|---------|--------|--------------|
| `ansi` | `wippy.tui:ansi` | `strip()`, `visible_width()`, `lines()`, `pad_right/left/center()`, `parse_mouse_sgr()` |
| `color` | `wippy.tui:color` | `hex()`, `rgb()`, `adaptive()`, `resolve()`, `fg()`, `bg()`, `set_profile()` |
| `border` | `wippy.tui:border` | `get(name)`, `styles()`, named sets: `.normal`, `.rounded`, `.thick`, `.double` |
| `style` | `wippy.tui:style` | `new()`, `:bold()`, `:fg()`, `:border()`, `:padding()`, `:width()`, `:render()` |
| `layout` | `wippy.tui:layout` | `horizontal()`, `vertical()`, `place()`, `table()`, `width()`, `height()` |
| `app` | `wippy.tui:app` | `run(opts)`, `quit()`, `cmd(fn)`, `batch()`, `tick(duration)` |
| `theme` | `wippy.tui:theme` | `get(name)`, `register(name, t)`, `list()`, `merge(base, overrides)` |

## Adding a New Library

1. Create the `.lua` file in `src/` (or `src/components/` / `src/cli/`)
2. Follow the module structure convention (doc comment, requires, table, API, return)
3. Register it in `src/_index.yaml` with:
   - `name`: the import identifier
   - `kind`: `library.lua`
   - `source`: `file://path/to/file.lua`
   - `modules`: runtime modules needed (e.g., `[io]`, `[time]`)
   - `imports`: other `wippy.tui:*` libraries needed
4. Update `README.md` with API documentation

## Adding a New Component

Components go in `src/components/` and must implement:
- `component.new(opts)` — returns a model table
- `component.update(model, msg)` — handles messages, returns updated model
- `component.view(model)` — returns a rendered string

Register in `_index.yaml` under the Components section. Most components have no `modules` or `imports` — they are self-contained.

## Known Limitations / In Progress

- **filepicker.lua** is a placeholder pending filesystem API finalization (Stage 6)
- **Terminal input** currently uses cooked-mode line reader (`io.readline()`); raw mode is planned (Stage 1)
- **Mouse support** is wired in `app.lua` with SGR mouse parsing in `ansi.lua`, but depends on Go-side raw mode
- **No test framework** is currently configured in the repository
