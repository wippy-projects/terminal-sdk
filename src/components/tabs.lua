--- Tabs component — tabbed navigation with keyboard switching.
---
--- Usage within a tui.app:
---   local tabs = require("tabs")
---
---   init = function()
---       return {
---           tabs = tabs.new({
---               items = {"General", "Network", "Security", "Advanced"},
---           })
---       }
---   end,
---   update = function(model, msg)
---       model.tabs = tabs.update(model.tabs, msg)
---       return model
---   end,
---   view = function(model)
---       return tabs.view(model.tabs) .. "\n\n" .. render_tab_content(model)
---   end
---
--- Responds to: left/right or h/l for tab switching,
--- 1-9 number keys for direct tab selection, home/end for first/last.

local tabs = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new tabs model.
---
--- Options:
---   items: array of string — tab labels (required)
---   active: integer — initially active tab index, 1-based (default: 1)
---   style: style for inactive tabs
---   active_style: style for the active tab
---   separator: string — separator between tabs (default: " │ ")
---   use_numbers: boolean — allow 1-9 keys for direct selection (default: true)
function tabs.new(opts)
    opts = opts or {}
    return {
        _type = "tabs",
        _items = opts.items or {},
        _active = opts.active or 1,
        _style = opts.style or nil,
        _active_style = opts.active_style or nil,
        _separator = opts.separator or " │ ",
        _use_numbers = opts.use_numbers ~= false,
    }
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get the active tab index (1-based).
function tabs.active(model): integer
    return model._active
end

--- Get the active tab label.
function tabs.active_label(model): string
    return model._items[model._active] or ""
end

--- Get the number of tabs.
function tabs.count(model): integer
    return #model._items
end

--- Set the active tab.
function tabs.set_active(model, idx: integer)
    if idx >= 1 and idx <= #model._items then
        model._active = idx
    end
    return model
end

--- Set tab items (resets active if out of bounds).
function tabs.set_items(model, items)
    model._items = items
    if model._active > #items then
        model._active = math.max(1, #items)
    end
    return model
end

--- Move to next tab (wraps around).
function tabs.next(model)
    model._active = (model._active % #model._items) + 1
    return model
end

--- Move to previous tab (wraps around).
function tabs.prev(model)
    model._active = ((model._active - 2) % #model._items) + 1
    return model
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update tabs state based on key messages.
function tabs.update(model, msg)
    if msg.kind ~= "key" then return model end
    if #model._items == 0 then return model end

    local key = msg.key

    if key == "right" or key == "l" or key == "tab" then
        return tabs.next(model)
    elseif key == "left" or key == "h" or key == "shift+tab" then
        return tabs.prev(model)
    elseif key == "home" then
        model._active = 1
        return model
    elseif key == "end" then
        model._active = #model._items
        return model
    end

    -- Number keys 1-9
    if model._use_numbers and #key == 1 then
        local n = key:byte() - 48  -- "1" = 49
        if n >= 1 and n <= 9 and n <= #model._items then
            model._active = n
            return model
        end
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the tab bar.
function tabs.view(model): string
    if #model._items == 0 then return "" end

    local parts = {}

    for i, label in ipairs(model._items) do
        local text
        if i == model._active then
            if model._active_style then
                text = model._active_style:render(label)
            else
                text = "\027[1;4m" .. label .. "\027[0m"  -- bold + underline
            end
        else
            if model._style then
                text = model._style:render(label)
            else
                text = "\027[2m" .. label .. "\027[0m"  -- dim
            end
        end
        table.insert(parts, text)
    end

    return table.concat(parts, model._separator)
end

--- Render tab bar with underline indicator.
function tabs.view_underline(model): string
    if #model._items == 0 then return "" end

    local labels = {}
    local indicators = {}

    for i, label in ipairs(model._items) do
        local text
        if i == model._active then
            if model._active_style then
                text = model._active_style:render(label)
            else
                text = "\027[1m" .. label .. "\027[0m"
            end
            table.insert(indicators, string.rep("━", #label))
        else
            if model._style then
                text = model._style:render(label)
            else
                text = "\027[2m" .. label .. "\027[0m"
            end
            table.insert(indicators, string.rep(" ", #label))
        end
        table.insert(labels, text)
    end

    local sep = model._separator
    local sep_plain = string.rep(" ", #sep)  -- spacing for indicator line

    return table.concat(labels, sep) .. "\n" .. table.concat(indicators, sep_plain)
end

return tabs
