--- Text input component — single-line text input with cursor, placeholder, and char limit.
---
--- Usage within a tui.app:
---   local textinput = require("textinput")
---
---   init = function()
---       return {
---           input = textinput.new({
---               placeholder = "Type something...",
---               char_limit = 100,
---           })
---       }
---   end,
---   update = function(model, msg)
---       model.input = textinput.update(model.input, msg)
---       return model
---   end,
---   view = function(model)
---       return textinput.view(model.input)
---   end
---
--- Responds to key messages: single characters for typing,
--- "backspace", "delete", "left", "right", "home", "end", "enter".
--- In line-input fallback mode, handles "line" messages (full line input).

local textinput = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new text input model.
---
--- Options:
---   placeholder: string — ghost text when empty (default: "")
---   prompt: string — prompt prefix shown before input (default: "> ")
---   char_limit: integer? — max characters (nil = unlimited)
---   width: integer? — display width (nil = auto)
---   password: boolean — mask characters (default: false)
---   password_char: string — mask character (default: "•")
---   style: style for the input text
---   placeholder_style: style for placeholder text
---   prompt_style: style for the prompt
---   cursor_style: style for the cursor character
---   focused: boolean — whether input accepts keys (default: true)
function textinput.new(opts)
    opts = opts or {}
    return {
        _type = "textinput",
        _value = opts.value or "",
        _cursor = 0,          -- cursor position (0 = before first char)
        _placeholder = opts.placeholder or "",
        _prompt = opts.prompt or "> ",
        _char_limit = opts.char_limit or nil,
        _width = opts.width or nil,
        _password = opts.password or false,
        _password_char = opts.password_char or "•",
        _style = opts.style or nil,
        _placeholder_style = opts.placeholder_style or nil,
        _prompt_style = opts.prompt_style or nil,
        _cursor_style = opts.cursor_style or nil,
        _focused = opts.focused ~= false,
        _suggestions = opts.suggestions or {},
    }
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get the current text value.
function textinput.value(model): string
    return model._value
end

--- Set the text value and clamp cursor.
function textinput.set_value(model, text: string)
    model._value = text
    if model._cursor > #text then
        model._cursor = #text
    end
    return model
end

--- Focus the input (enable key handling).
function textinput.focus(model)
    model._focused = true
    return model
end

--- Blur the input (disable key handling).
function textinput.blur(model)
    model._focused = false
    return model
end

--- Is the input focused?
function textinput.is_focused(model): boolean
    return model._focused
end

--- Reset the input.
function textinput.reset(model)
    model._value = ""
    model._cursor = 0
    return model
end

--- Get the cursor position.
function textinput.cursor_pos(model): integer
    return model._cursor
end

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function insert_at(s, pos, ch)
    return s:sub(1, pos) .. ch .. s:sub(pos + 1)
end

