# Terminal UI Toolkit

Lip Gloss-inspired style system, layout primitives, interactive components, and CLI SDK for Wippy.

Pure Lua — works on any `terminal.host` process using the `io` module. Two independent surfaces: a TUI framework
with Elm Architecture app runtime for interactive apps, and a CLI SDK for argument parsing, formatted output,
and prompts.

## Features

- **Style builder** — immutable, chainable API with box model, borders, colors, padding, margin, alignment
- **Layout engine** — horizontal/vertical joins, placement, tables, ANSI-aware measurement
- **App runtime** — Elm Architecture (init/update/view) event loop with frame diffing and async commands
- **12 interactive components** — spinner, progress, textinput, textarea, viewport, list, table, tabs, paginator, timer,
  help, multi-progress
- **Theme system** — 8 built-in themes (dracula, catppuccin, nord, tokyo night, gruvbox, solarized, light), custom
  registration
- **CLI SDK** — argument parser, structured output (tables, panels, trees), interactive prompts, progress bars, shell
  completions
- **Color profiles** — truecolor/256/16/none with automatic downsampling and adaptive light/dark support

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  PACKAGE  (butschster/tui)              namespace: tui             │
│                                                                    │
│  Core layers:                                                      │
│    ansi → color → style ─────────────────┐                         │
│    border ──────────┘                    │                         │
│    layout (uses ansi)                    ▼                         │
│    theme                           app runtime                     │
│                                    (io + time modules)             │
│  Components:                                                       │
│    spinner, progress, textinput, textarea, viewport, list,         │
│    table_view, tabs, paginator, timer, help, multi_progress        │
│                                                                    │
│  CLI SDK:                                                          │
│    args, output, prompt, cli_progress, completion                  │
└────────────────────────────────────────────────────────────────────┘
                         ▲
                         │  ns.dependency
                         │
┌────────────────────────────────────────────────────────────────────┐
│  YOUR APP                                                          │
│                                                                    │
│  terminal.host + process.lua                                       │
│  imports: style, color, layout, app, spinner, ...  from tui:*      │
└────────────────────────────────────────────────────────────────────┘
```

## Installation

### 1. Add the dependency

```yaml
# src/_index.yaml
version: "1.0"
namespace: app

entries:
  - name: dep.tui
    kind: ns.dependency
    component: butschster/tui
    version: "*"
```

### 2. Set up a terminal host

The TUI toolkit runs inside a `terminal.host` process. Add the host and a process entry:

```yaml
  # Terminal host — runs one process at a time
  - name: terminal
    kind: terminal.host

  # Your TUI app process
  - name: my_app
    kind: process.lua
    source: file://my_app.lua
    method: main
    modules: [ io, time ]
    imports:
      style: tui:style
      color: tui:color
      layout: tui:layout
      app: tui:app
      spinner: tui:spinner
