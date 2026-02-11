--- Paginator component — dot-style and numeric page indicators.
---
--- Usage within a tui.app:
---   local paginator = require("paginator")
---
---   init = function()
---       return { pager = paginator.new({ total = 5 }) }
---   end,
---   update = function(model, msg)
---       model.pager = paginator.update(model.pager, msg)
---       return model
---   end,
---   view = function(model)
---       return page_content[paginator.page(model.pager)]
---           .. "\n" .. paginator.view(model.pager)
---   end
---
--- Responds to: left/right or h/l for page switching.

local paginator = {}

---------------------------------------------------------------------------
-- Display modes
---------------------------------------------------------------------------

paginator.DOTS = "dots"
paginator.NUMERIC = "numeric"
paginator.ARABIC = "arabic"     -- "1/5" style

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new paginator model.
---
--- Options:
---   total: integer — total page count (required)
---   page: integer — initial page, 1-based (default: 1)
---   mode: string — "dots" (default), "numeric", or "arabic"
---   per_page: integer — items per page for automatic paging (optional)
---   wrap: boolean — wrap from last to first page (default: true)
---   active_dot: string — character for active page dot (default: "●")
---   inactive_dot: string — character for inactive page dot (default: "○")
---   active_style: style for active page indicator
---   inactive_style: style for inactive page indicator
function paginator.new(opts)
    opts = opts or {}
    return {
        _type = "paginator",
        _total = opts.total or 1,
        _page = opts.page or 1,
        _mode = opts.mode or paginator.DOTS,
        _per_page = opts.per_page or nil,
        _wrap = opts.wrap ~= false,
        _active_dot = opts.active_dot or "●",
        _inactive_dot = opts.inactive_dot or "○",
        _active_style = opts.active_style or nil,
        _inactive_style = opts.inactive_style or nil,
    }
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get current page (1-based).
function paginator.page(model): integer
    return model._page
end

--- Get total page count.
function paginator.total(model): integer
    return model._total
end

--- Set total page count (clamps current page).
function paginator.set_total(model, total: integer)
    model._total = math.max(1, total)
    if model._page > model._total then
        model._page = model._total
    end
    return model
end

--- Set current page.
function paginator.set_page(model, page: integer)
    if page >= 1 and page <= model._total then
        model._page = page
    end
    return model
end

--- Is this the first page?
function paginator.is_first(model): boolean
    return model._page == 1
end

--- Is this the last page?
function paginator.is_last(model): boolean
    return model._page == model._total
end

--- Go to next page.
function paginator.next_page(model)
    if model._page < model._total then
        model._page = model._page + 1
    elseif model._wrap then
        model._page = 1
    end
    return model
end

--- Go to previous page.
function paginator.prev_page(model)
    if model._page > 1 then
        model._page = model._page - 1
    elseif model._wrap then
        model._page = model._total
    end
    return model
end

--- Calculate items slice for the current page.
--- Returns start_index, end_index (1-based, inclusive) for use with table.move or ipairs.
function paginator.slice(model, total_items: integer): (integer, integer)
    if not model._per_page then
        return 1, total_items
    end
    local start = (model._page - 1) * model._per_page + 1
    local stop = math.min(start + model._per_page - 1, total_items)
    return start, stop
end

--- Auto-calculate total pages from item count and per_page.
function paginator.set_total_from_items(model, item_count: integer)
    if model._per_page and model._per_page > 0 then
        model._total = math.max(1, math.ceil(item_count / model._per_page))
        if model._page > model._total then
            model._page = model._total
        end
    end
    return model
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update paginator based on key messages.
function paginator.update(model, msg)
    if msg.kind ~= "key" then return model end

    local key = msg.key

    if key == "right" or key == "l" then
        return paginator.next_page(model)
    elseif key == "left" or key == "h" then
        return paginator.prev_page(model)
    elseif key == "home" then
        model._page = 1
        return model
    elseif key == "end" then
        model._page = model._total
        return model
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the paginator.
function paginator.view(model): string
    if model._total <= 1 then return "" end

    if model._mode == paginator.ARABIC then
        local text = model._page .. "/" .. model._total
        if model._active_style then
            return model._active_style:render(text)
        end
        return text
    end

    if model._mode == paginator.NUMERIC then
        local parts = {}
        for i = 1, model._total do
            local num = tostring(i)
            if i == model._page then
                if model._active_style then
                    num = model._active_style:render(num)
                else
                    num = "\027[1m" .. num .. "\027[0m"
                end
            else
                if model._inactive_style then
                    num = model._inactive_style:render(num)
                else
                    num = "\027[2m" .. num .. "\027[0m"
                end
            end
            table.insert(parts, num)
        end
        return table.concat(parts, " ")
    end

    -- Dots mode (default)
    local parts = {}
    for i = 1, model._total do
        if i == model._page then
            local dot = model._active_dot
            if model._active_style then
                dot = model._active_style:render(dot)
            end
            table.insert(parts, dot)
        else
            local dot = model._inactive_dot
            if model._inactive_style then
                dot = model._inactive_style:render(dot)
            end
            table.insert(parts, dot)
        end
    end
    return table.concat(parts, " ")
end

return paginator
