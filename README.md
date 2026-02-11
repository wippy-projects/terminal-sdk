# butschster/tui — Terminal UI Toolkit

Lip Gloss-inspired style system, layout primitives, and ANSI rendering for Wippy.

Pure Lua — no Go-side runtime changes required. Works today on any `terminal.host` process using the `io` module.

## Module Structure

```
terminal-sdk/
├── wippy.yaml              # Module manifest
├── wippy.lock
└── src/
    ├── _index.yaml         # Entry definitions (namespace: wippy.tui)
    ├── ansi.lua            # ANSI escape primitives, string measurement
    ├── color.lua           # Color system (named, ANSI 256, hex, adaptive)
    ├── border.lua          # Border character sets
    ├── style.lua           # Declarative style builder (main API)
    ├── layout.lua          # Layout joins, placement, measurement, tables
    ├── app.lua             # Elm Architecture app runtime
    ├── components/
    │   ├── spinner.lua     # Animated activity indicator (14 presets)
    │   ├── progress.lua    # Progress bar (solid/gradient)
    │   ├── textinput.lua   # Single-line text input with cursor
    │   ├── viewport.lua    # Scrollable content pane
    │   └── help.lua        # Key binding display
    └── cli/
        ├── args.lua        # Argument & option parser with help generation
        ├── output.lua      # Table, panel, definitions, tree, rule
        ├── prompt.lua      # Interactive prompts (text, confirm, select)
        └── cli_progress.lua # Line-based progress bar, spinner, multi-bar
```

## Libraries

**TUI Framework** — style, layout, and interactive app runtime:

| Entry                  | Import Name     | Purpose                                             |
|------------------------|-----------------|-----------------------------------------------------|
| `wippy.tui:ansi`       | `ansi`          | Low-level ANSI sequences, strip/measure/pad strings |
| `wippy.tui:color`      | `color`         | Color constructors, profile-aware rendering         |
| `wippy.tui:border`     | `border_defs`   | Named border character sets                         |
| `wippy.tui:style`      | `style`         | Immutable style builder with box model + rendering  |
| `wippy.tui:layout`     | `layout`        | Horizontal/vertical joins, placement, tables        |
| `wippy.tui:app`        | `app`           | Elm Architecture app runtime                        |
| `wippy.tui:spinner`    | `spinner`       | Animated spinner component (14 presets)             |
| `wippy.tui:progress`   | `progress`      | Progress bar with solid/gradient fill               |
| `wippy.tui:textinput`  | `textinput`     | Single-line text input with cursor                  |
| `wippy.tui:viewport`   | `viewport`      | Scrollable content pane with scrollbar              |
| `wippy.tui:help`       | `help`          | Key binding display (short/full modes)              |

**CLI SDK** — argument parsing, output formatting, prompts, and progress:

| Entry                      | Import Name      | Purpose                                         |
|----------------------------|------------------|-------------------------------------------------|
| `wippy.tui:args`           | `args`           | Argument/option parser with auto `--help`       |
| `wippy.tui:output`         | `output`         | Table, panel, definitions, tree, rule renderers |
| `wippy.tui:prompt`         | `prompt`         | Interactive prompts (text, password, select)     |
| `wippy.tui:cli_progress`   | `cli_progress`   | Line-based progress bar, spinner, multi-bar     |

## Quick Example

```yaml
# Consumer _index.yaml
entries:
  - name: __dependency.tui
    kind: ns.dependency
    component: butschster/tui
    version: "*"

  - name: my_cli
    kind: process.lua
    source: file://cli.lua
    method: main
    modules: [ io ]
    imports:
      style: wippy.tui:style
      color: wippy.tui:color
      layout: wippy.tui:layout
```

```lua
-- cli.lua
local io = require("io")
local style = require("style")
local color = require("color")
local layout = require("layout")

local function main()
    -- Inline shortcuts
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

    local a = card:render("Card A")
    local b = card:render("Card B\nTwo lines")
    io.print(layout.horizontal({a, b}, "center", 1))

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

## API Reference

### style (main API)

**Constructor & inheritance:**

```lua
local s = style.new()       -- Empty style
local s2 = s:inherit()      -- Independent copy
local s3 = s:copy()         -- Alias for inherit
```

**Text attributes** (each returns a new style):

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
color.ansi(1)                   -- Basic ANSI (0–15)
color.ansi256(196)              -- 256-palette
color.rgb(255, 87, 51)          -- Truecolor
color.hex("#FF5733")            -- Hex (also "#f53", "FF5733")
color.adaptive("#333", "#eee")  -- Light/dark background
color.resolve("red")            -- String → Color (named, hex, ansi256)

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
layout.width(s)     layout.height(s)    layout.size(s) → w, h
layout.table(headers, rows)
```

