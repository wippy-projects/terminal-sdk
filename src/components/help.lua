--- Help component — auto-generated key binding display.
---
--- Usage within a tui.app:
---   local help = require("help")
---
---   local bindings = {
---       { key = "↑/k", desc = "scroll up" },
---       { key = "↓/j", desc = "scroll down" },
---       { key = "q", desc = "quit" },
---       { key = "?", desc = "toggle help" },
---       -- Separator between groups
---       help.SEPARATOR,
---       { key = "enter", desc = "select" },
---       { key = "esc", desc = "back" },
---   }
---
---   init = function()
---       return { help = help.new({ bindings = bindings }) }
---   end,
---   update = function(model, msg)
---       if msg.kind == "key" and msg.key == "?" then
---           model.help = help.toggle(model.help)
---       end
---       return model
---   end,
---   view = function(model)
---       return content .. "\n" .. help.view(model.help)
---   end

local ansi = require("ansi")

local help = {}

---------------------------------------------------------------------------
-- Separator constant
---------------------------------------------------------------------------

help.SEPARATOR = { _separator = true }

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new help model.
---
--- Options:
---   bindings: array of {key: string, desc: string} or help.SEPARATOR
---   width: integer? — max width for truncation (nil = no limit)
---   full: boolean — start in full mode (default: false, shows short mode)
---   key_style: style for key text (default: bold)
---   desc_style: style for description text (default: dim)
---   separator_text: string between key-desc pairs in short mode (default: " • ")
---   short_separator: string between key and desc (default: " ")
function help.new(opts)
    opts = opts or {}
    return {
        _type = "help",
        _bindings = opts.bindings or {},
        _width = opts.width or nil,
        _full = opts.full or false,
        _key_style = opts.key_style or nil,
        _desc_style = opts.desc_style or nil,
        _separator_text = opts.separator_text or " • ",
        _short_separator = opts.short_separator or " ",
    }
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

--- Toggle between short and full display modes.
function help.toggle(model)
    model._full = not model._full
    return model
end

--- Set to full mode.
function help.show_full(model)
    model._full = true
    return model
end

--- Set to short mode.
function help.show_short(model)
    model._full = false
    return model
end

--- Is help in full mode?
function help.is_full(model): boolean
    return model._full
end

--- Update bindings list.
function help.set_bindings(model, bindings)
    model._bindings = bindings
    return model
end

---------------------------------------------------------------------------
-- Internal rendering helpers
---------------------------------------------------------------------------

local function render_key(text, key_style)
    if key_style then
        return key_style:render(text)
    end
    return "\027[1m" .. text .. "\027[0m"  -- bold
end

local function render_desc(text, desc_style)
    if desc_style then
        return desc_style:render(text)
    end
    return "\027[2m" .. text .. "\027[0m"  -- dim
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the help display.
function help.view(model): string
    local bindings = model._bindings
    if #bindings == 0 then return "" end

    if model._full then
        return help._view_full(model)
    else
        return help._view_short(model)
    end
end

--- Short mode: single line with key-desc pairs separated by dots.
function help._view_short(model): string
    local parts = {}

    for _, b in ipairs(model._bindings) do
        if b._separator then
            -- Skip separators in short mode (they compress away)
        else
            local pair = render_key(b.key, model._key_style) ..
                         model._short_separator ..
                         render_desc(b.desc, model._desc_style)
            table.insert(parts, pair)
        end
    end

    local line = table.concat(parts, model._separator_text)

    -- Truncate to width if needed
    if model._width then
        local vis = ansi.visible_width(line)
        if vis > model._width then
            -- Rebuild with fewer items until it fits + "…"
            local truncated = {}
            local total_vis = 0
            local ellipsis = " …"
            local max_w = model._width - ansi.visible_width(ellipsis)

            for _, part in ipairs(parts) do
                local sep_w = #truncated > 0 and ansi.visible_width(model._separator_text) or 0
                local part_w = ansi.visible_width(part)
                if total_vis + sep_w + part_w > max_w then
                    break
                end
                table.insert(truncated, part)
                total_vis = total_vis + sep_w + part_w
            end

            line = table.concat(truncated, model._separator_text) .. ellipsis
        end
    end

    return line
end

--- Full mode: multi-line, each binding on its own line, grouped by separators.
function help._view_full(model): string
    local lines = {}
    local max_key_w = 0

    -- Measure widest key for alignment
    for _, b in ipairs(model._bindings) do
        if not b._separator then
            local w = #b.key
            if w > max_key_w then max_key_w = w end
        end
    end

    for _, b in ipairs(model._bindings) do
        if b._separator then
            table.insert(lines, "")  -- blank line between groups
        else
            local padded_key = b.key .. string.rep(" ", max_key_w - #b.key)
            local line = "  " .. render_key(padded_key, model._key_style) ..
                         "  " .. render_desc(b.desc, model._desc_style)
            table.insert(lines, line)
        end
    end

    -- Remove leading/trailing blank lines
    while #lines > 0 and lines[1] == "" do
        table.remove(lines, 1)
    end
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Update (help typically doesn't handle messages itself;
-- toggle is called explicitly by the parent app)
---------------------------------------------------------------------------

function help.update(model, msg)
    return model
end

return help
