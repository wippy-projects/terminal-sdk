--- Color system for the TUI toolkit.
--- Supports named colors, ANSI 16, ANSI 256, hex truecolor, adaptive light/dark profiles.
--- Colors are tables with a `kind` discriminator for profile downsampling.

local ansi = require("ansi")

local color = {}

---------------------------------------------------------------------------
-- Color profiles
---------------------------------------------------------------------------

color.PROFILE_NONE      = "none"
color.PROFILE_ANSI16    = "16"
color.PROFILE_ANSI256   = "256"
color.PROFILE_TRUECOLOR = "truecolor"

--- Current active profile. Defaults to truecolor — downsampling at render time.
color._profile = color.PROFILE_TRUECOLOR

--- Whether terminal has dark background (nil = unknown, true = dark, false = light).
color._dark_background = true

--- Set the active color profile.
function color.set_profile(profile: string)
    color._profile = profile
end

--- Get the active color profile.
function color.profile(): string
    return color._profile
end

--- Set dark/light background hint.
function color.set_dark_background(dark: boolean?)
    color._dark_background = dark
end

--- Is the terminal background dark?
function color.is_dark(): boolean?
    return color._dark_background
end

---------------------------------------------------------------------------
-- Color type
---------------------------------------------------------------------------

type Color = {
    kind: string,       -- "ansi" | "ansi256" | "rgb" | "adaptive" | "none"
    code: integer?,     -- ANSI code (0–15) or 256-palette index
    r: integer?,
    g: integer?,
    b: integer?,
    light: Color?,      -- adaptive: color for light background
    dark: Color?,       -- adaptive: color for dark background
}

---------------------------------------------------------------------------
-- Constructors
---------------------------------------------------------------------------

--- No color (transparent / default).
function color.none(): Color
    return { kind = "none" }
end

--- Standard ANSI color by code (0–15).
function color.ansi(code: integer): Color
    return { kind = "ansi", code = code }
end

--- ANSI 256-palette color (0–255).
function color.ansi256(index: integer): Color
    return { kind = "ansi256", code = index }
end

--- Truecolor from RGB components (each 0–255).
function color.rgb(r: integer, g: integer, b: integer): Color
    return { kind = "rgb", r = r, g = g, b = b }
end

--- Truecolor from hex string: "#ff5500", "ff5500", "#f50".
function color.hex(hex_str: string): Color
    local s = hex_str:gsub("^#", "")
    if #s == 3 then
        s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
    end
    local r = tonumber(s:sub(1, 2), 16) or 0
    local g = tonumber(s:sub(3, 4), 16) or 0
    local b = tonumber(s:sub(5, 6), 16) or 0
    return { kind = "rgb", r = r, g = g, b = b }
end

--- Adaptive color that selects based on terminal background.
--- `light_color` is used on light backgrounds, `dark_color` on dark.
--- Both can be Color tables or hex strings.
function color.adaptive(light, dark): Color
    local function resolve(c)
        if type(c) == "string" then return color.hex(c) end
        return c
    end
    return { kind = "adaptive", light = resolve(light), dark = resolve(dark) }
end

---------------------------------------------------------------------------
-- Named color constants
---------------------------------------------------------------------------

color.black   = color.ansi(0)
color.red     = color.ansi(1)
color.green   = color.ansi(2)
color.yellow  = color.ansi(3)
color.blue    = color.ansi(4)
color.magenta = color.ansi(5)
color.cyan    = color.ansi(6)
color.white   = color.ansi(7)

color.bright_black   = color.ansi(8)
color.bright_red     = color.ansi(9)
color.bright_green   = color.ansi(10)
color.bright_yellow  = color.ansi(11)
color.bright_blue    = color.ansi(12)
color.bright_magenta = color.ansi(13)
color.bright_cyan    = color.ansi(14)
color.bright_white   = color.ansi(15)

--- Named color lookup table (string → Color).
local NAMED = {
    black   = color.black,   red     = color.red,
    green   = color.green,   yellow  = color.yellow,
    blue    = color.blue,    magenta = color.magenta,
    cyan    = color.cyan,    white   = color.white,
    bright_black   = color.bright_black,
    bright_red     = color.bright_red,
    bright_green   = color.bright_green,
    bright_yellow  = color.bright_yellow,
    bright_blue    = color.bright_blue,
    bright_magenta = color.bright_magenta,
    bright_cyan    = color.bright_cyan,
    bright_white   = color.bright_white,
}

