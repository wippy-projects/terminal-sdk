--- List component — item browser with filtering, pagination, and customizable rendering.
---
--- Usage within a tui.app:
---   local list = require("list")
---
---   local items = {
---       { title = "Apples",  desc = "Red fruit" },
---       { title = "Bananas", desc = "Yellow fruit" },
---       { title = "Cherries", desc = "Small red fruit" },
---   }
---
---   init = function()
---       return { list = list.new({ items = items, height = 10 }) }
---   end,
---   update = function(model, msg)
---       model.list = list.update(model.list, msg)
---       return model
---   end,
---   view = function(model)
---       return list.view(model.list)
---   end
---
--- Items are tables with at least a `title` field. Optional `desc` for description.
--- Supports fuzzy filtering via built-in text input, cursor navigation,
--- and custom item rendering via delegate functions.

local list = {}

---------------------------------------------------------------------------
-- Default delegate (item renderer)
---------------------------------------------------------------------------

--- Default item render function.
--- Override with opts.delegate for custom rendering.
local function default_delegate(item, index, is_selected, is_matched, width)
    local cursor = is_selected and "▸ " or "  "
    local title = item.title or tostring(item)
    local line = cursor .. title
    if item.desc then
        local desc_space = width - #cursor - #title - 2
        if desc_space > 4 then
            local desc = item.desc
            if #desc > desc_space then
                desc = desc:sub(1, desc_space - 1) .. "…"
            end
            line = line .. "  " .. "\027[2m" .. desc .. "\027[0m"
        end
    end
    if is_selected then
        line = "\027[1m" .. line .. "\027[0m"
    end
    return line
end

---------------------------------------------------------------------------
-- Fuzzy matching
---------------------------------------------------------------------------

--- Simple fuzzy match: check if all chars of pattern appear in order in str.
--- Returns true/false and a score (lower = better).
local function fuzzy_match(str: string, pattern: string): (boolean, number)
    if #pattern == 0 then return true, 0 end
    local lower_str = str:lower()
    local lower_pat = pattern:lower()
    local si = 1
    local pi = 1
    local score = 0
    local last_match = 0

    while si <= #lower_str and pi <= #lower_pat do
        if lower_str:sub(si, si) == lower_pat:sub(pi, pi) then
            local gap = si - last_match
            score = score + gap
            last_match = si
            pi = pi + 1
        end
        si = si + 1
    end

    if pi > #lower_pat then
        return true, score
    end
    return false, math.huge
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new list model.
---
--- Options:
---   items: array of item tables (each should have at least `title`)
---   height: integer — visible item count (default: 10)
---   width: integer — list width in characters (default: 40)
---   filterable: boolean — enable filter input (default: true)
---   filter_prompt: string — prompt for filter input (default: "/ ")
---   delegate: function(item, index, is_selected, is_matched, width) → string
---   title: string? — list title shown above items
---   status_text: string? — text shown in status bar
---   show_status: boolean — show item count status bar (default: true)
---   show_spinner: boolean — show spinner when filtering (default: false)
---   no_items_text: string — shown when list is empty (default: "No items.")
---   no_matches_text: string — shown when filter matches nothing (default: "No matches.")
---   style: style for the overall list
---   title_style: style for the title
---   status_style: style for the status bar
---   filter_style: style for the filter input
function list.new(opts)
    opts = opts or {}
    local items = opts.items or {}

    -- Build initial visible indices (all items)
    local visible = {}
    for i = 1, #items do
        table.insert(visible, i)
    end

    return {
        _type = "list",
        _items = items,
        _visible = visible,        -- indices into _items that match filter
        _cursor = 1,               -- 1-based index into _visible
        _offset = 0,               -- scroll offset for pagination
        _height = opts.height or 10,
        _width = opts.width or 40,
        _filterable = opts.filterable ~= false,
        _filter = "",              -- current filter text
        _filter_focused = false,   -- is filter input active
        _filter_prompt = opts.filter_prompt or "/ ",
        _delegate = opts.delegate or default_delegate,
        _title = opts.title or nil,
        _status_text = opts.status_text or nil,
        _show_status = opts.show_status ~= false,
        _no_items_text = opts.no_items_text or "No items.",
        _no_matches_text = opts.no_matches_text or "No matches.",
        _style = opts.style or nil,
        _title_style = opts.title_style or nil,
        _status_style = opts.status_style or nil,
        _filter_style = opts.filter_style or nil,
    }
end

---------------------------------------------------------------------------
-- Internal: re-filter items
---------------------------------------------------------------------------

