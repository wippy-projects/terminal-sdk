--- CLI output helpers — structured terminal output.
---
--- Provides table(), panel(), definitions(), tree(), and rule() renderers
--- for rich CLI output using the tui style system.
---
--- Usage:
---   local output = require("output")
---   local style = require("style")
---
---   io.print(output.table(
---       {"Name", "Status", "Uptime"},
---       {
---           {"web-1", "running", "3d 12h"},
---           {"web-2", "stopped", "--"},
---       }
---   ))
---
---   io.print(output.panel("Hello World", { title = "Greeting", border = "rounded" }))

local ansi = require("ansi")
local color_mod = require("color")
local border_defs = require("border_defs")

local output = {}

---------------------------------------------------------------------------
-- Table renderer
---------------------------------------------------------------------------

--- Render a formatted table with headers and rows.
---
--- Options:
---   border: string — border style name (default: "normal")
---   header_style: style object for header cells
---   padding: integer — cell padding (default: 1)
---   max_width: integer? — max total table width (truncate cells)
function output.table(headers: {string}, rows: {{string}}, opts)
    opts = opts or {}
    local bd = border_defs.get(opts.border or "normal")
    local pad = opts.padding or 1
    local pad_str = string.rep(" ", pad)

    -- Calculate column widths
    local col_count = #headers
    local col_widths = {}
    for i, h in ipairs(headers) do
        col_widths[i] = ansi.visible_width(h)
    end
    for _, row in ipairs(rows) do
        for i = 1, col_count do
            local cell = row[i] or ""
            local w = ansi.visible_width(cell)
            if w > (col_widths[i] or 0) then
                col_widths[i] = w
            end
        end
    end

    -- Max width truncation
    if opts.max_width then
        local total = 1  -- left border
        for i, w in ipairs(col_widths) do
            total = total + w + pad * 2 + 1  -- cell + padding + separator
        end
        if total > opts.max_width then
            -- Proportionally shrink columns
            local available = opts.max_width - col_count - 1 - col_count * pad * 2
            if available < col_count then available = col_count end
            local total_w = 0
            for _, w in ipairs(col_widths) do total_w = total_w + w end
            for i, w in ipairs(col_widths) do
                col_widths[i] = math.max(1, math.floor(w / total_w * available))
            end
        end
    end

    local result = {}

    -- Format a data row
    local function fmt_row(cells, is_header)
        local parts = {}
        for i = 1, col_count do
            local cell = cells[i] or ""
            local vis_w = ansi.visible_width(cell)
            local target = col_widths[i]

            -- Truncate if needed
            if vis_w > target then
                local plain = ansi.strip(cell)
                if target > 1 then
                    cell = plain:sub(1, target - 1) .. "…"
                else
                    cell = plain:sub(1, target)
                end
            end

            local padded = pad_str .. ansi.pad_right(cell, target) .. pad_str
            table.insert(parts, padded)
        end
        return bd.vertical .. table.concat(parts, bd.vertical) .. bd.vertical
    end

    -- Horizontal separator
    local function separator(left, mid, right)
        local segs = {}
        for i, w in ipairs(col_widths) do
            table.insert(segs, string.rep(bd.horizontal, w + pad * 2))
        end
        return left .. table.concat(segs, mid) .. right
    end

    -- Top border
    table.insert(result, separator(
        bd.top_left, bd.middle_top or bd.horizontal, bd.top_right
    ))

    -- Header
    table.insert(result, fmt_row(headers, true))

    -- Header separator
    table.insert(result, separator(
        bd.middle_left or bd.vertical,
        bd.cross or bd.horizontal,
        bd.middle_right or bd.vertical
    ))

    -- Data rows
    for _, row in ipairs(rows) do
        table.insert(result, fmt_row(row, false))
    end

    -- Bottom border
    table.insert(result, separator(
        bd.bottom_left, bd.middle_bottom or bd.horizontal, bd.bottom_right
    ))

    return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- Panel renderer
---------------------------------------------------------------------------

