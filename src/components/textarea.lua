--- Textarea component — multi-line text editor with line numbers, scrolling, and undo.
---
--- Usage within a tui.app:
---   local textarea = require("textarea")
---
---   init = function()
---       return { ta = textarea.new({ width = 60, height = 15 }) }
---   end,
---   update = function(model, msg)
---       model.ta = textarea.update(model.ta, msg)
---       return model
---   end,
---   view = function(model)
---       return textarea.view(model.ta)
---   end
---
--- Responds to key messages: printable characters, enter, backspace, delete,
--- arrow keys, home/end, ctrl+a/e/k/u/z, pgup/pgdn.
--- Also handles "line" messages for cooked-mode line input.

local textarea = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new textarea model.
---
--- Options:
---   width: integer — editor width in characters (default: 60)
---   height: integer — visible line count (default: 10)
---   placeholder: string — ghost text when empty (default: "")
---   show_line_numbers: boolean — show line numbers gutter (default: false)
---   line_number_width: integer — gutter width (default: 4)
---   max_lines: integer? — max line count (nil = unlimited)
---   max_length: integer? — max total character count (nil = unlimited)
---   word_wrap: boolean — wrap long lines (default: false)
---   tab_size: integer — spaces per tab (default: 4)
---   focused: boolean — accept input (default: true)
---   style: style for the text content
---   placeholder_style: style for placeholder
---   cursor_style: style for cursor character
---   line_number_style: style for line numbers
---   undo_limit: integer — max undo history entries (default: 100)
function textarea.new(opts)
    opts = opts or {}
    return {
        _type = "textarea",
        _lines = {""},              -- array of line strings
        _cursor_row = 1,            -- 1-based line number
        _cursor_col = 0,            -- 0-based column position
        _offset_row = 0,            -- vertical scroll offset
        _offset_col = 0,            -- horizontal scroll offset (no word_wrap)
        _width = opts.width or 60,
        _height = opts.height or 10,
        _placeholder = opts.placeholder or "",
        _show_line_numbers = opts.show_line_numbers or false,
        _line_number_width = opts.line_number_width or 4,
        _max_lines = opts.max_lines or nil,
        _max_length = opts.max_length or nil,
        _word_wrap = opts.word_wrap or false,
        _tab_size = opts.tab_size or 4,
        _focused = opts.focused ~= false,
        _style = opts.style or nil,
        _placeholder_style = opts.placeholder_style or nil,
        _cursor_style = opts.cursor_style or nil,
        _line_number_style = opts.line_number_style or nil,
        _undo_stack = {},
        _undo_limit = opts.undo_limit or 100,
    }
end

---------------------------------------------------------------------------
-- Internal: undo support
---------------------------------------------------------------------------

local function save_undo(model)
    -- Snapshot current state
    local snapshot = {
        lines = {},
        cursor_row = model._cursor_row,
        cursor_col = model._cursor_col,
    }
    for i, line in ipairs(model._lines) do
        snapshot.lines[i] = line
    end
    table.insert(model._undo_stack, snapshot)
    -- Trim history
    while #model._undo_stack > model._undo_limit do
        table.remove(model._undo_stack, 1)
    end
end

local function apply_undo(model)
    if #model._undo_stack == 0 then return model end
    local snapshot = table.remove(model._undo_stack)
    model._lines = snapshot.lines
    model._cursor_row = snapshot.cursor_row
    model._cursor_col = snapshot.cursor_col
    return model
end

---------------------------------------------------------------------------
-- Internal: scroll management
---------------------------------------------------------------------------

local function content_width(model)
    local w = model._width
    if model._show_line_numbers then
        w = w - model._line_number_width - 1  -- gutter + separator
    end
    return math.max(1, w)
end

local function ensure_cursor_visible(model)
    -- Vertical
    if model._cursor_row <= model._offset_row then
        model._offset_row = model._cursor_row - 1
    elseif model._cursor_row > model._offset_row + model._height then
        model._offset_row = model._cursor_row - model._height
    end
    if model._offset_row < 0 then model._offset_row = 0 end

    -- Horizontal (only if not word wrapping)
    if not model._word_wrap then
        local cw = content_width(model)
        if model._cursor_col < model._offset_col then
            model._offset_col = model._cursor_col
        elseif model._cursor_col >= model._offset_col + cw then
            model._offset_col = model._cursor_col - cw + 1
        end
        if model._offset_col < 0 then model._offset_col = 0 end
    end
end

local function clamp_cursor(model)
    if model._cursor_row < 1 then model._cursor_row = 1 end
    if model._cursor_row > #model._lines then model._cursor_row = #model._lines end
    local line = model._lines[model._cursor_row] or ""
    if model._cursor_col > #line then model._cursor_col = #line end
    if model._cursor_col < 0 then model._cursor_col = 0 end
end

---------------------------------------------------------------------------
-- Internal: total char count
---------------------------------------------------------------------------

