--- CLI interactive prompts — text, password, confirm, select, multiselect.
---
--- All prompts use io.readline() (cooked mode). Non-interactive fallback
--- returns defaults when stdin is not a TTY (detected by empty readline).
---
--- Usage:
---   local prompt = require("prompt")
---   local io = require("io")
---
---   local name = prompt.text("Your name", { default = "World" })
---   local pass = prompt.password("Password")
---   local ok = prompt.confirm("Continue?", { default = true })
---   local color = prompt.select("Pick a color", {"red", "green", "blue"})
---   local items = prompt.multiselect("Toppings", {"cheese", "peppers", "mushrooms"})

local prompt = {}

-- Dependencies injected at call time or via require
local _io = nil

--- Set the io module reference. Must be called before using prompts.
--- Alternatively, pass io in opts.io to each prompt call.
function prompt.set_io(io_mod)
    _io = io_mod
end

local function get_io(opts)
    return (opts and opts.io) or _io
end

---------------------------------------------------------------------------
-- Text input
---------------------------------------------------------------------------

--- Prompt for text input.
---
--- Options:
---   default: string? — default value (shown in brackets)
---   required: boolean — reject empty input (default: false)
---   validate: function(string) → (boolean, string?) — custom validator
---   io: io module reference (alternative to prompt.set_io)
function prompt.text(message: string, opts): string?
    opts = opts or {}
    local io_mod = get_io(opts)
    assert(io_mod, "prompt: io module not set. Call prompt.set_io(io) first")

    while true do
        local display = message
        if opts.default then
            display = display .. " [" .. opts.default .. "]"
        end
        io_mod.write(display .. ": ")
        io_mod.flush()

        local input = io_mod.readline()

        -- Non-interactive fallback
        if input == nil then
            return opts.default
        end

        input = input:match("^%s*(.-)%s*$") or ""

        -- Empty → use default
        if #input == 0 then
            if opts.default then return opts.default end
            if opts.required then
                io_mod.print("  Value is required. Please try again.")
                goto continue
            end
            return ""
        end

        -- Validate
        if opts.validate then
            local ok, err = opts.validate(input)
            if not ok then
                io_mod.print("  " .. (err or "Invalid input. Please try again."))
                goto continue
            end
        end

        return input

        ::continue::
    end
end

---------------------------------------------------------------------------
-- Password input
---------------------------------------------------------------------------

--- Prompt for password (input not echoed — uses asterisk feedback).
--- Note: True hidden input requires raw mode (Stage 1 Go-side).
--- Current fallback: reads line normally but marks it as password in prompt.
---
--- Options:
---   required: boolean (default: true)
---   confirm: boolean — ask to re-enter for confirmation (default: false)
---   io: io module reference
function prompt.password(message: string, opts): string?
    opts = opts or {}
    local io_mod = get_io(opts)
    assert(io_mod, "prompt: io module not set")

    local required = opts.required ~= false

    while true do
        io_mod.write(message .. ": ")
        io_mod.flush()

        local input = io_mod.readline()
        if input == nil then return nil end
        input = input:match("^%s*(.-)%s*$") or ""

        if #input == 0 and required then
            io_mod.print("  Password is required. Please try again.")
            goto continue
        end

        -- Confirmation
        if opts.confirm and #input > 0 then
            io_mod.write("Confirm " .. message:sub(1, 1):lower() .. message:sub(2) .. ": ")
            io_mod.flush()
            local confirm = io_mod.readline()
            if confirm ~= input then
                io_mod.print("  Passwords do not match. Please try again.")
                goto continue
            end
        end

        return input

        ::continue::
    end
end

---------------------------------------------------------------------------
-- Confirm (yes/no)
---------------------------------------------------------------------------

--- Prompt for yes/no confirmation.
---
--- Options:
---   default: boolean? — default when Enter is pressed (true = yes, false = no)
---   io: io module reference
function prompt.confirm(message: string, opts): boolean
    opts = opts or {}
    local io_mod = get_io(opts)
    assert(io_mod, "prompt: io module not set")

    local hint
    if opts.default == true then
        hint = "[Y/n]"
    elseif opts.default == false then
        hint = "[y/N]"
    else
        hint = "[y/n]"
    end

    while true do
        io_mod.write(message .. " " .. hint .. " ")
        io_mod.flush()

        local input = io_mod.readline()

        -- Non-interactive fallback
        if input == nil then
            return opts.default or false
        end

        input = (input:match("^%s*(.-)%s*$") or ""):lower()

        if #input == 0 and opts.default ~= nil then
            return opts.default
        end

        if input == "y" or input == "yes" then return true end
        if input == "n" or input == "no" then return false end

        io_mod.print("  Please answer yes or no.")
    end
end

---------------------------------------------------------------------------
-- Select (single choice)
---------------------------------------------------------------------------

