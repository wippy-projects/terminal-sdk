--- ANSI escape code primitives.
--- Low-level SGR sequences, cursor control, and screen operations.
--- This module produces raw escape strings — higher layers (color, style) build on it.

local ansi = {}

--- Escape sequence prefix
local ESC = "\027["

--- Reset all attributes
ansi.RESET = ESC .. "0m"

---------------------------------------------------------------------------
-- SGR (Select Graphic Rendition) text attributes
---------------------------------------------------------------------------

ansi.BOLD           = ESC .. "1m"
ansi.DIM            = ESC .. "2m"
ansi.ITALIC         = ESC .. "3m"
ansi.UNDERLINE      = ESC .. "4m"
ansi.BLINK          = ESC .. "5m"
ansi.REVERSE        = ESC .. "7m"
ansi.HIDDEN         = ESC .. "8m"
ansi.STRIKETHROUGH  = ESC .. "9m"

ansi.NO_BOLD          = ESC .. "22m"
ansi.NO_DIM           = ESC .. "22m"
ansi.NO_ITALIC        = ESC .. "23m"
ansi.NO_UNDERLINE     = ESC .. "24m"
ansi.NO_BLINK         = ESC .. "25m"
ansi.NO_REVERSE       = ESC .. "27m"
ansi.NO_HIDDEN        = ESC .. "28m"
ansi.NO_STRIKETHROUGH = ESC .. "29m"

---------------------------------------------------------------------------
-- Standard foreground colors (30–37)
---------------------------------------------------------------------------

ansi.FG_BLACK   = ESC .. "30m"
ansi.FG_RED     = ESC .. "31m"
ansi.FG_GREEN   = ESC .. "32m"
ansi.FG_YELLOW  = ESC .. "33m"
ansi.FG_BLUE    = ESC .. "34m"
ansi.FG_MAGENTA = ESC .. "35m"
ansi.FG_CYAN    = ESC .. "36m"
ansi.FG_WHITE   = ESC .. "37m"
ansi.FG_DEFAULT = ESC .. "39m"

---------------------------------------------------------------------------
-- Standard background colors (40–47)
---------------------------------------------------------------------------

ansi.BG_BLACK   = ESC .. "40m"
ansi.BG_RED     = ESC .. "41m"
ansi.BG_GREEN   = ESC .. "42m"
ansi.BG_YELLOW  = ESC .. "43m"
ansi.BG_BLUE    = ESC .. "44m"
ansi.BG_MAGENTA = ESC .. "45m"
ansi.BG_CYAN    = ESC .. "46m"
ansi.BG_WHITE   = ESC .. "47m"
ansi.BG_DEFAULT = ESC .. "49m"

---------------------------------------------------------------------------
-- Bright foreground (90–97)
---------------------------------------------------------------------------

ansi.FG_BRIGHT_BLACK   = ESC .. "90m"
ansi.FG_BRIGHT_RED     = ESC .. "91m"
ansi.FG_BRIGHT_GREEN   = ESC .. "92m"
ansi.FG_BRIGHT_YELLOW  = ESC .. "93m"
ansi.FG_BRIGHT_BLUE    = ESC .. "94m"
ansi.FG_BRIGHT_MAGENTA = ESC .. "95m"
ansi.FG_BRIGHT_CYAN    = ESC .. "96m"
ansi.FG_BRIGHT_WHITE   = ESC .. "97m"

---------------------------------------------------------------------------
-- Bright background (100–107)
---------------------------------------------------------------------------

ansi.BG_BRIGHT_BLACK   = ESC .. "100m"
ansi.BG_BRIGHT_RED     = ESC .. "101m"
ansi.BG_BRIGHT_GREEN   = ESC .. "102m"
ansi.BG_BRIGHT_YELLOW  = ESC .. "103m"
ansi.BG_BRIGHT_BLUE    = ESC .. "104m"
ansi.BG_BRIGHT_MAGENTA = ESC .. "105m"
ansi.BG_BRIGHT_CYAN    = ESC .. "106m"
ansi.BG_BRIGHT_WHITE   = ESC .. "107m"

---------------------------------------------------------------------------
-- Dynamic color sequences
---------------------------------------------------------------------------

--- Foreground color from 256-color palette (0–255)
function ansi.fg256(n: integer): string
    return ESC .. "38;5;" .. n .. "m"
end

--- Background color from 256-color palette (0–255)
function ansi.bg256(n: integer): string
    return ESC .. "48;5;" .. n .. "m"
end

--- Foreground color from RGB truecolor
function ansi.fg_rgb(r: integer, g: integer, b: integer): string
    return ESC .. "38;2;" .. r .. ";" .. g .. ";" .. b .. "m"
end

--- Background color from RGB truecolor
function ansi.bg_rgb(r: integer, g: integer, b: integer): string
    return ESC .. "48;2;" .. r .. ";" .. g .. ";" .. b .. "m"
end

---------------------------------------------------------------------------
-- Cursor control
---------------------------------------------------------------------------

function ansi.cursor_up(n: integer?): string
    return ESC .. (n or 1) .. "A"
end

function ansi.cursor_down(n: integer?): string
    return ESC .. (n or 1) .. "B"
end

function ansi.cursor_right(n: integer?): string
    return ESC .. (n or 1) .. "C"
end

function ansi.cursor_left(n: integer?): string
    return ESC .. (n or 1) .. "D"
end

function ansi.cursor_move_to(row: integer, col: integer): string
    return ESC .. row .. ";" .. col .. "H"
end

ansi.CURSOR_HIDE    = ESC .. "?25l"
ansi.CURSOR_SHOW    = ESC .. "?25h"
ansi.CURSOR_SAVE    = ESC .. "s"
ansi.CURSOR_RESTORE = ESC .. "u"