```

Import only what you need. Each `tui:<name>` entry is independent — you don't have to import the whole toolkit.

### 3. Run

```bash
wippy run -c
```

## Available Libraries

**TUI Framework** — style, layout, and interactive app runtime:

| Entry        | Import Name   | Purpose                                             |
|--------------|---------------|-----------------------------------------------------|
| `tui:ansi`   | `ansi`        | Low-level ANSI sequences, strip/measure/pad strings |
| `tui:color`  | `color`       | Color constructors, profile-aware rendering         |
| `tui:border` | `border_defs` | Named border character sets                         |
| `tui:style`  | `style`       | Immutable style builder with box model + rendering  |
| `tui:layout` | `layout`      | Horizontal/vertical joins, placement, tables        |
| `tui:theme`  | `theme`       | Color theme system (8 built-in + custom)            |
| `tui:app`    | `app`         | Elm Architecture app runtime                        |

**Components** — composable sub-models for `app.run()`:

| Entry                | Import Name      | Purpose                                           |
|----------------------|------------------|---------------------------------------------------|
| `tui:spinner`        | `spinner`        | Animated spinner (14 presets)                     |
| `tui:progress`       | `progress`       | Progress bar with solid/gradient fill             |
| `tui:textinput`      | `textinput`      | Single-line text input with cursor                |
| `tui:textarea`       | `textarea`       | Multi-line text editor with line numbers and undo |
| `tui:viewport`       | `viewport`       | Scrollable content pane with scrollbar            |
| `tui:list`           | `list`           | Item browser with fuzzy filtering and pagination  |
| `tui:table_view`     | `table_view`     | Navigable data table with row selection           |
| `tui:tabs`           | `tabs`           | Tabbed navigation with keyboard switching         |
| `tui:paginator`      | `paginator`      | Page indicator (dots, numeric, arabic)            |
| `tui:timer`          | `timer`          | Countdown timer and stopwatch                     |
| `tui:help`           | `help`           | Key binding display (short/full modes)            |
| `tui:multi_progress` | `multi_progress` | Cross-process progress aggregation                |

**CLI SDK** — works with plain `io` module, no app runtime needed:

| Entry              | Import Name    | Purpose                                         |
|--------------------|----------------|-------------------------------------------------|
| `tui:args`         | `args`         | Argument/option parser with auto `--help`       |
| `tui:output`       | `output`       | Table, panel, definitions, tree, rule renderers |
| `tui:prompt`       | `prompt`       | Interactive prompts (text, password, select)    |
| `tui:cli_progress` | `cli_progress` | Line-based progress bar, spinner, multi-bar     |
| `tui:completion`   | `completion`   | Shell completion generator (bash, zsh, fish)    |

## Quick Start

### Styled output (no app runtime)

```yaml
  - name: my_cli
    kind: process.lua
    source: file://my_cli.lua
    method: main
    modules: [ io ]
    imports:
      style: tui:style
      color: tui:color
      layout: tui:layout
```

```lua
-- my_cli.lua
local io = require("io")
local style = require("style")
local color = require("color")
local layout = require("layout")

local function main()
    -- Inline shortcuts — zero allocation, no box model
    io.print(style.bold("Hello") .. " " .. style.cyan("Wippy"))

    -- Builder pattern (immutable — each call returns a new style)
    local title = style.new()
        :bold()
        :foreground("#fafafa")
        :background("#7b2fff")
        :padding(0, 2)
        :border("rounded")
        :border_foreground(color.cyan)
        :width(40)
        :align("center")

    io.print(title:render("TUI Toolkit"))

    -- Inherit and extend
    local subtitle = title:inherit()
        :bold(false)
        :background(color.hex("#1a1a2e"))

    io.print(subtitle:render("Style system"))

    -- Layout: side-by-side cards
    local card = style.new()
        :border("rounded")
        :border_foreground(color.hex("#6c5ce7"))
        :padding(0, 2)
        :width(20)
        :align("center")

    io.print(layout.horizontal(
        { card:render("Card A"), card:render("Card B\nTwo lines") },
        "center", 1
    ))

    -- Tables
    io.print(layout.table(
        {"Name", "Role", "Status"},
        {
            {"Alice", "Admin", style.green("OK")},
            {"Bob",   "User",  style.yellow("WARN")},
        }
    ))

    return 0
end

return { main = main }
```

### Interactive app (Elm Architecture)

```yaml
  - name: my_tui
    kind: process.lua
    source: file://my_tui.lua
    method: main
    modules: [ io, time ]
    imports:
      app: tui:app
      spinner: tui:spinner
      progress: tui:progress
      help: tui:help
```

```lua
-- my_tui.lua
local app = require("app")
local spinner = require("spinner")
local progress = require("progress")
local help = require("help")