--- Prompt to select one item from a list.
--- Displays numbered options; user enters the number.
---
--- Items can be strings or {label: string, value: any} tables.
---
--- Options:
---   default: integer? — default selection index (1-based)
---   display: function(item) → string — custom display formatter
---   io: io module reference
---
--- Returns the selected item (string or value field).
function prompt.select(message: string, items, opts)
    opts = opts or {}
    local io_mod = get_io(opts)
    assert(io_mod, "prompt: io module not set")
    assert(#items > 0, "prompt.select: items must not be empty")

    io_mod.print(message .. ":")

    -- Display items
    for i, item in ipairs(items) do
        local label
        if type(item) == "table" then
            label = (opts.display and opts.display(item)) or item.label or tostring(item)
        else
            label = (opts.display and opts.display(item)) or tostring(item)
        end

        local marker = ""
        if opts.default == i then marker = " (default)" end
        io_mod.print("  " .. i .. ") " .. label .. marker)
    end

    while true do
        local hint = "Choose [1-" .. #items .. "]"
        if opts.default then hint = hint .. " (default: " .. opts.default .. ")" end
        io_mod.write(hint .. ": ")
        io_mod.flush()

        local input = io_mod.readline()
        if input == nil then
            if opts.default then return get_item_value(items[opts.default]) end
            return nil
        end

        input = input:match("^%s*(.-)%s*$") or ""

        -- Empty → default
        if #input == 0 and opts.default then
            return get_item_value(items[opts.default])
        end

        local n = tonumber(input)
        if n and n >= 1 and n <= #items and n == math.floor(n) then
            return get_item_value(items[n])
        end

        -- Try matching by label text
        for i, item in ipairs(items) do
            local label = type(item) == "table" and (item.label or "") or tostring(item)
            if label:lower() == input:lower() then
                return get_item_value(items[i])
            end
        end

        io_mod.print("  Invalid selection. Please enter a number between 1 and " .. #items .. ".")
    end
end

---------------------------------------------------------------------------
-- Multi-select (multiple choices)
---------------------------------------------------------------------------

--- Prompt to select multiple items from a list.
--- User enters comma-separated numbers or ranges (e.g., "1,3-5").
---
--- Options:
---   defaults: {integer}? — pre-selected indices
---   min: integer? — minimum selections
---   max: integer? — maximum selections
---   display: function(item) → string
---   io: io module reference
---
--- Returns array of selected items.
function prompt.multiselect(message: string, items, opts)
    opts = opts or {}
    local io_mod = get_io(opts)
    assert(io_mod, "prompt: io module not set")
    assert(#items > 0, "prompt.multiselect: items must not be empty")

    local defaults = opts.defaults or {}
    local default_set = {}
    for _, idx in ipairs(defaults) do default_set[idx] = true end

    io_mod.print(message .. " (comma-separated numbers or ranges like 1,3-5):")

    for i, item in ipairs(items) do
        local label
        if type(item) == "table" then
            label = (opts.display and opts.display(item)) or item.label or tostring(item)
        else
            label = (opts.display and opts.display(item)) or tostring(item)
        end

        local marker = default_set[i] and " *" or ""
        io_mod.print("  " .. i .. ") " .. label .. marker)
    end

    while true do
        local hint = "Choose [1-" .. #items .. "]"
        if #defaults > 0 then
            hint = hint .. " (default: " .. table.concat(defaults, ",") .. ")"
        end
        io_mod.write(hint .. ": ")
        io_mod.flush()

        local input = io_mod.readline()
        if input == nil then
            -- Non-interactive: return defaults
            local result = {}
            for _, idx in ipairs(defaults) do
                table.insert(result, get_item_value(items[idx]))
            end
            return result
        end

        input = input:match("^%s*(.-)%s*$") or ""

        -- Empty → defaults
        if #input == 0 and #defaults > 0 then
            local result = {}
            for _, idx in ipairs(defaults) do
                table.insert(result, get_item_value(items[idx]))
            end
            return result
        end

        -- Parse selection: "1,3-5,7"
        local selected = {}
        local valid = true

        for part in input:gmatch("[^,]+") do
            part = part:match("^%s*(.-)%s*$")
            local range_start, range_end = part:match("^(%d+)%-(%d+)$")
            if range_start then
                local s = tonumber(range_start)
                local e = tonumber(range_end)
                if s and e and s >= 1 and e <= #items and s <= e then
                    for i = s, e do selected[i] = true end
                else
                    valid = false; break
                end
            else
                local n = tonumber(part)
                if n and n >= 1 and n <= #items and n == math.floor(n) then
                    selected[n] = true
                else
                    valid = false; break
                end
            end
        end

        if not valid then
            io_mod.print("  Invalid selection. Enter numbers between 1 and " .. #items .. ".")
            goto continue
        end

        -- Collect results in order
        local result = {}
        for i = 1, #items do
            if selected[i] then
                table.insert(result, get_item_value(items[i]))
            end
        end

        -- Min/max validation
        if opts.min and #result < opts.min then
            io_mod.print("  Please select at least " .. opts.min .. " item(s).")
            goto continue
        end
        if opts.max and #result > opts.max then
            io_mod.print("  Please select at most " .. opts.max .. " item(s).")
            goto continue
        end

        return result

        ::continue::
    end
end

---------------------------------------------------------------------------
-- Internal helper
---------------------------------------------------------------------------

function get_item_value(item)
    if type(item) == "table" then
        return item.value ~= nil and item.value or item
    end
    return item
end

return prompt
