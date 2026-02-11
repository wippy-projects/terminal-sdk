--- Viewport component — scrollable content pane.
---
--- Usage within a tui.app:
---   local viewport = require("viewport")
---
---   init = function()
---       local vp = viewport.new({ width = 80, height = 20 })
---       vp = viewport.set_content(vp, long_text)
---       return { vp = vp }
---   end,
---   update = function(model, msg)
---       model.vp = viewport.update(model.vp, msg)
---       return model
---   end,
---   view = function(model)
---       return viewport.view(model.vp)
---   end
---
--- Responds to key messages: "up", "down", "pgup"/"page_up",
--- "pgdn"/"page_down", "home"/"g", "end"/"G".
--- Also handles mouse scroll: {kind = "mouse", action = "scroll_up"/"scroll_down"}.

local ansi = require("ansi")

local viewport = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new viewport model.
---
--- Options:
---   width: integer — viewport width in characters (required)
---   height: integer — viewport height in lines (required)
---   word_wrap: boolean — wrap long lines (default: false)
---   style: style object applied to viewport content area
function viewport.new(opts)
    opts = opts or {}
    return {
        _type = "viewport",
        _lines = {},        -- content split into lines
        _offset = 0,        -- scroll offset (0 = top)
        _width = opts.width or 80,
        _height = opts.height or 20,
        _word_wrap = opts.word_wrap or false,
        _style = opts.style or nil,
        _total_lines = 0,   -- cached line count
    }
end

---------------------------------------------------------------------------
-- Word wrapping (defined early — used by set_content/append)
---------------------------------------------------------------------------

--- Wrap text to fit within a given width.
--- Respects word boundaries where possible.
local function wrap_lines(text: string, width: integer): {string}
    local raw = ansi.lines(text)
    local result = {}

    for _, line in ipairs(raw) do
        local vis_w = ansi.visible_width(line)
        if vis_w <= width then
            table.insert(result, line)
        else
            local plain = ansi.strip(line)
            local pos = 1
            while pos <= #plain do
                local segment = plain:sub(pos, pos + width - 1)

                if pos + width - 1 < #plain then
                    local last_space = segment:match(".*()%s")
                    if last_space and last_space > 1 then
                        segment = plain:sub(pos, pos + last_space - 2)
                        pos = pos + last_space
                    else
                        pos = pos + width
                    end
                else
                    pos = #plain + 1
                end

                table.insert(result, segment)
            end
        end
    end

    return result
end

---------------------------------------------------------------------------
-- Content management
---------------------------------------------------------------------------

--- Set the viewport content. Resets scroll to top.
function viewport.set_content(model, content: string)
    if model._word_wrap then
        model._lines = wrap_lines(content, model._width)
    else
        model._lines = ansi.lines(content)
    end
    model._total_lines = #model._lines
    model._offset = 0
    return model
end

--- Append content to the viewport (useful for streaming/logs).
--- Optionally auto-scroll to bottom if `auto_scroll` is true.
function viewport.append(model, content: string, auto_scroll: boolean?)
    local new_lines
    if model._word_wrap then
        new_lines = wrap_lines(content, model._width)
    else
        new_lines = ansi.lines(content)
    end
    for _, line in ipairs(new_lines) do
        table.insert(model._lines, line)
    end
    model._total_lines = #model._lines

    if auto_scroll then
        model._offset = math.max(0, model._total_lines - model._height)
    end
    return model
end

--- Get the total number of content lines.
function viewport.total_lines(model): integer
    return model._total_lines
end

--- Get the current scroll offset.
function viewport.offset(model): integer
    return model._offset
end

--- Get the scroll percentage (0.0 to 1.0).
function viewport.scroll_percent(model): number
    local max_offset = math.max(0, model._total_lines - model._height)
    if max_offset == 0 then return 1.0 end
    return model._offset / max_offset
end

--- Is the viewport scrolled to the top?
function viewport.at_top(model): boolean
    return model._offset == 0
end

--- Is the viewport scrolled to the bottom?
function viewport.at_bottom(model): boolean
    return model._offset >= math.max(0, model._total_lines - model._height)
end

---------------------------------------------------------------------------
-- Scroll control
---------------------------------------------------------------------------