local function main()
    app.run({
        init = function()
            local model = {
                spin = spinner.new({ preset = spinner.DOTS }),
                bar = progress.new({
                    width = 30,
                    gradient_start = "#5A56E0",
                    gradient_end = "#EE6FF8",
                }),
                done = false,
                help = help.new({ bindings = {
                    { key = "q", desc = "quit" },
                }}),
            }
            app.tick(spinner.interval(model.spin))
            return model
        end,

        update = function(model, msg)
            if msg.kind == "key" and msg.key == "q" then app.quit() end
            if msg.kind == "tick" then
                model.spin = spinner.update(model.spin, msg)
                model.bar = progress.incr(model.bar, 0.02)
                if progress.percent(model.bar) >= 1 then
                    model.done = true
                else
                    app.tick(spinner.interval(model.spin))
                end
            end
            return model
        end,

        view = function(model)
            if model.done then
                return "Done!\n\n" .. help.view(model.help)
            end
            return spinner.view(model.spin) .. " Loading... " ..
                   progress.view(model.bar) .. "\n\n" ..
                   help.view(model.help)
        end,
    })
    return 0
end

return { main = main }
```

## API Reference

### style

The main styling API. Every method returns a **new** style — the original is unchanged.

**Constructor & inheritance:**

```lua
local s = style.new()       -- Empty style
local s2 = s:inherit()      -- Independent copy
local s3 = s:copy()         -- Alias for inherit
```

**Text attributes:**

```lua
s:bold()      s:bold(false)
s:italic()    s:dim()         s:underline()
s:strikethrough()             s:reverse()     s:blink()
```

**Colors** — accept Color table, hex `"#ff5500"`, named `"red"`, ANSI256 `"196"`:

```lua
s:foreground("#FF5733")       s:fg(color.cyan)
s:background(color.hex("#1a1a2e"))
s:fg(style.adaptive("#333", "#eee"))  -- light/dark adaptive
```

**Box model:**

```lua
s:width(40)       s:height(10)
s:max_width(80)   s:max_height(20)
s:padding(1)      s:padding(1, 2)       s:padding(1, 2, 1, 2)
s:margin(1)       s:margin(1, 2)        s:margin(1, 2, 1, 2)
s:align("center") s:valign("middle")    s:align("right", "bottom")
```

**Borders:**

```lua
s:border("rounded")          -- "normal", "rounded", "thick", "double", "hidden", "none"
s:border_foreground("#888")
s:border_background("#111")
s:border_top(false)          -- Disable specific sides
s:unicode(false)             -- Force ASCII border fallback
```

**Rendering:**

```lua
local output = s:render("text")   -- Returns styled ANSI string
local output = s("text")          -- Shorthand: __call
```

**Inline shortcuts** (no allocation, no box model):

```lua
style.bold("text")      style.dim("text")       style.italic("text")
style.underline("text") style.strikethrough("text")
style.red("text")       style.green("text")     style.yellow("text")
style.blue("text")      style.magenta("text")   style.cyan("text")
style.color(196, "text")                         -- ANSI 256
style.rgb(255, 128, 0, "text")                   -- Truecolor fg
style.bg_rgb(30, 30, 30, "text")                 -- Truecolor bg
style.strip(ansi_string)                         -- Remove all ANSI
```

### color

```lua
color.none()                    -- Transparent / default
color.ansi(1)                   -- Basic ANSI (0-15)
color.ansi256(196)              -- 256-palette
color.rgb(255, 87, 51)          -- Truecolor
color.hex("#FF5733")            -- Hex (also "#f53", "FF5733")
color.adaptive("#333", "#eee")  -- Light/dark background
color.resolve("red")            -- String -> Color (named, hex, ansi256)

-- Named constants
color.red  color.green  color.yellow  color.blue
color.cyan color.magenta color.white  color.black
color.bright_red  ... color.bright_white

