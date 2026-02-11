--- Progress bar component — visual progress indicator.
---
--- Usage within a tui.app:
---   local progress = require("progress")
---
---   init = function()
---       return { bar = progress.new({ width = 40 }) }
---   end,
---   update = function(model, msg)
---       if msg.kind == "tick" then
---           model.bar = progress.set(model.bar, model.bar._percent + 0.01)
---       end
---       return model
---   end,
---   view = function(model)
---       return progress.view(model.bar)
---   end

local progress = {}

---------------------------------------------------------------------------
-- Fill styles
---------------------------------------------------------------------------

progress.SOLID = "solid"
progress.GRADIENT = "gradient"

---------------------------------------------------------------------------
-- Default characters
---------------------------------------------------------------------------

local DEFAULT_FULL = "█"
local DEFAULT_EMPTY = "░"
local DEFAULT_HEAD = "█"

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new progress bar model.
---
--- Options:
---   width: integer — bar width in characters (default: 40)
---   full_char: string — character for filled portion (default: "█")
---   empty_char: string — character for empty portion (default: "░")
---   head_char: string? — character at the fill edge (default: nil, uses full_char)
---   show_percent: boolean — display percentage text (default: true)
---   percent_format: string — format string for percentage (default: " %3.0f%%")
---   style: style object for the full portion
---   empty_style: style object for the empty portion
---   percent_style: style object for the percentage text
---   full_color: Color or hex string for filled portion foreground
---   empty_color: Color or hex string for empty portion foreground
---   gradient_start: Color or hex string — start color for gradient fill
---   gradient_end: Color or hex string — end color for gradient fill
function progress.new(opts)
    opts = opts or {}
    return {
        _type = "progress",
        _percent = 0,
        _width = opts.width or 40,
        _full_char = opts.full_char or DEFAULT_FULL,
        _empty_char = opts.empty_char or DEFAULT_EMPTY,
        _head_char = opts.head_char or nil,
        _show_percent = opts.show_percent ~= false,
        _percent_format = opts.percent_format or " %3.0f%%",
        _style = opts.style or nil,
        _empty_style = opts.empty_style or nil,
        _percent_style = opts.percent_style or nil,
        _full_color = opts.full_color or nil,
        _empty_color = opts.empty_color or nil,
        _gradient_start = opts.gradient_start or nil,
        _gradient_end = opts.gradient_end or nil,
    }
end

---------------------------------------------------------------------------
-- State mutation
---------------------------------------------------------------------------

--- Set the progress value (0.0 to 1.0). Clamps to range.
function progress.set(model, percent: number)
    if percent < 0 then percent = 0 end
    if percent > 1 then percent = 1 end
    model._percent = percent
    return model
end

--- Increment progress by delta.
function progress.incr(model, delta: number)
    return progress.set(model, model._percent + (delta or 0.01))
end

--- Get the current progress value.
function progress.percent(model): number
    return model._percent
end

---------------------------------------------------------------------------
-- Internal: color interpolation for gradient
---------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
    return math.floor(a + (b - a) * t + 0.5)
end

local function parse_hex(hex: string): (integer, integer, integer)
    local s = hex:gsub("^#", "")
    if #s == 3 then
        s = s:sub(1,1):rep(2) .. s:sub(2,2):rep(2) .. s:sub(3,3):rep(2)
    end
    return tonumber(s:sub(1,2), 16) or 0,
           tonumber(s:sub(3,4), 16) or 0,
           tonumber(s:sub(5,6), 16) or 0
end

local function color_to_rgb(c)
    if type(c) == "string" then
        local r, g, b = parse_hex(c)
        return r, g, b
    end
    if type(c) == "table" and c.r then
        return c.r, c.g, c.b
    end
    return 255, 255, 255
end

local function rgb_fg(r: integer, g: integer, b: integer): string
    return "\027[38;2;" .. r .. ";" .. g .. ";" .. b .. "m"
end

local RESET = "\027[0m"

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the progress bar.
function progress.view(model): string
    local w = model._width
    local filled_count = math.floor(w * model._percent + 0.5)
    if filled_count > w then filled_count = w end
    local empty_count = w - filled_count
    local has_head = model._head_char and filled_count > 0 and filled_count < w

    -- Build bar string
    local parts = {}

    if model._gradient_start and model._gradient_end then
        -- Gradient rendering: each filled char gets interpolated color
        local sr, sg, sb = color_to_rgb(model._gradient_start)
        local er, eg, eb = color_to_rgb(model._gradient_end)

        for i = 1, filled_count do
            local t = (i - 1) / math.max(w - 1, 1)
            local r = lerp(sr, er, t)
            local g = lerp(sg, eg, t)
            local b = lerp(sb, eb, t)
            local ch = model._full_char
            if has_head and i == filled_count then
                ch = model._head_char
            end
            table.insert(parts, rgb_fg(r, g, b) .. ch)
        end
        if filled_count > 0 then
            table.insert(parts, RESET)
        end
    else
        -- Solid rendering
        local fill_str
        if has_head then
            fill_str = string.rep(model._full_char, filled_count - 1) .. model._head_char
        else
            fill_str = string.rep(model._full_char, filled_count)
        end

        if model._style then
            table.insert(parts, model._style:render(fill_str))
        elseif model._full_color then
            local cr, cg, cb = color_to_rgb(model._full_color)
            table.insert(parts, rgb_fg(cr, cg, cb) .. fill_str .. RESET)
        else
            table.insert(parts, fill_str)
        end
    end

    -- Empty portion
    local empty_str = string.rep(model._empty_char, empty_count)
    if model._empty_style then
        table.insert(parts, model._empty_style:render(empty_str))
    elseif model._empty_color then
        local cr, cg, cb = color_to_rgb(model._empty_color)
        table.insert(parts, rgb_fg(cr, cg, cb) .. empty_str .. RESET)
    else
        table.insert(parts, empty_str)
    end

    -- Percentage text
    if model._show_percent then
        local pct_text = string.format(model._percent_format, model._percent * 100)
        if model._percent_style then
            table.insert(parts, model._percent_style:render(pct_text))
        else
            table.insert(parts, pct_text)
        end
    end

    return table.concat(parts)
end

---------------------------------------------------------------------------
-- Update (progress bars typically don't react to messages themselves,
-- but we provide update() for API consistency)
---------------------------------------------------------------------------

--- Update progress model. Currently a no-op passthrough —
--- progress is driven by explicit set()/incr() calls from the parent.
function progress.update(model, msg)
    return model
end

return progress