local function clamp_offset(model)
    local max_offset = math.max(0, model._total_lines - model._height)
    if model._offset < 0 then model._offset = 0 end
    if model._offset > max_offset then model._offset = max_offset end
end

--- Scroll to a specific line offset.
function viewport.goto_top(model)
    model._offset = 0
    return model
end

function viewport.goto_bottom(model)
    model._offset = math.max(0, model._total_lines - model._height)
    return model
end

function viewport.scroll_up(model, n: integer?)
    model._offset = model._offset - (n or 1)
    clamp_offset(model)
    return model
end

function viewport.scroll_down(model, n: integer?)
    model._offset = model._offset + (n or 1)
    clamp_offset(model)
    return model
end

function viewport.page_up(model)
    return viewport.scroll_up(model, model._height)
end

function viewport.page_down(model)
    return viewport.scroll_down(model, model._height)
end

function viewport.half_page_up(model)
    return viewport.scroll_up(model, math.floor(model._height / 2))
end

function viewport.half_page_down(model)
    return viewport.scroll_down(model, math.floor(model._height / 2))
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update viewport state based on messages.
--- Handles arrow keys, page up/down, home/end, mouse scroll.
function viewport.update(model, msg)
    if msg.kind == "key" then
        local key = msg.key
        if key == "up" or key == "k" then
            return viewport.scroll_up(model, 1)
        elseif key == "down" or key == "j" then
            return viewport.scroll_down(model, 1)
        elseif key == "pgup" or key == "page_up" or key == "ctrl+b" then
            return viewport.page_up(model)
        elseif key == "pgdn" or key == "page_down" or key == "ctrl+f" then
            return viewport.page_down(model)
        elseif key == "home" or key == "g" then
            return viewport.goto_top(model)
        elseif key == "end" or key == "G" then
            return viewport.goto_bottom(model)
        elseif key == "ctrl+u" then
            return viewport.half_page_up(model)
        elseif key == "ctrl+d" then
            return viewport.half_page_down(model)
        end
    end

    if msg.kind == "mouse" then
        if msg.action == "scroll_up" then
            return viewport.scroll_up(model, 3)
        elseif msg.action == "scroll_down" then
            return viewport.scroll_down(model, 3)
        end
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the visible portion of the viewport content.
function viewport.view(model): string
    local visible = {}
    local start = model._offset + 1
    local stop = math.min(model._offset + model._height, model._total_lines)

    for i = start, stop do
        local line = model._lines[i] or ""
        -- Pad to viewport width for consistent rendering
        table.insert(visible, ansi.pad_right(line, model._width))
    end

    -- Fill remaining lines if content shorter than viewport
    local empty_line = string.rep(" ", model._width)
    while #visible < model._height do
        table.insert(visible, empty_line)
    end

    local output = table.concat(visible, "\n")

    if model._style then
        return model._style:render(output)
    end
    return output
end

--- View with a scroll indicator on the right edge.
function viewport.view_with_scrollbar(model): string
    local visible = {}
    local start = model._offset + 1
    local stop = math.min(model._offset + model._height, model._total_lines)

    -- Scrollbar calculations
    local show_bar = model._total_lines > model._height
    local bar_height = 0
    local bar_start = 0
    if show_bar then
        bar_height = math.max(1, math.floor(model._height * model._height / model._total_lines + 0.5))
        local max_offset = model._total_lines - model._height
        if max_offset > 0 then
            bar_start = math.floor(model._offset / max_offset * (model._height - bar_height) + 0.5)
        end
    end

    for i = start, stop do
        local line = model._lines[i] or ""
        local padded = ansi.pad_right(line, model._width)
        local row_idx = i - start  -- 0-based row index

        if show_bar then
            if row_idx >= bar_start and row_idx < bar_start + bar_height then
                padded = padded .. "█"
            else
                padded = padded .. "░"
            end
        end

        table.insert(visible, padded)
    end

    -- Fill remaining
    local empty_line = string.rep(" ", model._width)
    while #visible < model._height do
        local suffix = show_bar and "░" or ""
        table.insert(visible, empty_line .. suffix)
    end

    return table.concat(visible, "\n")
end

return viewport