-- Profile control
color.set_profile("truecolor")  -- "truecolor", "256", "16", "none"
color.set_dark_background(true)
```

### layout

```lua
layout.horizontal({a, b, c}, "center", 1)  -- Side-by-side, gap=1
layout.vertical({a, b, c}, "center", 1)    -- Stacked, gap=1
layout.place(80, 24, "center", "middle", content)
layout.width(s)     layout.height(s)    layout.size(s) -- returns w, h
layout.table(headers, rows)
```

### ansi

Low-level ANSI primitives. Most users won't need this directly — `style` and `layout` use it internally.

```lua
ansi.strip(s)              -- Remove ANSI escapes
ansi.visible_width(s)      -- Visual width ignoring escapes
ansi.lines(s)              -- Split into line array
ansi.max_width(s)          -- Widest line
ansi.height(s)             -- Line count
ansi.pad_right(s, w)       ansi.pad_left(s, w)     ansi.pad_center(s, w)
```

### border

```lua
border.normal   border.rounded   border.thick    border.double
border.block    border.hidden    border.none     border.ascii
border.inner_half_block          border.outer_half_block
border.get("rounded")            border.styles()  -- list all names
```

### theme

8 built-in themes: `default`, `dracula`, `catppuccin`, `nord`, `tokyo_night`, `gruvbox`, `solarized_dark`, `light`.

Each theme provides semantic color slots: `bg`, `fg`, `primary`, `secondary`, `accent`, `muted`, `border`,
`success`, `warning`, `error`, `info`, `highlight`, `surface`.

```lua
local theme = require("theme")

local t = theme.get("dracula")
local title_style = style.new():foreground(t.primary):bold()
local error_style = style.new():foreground(t.error)

-- List available themes
theme.list()  -- {"catppuccin", "default", "dracula", "gruvbox", ...}

-- Register custom theme
theme.register("my_theme", {
    name = "My Theme", dark = true,
    bg = "#1a1b26", fg = "#c0caf5", primary = "#7aa2f7",
    secondary = "#7dcfff", accent = "#bb9af7", muted = "#565f89",
    border = "#3b4261", success = "#9ece6a", warning = "#e0af68",
    error = "#f7768e", info = "#2ac3de",
    highlight = "#292e42", surface = "#24283b",
})

-- Merge overrides onto a base theme
local custom = theme.merge(theme.get("nord"), { error = "#ff0000" })
```

### app

Elm Architecture runtime. One app per `terminal.host` process.

```lua
app.run({
    init = function()
        -- Return initial model. Call app.tick() / app.cmd() here.
        return { count = 0 }
    end,
    update = function(model, msg)
        -- msg.kind: "key", "tick", "custom", "resize"
        -- msg.key: key name for key events
        if msg.kind == "key" and msg.key == "q" then app.quit() end
        return model
    end,
    view = function(model)
        -- Return a string. Only changed frames are redrawn.
        return "Count: " .. model.count
    end,
    alt_screen = true,  -- Use alternate screen buffer (default: true)
})
```

**Side effects:**

```lua
app.quit()                     -- Exit after current update cycle
app.tick("80ms")               -- Schedule a {kind="tick"} message
app.cmd(function()             -- Async command (runs in coroutine)
    return {kind="custom", type="loaded", data=result}
end)
app.batch(fn1, fn2, fn3)      -- Multiple concurrent commands
```

## Components

All components follow the **sub-model pattern**: `new(opts)`, `update(model, msg)`, `view(model)`.
Embed them in your app model and delegate messages in `update()`.

### spinner

```lua
-- Presets: DOTS, LINE, MINI_DOTS, JUMP, PULSE, GLOBE, MOON, MONKEY,
--          METER, HAMBURGER, ELLIPSIS, POINTS, ARROW, BOUNCING_BAR

local s = spinner.new()                          -- default DOTS
local s = spinner.new({ preset = spinner.MOON }) -- custom preset
local s = spinner.new({ frames = {"*","o","O"}, interval = "80ms" })

s = spinner.update(s, msg)       -- advance on {kind="tick"}
spinner.view(s)                  -- current frame
spinner.interval(s)              -- "80ms" (pass to app.tick())
spinner.set_style(s, my_style)   -- apply style to frame
spinner.reset(s)                 -- back to frame 1
```

### progress

```lua
local p = progress.new({ width = 40 })
local p = progress.new({
    width = 50,
    gradient_start = "#5A56E0",
    gradient_end = "#EE6FF8",
    show_percent = true,
})

p = progress.set(p, 0.75)       -- set to 75%
p = progress.incr(p, 0.01)      -- increment by 1%
progress.percent(p)              -- 0.76
progress.view(p)                 -- "████████████████████████████░░░░  76%"
```

### textinput

```lua
local ti = textinput.new({
    placeholder = "Enter name...",
    prompt = "> ",
    char_limit = 50,
    -- password = true,
})

