--- Table component — navigable data table with row selection and column definitions.
---
--- Usage within a tui.app:
---   local tbl = require("table_view")
---
---   local columns = {
---       { key = "name",   title = "Name",   width = 20 },
---       { key = "status", title = "Status",  width = 10 },
---       { key = "count",  title = "Count",   width = 8, align = "right" },
---   }
---   local rows = {
---       { name = "Alpha",   status = "active",  count = 42 },
---       { name = "Beta",    status = "pending", count = 7 },
---       { name = "Gamma",   status = "done",    count = 100 },
---   }
---
---   init = function()
---       return { tbl = tbl.new({ columns = columns, rows = rows, height = 10 }) }
---   end,
---   update = function(model, msg)
---       model.tbl = tbl.update(model.tbl, msg)
---       return model
---   end,
---   view = function(model)
---       return tbl.view(model.tbl)
---   end
---
--- Responds to key messages: up/down for row navigation,
--- pgup/pgdn for page scrolling, home/end for first/last row.

local table_view = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new table model.
---
--- Options:
---   columns: array of column definitions
---       { key: string, title: string, width: integer, align?: "left"|"right"|"center",
---         render?: function(value, row, col) → string }
---   rows: array of row tables (keyed by column.key)
---   height: integer — visible row count, not including header (default: 10)
---   show_header: boolean — show header row (default: true)
---   cursor_enabled: boolean — enable row selection (default: true)
---   style: style for the table
---   header_style: style for header row
---   selected_style: style for the selected row
---   cell_style: style for normal cells
---   border_char: string — column separator character (default: "│")
---   header_border_char: string — header underline character (default: "─")
function table_view.new(opts)
    opts = opts or {}
    return {
        _type = "table_view",
        _columns = opts.columns or {},
        _rows = opts.rows or {},
        _cursor = 1,               -- selected row (1-based)
        _offset = 0,               -- scroll offset
        _height = opts.height or 10,
        _show_header = opts.show_header ~= false,
        _cursor_enabled = opts.cursor_enabled ~= false,
        _style = opts.style or nil,
        _header_style = opts.header_style or nil,
        _selected_style = opts.selected_style or nil,
        _cell_style = opts.cell_style or nil,
        _border_char = opts.border_char or "│",
        _header_border_char = opts.header_border_char or "─",
    }
end

---------------------------------------------------------------------------
-- Internal: cell formatting
---------------------------------------------------------------------------

local function truncate(s: string, width: integer): string
    if #s <= width then return s end
    if width <= 1 then return s:sub(1, width) end
    return s:sub(1, width - 1) .. "…"
end

local function align_cell(text: string, width: integer, alignment: string?): string
    local t = truncate(text, width)
    local pad = width - #t
    if pad <= 0 then return t end

    if alignment == "right" then
        return string.rep(" ", pad) .. t
    elseif alignment == "center" then
        local left = math.floor(pad / 2)
        local right = pad - left
        return string.rep(" ", left) .. t .. string.rep(" ", right)
    end
    -- left (default)
    return t .. string.rep(" ", pad)
end

---------------------------------------------------------------------------
-- Scroll helpers
---------------------------------------------------------------------------