local function total_length(model): integer
    local len = 0
    for _, line in ipairs(model._lines) do
        len = len + #line
    end
    -- Add newlines between lines
    len = len + math.max(0, #model._lines - 1)
    return len
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get all text as a single string.
function textarea.value(model): string
    return table.concat(model._lines, "\n")
end

--- Set text content. Resets cursor to start.
function textarea.set_value(model, text: string)
    save_undo(model)
    model._lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(model._lines, line)
    end
    if #model._lines == 0 then
        model._lines = {""}
    end
    model._cursor_row = 1
    model._cursor_col = 0
    model._offset_row = 0
    model._offset_col = 0
    return model
end

--- Get cursor position as (row, col).
function textarea.cursor_pos(model): (integer, integer)
    return model._cursor_row, model._cursor_col
end

--- Get line count.
function textarea.line_count(model): integer
    return #model._lines
end

--- Focus/blur.
function textarea.focus(model)
    model._focused = true
    return model
end

function textarea.blur(model)
    model._focused = false
    return model
end

function textarea.is_focused(model): boolean
    return model._focused
end

--- Reset to empty.
function textarea.reset(model)
    save_undo(model)
    model._lines = {""}
    model._cursor_row = 1
    model._cursor_col = 0
    model._offset_row = 0
    model._offset_col = 0
    return model
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update textarea state based on messages.
function textarea.update(model, msg)
    if not model._focused then return model end
    if msg.kind ~= "key" then return model end

    local key = msg.key

    -- Line input fallback (cooked mode)
    if key == "line" and msg.value then
        save_undo(model)
        table.insert(model._lines, msg.value)
        model._cursor_row = #model._lines
        model._cursor_col = #model._lines[model._cursor_row]
        ensure_cursor_visible(model)
        return model
    end

    -- Enter: split line
    if key == "enter" then
        if model._max_lines and #model._lines >= model._max_lines then
            return model
        end
        save_undo(model)
        local line = model._lines[model._cursor_row]
        local before = line:sub(1, model._cursor_col)
        local after = line:sub(model._cursor_col + 1)
        model._lines[model._cursor_row] = before
        table.insert(model._lines, model._cursor_row + 1, after)
        model._cursor_row = model._cursor_row + 1
        model._cursor_col = 0
        ensure_cursor_visible(model)
        return model
    end

    -- Backspace
    if key == "backspace" or key == "ctrl+h" then
        if model._cursor_col > 0 then
            save_undo(model)
            local line = model._lines[model._cursor_row]
            model._lines[model._cursor_row] = line:sub(1, model._cursor_col - 1) .. line:sub(model._cursor_col + 1)
            model._cursor_col = model._cursor_col - 1
        elseif model._cursor_row > 1 then
            -- Join with previous line
            save_undo(model)
            local prev = model._lines[model._cursor_row - 1]
            local curr = model._lines[model._cursor_row]
            model._cursor_col = #prev
            model._lines[model._cursor_row - 1] = prev .. curr
            table.remove(model._lines, model._cursor_row)
            model._cursor_row = model._cursor_row - 1
        end
        ensure_cursor_visible(model)
        return model
    end

    -- Delete
    if key == "delete" or key == "ctrl+d" then
        local line = model._lines[model._cursor_row]
        if model._cursor_col < #line then
            save_undo(model)
            model._lines[model._cursor_row] = line:sub(1, model._cursor_col) .. line:sub(model._cursor_col + 2)
        elseif model._cursor_row < #model._lines then
            -- Join with next line
            save_undo(model)
            local next_line = model._lines[model._cursor_row + 1]
            model._lines[model._cursor_row] = line .. next_line
            table.remove(model._lines, model._cursor_row + 1)
        end
        return model
    end

    -- Arrow keys
    if key == "left" or key == "ctrl+b" then
        if model._cursor_col > 0 then
            model._cursor_col = model._cursor_col - 1
        elseif model._cursor_row > 1 then
            model._cursor_row = model._cursor_row - 1
            model._cursor_col = #model._lines[model._cursor_row]
        end
        ensure_cursor_visible(model)
        return model
    end

    if key == "right" or key == "ctrl+f" then
        local line = model._lines[model._cursor_row]
        if model._cursor_col < #line then
            model._cursor_col = model._cursor_col + 1
        elseif model._cursor_row < #model._lines then
            model._cursor_row = model._cursor_row + 1
            model._cursor_col = 0
        end
        ensure_cursor_visible(model)
        return model
    end

    if key == "up" then
        if model._cursor_row > 1 then
            model._cursor_row = model._cursor_row - 1
            clamp_cursor(model)
            ensure_cursor_visible(model)
        end
        return model
    end

    if key == "down" then
        if model._cursor_row < #model._lines then
            model._cursor_row = model._cursor_row + 1
            clamp_cursor(model)
            ensure_cursor_visible(model)
        end
        return model
    end

    -- Home/End
    if key == "home" or key == "ctrl+a" then
        model._cursor_col = 0
        ensure_cursor_visible(model)
        return model
    end

    if key == "end" or key == "ctrl+e" then
        model._cursor_col = #model._lines[model._cursor_row]
        ensure_cursor_visible(model)
        return model
    end

    -- Page up/down
    if key == "pgup" or key == "page_up" or key == "ctrl+b" then
        model._cursor_row = math.max(1, model._cursor_row - model._height)
        clamp_cursor(model)
        ensure_cursor_visible(model)
        return model
    end

    if key == "pgdn" or key == "page_down" or key == "ctrl+f" then
        model._cursor_row = math.min(#model._lines, model._cursor_row + model._height)
        clamp_cursor(model)
        ensure_cursor_visible(model)
        return model
    end

    -- Kill line (ctrl+k)
    if key == "ctrl+k" then
        save_undo(model)
        model._lines[model._cursor_row] = model._lines[model._cursor_row]:sub(1, model._cursor_col)
        return model
    end

    -- Kill to start (ctrl+u)
    if key == "ctrl+u" then
        save_undo(model)
        model._lines[model._cursor_row] = model._lines[model._cursor_row]:sub(model._cursor_col + 1)
        model._cursor_col = 0
        ensure_cursor_visible(model)
        return model
    end

    -- Undo (ctrl+z)
    if key == "ctrl+z" then
        apply_undo(model)
        ensure_cursor_visible(model)
        return model
    end

    -- Tab
    if key == "tab" then
        local spaces = string.rep(" ", model._tab_size)
        if model._max_length and total_length(model) + model._tab_size > model._max_length then
            return model
        end
        save_undo(model)
        local line = model._lines[model._cursor_row]
        model._lines[model._cursor_row] = line:sub(1, model._cursor_col) .. spaces .. line:sub(model._cursor_col + 1)
        model._cursor_col = model._cursor_col + model._tab_size
        ensure_cursor_visible(model)
        return model
    end

    -- Regular character input
    if #key == 1 and key:byte() >= 32 then
        if model._max_length and total_length(model) >= model._max_length then
            return model
        end
        save_undo(model)
        local line = model._lines[model._cursor_row]
        model._lines[model._cursor_row] = line:sub(1, model._cursor_col) .. key .. line:sub(model._cursor_col + 1)
        model._cursor_col = model._cursor_col + 1
        ensure_cursor_visible(model)
        return model
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the textarea.
function textarea.view(model): string
    local lines = {}
    local cw = content_width(model)
    local show_ln = model._show_line_numbers
    local ln_w = model._line_number_width

    -- Empty placeholder
    if #model._lines == 1 and #model._lines[1] == 0 and not model._focused then
        local ph = model._placeholder
        if model._placeholder_style then
            ph = model._placeholder_style:render(ph)
        elseif #ph > 0 then
            ph = "\027[2m" .. ph .. "\027[0m"
        end
        if show_ln then
            local gutter = string.rep(" ", ln_w) .. "│"
            ph = "\027[2m" .. gutter .. "\027[0m " .. ph
        end
        table.insert(lines, ph)
        -- Pad remaining height
        for _ = 2, model._height do
            if show_ln then
                table.insert(lines, "\027[2m" .. string.rep(" ", ln_w) .. "│\027[0m")
            else
                table.insert(lines, "")
            end
        end
        return table.concat(lines, "\n")
    end

    -- Visible range
    local start = model._offset_row + 1
    local stop = math.min(model._offset_row + model._height, #model._lines)

    for i = start, stop do
        local line = model._lines[i]
        local display = line

        -- Horizontal scroll (non-wrap mode)
        if not model._word_wrap and model._offset_col > 0 then
            display = display:sub(model._offset_col + 1)
        end

        -- Truncate to content width
        if #display > cw then
            display = display:sub(1, cw)
        end

        -- Render cursor
        if model._focused and i == model._cursor_row then
            local col = model._cursor_col - model._offset_col
            if col >= 0 and col <= #display then
                local before = display:sub(1, col)
                local cursor_ch = display:sub(col + 1, col + 1)
                local after = display:sub(col + 2)
                if #cursor_ch == 0 then cursor_ch = " " end
                if model._cursor_style then
                    cursor_ch = model._cursor_style:render(cursor_ch)
                else
                    cursor_ch = "\027[7m" .. cursor_ch .. "\027[0m"
                end
                display = before .. cursor_ch .. after
            end
        end

        -- Pad to width
        local vis_len = #line  -- approximate
        if vis_len < cw then
            display = display .. string.rep(" ", cw - math.min(#display, cw))
        end

        -- Apply text style
        if model._style and not (model._focused and i == model._cursor_row) then
            display = model._style:render(display)
        end

        -- Line numbers
        if show_ln then
            local ln_str = string.format("%" .. ln_w .. "d", i)
            if model._line_number_style then
                ln_str = model._line_number_style:render(ln_str)
            else
                ln_str = "\027[2m" .. ln_str .. "\027[0m"
            end
            display = ln_str .. "\027[2m│\027[0m" .. display
        end

        table.insert(lines, display)
    end

    -- Pad remaining height
    local rendered = stop - start + 1
    while rendered < model._height do
        local empty = string.rep(" ", cw)
        if show_ln then
            local gutter = string.rep(" ", ln_w) .. "│"
            empty = "\027[2m" .. gutter .. "\027[0m" .. empty
        end
        table.insert(lines, empty)
        rendered = rendered + 1
    end

    return table.concat(lines, "\n")
end

return textarea