ti = textinput.update(ti, msg)   -- handles key events
textinput.view(ti)               -- "> John|doe"
textinput.value(ti)              -- "Johndoe"
textinput.focus(ti)              -- enable input
textinput.blur(ti)               -- disable input
textinput.reset(ti)              -- clear value
```

Keys: printable chars, backspace, delete, left/right, home/end, ctrl+a/e/k/u/w (readline-style).

### textarea

Multi-line text editor with line numbers, scrolling, word wrap, and undo.

```lua
local ta = textarea.new({
    width = 80,
    height = 20,
    placeholder = "Type here...",
    show_line_numbers = true,
    word_wrap = true,
    undo_limit = 100,
})

ta = textarea.update(ta, msg)
textarea.view(ta)
textarea.value(ta)               -- full text content
textarea.set_value(ta, text)     -- replace content
textarea.cursor_pos(ta)          -- row, col
textarea.line_count(ta)
textarea.focus(ta) / textarea.blur(ta)
textarea.reset(ta)
```

### viewport

Scrollable content pane with optional scrollbar.

```lua
local vp = viewport.new({ width = 80, height = 20, word_wrap = true })
vp = viewport.set_content(vp, long_text)
vp = viewport.append(vp, more_text, true)  -- auto-scroll to bottom

vp = viewport.update(vp, msg)
viewport.view(vp)
viewport.view_with_scrollbar(vp)
viewport.scroll_percent(vp)         -- 0.0-1.0
viewport.at_top(vp) / viewport.at_bottom(vp)
```

Keys: up/k, down/j, pgup/ctrl+b, pgdn/ctrl+f, home/g, end/G, ctrl+u/d (half page).

### list

Item browser with fuzzy filtering, pagination, and custom rendering.

```lua
local l = list.new({
    items = {
        { title = "Apples",  desc = "Red fruit" },
        { title = "Bananas", desc = "Yellow fruit" },
    },
    height = 10,
    filterable = true,
    filter_prompt = "Filter: ",
})

l = list.update(l, msg)
list.view(l)
list.selected(l)                 -- selected item table
list.selected_index(l)           -- original index
list.filter(l)                   -- current filter text
list.is_filtering(l)             -- filter input active?
list.set_items(l, new_items)     -- replace items
list.set_title(l, "Fruits")
```

Items must have a `title` field. Optional `desc` for description.

### table_view

Navigable data table with row selection and column alignment.

```lua
local tv = table_view.new({
    columns = {
        { key = "name",   title = "Name",   width = 20 },
        { key = "status", title = "Status",  width = 10, align = "center" },
        { key = "uptime", title = "Uptime",  width = 15, align = "right" },
    },
    rows = {
        { name = "web-1", status = "running", uptime = "3d 12h" },
        { name = "web-2", status = "stopped", uptime = "--" },
    },
    height = 10,
})

tv = table_view.update(tv, msg)
table_view.view(tv)
table_view.selected(tv)         -- selected row table
table_view.selected_index(tv)
table_view.set_rows(tv, new_rows)
```

### tabs

```lua
local t = tabs.new({
    items = { "General", "Logs", "Config" },
    use_numbers = true,   -- 1/2/3 keys to switch
})

t = tabs.update(t, msg)
tabs.view(t)                    -- "[ General ] | Logs | Config"
tabs.view_underline(t)          -- underline indicator variant
tabs.active(t)                  -- 1 (1-based index)
tabs.active_label(t)            -- "General"
tabs.next(t) / tabs.prev(t)    -- wraps around
```

Keys: left/h, right/l, 1-9 (with `use_numbers`), home, end.

### paginator

```lua
local pg = paginator.new({
    total = 10,
    mode = paginator.DOTS,    -- DOTS, NUMERIC, or ARABIC
    per_page = 5,             -- for slice() calculations
})