local function refilter(model)
    local pattern = model._filter
    if #pattern == 0 then
        -- Show all items
        model._visible = {}
        for i = 1, #model._items do
            table.insert(model._visible, i)
        end
    else
        -- Fuzzy filter and sort by score
        local matches = {}
        for i, item in ipairs(model._items) do
            local title = item.title or tostring(item)
            local ok, score = fuzzy_match(title, pattern)
            if ok then
                table.insert(matches, {index = i, score = score})
            end
        end
        table.sort(matches, function(a, b) return a.score < b.score end)
        model._visible = {}
        for _, m in ipairs(matches) do
            table.insert(model._visible, m.index)
        end
    end

    -- Reset cursor if out of bounds
    if model._cursor > #model._visible then
        model._cursor = math.max(1, #model._visible)
    end
    if model._cursor < 1 then
        model._cursor = 1
    end

    -- Reset offset
    model._offset = 0
end

---------------------------------------------------------------------------
-- Scroll helpers
---------------------------------------------------------------------------

local function ensure_visible(model)
    -- Keep cursor within visible window
    if model._cursor <= model._offset then
        model._offset = model._cursor - 1
    elseif model._cursor > model._offset + model._height then
        model._offset = model._cursor - model._height
    end
    -- Clamp offset
    local max_offset = math.max(0, #model._visible - model._height)
    if model._offset < 0 then model._offset = 0 end
    if model._offset > max_offset then model._offset = max_offset end
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get the currently selected item (or nil if list empty).
function list.selected(model)
    if #model._visible == 0 then return nil end
    local idx = model._visible[model._cursor]
    return model._items[idx]
end

--- Get the index (in original items array) of the selected item.
function list.selected_index(model): integer?
    if #model._visible == 0 then return nil end
    return model._visible[model._cursor]
end

--- Get the cursor position (1-based, within visible items).
function list.cursor(model): integer
    return model._cursor
end

--- Get visible item count after filtering.
function list.visible_count(model): integer
    return #model._visible
end

--- Get total item count.
function list.total_count(model): integer
    return #model._items
end

--- Get the current filter text.
function list.filter(model): string
    return model._filter
end

--- Is the filter input focused?
function list.is_filtering(model): boolean
    return model._filter_focused
end

--- Set items and refilter.
function list.set_items(model, items)
    model._items = items
    refilter(model)
    return model
end

--- Set filter text programmatically.
function list.set_filter(model, text: string)
    model._filter = text
    refilter(model)
    return model
end

--- Set title.
function list.set_title(model, title: string)
    model._title = title
    return model
end

--- Set status text.
function list.set_status(model, text: string)
    model._status_text = text
    return model
end

--- Move cursor to specific position.
function list.select_index(model, idx: integer)
    model._cursor = math.max(1, math.min(idx, #model._visible))
    ensure_visible(model)
    return model
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update list state based on messages.
--- Handles navigation (up/down/pgup/pgdn/home/end), filtering (/), and selection (enter).
function list.update(model, msg)
    if msg.kind ~= "key" then return model end

    local key = msg.key

    -- Filter input mode
    if model._filter_focused then
        if key == "escape" then
            model._filter_focused = false
            if #model._filter == 0 then
                refilter(model)
            end
            return model
        elseif key == "enter" then
            model._filter_focused = false
            return model
        elseif key == "backspace" or key == "ctrl+h" then
            if #model._filter > 0 then
                model._filter = model._filter:sub(1, -2)
                refilter(model)
            else
                model._filter_focused = false
            end
            return model
        elseif key == "ctrl+u" then
            model._filter = ""
            refilter(model)
            return model
        elseif #key == 1 and key:byte() >= 32 then
            model._filter = model._filter .. key
            refilter(model)
            return model
        end
        -- Pass navigation through even while filtering
    end

    -- Navigation
    if key == "up" or key == "k" then
        if model._cursor > 1 then
            model._cursor = model._cursor - 1
            ensure_visible(model)
        end
        return model
    elseif key == "down" or key == "j" then
        if model._cursor < #model._visible then
            model._cursor = model._cursor + 1
            ensure_visible(model)
        end
        return model
    elseif key == "pgup" or key == "page_up" then
        model._cursor = math.max(1, model._cursor - model._height)
        ensure_visible(model)
        return model
    elseif key == "pgdn" or key == "page_down" then
        model._cursor = math.min(#model._visible, model._cursor + model._height)
        ensure_visible(model)
        return model
    elseif key == "home" or key == "g" then
        model._cursor = 1
        ensure_visible(model)
        return model
    elseif key == "end" or key == "G" then
        model._cursor = #model._visible
        ensure_visible(model)
        return model
    end

    -- Activate filter
    if key == "/" and model._filterable and not model._filter_focused then
        model._filter_focused = true
        return model
    end

    -- Clear filter
    if key == "escape" and #model._filter > 0 then
        model._filter = ""
        refilter(model)
        return model
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the list.
function list.view(model): string
    local lines = {}
    local w = model._width

    -- Title
    if model._title then
        local title = model._title
        if model._title_style then
            title = model._title_style:render(title)
        else
            title = "\027[1m" .. title .. "\027[0m"
        end
        table.insert(lines, title)
    end

    -- Filter line
    if model._filterable and (model._filter_focused or #model._filter > 0) then
        local filter_line = model._filter_prompt .. model._filter
        if model._filter_focused then
            filter_line = filter_line .. "\027[7m \027[0m"  -- cursor
        end
        if model._filter_style then
            filter_line = model._filter_style:render(filter_line)
        end
        table.insert(lines, filter_line)
    end

    -- Items
    if #model._items == 0 then
        table.insert(lines, "\027[2m" .. model._no_items_text .. "\027[0m")
    elseif #model._visible == 0 then
        table.insert(lines, "\027[2m" .. model._no_matches_text .. "\027[0m")
    else
        local start = model._offset + 1
        local stop = math.min(model._offset + model._height, #model._visible)

        for vi = start, stop do
            local item_idx = model._visible[vi]
            local item = model._items[item_idx]
            local is_selected = (vi == model._cursor)
            local is_matched = #model._filter > 0
            local line = model._delegate(item, item_idx, is_selected, is_matched, w)
            table.insert(lines, line)
        end

        -- Pad remaining lines for consistent height
        local rendered = stop - start + 1
        while rendered < model._height do
            table.insert(lines, "")
            rendered = rendered + 1
        end
    end

    -- Status bar
    if model._show_status then
        local status
        if model._status_text then
            status = model._status_text
        else
            if #model._filter > 0 then
                status = #model._visible .. "/" .. #model._items .. " items"
            else
                status = #model._items .. " items"
            end
        end
        if model._status_style then
            status = model._status_style:render(status)
        else
            status = "\027[2m" .. status .. "\027[0m"
        end
        table.insert(lines, status)
    end

    local output = table.concat(lines, "\n")
    if model._style then
        return model._style:render(output)
    end
    return output
end

return list