local function ensure_visible(model)
    if model._cursor <= model._offset then
        model._offset = model._cursor - 1
    elseif model._cursor > model._offset + model._height then
        model._offset = model._cursor - model._height
    end
    local max_offset = math.max(0, #model._rows - model._height)
    if model._offset < 0 then model._offset = 0 end
    if model._offset > max_offset then model._offset = max_offset end
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get the currently selected row (or nil).
function table_view.selected(model)
    if #model._rows == 0 then return nil end
    return model._rows[model._cursor]
end

--- Get the selected row index (1-based).
function table_view.selected_index(model): integer
    return model._cursor
end

--- Get total row count.
function table_view.row_count(model): integer
    return #model._rows
end

--- Set rows and reset cursor.
function table_view.set_rows(model, rows)
    model._rows = rows
    if model._cursor > #rows then
        model._cursor = math.max(1, #rows)
    end
    model._offset = 0
    ensure_visible(model)
    return model
end

--- Set columns.
function table_view.set_columns(model, columns)
    model._columns = columns
    return model
end

--- Move cursor to specific row.
function table_view.select_row(model, idx: integer)
    model._cursor = math.max(1, math.min(idx, #model._rows))
    ensure_visible(model)
    return model
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update table state based on key messages.
function table_view.update(model, msg)
    if not model._cursor_enabled then return model end
    if msg.kind ~= "key" then return model end
    if #model._rows == 0 then return model end

    local key = msg.key

    if key == "up" or key == "k" then
        if model._cursor > 1 then
            model._cursor = model._cursor - 1
            ensure_visible(model)
        end
    elseif key == "down" or key == "j" then
        if model._cursor < #model._rows then
            model._cursor = model._cursor + 1
            ensure_visible(model)
        end
    elseif key == "pgup" or key == "page_up" then
        model._cursor = math.max(1, model._cursor - model._height)
        ensure_visible(model)
    elseif key == "pgdn" or key == "page_down" then
        model._cursor = math.min(#model._rows, model._cursor + model._height)
        ensure_visible(model)
    elseif key == "home" or key == "g" then
        model._cursor = 1
        ensure_visible(model)
    elseif key == "end" or key == "G" then
        model._cursor = #model._rows
        ensure_visible(model)
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render a single row's cells as a line.
local function render_row(columns, row, border_char, cell_style)
    local cells = {}
    for _, col in ipairs(columns) do
        local raw_val = row[col.key]
        local text
        if col.render then
            text = col.render(raw_val, row, col)
        else
            text = raw_val ~= nil and tostring(raw_val) or ""
        end
        table.insert(cells, align_cell(text, col.width, col.align))
    end
    local line = " " .. table.concat(cells, " " .. border_char .. " ") .. " "
    if cell_style then
        return cell_style:render(line)
    end
    return line
end

--- Render the table.
function table_view.view(model): string
    local lines = {}
    local cols = model._columns
    local sep = model._border_char

    -- Header
    if model._show_header and #cols > 0 then
        local header_cells = {}
        for _, col in ipairs(cols) do
            table.insert(header_cells, align_cell(col.title or col.key, col.width, col.align))
        end
        local header_line = " " .. table.concat(header_cells, " " .. sep .. " ") .. " "
        if model._header_style then
            header_line = model._header_style:render(header_line)
        else
            header_line = "\027[1m" .. header_line .. "\027[0m"
        end
        table.insert(lines, header_line)

        -- Header border
        local border_parts = {}
        for _, col in ipairs(cols) do
            table.insert(border_parts, string.rep(model._header_border_char, col.width))
        end
        local border_sep = model._header_border_char .. "┼" .. model._header_border_char
        local border_line = model._header_border_char .. table.concat(border_parts, border_sep) .. model._header_border_char
        table.insert(lines, "\027[2m" .. border_line .. "\027[0m")
    end

    -- Rows
    if #model._rows == 0 then
        table.insert(lines, "\027[2mNo data.\027[0m")
    else
        local start = model._offset + 1
        local stop = math.min(model._offset + model._height, #model._rows)

        for ri = start, stop do
            local row = model._rows[ri]
            local is_selected = model._cursor_enabled and (ri == model._cursor)

            local line = render_row(cols, row, sep, model._cell_style)

            if is_selected then
                if model._selected_style then
                    -- Re-render with selected style
                    line = render_row(cols, row, sep, model._selected_style)
                else
                    line = "\027[7m" .. line .. "\027[0m"  -- reverse video
                end
            end

            table.insert(lines, line)
        end

        -- Pad remaining
        local rendered = stop - start + 1
        while rendered < model._height do
            table.insert(lines, "")
            rendered = rendered + 1
        end
    end

    local output = table.concat(lines, "\n")
    if model._style then
        return model._style:render(output)
    end
    return output
end

return table_view