pg = paginator.update(pg, msg)
paginator.view(pg)                    -- "● ○ ○ ○ ○ ○ ○ ○ ○ ○"
paginator.page(pg)                    -- 1
paginator.next_page(pg) / paginator.prev_page(pg)
local start, finish = paginator.slice(pg, total_items)
paginator.set_total_from_items(pg, item_count)
```

### timer

```lua
-- Countdown timer
local t = timer.new({ duration = "5m", interval = "1s", auto_start = true })
t = timer.update(t, msg)
timer.view(t)                   -- "04:59"
timer.remaining(t)              -- ms remaining
timer.is_done(t)
timer.start(t) / timer.stop(t) / timer.toggle(t) / timer.reset(t)

-- Stopwatch
local sw = stopwatch.new({ interval = "100ms" })
sw = stopwatch.start(sw)
sw = stopwatch.update(sw, msg)
stopwatch.view(sw)              -- "00:03.2"
stopwatch.elapsed(sw)           -- ms elapsed
sw = stopwatch.lap(sw)
stopwatch.laps(sw)              -- array of lap times
```

Both export `interval(model)` — pass to `app.tick()`.

### help

```lua
local h = help.new({
    bindings = {
        { key = "up/k",  desc = "scroll up" },
        { key = "down/j", desc = "scroll down" },
        help.SEPARATOR,
        { key = "q", desc = "quit" },
        { key = "?", desc = "toggle help" },
    },
    width = 60,
})

help.view(h)          -- short: "up/k scroll up . down/j scroll down . q quit"
h = help.toggle(h)
help.view(h)          -- full: multi-line, aligned, grouped
```

### multi_progress

Aggregates progress from spawned worker processes via message passing.

```lua
local mp = multi_progress.new({
    width = 40,
    show_percent = true,
    topic = "progress",   -- inbox message topic to listen for
})

mp = multi_progress.register(mp, worker_pid, "Worker 1")
mp = multi_progress.handle_message(mp, msg)   -- process inbox messages
multi_progress.view(mp)
multi_progress.overall_percent(mp)
multi_progress.all_done(mp)
```

Workers send progress updates via `process.send(parent, "progress", { percent = 0.5 })`.

## CLI SDK

The CLI SDK works with the plain `io` module — no app runtime needed. Use it for non-interactive
command-line tools.

### args

```yaml
  - name: my_command
    kind: process.lua
    source: file://deploy.lua
    method: main
    modules: [ io ]
    imports:
      args: tui:args
      output: tui:output
      prompt: tui:prompt
```

```lua
local args = require("args")
local io = require("io")

local def = args.define({
    name = "deploy",
    description = "Deploy the application to a target environment",
    arguments = {
        { name = "environment", description = "Target environment",
          required = true, choices = {"staging", "production"} },
    },
    options = {
        { name = "force",    short = "f", type = "boolean", description = "Skip confirmation" },
        { name = "tag",      short = "t", type = "string",  description = "Image tag", default = "latest" },
        { name = "replicas", short = "r", type = "number",  description = "Replica count", default = 1 },
    },
    examples = {
        "deploy staging",
        "deploy production --tag v2.1.0 -r 3 -f",
    },
})

local parsed, err = args.parse(def, io.args())
if parsed and parsed.help then
    io.print(args.help(def))
    return 0
end
if err then
    io.eprint("Error: " .. err)
    io.print(args.help(def))
    return 1
end

-- Access parsed values
local env = parsed.arguments.environment     -- "staging"
local tag = parsed.options.tag               -- "v2.1.0"
local force = parsed.options.force           -- true
args.has_option(parsed, "replicas")          -- true if explicitly set
```

Supports: positional arguments (`required`, `choices`, `default`), long options (`--name`, `--name=value`),
short options (`-f`, `-fv` combined), boolean negation (`--no-force`), `--` separator for rest args,
types (`string`, `number`, `integer`, `boolean`), auto `--help`/`-h`.

### output

Structured output renderers.

```lua
local output = require("output")

