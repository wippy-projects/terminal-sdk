--- Border definitions and character sets.
--- Provides named border styles used by the style builder.

local border = {}

---------------------------------------------------------------------------
-- Border style type
---------------------------------------------------------------------------

type BorderStyle = {
    top_left: string,
    top_right: string,
    bottom_left: string,
    bottom_right: string,
    horizontal: string,
    vertical: string,
    middle_left: string?,
    middle_right: string?,
    middle_horizontal: string?,
    middle_top: string?,
    middle_bottom: string?,
    cross: string?,
}

---------------------------------------------------------------------------
-- Predefined border styles
---------------------------------------------------------------------------

border.none = {
    top_left = "", top_right = "", bottom_left = "", bottom_right = "",
    horizontal = "", vertical = "",
}

border.hidden = {
    top_left = " ", top_right = " ", bottom_left = " ", bottom_right = " ",
    horizontal = " ", vertical = " ",
}

border.normal = {
    top_left = "┌", top_right = "┐", bottom_left = "└", bottom_right = "┘",
    horizontal = "─", vertical = "│",
    middle_left = "├", middle_right = "┤",
    middle_horizontal = "─",
    middle_top = "┬", middle_bottom = "┴",
    cross = "┼",
}

border.rounded = {
    top_left = "╭", top_right = "╮", bottom_left = "╰", bottom_right = "╯",
    horizontal = "─", vertical = "│",
    middle_left = "├", middle_right = "┤",
    middle_horizontal = "─",
    middle_top = "┬", middle_bottom = "┴",
    cross = "┼",
}

border.thick = {
    top_left = "┏", top_right = "┓", bottom_left = "┗", bottom_right = "┛",
    horizontal = "━", vertical = "┃",
    middle_left = "┣", middle_right = "┫",
    middle_horizontal = "━",
    middle_top = "┳", middle_bottom = "┻",
    cross = "╋",
}

border.double = {
    top_left = "╔", top_right = "╗", bottom_left = "╚", bottom_right = "╝",
    horizontal = "═", vertical = "║",
    middle_left = "╠", middle_right = "╣",
    middle_horizontal = "═",
    middle_top = "╦", middle_bottom = "╩",
    cross = "╬",
}

border.block = {
    top_left = "█", top_right = "█", bottom_left = "█", bottom_right = "█",
    horizontal = "█", vertical = "█",
}

border.inner_half_block = {
    top_left = "▗", top_right = "▖", bottom_left = "▝", bottom_right = "▘",
    horizontal = "▄", vertical = "▐",
}

border.outer_half_block = {
    top_left = "▛", top_right = "▜", bottom_left = "▙", bottom_right = "▟",
    horizontal = "▀", vertical = "▌",
}

--- ASCII fallback for non-unicode terminals.
border.ascii = {
    top_left = "+", top_right = "+", bottom_left = "+", bottom_right = "+",
    horizontal = "-", vertical = "|",
    middle_left = "+", middle_right = "+",
    middle_horizontal = "-",
    middle_top = "+", middle_bottom = "+",
    cross = "+",
}

--- Get a border style by name. Returns `border.none` for unknown names.
function border.get(name: string): BorderStyle
    return border[name] or border.none
end

--- List all available border style names.
function border.styles(): {string}
    return {
        "none", "hidden", "normal", "rounded", "thick",
        "double", "block", "inner_half_block", "outer_half_block", "ascii"
    }
end

return border
