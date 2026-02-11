--- Theme system — predefined and custom color themes for TUI applications.
---
--- Usage:
---   local theme = require("theme")
---   local style = require("style")
---
---   -- Use a built-in theme
---   local t = theme.get("dracula")
---
---   -- Apply theme colors to styles
---   local title_style = style.new()
---       :foreground(t.primary)
---       :bold(true)
---   local error_style = style.new()
---       :foreground(t.error)
---
---   -- Theme-aware component styling
---   local spinner = spinner.new({
---       style = style.new():foreground(t.accent),
---   })
---
---   -- Create a custom theme
---   theme.register("my_theme", {
---       name = "My Theme",
---       dark = true,
---       bg = "#1a1b26",
---       fg = "#c0caf5",
---       primary = "#7aa2f7",
---       -- ...
---   })
---
--- Themes define a standard palette of semantic colors that components
--- and applications can reference for consistent styling.

local theme = {}

---------------------------------------------------------------------------
-- Theme structure
---------------------------------------------------------------------------

--- Standard theme color slots:
---   bg:         background color
---   fg:         default foreground/text color
---   primary:    main accent (buttons, active tabs, links)
---   secondary:  secondary accent (borders, subtle highlights)
---   accent:     tertiary accent (spinners, progress bars)
---   muted:      subdued text (placeholders, help, status bars)
---   border:     border color
---   success:    success/positive (green family)
---   warning:    warning/caution (yellow/orange family)
---   error:      error/danger (red family)
---   info:       informational (blue/cyan family)
---   highlight:  selection/cursor highlight background
---   surface:    elevated surface bg (panels, cards)
---   dark:       boolean — is this a dark theme?
---   name:       human-readable theme name

---------------------------------------------------------------------------
-- Built-in themes
---------------------------------------------------------------------------

local themes = {}

themes["default"] = {
    name = "Default",
    dark = true,
    bg = "#1e1e2e",
    fg = "#cdd6f4",
    primary = "#89b4fa",
    secondary = "#74c7ec",
    accent = "#cba6f7",
    muted = "#6c7086",
    border = "#585b70",
    success = "#a6e3a1",
    warning = "#f9e2af",
    error = "#f38ba8",
    info = "#89dceb",
    highlight = "#313244",
    surface = "#313244",
}

themes["dracula"] = {
    name = "Dracula",
    dark = true,
    bg = "#282a36",
    fg = "#f8f8f2",
    primary = "#bd93f9",
    secondary = "#8be9fd",
    accent = "#ff79c6",
    muted = "#6272a4",
    border = "#44475a",
    success = "#50fa7b",
    warning = "#f1fa8c",
    error = "#ff5555",
    info = "#8be9fd",
    highlight = "#44475a",
    surface = "#44475a",
}

themes["catppuccin"] = {
    name = "Catppuccin Mocha",
    dark = true,
    bg = "#1e1e2e",
    fg = "#cdd6f4",
    primary = "#89b4fa",
    secondary = "#74c7ec",
    accent = "#cba6f7",
    muted = "#6c7086",
    border = "#585b70",
    success = "#a6e3a1",
    warning = "#f9e2af",
    error = "#f38ba8",
    info = "#89dceb",
    highlight = "#313244",
    surface = "#313244",
}

themes["nord"] = {
    name = "Nord",
    dark = true,
    bg = "#2e3440",
    fg = "#d8dee9",
    primary = "#88c0d0",
    secondary = "#81a1c1",
    accent = "#b48ead",
    muted = "#4c566a",
    border = "#3b4252",
    success = "#a3be8c",
    warning = "#ebcb8b",
    error = "#bf616a",
    info = "#88c0d0",
    highlight = "#3b4252",
    surface = "#3b4252",
}

themes["tokyo_night"] = {
    name = "Tokyo Night",
    dark = true,
    bg = "#1a1b26",
    fg = "#c0caf5",
    primary = "#7aa2f7",
    secondary = "#7dcfff",
    accent = "#bb9af7",
    muted = "#565f89",
    border = "#3b4261",
    success = "#9ece6a",
    warning = "#e0af68",
    error = "#f7768e",
    info = "#2ac3de",
    highlight = "#292e42",
    surface = "#24283b",
}

themes["gruvbox"] = {
    name = "Gruvbox Dark",
    dark = true,
    bg = "#282828",
    fg = "#ebdbb2",
    primary = "#458588",
    secondary = "#689d6a",
    accent = "#d3869b",
    muted = "#928374",
    border = "#504945",
    success = "#b8bb26",
    warning = "#fabd2f",
    error = "#fb4934",
    info = "#83a598",
    highlight = "#3c3836",
    surface = "#3c3836",
}

themes["solarized_dark"] = {
    name = "Solarized Dark",
    dark = true,
    bg = "#002b36",
    fg = "#839496",
    primary = "#268bd2",
    secondary = "#2aa198",
    accent = "#6c71c4",
    muted = "#586e75",
    border = "#073642",
    success = "#859900",
    warning = "#b58900",
    error = "#dc322f",
    info = "#2aa198",
    highlight = "#073642",
    surface = "#073642",
}

themes["light"] = {
    name = "Light",
    dark = false,
    bg = "#ffffff",
    fg = "#1e1e1e",
    primary = "#0078d4",
    secondary = "#005a9e",
    accent = "#8764b8",
    muted = "#888888",
    border = "#d1d1d1",
    success = "#107c10",
    warning = "#ca5010",
    error = "#d13438",
    info = "#0078d4",
    highlight = "#e6f2ff",
    surface = "#f3f3f3",
}

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

--- Get a theme by name. Returns theme table or nil.
function theme.get(name: string)
    return themes[name]
end

--- Get a theme by name, falling back to "default".
function theme.get_or_default(name: string)
    return themes[name] or themes["default"]
end

--- Register a custom theme.
function theme.register(name: string, t)
    themes[name] = t
end

--- List all available theme names.
function theme.list(): {string}
    local names = {}
    for name, _ in pairs(themes) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Check if a theme is dark.
function theme.is_dark(t): boolean
    return t.dark ~= false
end

--- Create a themed color pair for adaptive light/dark support.
--- Returns the appropriate color based on the theme's dark/light mode.
function theme.adaptive(t, dark_color: string, light_color: string): string
    if t.dark then
        return dark_color
    end
    return light_color
end

--- Merge a partial theme over a base theme.
--- Useful for user overrides: theme.merge(theme.get("dracula"), {error = "#ff0000"})
function theme.merge(base, overrides)
    local result = {}
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        result[k] = v
    end
    return result
end

return theme