--- Render text inside a bordered panel with optional title.
---
--- Options:
---   title: string? — title displayed in top border
---   border: string — border style name (default: "rounded")
---   width: integer? — fixed width (nil = auto)
---   padding: integer — inner padding (default: 1)
---   title_color: Color or hex string for title
---   border_color: Color or hex string for border
function output.panel(text: string, opts)
    opts = opts or {}
    local bd = border_defs.get(opts.border or "rounded")
    local pad = opts.padding or 1
    local pad_str = string.rep(" ", pad)

    local lines = ansi.lines(text)

    -- Calculate content width
    local content_w = 0
    for _, line in ipairs(lines) do
        local w = ansi.visible_width(line)
        if w > content_w then content_w = w end
    end

    -- Apply fixed width
    local inner_w = content_w + pad * 2
    if opts.width then
        inner_w = opts.width - 2  -- minus border characters
        if inner_w < 1 then inner_w = 1 end
        content_w = inner_w - pad * 2
        if content_w < 0 then content_w = 0 end
    end

    local result = {}

    -- Border color helpers
    local bc_on = ""
    local bc_off = ""
    if opts.border_color then
        local c = color_mod.resolve(opts.border_color)
        bc_on = color_mod.fg(c)
        bc_off = ansi.RESET
    end

    -- Top border with optional title
    local top_bar = string.rep(bd.horizontal, inner_w)
    if opts.title then
        local title = opts.title
        if opts.title_color then
            local tc = color_mod.resolve(opts.title_color)
            title = color_mod.fg(tc) .. " " .. title .. " " .. ansi.RESET
            local title_vis = ansi.visible_width(opts.title) + 2
            if title_vis < inner_w then
                top_bar = bd.horizontal ..
                    bc_off .. title .. bc_on ..
                    string.rep(bd.horizontal, inner_w - title_vis - 1)
            end
        else
            local title_vis = #opts.title + 2
            if title_vis < inner_w then
                top_bar = bd.horizontal .. " " .. opts.title .. " " ..
                    string.rep(bd.horizontal, inner_w - title_vis - 1)
            end
        end
    end
    table.insert(result, bc_on .. bd.top_left .. top_bar .. bd.top_right .. bc_off)

    -- Content lines
    for _, line in ipairs(lines) do
        local padded = pad_str .. ansi.pad_right(line, content_w) .. pad_str
        table.insert(result,
            bc_on .. bd.vertical .. bc_off ..
            padded ..
            bc_on .. bd.vertical .. bc_off
        )
    end

    -- Bottom border
    table.insert(result,
        bc_on .. bd.bottom_left .. string.rep(bd.horizontal, inner_w) .. bd.bottom_right .. bc_off
    )

    return table.concat(result, "\n")
end

---------------------------------------------------------------------------
-- Definitions list renderer
---------------------------------------------------------------------------

--- Render a key-value definitions list.
---
--- Items is an array of {key, value} pairs.
---
--- Options:
---   separator: string — between key and value (default: " : ")
---   key_color: Color or hex string
---   value_color: Color or hex string
---   indent: integer — left indent (default: 0)
function output.definitions(items: {{string}}, opts)
    opts = opts or {}
    local sep = opts.separator or " : "
    local indent = string.rep(" ", opts.indent or 0)

    -- Measure max key width
    local max_key = 0
    for _, item in ipairs(items) do
        local w = ansi.visible_width(item[1])
        if w > max_key then max_key = w end
    end

    local lines = {}
    local key_on, key_off = "", ""
    local val_on, val_off = "", ""

    if opts.key_color then
        local c = color_mod.resolve(opts.key_color)
        key_on = color_mod.fg(c)
        key_off = ansi.RESET
    end
    if opts.value_color then
        local c = color_mod.resolve(opts.value_color)
        val_on = color_mod.fg(c)
        val_off = ansi.RESET
    end

    for _, item in ipairs(items) do
        local key = item[1]
        local value = item[2] or ""
        local padded_key = ansi.pad_right(key, max_key)
        table.insert(lines,
            indent .. key_on .. padded_key .. key_off ..
            sep ..
            val_on .. value .. val_off
        )
    end

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Tree renderer
---------------------------------------------------------------------------

--- Render a tree structure.
---
--- Each node is { label = "text", children = { ... } }.
---
--- Options:
---   indent: integer — initial indent (default: 0)
---   guides: boolean — show tree guide lines (default: true)
function output.tree(root, opts)
    opts = opts or {}
    local show_guides = opts.guides ~= false
    local lines = {}

    local function render_node(node, prefix, is_last)
        local connector
        if prefix == "" then
            connector = ""
        elseif is_last then
            connector = show_guides and "└── " or "    "
        else
            connector = show_guides and "├── " or "    "
        end

        table.insert(lines, prefix .. connector .. (node.label or ""))

        local children = node.children or {}
        local child_prefix
        if prefix == "" then
            child_prefix = ""
        elseif is_last then
            child_prefix = prefix .. (show_guides and "    " or "    ")
        else
            child_prefix = prefix .. (show_guides and "│   " or "    ")
        end

        for i, child in ipairs(children) do
            render_node(child, child_prefix, i == #children)
        end
    end

    render_node(root, "", true)
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Horizontal rule
---------------------------------------------------------------------------

--- Render a horizontal rule (divider line).
---
--- Options:
---   width: integer — rule width (default: 40)
---   char: string — fill character (default: "─")
---   title: string? — centered title text
---   color: Color or hex string
function output.rule(opts)
    opts = opts or {}
    local width = opts.width or 40
    local char = opts.char or "─"
    local c_on, c_off = "", ""

    if opts.color then
        local c = color_mod.resolve(opts.color)
        c_on = color_mod.fg(c)
        c_off = ansi.RESET
    end

    if opts.title then
        local title = " " .. opts.title .. " "
        local title_w = #title
        if title_w >= width then
            return c_on .. title .. c_off
        end
        local left = math.floor((width - title_w) / 2)
        local right = width - title_w - left
        return c_on .. string.rep(char, left) .. c_off ..
               title ..
               c_on .. string.rep(char, right) .. c_off
    end

    return c_on .. string.rep(char, width) .. c_off
end

return output
