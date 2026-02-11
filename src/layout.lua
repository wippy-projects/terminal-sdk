--- Layout primitives — horizontal/vertical joins, placement, and measurement.
--- Operates on rendered (multi-line) strings, composing them spatially.

local ansi = require("ansi")

local layout = {}

---------------------------------------------------------------------------
-- Measurement
---------------------------------------------------------------------------

--- Get the visible width of a rendered block (max line width).
function layout.width(s: string): integer
    return ansi.max_width(s)
end

--- Get the height (line count) of a rendered block.
function layout.height(s: string): integer
    return ansi.height(s)
end

--- Get both width and height as (width, height).
function layout.size(s: string): (integer, integer)
    local lines = ansi.lines(s)
    local max_w = 0
    for _, line in ipairs(lines) do
        local w = ansi.visible_width(line)
        if w > max_w then max_w = w end
    end
    return max_w, #lines
end

---------------------------------------------------------------------------
-- Position alignment for joins
---------------------------------------------------------------------------

layout.TOP    = "top"
layout.CENTER = "center"
layout.BOTTOM = "bottom"
layout.LEFT   = "left"
layout.RIGHT  = "right"

---------------------------------------------------------------------------
-- Horizontal join — place blocks side by side
---------------------------------------------------------------------------

--- Join multiple rendered blocks horizontally (left to right).
--- `position` controls vertical alignment: "top" (default), "center", "bottom".
--- Optional `gap` inserts N spaces between blocks.
function layout.horizontal(blocks: {string}, position: string?, gap: integer?): string
    position = position or "top"
    gap = gap or 0
    local gap_str = string.rep(" ", gap)

    if #blocks == 0 then return "" end
    if #blocks == 1 then return blocks[1] end

    -- Parse all blocks into line arrays and measure
    local parsed = {}
    local max_h = 0
    for _, block in ipairs(blocks) do
        local lines = ansi.lines(block)
        local w = 0
        for _, line in ipairs(lines) do
            local lw = ansi.visible_width(line)
            if lw > w then w = lw end
        end
        table.insert(parsed, { lines = lines, width = w, height = #lines })
        if #lines > max_h then max_h = #lines end
    end

    -- Pad each block's lines to uniform height and width
    local result_lines = {}
    for row = 1, max_h do
        local parts = {}
        for i, p in ipairs(parsed) do
            local offset = 0
            if position == "center" then
                offset = math.floor((max_h - p.height) / 2)
            elseif position == "bottom" then
                offset = max_h - p.height
            end

            local line_idx = row - offset
            local line
            if line_idx >= 1 and line_idx <= p.height then
                line = ansi.pad_right(p.lines[line_idx], p.width)
            else
                line = string.rep(" ", p.width)
            end

            table.insert(parts, line)
        end
        table.insert(result_lines, table.concat(parts, gap_str))
    end

    return table.concat(result_lines, "\n")
end

---------------------------------------------------------------------------
-- Vertical join — stack blocks top to bottom
---------------------------------------------------------------------------

--- Join multiple rendered blocks vertically (top to bottom).
--- `position` controls horizontal alignment: "left" (default), "center", "right".
--- Optional `gap` inserts N blank lines between blocks.
function layout.vertical(blocks: {string}, position: string?, gap: integer?): string
    position = position or "left"
    gap = gap or 0

    if #blocks == 0 then return "" end
    if #blocks == 1 then return blocks[1] end

    -- Find the widest block
    local max_w = 0
    local all_lines = {}
    for idx, block in ipairs(blocks) do
        local lines = ansi.lines(block)
        for _, line in ipairs(lines) do
            local w = ansi.visible_width(line)
            if w > max_w then max_w = w end
        end
        table.insert(all_lines, lines)
    end

    -- Combine with alignment
    local result = {}
    for idx, lines in ipairs(all_lines) do
        -- Insert gap between blocks (not before first)
        if idx > 1 and gap > 0 then
            for _ = 1, gap do
                table.insert(result, "")
            end
        end

        for _, line in ipairs(lines) do
            if position == "center" then
                table.insert(result, ansi.pad_center(line, max_w))
            elseif position == "right" then
                table.insert(result, ansi.pad_left(line, max_w))
            else
                table.insert(result, ansi.pad_right(line, max_w))
            end
        end
    end

    return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- Place — position a block within a larger canvas
---------------------------------------------------------------------------

--- Place a rendered block within a canvas of given dimensions.
--- `h_pos` = "left", "center", "right"
--- `v_pos` = "top", "center", "bottom"
function layout.place(
    width: integer,
    height: integer,
    h_pos: string,
    v_pos: string,
    content: string
): string
    h_pos = h_pos or "center"
    v_pos = v_pos or "center"

    local lines = ansi.lines(content)
    local content_h = #lines

    -- Vertical positioning
    local top_gap = 0
    if v_pos == "center" then
        top_gap = math.floor((height - content_h) / 2)
    elseif v_pos == "bottom" then
        top_gap = height - content_h
    end
    if top_gap < 0 then top_gap = 0 end

    local result = {}
    local empty_line = string.rep(" ", width)

    -- Top padding
    for _ = 1, top_gap do
        table.insert(result, empty_line)
    end

    -- Content lines with horizontal positioning
    for _, line in ipairs(lines) do
        if h_pos == "center" then
            table.insert(result, ansi.pad_center(line, width))
        elseif h_pos == "right" then
            table.insert(result, ansi.pad_left(line, width))
        else
            table.insert(result, ansi.pad_right(line, width))
        end
    end

    -- Bottom padding
    local used = top_gap + content_h
    for _ = used + 1, height do
        table.insert(result, empty_line)
    end

    return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- Utility: Table rendering
---------------------------------------------------------------------------

--- Render a simple table from headers and rows.
--- Each row is an array of strings. Returns a formatted multi-line string.
function layout.table(headers: {string}, rows: {{string}}, border_style: string?): string
    border_style = border_style or "normal"

    -- Calculate column widths
    local col_widths = {}
    for i, h in ipairs(headers) do
        col_widths[i] = ansi.visible_width(h)
    end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            local w = ansi.visible_width(cell)
            if not col_widths[i] or w > col_widths[i] then
                col_widths[i] = w
            end
        end
    end

    local result = {}

    -- Format a row
    local function fmt_row(cells)
        local parts = {}
        for i, cell in ipairs(cells) do
            table.insert(parts, " " .. ansi.pad_right(cell, col_widths[i]) .. " ")
        end
        return "│" .. table.concat(parts, "│") .. "│"
    end

    -- Horizontal separator
    local function separator(left, mid, right, fill)
        local parts = {}
        for _, w in ipairs(col_widths) do
            table.insert(parts, string.rep(fill, w + 2))
        end
        return left .. table.concat(parts, mid) .. right
    end

    table.insert(result, separator("┌", "┬", "┐", "─"))
    table.insert(result, fmt_row(headers))
    table.insert(result, separator("├", "┼", "┤", "─"))
    for _, row in ipairs(rows) do
        table.insert(result, fmt_row(row))
    end
    table.insert(result, separator("└", "┴", "┘", "─"))

    return table.concat(result, "\n")
end

return layout
