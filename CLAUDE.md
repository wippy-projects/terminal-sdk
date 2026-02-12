# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Wippy module (`butschster/tui`) providing a Lip Gloss-inspired terminal UI toolkit in pure Lua. Published as namespace
`tui`. This is a **library**, not an application — there is no HTTP server or main entrypoint. Consumers import
individual entries (e.g., `tui:style`) in their own `_index.yaml`.

## Commands

```bash
wippy lint                    # Lint (errors + warnings)
wippy lint --level hint       # All diagnostics
wippy update                  # Regenerate wippy.lock after adding/removing files in src/
```

There is no `wippy run` for this project — it's a library consumed by other projects.

## Architecture

### Entry System

`src/_index.yaml` declares all library entries under the `tui` namespace. Every entry has `kind: library.lua` (not
`function.lua` or `process.lua` like HTTP projects). Entries reference each other via `imports:` and built-in Wippy
modules via `modules:`.

### Layer Dependency Graph

```
ansi          ← lowest level: raw ANSI escape sequences, string measurement
  ↑
color         ← color constructors, profile-aware downsampling (truecolor → 256 → 16 → none)
  ↑
border        ← named border character sets (standalone, no deps)
  ↑
style         ← immutable builder with box model, colors, borders, rendering (depends on ansi, color, border)
  ↑
layout        ← spatial composition: horizontal/vertical joins, placement, tables (depends on ansi only)
  ↑
app           ← Elm Architecture runtime: event loop, message dispatch, frame diffing (depends on ansi + io/time modules)
```

Components (`src/components/`) and CLI SDK (`src/cli/`) sit above these layers.

### Two SDK Surfaces

1. **TUI Framework** (`style`, `layout`, `app`, components) — for interactive terminal apps using the Elm Architecture (
   `init`/`update`/`view`). Components follow the sub-model pattern: `new(opts)` → `update(model, msg)` → `view(model)`.

2. **CLI SDK** (`args`, `output`, `prompt`, `cli_progress`, `completion`) — for non-interactive CLI tools. Works with
   plain `io` module, no app runtime needed.

### Key Design Patterns

- **Immutable styles** — every method on a style returns a new style; safe to share and extend.
- **Profile-aware colors** — hex/RGB auto-downsample based on `color._profile`. Use `color.set_profile()` to change.
- **ANSI-aware measurement** — always use `ansi.visible_width()` for width calculations; raw `#string` includes escape
  sequences.
- **Sub-model composition** — components embed into `app.run()` models. Delegate `msg` to sub-component `update()`, call
  sub-component `view()` in your `view()`.

### Incomplete / Placeholder

- `src/components/filepicker.lua` — placeholder, pending filesystem API (Stage 6).

## Wippy Documentation

- Docs: https://home.wj.wippy.ai/
- LLM index: https://home.wj.wippy.ai/llms.txt
- Batch fetch: `https://home.wj.wippy.ai/llm/context?paths=<comma-separated-paths>`
- Search: `https://home.wj.wippy.ai/llm/search?q=<query>`