### ansi (low-level)

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

### Components

All components follow the composable sub-model pattern: `new(opts)`, `update(model, msg)`, `view(model)`.
Embed them in your `tui.app()` model and delegate messages.

#### spinner

```lua
local spinner = require("spinner")

-- Presets: DOTS, LINE, MINI_DOTS, JUMP, PULSE, GLOBE, MOON, MONKEY,
--          METER, HAMBURGER, ELLIPSIS, POINTS, ARROW, BOUNCING_BAR

local s = spinner.new()                          -- default DOTS
local s = spinner.new({ preset = spinner.MOON }) -- custom preset
local s = spinner.new({ frames = {"⣾","⣽","⣻"}, interval = "80ms" })

s = spinner.update(s, msg)       -- advance on {kind="tick"}
spinner.view(s)                  -- "⠋" (current frame)
spinner.interval(s)              -- "80ms" (pass to app.tick())
spinner.set_style(s, my_style)   -- apply style to frame
spinner.reset(s)                 -- back to frame 1
```

#### progress

```lua
local progress = require("progress")

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
progress.view(p)                 -- "████████████████████████████░░░░░░░░░░░░  76%"
```

#### textinput

```lua
local textinput = require("textinput")

local ti = textinput.new({
    placeholder = "Enter name...",
    prompt = "> ",
    char_limit = 50,
    -- password = true,
})

ti = textinput.update(ti, msg)   -- handles key events
textinput.view(ti)               -- "> John█doe"
textinput.value(ti)              -- "Johndoe"
textinput.focus(ti)              -- enable input
textinput.blur(ti)               -- disable input
textinput.reset(ti)              -- clear value
```

**Supported keys**: printable chars, backspace, delete, left/right arrows, home/end,
ctrl+a/e/k/u/w (readline-style), line input (cooked mode fallback).

#### viewport

```lua
local viewport = require("viewport")

local vp = viewport.new({ width = 80, height = 20, word_wrap = true })
vp = viewport.set_content(vp, long_text)
vp = viewport.append(vp, more_text, true)  -- auto-scroll to bottom

vp = viewport.update(vp, msg)       -- handles up/down/pgup/pgdn/home/end/mouse
viewport.view(vp)                   -- visible portion
viewport.view_with_scrollbar(vp)    -- with right-edge scrollbar
viewport.scroll_percent(vp)         -- 0.0–1.0
viewport.at_top(vp)                 -- boolean
viewport.at_bottom(vp)              -- boolean
```

**Supported keys**: up/k, down/j, pgup/ctrl+b, pgdn/ctrl+f, home/g, end/G, ctrl+u/d (half page).

#### help

```lua
local help = require("help")

local h = help.new({
    bindings = {
        { key = "↑/k", desc = "scroll up" },
        { key = "↓/j", desc = "scroll down" },
        help.SEPARATOR,
        { key = "q", desc = "quit" },
        { key = "?", desc = "toggle help" },
    },
    width = 60,
})

help.view(h)          -- short: "↑/k scroll up • ↓/j scroll down • q quit • ? toggle help"
h = help.toggle(h)
help.view(h)          -- full: multi-line, aligned, grouped
```

### Component composition example

```lua
local app = require("app")
local spinner = require("spinner")
local progress = require("progress")
local help = require("help")

app.run({
    init = function()
        local model = {
            spin = spinner.new({ preset = spinner.DOTS }),
            bar = progress.new({ width = 30, gradient_start = "#5A56E0", gradient_end = "#EE6FF8" }),
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
```

## CLI SDK

### args — Argument & option parser