-- Table with borders
io.print(output.table(
    {"Name", "Status", "Uptime"},
    {
        {"web-1", "running", "3d 12h"},
        {"web-2", "stopped", "--"},
    },
    { border = "rounded", padding = 1, max_width = 60 }
))

-- Panel with title
io.print(output.panel("Deployed successfully!", {
    title = "Deploy",
    border = "rounded",
    border_color = "#6c5ce7",
    title_color = "#00b894",
}))

-- Definitions list (key-value pairs)
io.print(output.definitions({
    {"Version", "2.1.0"},
    {"Environment", "production"},
}, { key_color = "cyan", separator = " -> " }))

-- Tree structure
io.print(output.tree({
    label = "src/",
    children = {
        { label = "api/", children = {
            { label = "users.lua" },
        }},
    }
}))

-- Horizontal rule
io.print(output.rule({ width = 60, title = "Section", color = "#888" }))
```

### prompt

Interactive prompts. Requires `prompt.set_io(io)` before use.

```lua
local prompt = require("prompt")
prompt.set_io(io)

local name = prompt.text("Your name", { default = "World", required = true })
local pass = prompt.password("Password", { confirm = true })
local ok = prompt.confirm("Deploy to production?", { default = false })

-- Single select (numbered list)
local env = prompt.select("Target environment", {
    "development", "staging", "production",
}, { default = 2 })

-- Select with labels and values
local db = prompt.select("Database", {
    { label = "PostgreSQL", value = "postgres" },
    { label = "SQLite",     value = "sqlite" },
})

-- Multi-select (comma-separated numbers or ranges: "1,3-4")
local features = prompt.multiselect("Enable features", {
    "caching", "logging", "metrics", "tracing",
}, { defaults = {1, 2}, min = 1 })
```

### cli_progress

Line-based progress indicators using `\r` to overwrite the current line.

```lua
local cli_progress = require("cli_progress")

-- Progress bar
local bar = cli_progress.bar({ total = 100, width = 30, message = "Downloading" })
for i = 1, 100 do
    cli_progress.update(bar, i)
    cli_progress.render(bar, io)
end
cli_progress.finish(bar, io, "Download complete!")

-- Spinner
local spin = cli_progress.spinner({ message = "Processing..." })
for i = 1, 50 do
    cli_progress.tick_spinner(spin)
    cli_progress.render_spinner(spin, io)
end
cli_progress.finish_spinner(spin, io, "Done!")

-- Multi-bar (multiple named progress bars)
local multi = cli_progress.multi()
cli_progress.add_bar(multi, "download", { total = 100, message = "Downloading" })
cli_progress.add_bar(multi, "extract",  { total = 50,  message = "Extracting" })
for i = 1, 100 do
    cli_progress.update_bar(multi, "download", i)
    if i > 30 then
        cli_progress.update_bar(multi, "extract", math.min(50, i - 30))
    end
    cli_progress.render_multi(multi, io)
end
cli_progress.finish_multi(multi, io)
```

### completion

Generate shell completions from `args.define()` definitions.

```lua
local completion = require("completion")

-- Single command
local script = completion.bash(def, "myapp")
local script = completion.zsh(def, "myapp")
local script = completion.fish(def, "myapp")

-- Multi-command CLI
local script = completion.bash_multi({deploy_def, status_def}, "myapp")
local script = completion.fish_multi({deploy_def, status_def}, "myapp")
```

## Design Decisions

- **Immutable styles** — every method returns a new style. Safe to share, extend, compose.
- **Profile-aware colors** — hex/RGB colors auto-downsample to 256/16/none based on `color._profile`.
- **ANSI-aware measurement** — `ansi.visible_width()` strips escapes for correct width calculation. Layout joins use
  this to align multi-line blocks correctly.
- **ASCII fallback** — `style:unicode(false)` switches borders to `+`, `-`, `|` characters.
- **Adaptive colors** — `color.adaptive(light, dark)` picks based on `color._dark_background`.
- **Composable components** — sub-model pattern (new/update/view) embeds into any `app.run()`.
- **CLI SDK decoupled from TUI** — args, output, prompts work with plain `io` module. No app runtime needed.

## License

MIT