--- Resolve a color from various input formats:
---  - Color table → returned as-is
---  - "#hex" string → parsed as hex
---  - "red" / named string → looked up
---  - "196" / numeric string → ANSI 256
---  - nil → color.none()
function color.resolve(c): Color
    if c == nil then return color.none() end
    if type(c) == "table" then return c end
    if type(c) == "string" then
        -- Named color
        if NAMED[c] then return NAMED[c] end
        -- Hex color
        if c:sub(1, 1) == "#" then return color.hex(c) end
        -- Try as ANSI 256 index
        local n = tonumber(c)
        if n and n >= 0 and n <= 255 then return color.ansi256(n) end
        -- Fallback: try hex without #
        if #c == 6 and c:match("^%x+$") then return color.hex(c) end
    end
    return color.none()
end

---------------------------------------------------------------------------
-- RGB downsampling
---------------------------------------------------------------------------

local function rgb_to_256(r: integer, g: integer, b: integer): integer
    if r == g and g == b then
        if r < 8 then return 16 end
        if r > 248 then return 231 end
        return math.floor((r - 8) / 247 * 24) + 232
    end
    local ri = math.floor(r / 255 * 5 + 0.5)
    local gi = math.floor(g / 255 * 5 + 0.5)
    local bi = math.floor(b / 255 * 5 + 0.5)
    return 16 + 36 * ri + 6 * gi + bi
end

local function rgb_to_16(r: integer, g: integer, b: integer): integer
    local brightness = (r * 299 + g * 587 + b * 114) / 1000
    local bright = brightness > 128
    local function hi(v) return v > 128 end
    local base = 0
    if hi(r) then base = base + 1 end
    if hi(g) then base = base + 2 end
    if hi(b) then base = base + 4 end
    if bright and base > 0 then base = base + 8 end
    return base
end

---------------------------------------------------------------------------
-- Resolve adaptive colors
---------------------------------------------------------------------------

local function resolve_adaptive(c: Color): Color
    if c.kind ~= "adaptive" then return c end
    if color._dark_background then
        return c.dark or c.light or color.none()
    else
        return c.light or c.dark or color.none()
    end
end

---------------------------------------------------------------------------
-- Rendering (Color → ANSI escape string)
---------------------------------------------------------------------------

--- Render a color as a foreground ANSI sequence, respecting the active profile.
function color.fg(c: Color): string
    if not c or c.kind == "none" then return "" end
    c = resolve_adaptive(c)
    if c.kind == "none" then return "" end

    local profile = color._profile
    if profile == color.PROFILE_NONE then return "" end

    if c.kind == "rgb" then
        if profile == color.PROFILE_TRUECOLOR then
            return ansi.fg_rgb(c.r, c.g, c.b)
        elseif profile == color.PROFILE_ANSI256 then
            return ansi.fg256(rgb_to_256(c.r, c.g, c.b))
        else
            return ansi.fg256(rgb_to_16(c.r, c.g, c.b))
        end
    elseif c.kind == "ansi256" then
        if profile == color.PROFILE_TRUECOLOR or profile == color.PROFILE_ANSI256 then
            return ansi.fg256(c.code)
        else
            if c.code < 16 then return ansi.fg256(c.code) end
            return ""
        end
    elseif c.kind == "ansi" then
        if c.code < 8 then
            return "\027[" .. (30 + c.code) .. "m"
        else
            return "\027[" .. (90 + c.code - 8) .. "m"
        end
    end
    return ""
end

--- Render a color as a background ANSI sequence, respecting the active profile.
function color.bg(c: Color): string
    if not c or c.kind == "none" then return "" end
    c = resolve_adaptive(c)
    if c.kind == "none" then return "" end

    local profile = color._profile
    if profile == color.PROFILE_NONE then return "" end

    if c.kind == "rgb" then
        if profile == color.PROFILE_TRUECOLOR then
            return ansi.bg_rgb(c.r, c.g, c.b)
        elseif profile == color.PROFILE_ANSI256 then
            return ansi.bg256(rgb_to_256(c.r, c.g, c.b))
        else
            return ansi.bg256(rgb_to_16(c.r, c.g, c.b))
        end
    elseif c.kind == "ansi256" then
        if profile == color.PROFILE_TRUECOLOR or profile == color.PROFILE_ANSI256 then
            return ansi.bg256(c.code)
        else
            if c.code < 16 then return ansi.bg256(c.code) end
            return ""
        end
    elseif c.kind == "ansi" then
        if c.code < 8 then
            return "\027[" .. (40 + c.code) .. "m"
        else
            return "\027[" .. (100 + c.code - 8) .. "m"
        end
    end
    return ""
end

return color