---------------------------------------------------------------------------
-- Screen operations
---------------------------------------------------------------------------

ansi.CLEAR_SCREEN     = ESC .. "2J"
ansi.CLEAR_LINE       = ESC .. "2K"
ansi.CLEAR_LINE_RIGHT = ESC .. "0K"
ansi.CLEAR_LINE_LEFT  = ESC .. "1K"
ansi.CLEAR_DOWN       = ESC .. "0J"
ansi.CLEAR_UP         = ESC .. "1J"

ansi.ALT_SCREEN_ON  = ESC .. "?1049h"
ansi.ALT_SCREEN_OFF = ESC .. "?1049l"

---------------------------------------------------------------------------
-- Mouse tracking
---------------------------------------------------------------------------

-- SGR mouse mode (1006) with button events (1000) and motion tracking (1003)
ansi.MOUSE_ENABLE       = ESC .. "?1000h" .. ESC .. "?1006h"
ansi.MOUSE_DISABLE      = ESC .. "?1000l" .. ESC .. "?1006l"
-- Extended: also track motion (any-event mode)
ansi.MOUSE_MOTION_ENABLE  = ESC .. "?1003h" .. ESC .. "?1006h"
ansi.MOUSE_MOTION_DISABLE = ESC .. "?1003l" .. ESC .. "?1006l"

--- Parse an SGR mouse sequence into a structured event.
--- SGR format: ESC[<btn;col;row(M|m)
---   M = press, m = release
---   btn bits: 0=left, 1=middle, 2=right, 32=motion, 64=scroll
--- Returns a table {kind="mouse", button, action, row, col, shift, alt, ctrl} or nil.
function ansi.parse_mouse_sgr(seq: string)
    local btn_s, col_s, row_s, suffix = seq:match("^%[<(%d+);(%d+);(%d+)([Mm])$")
    if not btn_s then return nil end

    local btn = tonumber(btn_s)
    local col = tonumber(col_s)
    local row = tonumber(row_s)
    local released = (suffix == "m")

    local shift = (btn & 4) ~= 0
    local alt   = (btn & 8) ~= 0
    local ctrl  = (btn & 16) ~= 0
    local motion = (btn & 32) ~= 0
    local base = btn & 3

    local action
    local button

    if (btn & 64) ~= 0 then
        -- Scroll events
        button = "scroll"
        action = (base == 0) and "scroll_up" or "scroll_down"
    elseif motion then
        button = ({"left", "middle", "right"})[base + 1] or "none"
        action = "motion"
    elseif released then
        button = ({"left", "middle", "right"})[base + 1] or "none"
        action = "release"
    else
        button = ({"left", "middle", "right"})[base + 1] or "none"
        action = "press"
    end

    return {
        kind = "mouse",
        button = button,
        action = action,
        row = row,
        col = col,
        shift = shift,
        alt = alt,
        ctrl = ctrl,
    }
end

--- Hit-test helper: check if mouse event is within a rectangular region.
--- Region is defined as {row, col, width, height} (1-based, inclusive).
function ansi.in_region(mouse_event, row: integer, col: integer, width: integer, height: integer): boolean
    local mr = mouse_event.row
    local mc = mouse_event.col
    return mr >= row and mr < row + height and mc >= col and mc < col + width
end

---------------------------------------------------------------------------
-- String measurement (strip ANSI for width calculation)
---------------------------------------------------------------------------

--- Strip all ANSI escape sequences from a string.
--- Returns the visible text only.
function ansi.strip(s: string): string
    return s:gsub("\027%[[%d;]*[A-Za-z]", "")
end

--- Measure the visible width of a string (ignoring ANSI escapes).
function ansi.visible_width(s: string): integer
    return #ansi.strip(s)
end

--- Split a string into lines.
function ansi.lines(s: string): {string}
    local result = {}
    for line in s:gmatch("([^\n]*)\n?") do
        -- gmatch produces an extra empty string at the end for strings ending with \n
        -- Only skip the very last empty match
        table.insert(result, line)
    end
    -- Remove trailing empty line artifact
    if #result > 0 and result[#result] == "" then
        table.remove(result)
    end
    -- If input was empty, return one empty line
    if #result == 0 then
        table.insert(result, "")
    end
    return result
end

--- Measure the widest visible line in a (potentially multi-line) string.
function ansi.max_width(s: string): integer
    local max = 0
    for _, line in ipairs(ansi.lines(s)) do
        local w = ansi.visible_width(line)
        if w > max then max = w end
    end
    return max
end

--- Measure the height (number of lines) of a string.
function ansi.height(s: string): integer
    return #ansi.lines(s)
end

--- Pad a string on the right to a given visible width with a fill char.
function ansi.pad_right(s: string, width: integer, fill: string?): string
    fill = fill or " "
    local visible = ansi.visible_width(s)
    if visible >= width then return s end
    return s .. string.rep(fill, width - visible)
end

--- Pad a string on the left to a given visible width.
function ansi.pad_left(s: string, width: integer, fill: string?): string
    fill = fill or " "
    local visible = ansi.visible_width(s)
    if visible >= width then return s end
    return string.rep(fill, width - visible) .. s
end

--- Center a string within a given width.
function ansi.pad_center(s: string, width: integer, fill: string?): string
    fill = fill or " "
    local visible = ansi.visible_width(s)
    if visible >= width then return s end
    local total_pad = width - visible
    local left = math.floor(total_pad / 2)
    local right = total_pad - left
    return string.rep(fill, left) .. s .. string.rep(fill, right)
end

return ansi
