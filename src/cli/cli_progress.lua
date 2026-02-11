--- CLI progress indicators — line-based (non-TUI) progress display.
---
--- Simple progress bar, spinner, and multi-bar that work with io.write()
--- on a single terminal line (using carriage return \r for updates).
---
--- Usage:
---   local cli_progress = require("cli_progress")
---   local io = require("io")
---
---   -- Simple progress bar
---   local bar = cli_progress.bar({ total = 100, width = 30 })
---   for i = 1, 100 do
---       cli_progress.update(bar, i)
---       cli_progress.render(bar, io)
---       -- do work...
---   end
---   cli_progress.finish(bar, io)
---
---   -- Spinner with message
---   local spin = cli_progress.spinner({ message = "Downloading..." })
---   for i = 1, 50 do
---       cli_progress.tick_spinner(spin)
---       cli_progress.render_spinner(spin, io)
---       -- do work...
---   end
---   cli_progress.finish_spinner(spin, io, "Done!")

local cli_progress = {}

---------------------------------------------------------------------------
-- Progress bar
---------------------------------------------------------------------------

--- Create a CLI progress bar state.
---
--- Options:
---   total: number — total value (required)
---   width: integer — bar width in characters (default: 30)
---   full_char: string (default: "█")
---   empty_char: string (default: "░")
---   show_percent: boolean (default: true)
---   show_count: boolean — show current/total (default: false)
---   message: string? — prefix message
---   complete_message: string? — message shown on finish
function cli_progress.bar(opts)
    opts = opts or {}
    return {
        _type = "cli_bar",
        _total = opts.total or 100,
        _current = 0,
        _width = opts.width or 30,
        _full_char = opts.full_char or "█",
        _empty_char = opts.empty_char or "░",
        _show_percent = opts.show_percent ~= false,
        _show_count = opts.show_count or false,
        _message = opts.message or nil,
        _complete_message = opts.complete_message or nil,
    }
end

--- Update the progress bar value.
function cli_progress.update(bar, current: number)
    if current < 0 then current = 0 end
    if current > bar._total then current = bar._total end
    bar._current = current
    return bar
end

--- Increment the progress bar by delta.
function cli_progress.incr_bar(bar, delta: number?)
    return cli_progress.update(bar, bar._current + (delta or 1))
end

--- Render the progress bar to a single line (overwrites current line).
function cli_progress.render(bar, io_mod)
    local percent = bar._current / bar._total
    if percent > 1 then percent = 1 end
    local filled = math.floor(bar._width * percent + 0.5)
    local empty = bar._width - filled

    local parts = {}

    if bar._message then
        table.insert(parts, bar._message .. " ")
    end

    table.insert(parts, string.rep(bar._full_char, filled))
    table.insert(parts, string.rep(bar._empty_char, empty))

    if bar._show_percent then
        table.insert(parts, string.format(" %3.0f%%", percent * 100))
    end

    if bar._show_count then
        table.insert(parts, string.format(" (%d/%d)", bar._current, bar._total))
    end

    io_mod.write("\r" .. table.concat(parts))
    io_mod.flush()
end

--- Finish the progress bar (print newline, optional complete message).
function cli_progress.finish(bar, io_mod, message: string?)
    local msg = message or bar._complete_message
    if msg then
        io_mod.write("\r\027[2K" .. msg .. "\n")
    else
        io_mod.write("\n")
    end
    io_mod.flush()
end

---------------------------------------------------------------------------
-- Spinner
---------------------------------------------------------------------------

local SPINNER_FRAMES = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

--- Create a CLI spinner state.
---
--- Options:
---   message: string? — text shown after spinner
---   frames: {string}? — custom animation frames
function cli_progress.spinner(opts)
    opts = opts or {}
    return {
        _type = "cli_spinner",
        _frames = opts.frames or SPINNER_FRAMES,
        _frame = 1,
        _message = opts.message or "",
    }
end

--- Advance the spinner frame.
function cli_progress.tick_spinner(spin)
    spin._frame = (spin._frame % #spin._frames) + 1
    return spin
end

--- Update spinner message.
function cli_progress.set_message(spin, message: string)
    spin._message = message
    return spin
end

--- Render the spinner to current line.
function cli_progress.render_spinner(spin, io_mod)
    local frame = spin._frames[spin._frame]
    io_mod.write("\r\027[2K" .. frame .. " " .. spin._message)
    io_mod.flush()
end

--- Finish the spinner (clear line, print final message).
function cli_progress.finish_spinner(spin, io_mod, message: string?)
    local msg = message or "Done"
    io_mod.write("\r\027[2K" .. "✓ " .. msg .. "\n")
    io_mod.flush()
end

---------------------------------------------------------------------------
-- Multi-bar (multiple named progress bars)
---------------------------------------------------------------------------

--- Create a multi-bar progress tracker.
---
--- Usage:
---   local multi = cli_progress.multi()
---   cli_progress.add_bar(multi, "download", { total = 100, message = "Downloading" })
---   cli_progress.add_bar(multi, "extract", { total = 50, message = "Extracting" })
---   cli_progress.update_bar(multi, "download", 50)
---   cli_progress.render_multi(multi, io)
function cli_progress.multi()
    return {
        _type = "cli_multi",
        _bars = {},
        _order = {},
        _prev_lines = 0,
    }
end

--- Add a named bar to the multi-bar tracker.
function cli_progress.add_bar(multi, name: string, opts)
    multi._bars[name] = cli_progress.bar(opts)
    table.insert(multi._order, name)
    return multi
end

--- Update a named bar's value.
function cli_progress.update_bar(multi, name: string, current: number)
    local bar = multi._bars[name]
    if bar then
        cli_progress.update(bar, current)
    end
    return multi
end

--- Increment a named bar.
function cli_progress.incr_multi_bar(multi, name: string, delta: number?)
    local bar = multi._bars[name]
    if bar then
        cli_progress.update(bar, bar._current + (delta or 1))
    end
    return multi
end

--- Render all bars in the multi-bar tracker.
function cli_progress.render_multi(multi, io_mod)
    -- Move cursor up to overwrite previous render
    if multi._prev_lines > 0 then
        io_mod.write("\027[" .. multi._prev_lines .. "A")
    end

    local line_count = 0
    for _, name in ipairs(multi._order) do
        local bar = multi._bars[name]
        local percent = bar._current / bar._total
        if percent > 1 then percent = 1 end
        local filled = math.floor(bar._width * percent + 0.5)
        local empty = bar._width - filled

        local parts = {}
        if bar._message then
            table.insert(parts, bar._message)
        else
            table.insert(parts, name)
        end

        -- Pad message to 15 chars for alignment
        local msg = table.concat(parts)
        local msg_w = #msg
        if msg_w < 15 then
            msg = msg .. string.rep(" ", 15 - msg_w)
        end

        local line = msg .. " " ..
            string.rep(bar._full_char, filled) ..
            string.rep(bar._empty_char, empty)

        if bar._show_percent then
            line = line .. string.format(" %3.0f%%", percent * 100)
        end
        if bar._show_count then
            line = line .. string.format(" (%d/%d)", bar._current, bar._total)
        end

        io_mod.write("\027[2K" .. line .. "\n")
        line_count = line_count + 1
    end

    multi._prev_lines = line_count
    io_mod.flush()
end

--- Finish multi-bar (leave cursor below).
function cli_progress.finish_multi(multi, io_mod)
    multi._prev_lines = 0
end

return cli_progress