local function delete_at(s, pos)
    if pos < 1 then return s end
    return s:sub(1, pos - 1) .. s:sub(pos + 1)
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update text input state based on messages.
--- Handles key events: characters, backspace, delete, arrow keys, home, end.
function textinput.update(model, msg)
    if not model._focused then return model end
    if msg.kind ~= "key" then return model end

    local key = msg.key

    -- Full line input (cooked-mode fallback)
    if key == "line" and msg.value then
        local text = msg.value
        if model._char_limit then
            text = text:sub(1, model._char_limit)
        end
        model._value = text
        model._cursor = #text
        return model
    end

    -- Backspace
    if key == "backspace" or key == "ctrl+h" then
        if model._cursor > 0 then
            model._value = delete_at(model._value, model._cursor)
            model._cursor = model._cursor - 1
        end
        return model
    end

    -- Delete
    if key == "delete" or key == "ctrl+d" then
        if model._cursor < #model._value then
            model._value = delete_at(model._value, model._cursor + 1)
        end
        return model
    end

    -- Left arrow
    if key == "left" or key == "ctrl+b" then
        if model._cursor > 0 then
            model._cursor = model._cursor - 1
        end
        return model
    end

    -- Right arrow
    if key == "right" or key == "ctrl+f" then
        if model._cursor < #model._value then
            model._cursor = model._cursor + 1
        end
        return model
    end

    -- Home
    if key == "home" or key == "ctrl+a" then
        model._cursor = 0
        return model
    end

    -- End
    if key == "end" or key == "ctrl+e" then
        model._cursor = #model._value
        return model
    end

    -- Kill line (ctrl+k)
    if key == "ctrl+k" then
        model._value = model._value:sub(1, model._cursor)
        return model
    end

    -- Kill to start (ctrl+u)
    if key == "ctrl+u" then
        model._value = model._value:sub(model._cursor + 1)
        model._cursor = 0
        return model
    end

    -- Kill word back (ctrl+w)
    if key == "ctrl+w" then
        local before = model._value:sub(1, model._cursor)
        local after = model._value:sub(model._cursor + 1)
        -- Remove trailing spaces then word characters
        local trimmed = before:gsub("%s+$", "")
        trimmed = trimmed:gsub("[^%s]+$", "")
        model._value = trimmed .. after
        model._cursor = #trimmed
        return model
    end

    -- Regular character input (single printable char)
    if #key == 1 and key:byte() >= 32 then
        if model._char_limit and #model._value >= model._char_limit then
            return model
        end
        model._value = insert_at(model._value, model._cursor, key)
        model._cursor = model._cursor + 1
        return model
    end

    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

local CURSOR_BLOCK = "▎"

--- Render the text input.
function textinput.view(model): string
    local parts = {}

    -- Prompt
    local prompt = model._prompt
    if model._prompt_style then
        prompt = model._prompt_style:render(prompt)
    end
    table.insert(parts, prompt)

    local val = model._value

    -- Empty → show placeholder
    if #val == 0 and not model._focused then
        local ph = model._placeholder
        if model._placeholder_style then
            ph = model._placeholder_style:render(ph)
        else
            ph = "\027[2m" .. ph .. "\027[0m"  -- dim
        end
        table.insert(parts, ph)
        return table.concat(parts)
    end

    if #val == 0 and model._focused then
        -- Show cursor + placeholder
        local cursor_ch = CURSOR_BLOCK
        if model._cursor_style then
            cursor_ch = model._cursor_style:render(cursor_ch)
        else
            cursor_ch = "\027[7m" .. " " .. "\027[0m"  -- reverse video space
        end
        table.insert(parts, cursor_ch)

        if #model._placeholder > 0 then
            local ph = model._placeholder
            if model._placeholder_style then
                ph = model._placeholder_style:render(ph)
            else
                ph = "\027[2m" .. ph .. "\027[0m"
            end
            table.insert(parts, ph)
        end
        return table.concat(parts)
    end

    -- Build display value
    local display = val
    if model._password then
        display = string.rep(model._password_char, #val)
    end

    -- Render with cursor
    if model._focused then
        local before = display:sub(1, model._cursor)
        local cursor_char = display:sub(model._cursor + 1, model._cursor + 1)
        local after = display:sub(model._cursor + 2)

        if model._style then
            before = model._style:render(before)
            after = model._style:render(after)
        end

        -- Cursor: reverse the character under cursor
        if #cursor_char == 0 then
            cursor_char = " "  -- cursor at end → space
        end
        if model._cursor_style then
            cursor_char = model._cursor_style:render(cursor_char)
        else
            cursor_char = "\027[7m" .. cursor_char .. "\027[0m"
        end

        table.insert(parts, before)
        table.insert(parts, cursor_char)
        table.insert(parts, after)
    else
        if model._style then
            table.insert(parts, model._style:render(display))
        else
            table.insert(parts, display)
        end
    end

    return table.concat(parts)
end

return textinput
