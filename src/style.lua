--- Lip Gloss-inspired declarative style builder.
--- Immutable builder pattern: every method returns a new style, the original is unchanged.
---
--- Usage:
---   local style = require("style")
---   local color = require("color")
---
---   local base = style.new():bold():foreground("#fafafa")
---   local title = base:inherit():background("#7b2fff"):padding(0, 1)
---
---   io.print(base:render("Plain bold"))
---   io.print(title:render("Styled title"))

local ansi = require("ansi")
local color_mod = require("color")
local border_defs = require("border_defs")

local style = {}

---------------------------------------------------------------------------
-- Alignment constants
---------------------------------------------------------------------------

style.LEFT   = "left"
style.CENTER = "center"
style.RIGHT  = "right"
style.TOP    = "top"
style.MIDDLE = "middle"
style.BOTTOM = "bottom"

---------------------------------------------------------------------------
-- Re-export color utilities for convenience
---------------------------------------------------------------------------

--- Create an adaptive color (selects based on terminal background).
--- Both args can be hex strings or Color tables.
function style.adaptive(light, dark)
    return color_mod.adaptive(light, dark)
end

---------------------------------------------------------------------------
-- Internal: deep-copy a table (one level)
---------------------------------------------------------------------------

local function shallow_copy_array(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    return c
end

---------------------------------------------------------------------------
-- Style object
---------------------------------------------------------------------------

local StyleMT = {}
StyleMT.__index = StyleMT

--- Clone self into a new independent style (immutable builder).
local function clone(self)
    local c = {}
    c._bold          = self._bold
    c._italic        = self._italic
    c._underline     = self._underline
    c._dim           = self._dim
    c._strikethrough = self._strikethrough
    c._reverse       = self._reverse
    c._blink         = self._blink
    c._fg            = self._fg
    c._bg            = self._bg
    c._width         = self._width
    c._height        = self._height
    c._max_width     = self._max_width
    c._max_height    = self._max_height
    c._padding       = shallow_copy_array(self._padding)
    c._margin        = shallow_copy_array(self._margin)
    c._align_h       = self._align_h
    c._align_v       = self._align_v
    c._border_style  = self._border_style
    c._border_fg     = self._border_fg
    c._border_bg     = self._border_bg
    c._border_top    = self._border_top
    c._border_bottom = self._border_bottom
    c._border_left   = self._border_left
    c._border_right  = self._border_right
    c._inline        = self._inline
    c._unicode       = self._unicode
    return setmetatable(c, StyleMT)
end

--- Resolve a color argument: accepts Color table, hex string, named string, ansi256 string.
local function resolve_color(c)
    if c == nil then return nil end
    return color_mod.resolve(c)
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

function style.new()
    local s = {
        _bold          = false,
        _italic        = false,
        _underline     = false,
        _dim           = false,
        _strikethrough = false,
        _reverse       = false,
        _blink         = false,
        _fg            = nil,
        _bg            = nil,
        _width         = nil,
        _height        = nil,
        _max_width     = nil,
        _max_height    = nil,
        _padding       = {0, 0, 0, 0},
        _margin        = {0, 0, 0, 0},
        _align_h       = "left",
        _align_v       = "top",
        _border_style  = nil,
        _border_fg     = nil,
        _border_bg     = nil,
        _border_top    = true,
        _border_bottom = true,
        _border_left   = true,
        _border_right  = true,
        _inline        = false,
        _unicode       = true,
    }
    return setmetatable(s, StyleMT)
end

---------------------------------------------------------------------------
-- Inheritance
---------------------------------------------------------------------------

--- Create an independent copy of this style. Equivalent to clone.
function StyleMT:inherit()
    return clone(self)
end

--- Copy this style (alias for inherit).
function StyleMT:copy()
    return clone(self)
end

---------------------------------------------------------------------------
-- Text attributes (each returns new style)
---------------------------------------------------------------------------

function StyleMT:bold(v: boolean?)
    local c = clone(self); c._bold = v ~= false; return c
end
function StyleMT:italic(v: boolean?)
    local c = clone(self); c._italic = v ~= false; return c
end
function StyleMT:underline(v: boolean?)
    local c = clone(self); c._underline = v ~= false; return c
end
function StyleMT:dim(v: boolean?)
    local c = clone(self); c._dim = v ~= false; return c
end
function StyleMT:strikethrough(v: boolean?)
    local c = clone(self); c._strikethrough = v ~= false; return c
end
function StyleMT:reverse(v: boolean?)
    local c = clone(self); c._reverse = v ~= false; return c
end
function StyleMT:blink(v: boolean?)
    local c = clone(self); c._blink = v ~= false; return c
end

---------------------------------------------------------------------------
-- Colors — accept Color table, hex string "#ff5500", named "red", ansi "196"
---------------------------------------------------------------------------

function StyleMT:foreground(c)
    local s = clone(self); s._fg = resolve_color(c); return s
end

function StyleMT:background(c)
    local s = clone(self); s._bg = resolve_color(c); return s
end

StyleMT.fg = StyleMT.foreground
StyleMT.bg = StyleMT.background

---------------------------------------------------------------------------
-- Box model
---------------------------------------------------------------------------

function StyleMT:width(w: integer)
    local c = clone(self); c._width = w; return c
end
function StyleMT:height(h: integer)
    local c = clone(self); c._height = h; return c
end
function StyleMT:max_width(w: integer)
    local c = clone(self); c._max_width = w; return c
end
function StyleMT:max_height(h: integer)
    local c = clone(self); c._max_height = h; return c
end

--- Padding: (all), (vertical, horizontal), or (top, right, bottom, left).
function StyleMT:padding(...)
    local c = clone(self)
    local args = {...}
    if #args == 1 then
        c._padding = {args[1], args[1], args[1], args[1]}
    elseif #args == 2 then
        c._padding = {args[1], args[2], args[1], args[2]}
    elseif #args == 4 then
        c._padding = {args[1], args[2], args[3], args[4]}
    end
    return c
end

function StyleMT:padding_top(n: integer)
    local c = clone(self); c._padding[1] = n; return c
end
function StyleMT:padding_right(n: integer)
    local c = clone(self); c._padding[2] = n; return c
end
function StyleMT:padding_bottom(n: integer)
    local c = clone(self); c._padding[3] = n; return c
end
function StyleMT:padding_left(n: integer)
    local c = clone(self); c._padding[4] = n; return c
end

--- Margin: same signature as padding.
function StyleMT:margin(...)
    local c = clone(self)
    local args = {...}
    if #args == 1 then
        c._margin = {args[1], args[1], args[1], args[1]}
    elseif #args == 2 then
        c._margin = {args[1], args[2], args[1], args[2]}
    elseif #args == 4 then
        c._margin = {args[1], args[2], args[3], args[4]}
    end
    return c
end

function StyleMT:margin_top(n: integer)
    local c = clone(self); c._margin[1] = n; return c
end
function StyleMT:margin_right(n: integer)
    local c = clone(self); c._margin[2] = n; return c
end
function StyleMT:margin_bottom(n: integer)
    local c = clone(self); c._margin[3] = n; return c
end
function StyleMT:margin_left(n: integer)
    local c = clone(self); c._margin[4] = n; return c
end

---------------------------------------------------------------------------
-- Alignment
---------------------------------------------------------------------------

function StyleMT:align(h: string, v: string?)
    local c = clone(self)
    c._align_h = h or "left"
    if v then c._align_v = v end
    return c
end

function StyleMT:valign(v: string)
    local c = clone(self); c._align_v = v; return c
end

StyleMT.align_vertical = StyleMT.valign

---------------------------------------------------------------------------
-- Border
---------------------------------------------------------------------------

--- Set border style by name ("normal", "rounded", "thick", "double", "hidden", "none")
--- or a BorderStyle table. Optionally toggle specific sides.
function StyleMT:border(b, top: boolean?, right: boolean?, bottom: boolean?, left: boolean?)
    local c = clone(self)
    if type(b) == "string" then
        c._border_style = border_defs.get(b)
    elseif type(b) == "table" then
        c._border_style = b
    end
    if top ~= nil then c._border_top = top end
    if right ~= nil then c._border_right = right end
    if bottom ~= nil then c._border_bottom = bottom end
    if left ~= nil then c._border_left = left end
    return c
end

function StyleMT:border_foreground(c)
    local s = clone(self); s._border_fg = resolve_color(c); return s
end

function StyleMT:border_background(c)
    local s = clone(self); s._border_bg = resolve_color(c); return s
end

function StyleMT:border_top(v: boolean)
    local c = clone(self); c._border_top = v; return c
end
function StyleMT:border_bottom(v: boolean)
    local c = clone(self); c._border_bottom = v; return c
end
function StyleMT:border_left(v: boolean)
    local c = clone(self); c._border_left = v; return c
end
function StyleMT:border_right(v: boolean)
    local c = clone(self); c._border_right = v; return c
end

---------------------------------------------------------------------------
-- Inline / Unicode
---------------------------------------------------------------------------

function StyleMT:inline(v: boolean?)
    local c = clone(self); c._inline = v ~= false; return c
end

function StyleMT:unicode(v: boolean?)
    local c = clone(self); c._unicode = v ~= false; return c
end

---------------------------------------------------------------------------
-- Rendering internals
---------------------------------------------------------------------------

--- ASCII fallback border for non-unicode terminals.
local ASCII_BORDER = {
    top_left = "+", top_right = "+", bottom_left = "+", bottom_right = "+",
    horizontal = "-", vertical = "|",
    middle_left = "+", middle_right = "+",
    middle_horizontal = "-",
    middle_top = "+", middle_bottom = "+",
    cross = "+",
}

--- Build the opening SGR sequence for text attributes + colors.
function StyleMT:_build_sgr(): string
    local parts = {}
    if self._bold then table.insert(parts, ansi.BOLD) end
    if self._dim then table.insert(parts, ansi.DIM) end
    if self._italic then table.insert(parts, ansi.ITALIC) end
    if self._underline then table.insert(parts, ansi.UNDERLINE) end
    if self._blink then table.insert(parts, ansi.BLINK) end
    if self._reverse then table.insert(parts, ansi.REVERSE) end
    if self._strikethrough then table.insert(parts, ansi.STRIKETHROUGH) end
    if self._fg then table.insert(parts, color_mod.fg(self._fg)) end
    if self._bg then table.insert(parts, color_mod.bg(self._bg)) end
    return table.concat(parts)
end

--- Build SGR for border characters.
function StyleMT:_build_border_sgr(): string
    local parts = {}
    if self._border_fg then table.insert(parts, color_mod.fg(self._border_fg)) end
    if self._border_bg then table.insert(parts, color_mod.bg(self._border_bg)) end
    return table.concat(parts)
end

--- Get the effective border style (with ASCII fallback).
function StyleMT:_effective_border()
    local bd = self._border_style
    if not bd then return nil end
    if bd.horizontal == "" then return nil end -- "none" border
    if not self._unicode then return ASCII_BORDER end
    return bd
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

--- Render a string with this style applied.
--- Returns a fully styled, potentially multi-line string.
function StyleMT:render(text: string): string
    text = text or ""

    -- Inline mode: just wrap with SGR, no box model
    if self._inline then
        local sgr = self:_build_sgr()
        if #sgr > 0 then
            return sgr .. text .. ansi.RESET
        end
        return text
    end

    local lines = ansi.lines(text)
    local sgr = self:_build_sgr()
    local bsgr = self:_build_border_sgr()
    local bd = self:_effective_border()

    -- Measure content width
    local content_w = 0
    for _, line in ipairs(lines) do
        local w = ansi.visible_width(line)
        if w > content_w then content_w = w end
    end

    -- Calculate decoration widths
    local pad_h = self._padding[4] + self._padding[2]
    local border_h = 0
    if bd then
        if self._border_left then border_h = border_h + 1 end
        if self._border_right then border_h = border_h + 1 end
    end

    -- Apply explicit width (total outer width)
    if self._width then
        local interior = self._width - pad_h - border_h
        if interior < 0 then interior = 0 end
        content_w = interior
    end

    if self._max_width then
        local max_interior = self._max_width - pad_h - border_h
        if max_interior < 0 then max_interior = 0 end
        if content_w > max_interior then content_w = max_interior end
    end

    -- Horizontal alignment of content lines
    local aligned = {}
    for _, line in ipairs(lines) do
        local w = ansi.visible_width(line)
        if w < content_w then
            if self._align_h == "center" then
                table.insert(aligned, ansi.pad_center(line, content_w))
            elseif self._align_h == "right" then
                table.insert(aligned, ansi.pad_left(line, content_w))
            else
                table.insert(aligned, ansi.pad_right(line, content_w))
            end
        else
            -- Truncate or pad to exact width
            table.insert(aligned, ansi.pad_right(line, content_w))
        end
    end

    -- Vertical sizing
    local border_v = 0
    if bd then
        if self._border_top then border_v = border_v + 1 end
        if self._border_bottom then border_v = border_v + 1 end
    end

    if self._height then
        local interior_h = self._height - self._padding[1] - self._padding[3] - border_v
        if interior_h < 1 then interior_h = 1 end

        if #aligned < interior_h then
            local empty_line = string.rep(" ", content_w)
            local gap = interior_h - #aligned

            if self._align_v == "middle" then
                local top_gap = math.floor(gap / 2)
                local bot_gap = gap - top_gap
                for _ = 1, top_gap do table.insert(aligned, 1, empty_line) end
                for _ = 1, bot_gap do table.insert(aligned, empty_line) end
            elseif self._align_v == "bottom" then
                for _ = 1, gap do table.insert(aligned, 1, empty_line) end
            else
                for _ = 1, gap do table.insert(aligned, empty_line) end
            end
        end
    end

    -- Apply max_height
    if self._max_height then
        local max_interior = self._max_height - self._padding[1] - self._padding[3] - border_v
        if max_interior < 1 then max_interior = 1 end
        while #aligned > max_interior do
            table.remove(aligned)
        end
    end

    -- Apply padding
    local padded = {}
    local pad_left_str = string.rep(" ", self._padding[4])
    local pad_right_str = string.rep(" ", self._padding[2])
    local padded_width = content_w + pad_h
    local blank_line = string.rep(" ", padded_width)

    for _ = 1, self._padding[1] do
        table.insert(padded, blank_line)
    end
    for _, line in ipairs(aligned) do
        table.insert(padded, pad_left_str .. line .. pad_right_str)
    end
    for _ = 1, self._padding[3] do
        table.insert(padded, blank_line)
    end

    -- Apply text SGR + background to each padded line
    local styled = {}
    for _, line in ipairs(padded) do
        local vis_w = ansi.visible_width(line)
        if vis_w < padded_width then
            line = line .. string.rep(" ", padded_width - vis_w)
        end
        if #sgr > 0 then
            table.insert(styled, sgr .. line .. ansi.RESET)
        else
            table.insert(styled, line)
        end
    end

    -- Apply border
    if bd then
        local bordered = {}
        local h_bar = string.rep(bd.horizontal, padded_width)

        if self._border_top then
            local top_l = self._border_left and bd.top_left or ""
            local top_r = self._border_right and bd.top_right or ""
            local top_line = top_l .. h_bar .. top_r
            if #bsgr > 0 then
                table.insert(bordered, bsgr .. top_line .. ansi.RESET)
            else
                table.insert(bordered, top_line)
            end
        end

        for _, line in ipairs(styled) do
            local row = ""
            if self._border_left then
                if #bsgr > 0 then
                    row = row .. bsgr .. bd.vertical .. ansi.RESET
                else
                    row = row .. bd.vertical
                end
            end
            row = row .. line
            if self._border_right then
                if #bsgr > 0 then
                    row = row .. bsgr .. bd.vertical .. ansi.RESET
                else
                    row = row .. bd.vertical
                end
            end
            table.insert(bordered, row)
        end

        if self._border_bottom then
            local bot_l = self._border_left and bd.bottom_left or ""
            local bot_r = self._border_right and bd.bottom_right or ""
            local bot_line = bot_l .. h_bar .. bot_r
            if #bsgr > 0 then
                table.insert(bordered, bsgr .. bot_line .. ansi.RESET)
            else
                table.insert(bordered, bot_line)
            end
        end

        styled = bordered
    end

    -- Apply margin
    local result = {}

    for _ = 1, self._margin[1] do
        table.insert(result, "")
    end

    local margin_left = string.rep(" ", self._margin[4])
    for _, line in ipairs(styled) do
        if self._margin[4] > 0 then
            table.insert(result, margin_left .. line)
        else
            table.insert(result, line)
        end
    end

    for _ = 1, self._margin[3] do
        table.insert(result, "")
    end

    return table.concat(result, "\n")
end

--- Shorthand: call the style object as a function to render.
StyleMT.__call = function(self, text)
    return self:render(text)
end

---------------------------------------------------------------------------
-- Quick inline style shortcuts (no box model, no allocation)
---------------------------------------------------------------------------

function style.bold(text: string): string
    return ansi.BOLD .. text .. ansi.RESET
end

function style.dim(text: string): string
    return ansi.DIM .. text .. ansi.RESET
end

function style.italic(text: string): string
    return ansi.ITALIC .. text .. ansi.RESET
end

function style.underline(text: string): string
    return ansi.UNDERLINE .. text .. ansi.RESET
end

function style.strikethrough(text: string): string
    return ansi.STRIKETHROUGH .. text .. ansi.RESET
end

function style.reverse(text: string): string
    return ansi.REVERSE .. text .. ansi.RESET
end

-- Named foreground colors
function style.red(text: string): string
    return ansi.FG_RED .. text .. ansi.RESET
end
function style.green(text: string): string
    return ansi.FG_GREEN .. text .. ansi.RESET
end
function style.yellow(text: string): string
    return ansi.FG_YELLOW .. text .. ansi.RESET
end
function style.blue(text: string): string
    return ansi.FG_BLUE .. text .. ansi.RESET
end
function style.magenta(text: string): string
    return ansi.FG_MAGENTA .. text .. ansi.RESET
end
function style.cyan(text: string): string
    return ansi.FG_CYAN .. text .. ansi.RESET
end
function style.white(text: string): string
    return ansi.FG_WHITE .. text .. ansi.RESET
end

--- Apply ANSI 256 foreground color.
function style.color(index: integer, text: string): string
    return ansi.fg256(index) .. text .. ansi.RESET
end

--- Apply RGB truecolor foreground.
function style.rgb(r: integer, g: integer, b: integer, text: string): string
    return ansi.fg_rgb(r, g, b) .. text .. ansi.RESET
end

--- Apply RGB truecolor background.
function style.bg_rgb(r: integer, g: integer, b: integer, text: string): string
    return ansi.bg_rgb(r, g, b) .. text .. ansi.RESET
end

--- Strip all ANSI escape sequences. Returns plain visible text.
function style.strip(text: string): string
    return ansi.strip(text)
end

return style