```yaml
# Consumer entry with CLI SDK imports
- name: my_command
  kind: process.lua
  meta:
    command:
      name: deploy
      short: Deploy the application
  source: file://deploy.lua
  method: main
  modules: [ io ]
  imports:
    args: wippy.tui:args
    output: wippy.tui:output
    prompt: wippy.tui:prompt
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

**Features:**
- Positional arguments with `required`, `choices`, `default`, type coercion
- Long options (`--name`, `--name=value`), short options (`-f`, `-fv` combined)
- Boolean negation (`--no-force`), `--` separator for rest args
- Types: `string`, `number`, `integer`, `boolean`
- Auto `--help`/`-h` detection
- `args.help(def)` generates formatted help text

### output — Structured CLI output

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
io.print(output.panel("Application deployed successfully!", {
    title = "Deploy",
    border = "rounded",
    border_color = "#6c5ce7",
    title_color = "#00b894",
}))

-- Definitions list (key-value pairs)
io.print(output.definitions({
    {"Version", "2.1.0"},
    {"Environment", "production"},
    {"Replicas", "3"},
}, { key_color = "cyan", separator = " → " }))

-- Tree structure
io.print(output.tree({
    label = "src/",
    children = {
        { label = "api/", children = {
            { label = "users.lua" },
            { label = "orders.lua" },
        }},
        { label = "workers/", children = {
            { label = "email.lua" },
        }},
    }
}))

-- Horizontal rule
io.print(output.rule({ width = 60, title = "Section", color = "#888" }))
```

### prompt — Interactive prompts

```lua
local prompt = require("prompt")
local io = require("io")

prompt.set_io(io)  -- Required: inject io module

-- Text input
local name = prompt.text("Your name", { default = "World", required = true })

-- Password (note: visible in cooked mode until Stage 1 raw mode lands)
local pass = prompt.password("Password", { confirm = true })

-- Yes/No confirmation
local ok = prompt.confirm("Deploy to production?", { default = false })

-- Single select (numbered list)
local env = prompt.select("Target environment", {
    "development",
    "staging",
    "production",
}, { default = 2 })

-- Select with labels and values
local db = prompt.select("Database", {
    { label = "PostgreSQL", value = "postgres" },
    { label = "SQLite",     value = "sqlite" },
    { label = "MySQL",      value = "mysql" },
})

-- Multi-select (comma-separated numbers or ranges)
local features = prompt.multiselect("Enable features", {
    "caching",
    "logging",
    "metrics",
    "tracing",
}, { defaults = {1, 2}, min = 1 })
-- User enters: "1,3-4" → returns {"caching", "metrics", "tracing"}
```

### cli_progress — Line-based progress

```lua
local cli_progress = require("cli_progress")
local io = require("io")

-- Simple progress bar (uses \r to overwrite line)
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
cli_progress.finish_spinner(spin, io, "Processing complete!")

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

## Design Decisions

- **Immutable styles** — every method returns a new style. Safe to share, extend, compose.
- **Profile-aware colors** — hex/RGB colors auto-downsample to 256/16/none based on `color._profile`.
- **ANSI-aware measurement** — `ansi.visible_width()` strips escapes for correct width calculation.
  Layout joins use this to align multi-line blocks correctly.
- **ASCII fallback** — `style:unicode(false)` switches borders to `+`, `-`, `|` characters.
- **Adaptive colors** — `color.adaptive(light, dark)` picks based on `color._dark_background`.
- **Composable components** — sub-model pattern (new/update/view) embeds into any `tui.app()`.
- **CLI SDK decoupled from TUI** — args, output, prompts work with plain `io` module. No app runtime needed.

## Coverage

From the [master checklist](../docs/ideas/terminal-sdk/master-checklist.md):

**Stage 2: Style & Layout** ✅
- [x] 2.1–2.6: Style builder, colors, box model, borders, layout, shorthands
- [ ] 2.7: Runtime verification pending

**Stage 3: TUI App Runtime** ✅
- [x] 3.1–3.7: Elm Architecture runtime, message dispatch, frame diffing, cmd/batch/tick, crash recovery
- [ ] 3.8: Runtime verification pending

**Stage 4: Core Components** ✅
- [x] 4.1–4.5: Spinner, progress, textinput, viewport, help
- [ ] 4.6: Runtime verification pending

**Stage 5: CLI SDK** ✅
- [x] 5.1–5.6: Args parser, help generation, output helpers, prompts, CLI progress
- [ ] 5.7: Runtime verification pending
