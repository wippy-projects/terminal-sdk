--- TUI App Runtime — Elm Architecture (Model-Update-View) for terminal applications.
---
--- Manages the event loop, dispatches messages to update(), calls view() for rendering,
--- handles async side effects via cmd(), and provides frame-level diffing.
---
--- Usage:
---   local app = require("app")
---   local style = require("style")
---
---   app.run({
---       init = function() return { count = 0 } end,
---       update = function(model, msg)
---           if msg.kind == "key" and msg.key == "q" then app.quit() end
---           if msg.kind == "key" and msg.key == "up" then model.count = model.count + 1 end
---           return model
---       end,
---       view = function(model) return "Count: " .. model.count .. "\n\nPress q to quit." end,
---       alt_screen = true,
---   })

local io_mod = require("io")
local time = require("time")
local ansi = require("ansi")

local app = {}

---------------------------------------------------------------------------
-- Internal state (module-level, one app per process)
---------------------------------------------------------------------------

local _quit_requested = false
local _cmd_ch = nil           -- channel for cmd() results
local _tick_ch = nil          -- current tick timer channel
local _running = false
local _term_width = 80        -- terminal width (columns)
local _term_height = 24       -- terminal height (rows)

---------------------------------------------------------------------------
-- Public API: quit, cmd, batch, tick
---------------------------------------------------------------------------

--- Signal the app to exit after the current update cycle.
function app.quit()
    _quit_requested = true
end

--- Execute an async side effect. The function runs in a concurrent coroutine.
--- When it returns a table, that table is delivered as a message to update().
--- Returning nil means no message is delivered.
function app.cmd(fn)
    if not _cmd_ch then return end
    coroutine.spawn(function()
        local ok, result = pcall(fn)
        if ok and result ~= nil then
            _cmd_ch:send(result)
        elseif not ok then
            _cmd_ch:send({kind = "custom", type = "error", message = tostring(result)})
        end
    end)
end

--- Execute multiple commands concurrently. Each argument is a function.
function app.batch(...)
    local fns = {...}
    for _, fn in ipairs(fns) do
        app.cmd(fn)
    end
end

--- Schedule a tick message after the given duration.
--- Delivers {kind = "tick"} to update(). One-shot: call again in update() to repeat.
function app.tick(duration: string)
    _tick_ch = time.after(duration)
end

--- Send a message to a child/worker process.
--- Convenience wrapper around process.send().
function app.send(pid, topic: string, payload)
    process.send(pid, topic, payload)
end

--- Spawn a monitored child process. Returns the PID.
--- When the child exits, the app receives {kind = "inbox", value = msg}
--- where msg contains the EXIT event via process.events() in the child's parent.
function app.spawn(entry: string, host: string, ...)
    return process.spawn_monitored(entry, host, ...)
end

--- Get the terminal width (columns). Updated on startup and resize.
function app.width(): integer
    return _term_width
end

--- Get the terminal height (rows). Updated on startup and resize.
function app.height(): integer
    return _term_height
end

--- Get terminal size as (width, height).
function app.size(): (integer, integer)
    return _term_width, _term_height
end

---------------------------------------------------------------------------
-- Terminal size detection (DSR cursor position trick)
---------------------------------------------------------------------------

--- Read a single byte from stdin (used before input reader starts).
local function read_one_byte()
    local ch, err = io_mod.read(1)
    if err or not ch or #ch == 0 then return nil end
    return ch:byte(1)
end

--- Query terminal size using ANSI DSR (Device Status Report).
--- Must be called in raw mode, before the input reader starts.
--- Moves cursor to bottom-right, queries position, restores cursor.
local function query_terminal_size()
    -- Save cursor position
    io_mod.write(ansi.CURSOR_SAVE)
    -- Move cursor to a very large position (bottom-right corner)
    io_mod.write(ansi.cursor_move_to(9999, 9999))
    -- Query cursor position: terminal responds with ESC[rows;colsR
    io_mod.write("\027[6n")
    io_mod.flush()

    -- Read response: ESC [ rows ; cols R
    local b = read_one_byte()
    if not b or b ~= 27 then
        io_mod.write(ansi.CURSOR_RESTORE)
        io_mod.flush()
        return
    end
    b = read_one_byte()
    if not b or b ~= 91 then  -- '['
        io_mod.write(ansi.CURSOR_RESTORE)
        io_mod.flush()
        return
    end

    -- Read rows
    local rows_str = ""
    while true do
        b = read_one_byte()
        if not b then break end
        if b == 59 then break end  -- ';'
        rows_str = rows_str .. string.char(b)
    end

    -- Read cols
    local cols_str = ""
    while true do
        b = read_one_byte()
        if not b then break end
        if b == 82 then break end  -- 'R'
        cols_str = cols_str .. string.char(b)
    end

    -- Restore cursor position
    io_mod.write(ansi.CURSOR_RESTORE)
    io_mod.flush()

    local rows = tonumber(rows_str)
    local cols = tonumber(cols_str)
    if rows and rows > 0 then _term_height = rows end
    if cols and cols > 0 then _term_width = cols end
end

---------------------------------------------------------------------------
-- Frame renderer with line-level diffing
---------------------------------------------------------------------------

local _prev_lines = nil    -- previous frame's lines (for diffing)
local _frame_height = 0    -- how many lines the previous frame occupied
local _alt_screen = false  -- whether alternate screen buffer is active

--- Newline sequence: in raw mode \n doesn't carriage-return, so use \r\n.
local NL = "\r\n"

--- Render initial frame (full draw).
local function render_full(frame: string)
    local lines = ansi.lines(frame)
    _prev_lines = lines
    _frame_height = #lines

    if _alt_screen then
        io_mod.write(ansi.cursor_move_to(1, 1))
    end
    io_mod.write(ansi.CURSOR_HIDE)
    for i, line in ipairs(lines) do
        io_mod.write(line)
        if i < #lines then
            io_mod.write(NL)
        end
    end
    io_mod.flush()
end

--- Render frame with line-level diffing against previous frame.
local function render_diff(frame: string)
    local lines = ansi.lines(frame)
    local prev = _prev_lines or {}

    local max_lines = math.max(#lines, #prev)

    -- Move cursor to the start of the frame region.
    if _alt_screen then
        io_mod.write(ansi.cursor_move_to(1, 1))
    else
        if _frame_height > 1 then
            io_mod.write(ansi.cursor_up(_frame_height - 1))
        end
        io_mod.write("\r")
    end

    -- Line-level diffing: only redraw changed lines.
    for i = 1, max_lines do
        local new_line = lines[i] or ""
        local old_line = prev[i] or ""

        if new_line ~= old_line then
            io_mod.write(ansi.CLEAR_LINE)
            io_mod.write(new_line)
        end

        if i < max_lines then
            io_mod.write(NL)
        end
    end

    -- If new frame is shorter, clear remaining old lines
    if #lines < #prev then
        for _ = #lines + 1, #prev do
            io_mod.write(NL .. ansi.CLEAR_LINE)
        end
        if #prev > #lines then
            io_mod.write(ansi.cursor_up(#prev - #lines))
        end
    end

    io_mod.flush()

    _prev_lines = lines
    _frame_height = #lines
end

---------------------------------------------------------------------------
-- Terminal state management
---------------------------------------------------------------------------

local function setup_terminal(opts)
    _alt_screen = opts.alt_screen or false
    io_mod.raw(true)
    if opts.alt_screen then
        io_mod.write(ansi.ALT_SCREEN_ON)
        io_mod.write(ansi.CLEAR_SCREEN)
        io_mod.write(ansi.cursor_move_to(1, 1))
    end
    if opts.mouse then
        io_mod.write(ansi.MOUSE_ENABLE)
    end
    io_mod.write(ansi.CURSOR_HIDE)
    io_mod.flush()
end

local function restore_terminal(opts)
    io_mod.write(ansi.CURSOR_SHOW)
    if opts.mouse then
        io_mod.write(ansi.MOUSE_DISABLE)
    end
    if opts.alt_screen then
        io_mod.write(ansi.ALT_SCREEN_OFF)
    end
    io_mod.write(ansi.RESET)
    io_mod.flush()
    io_mod.raw(false)
end

---------------------------------------------------------------------------
-- Raw-mode input reader
---------------------------------------------------------------------------

--- Read a single byte from stdin. Returns the byte value or nil on error.
local function read_byte()
    local ch, err = io_mod.read(1)
    if err or not ch or #ch == 0 then return nil end
    return ch:byte(1)
end

--- Try to read next byte with a very short timeout.
--- Returns byte value or nil if nothing available.
local function read_byte_timeout()
    -- In raw mode io.read(1) blocks, so we just read directly.
    -- Escape sequence bytes arrive in rapid succession.
    return read_byte()
end

--- Parse a CSI (Control Sequence Introducer) sequence after ESC[.
--- Returns a structured event table or nil.
local function parse_csi(events_ch)
    local buf = ""

    while true do
        local b = read_byte()
        if not b then return end

        local c = string.char(b)

        -- SGR mouse: ESC[< starts mouse sequence
        if #buf == 0 and c == "<" then
            -- Read until M or m (SGR mouse terminator)
            local mouse_buf = ""
            while true do
                local mb = read_byte()
                if not mb then return end
                local mc = string.char(mb)
                if mc == "M" or mc == "m" then
                    -- Parse: btn;col;row + suffix
                    local mouse_seq = "[<" .. mouse_buf .. mc
                    local evt = ansi.parse_mouse_sgr(mouse_seq)
                    if evt then
                        events_ch:send(evt)
                    end
                    return
                end
                mouse_buf = mouse_buf .. mc
            end
        end

        -- Accumulate parameter bytes (digits, semicolons)
        if b >= 0x30 and b <= 0x3F then
            buf = buf .. c
        -- Final byte: determines the sequence meaning
        elseif b >= 0x40 and b <= 0x7E then
            -- Simple arrow/navigation keys (no params)
            if #buf == 0 then
                local key_map = {
                    A = "up", B = "down", C = "right", D = "left",
                    H = "home", F = "end", Z = "shift+tab",
                }
                local key = key_map[c]
                if key then
                    events_ch:send({kind = "key", key = key})
                end
                return
            end

            -- Tilde sequences: ESC[N~ (delete, pgup, pgdown, etc.)
            if c == "~" then
                local tilde_map = {
                    ["1"]  = "home",   ["2"]  = "insert",
                    ["3"]  = "delete", ["4"]  = "end",
                    ["5"]  = "pgup",   ["6"]  = "pgdown",
                    ["11"] = "f1",     ["12"] = "f2",
                    ["13"] = "f3",     ["14"] = "f4",
                    ["15"] = "f5",     ["17"] = "f6",
                    ["18"] = "f7",     ["19"] = "f8",
                    ["20"] = "f9",     ["21"] = "f10",
                    ["23"] = "f11",    ["24"] = "f12",
                }
                -- Strip modifier suffix (e.g., "3;5" → "3")
                local param = buf:match("^(%d+)")
                local key = tilde_map[param]
                if key then
                    events_ch:send({kind = "key", key = key})
                end
                return
            end

            -- Modified arrows: ESC[1;NX where N=modifier, X=direction
            if buf:match("^1;") and #c == 1 then
                local mod_n = tonumber(buf:match("^1;(%d+)"))
                local dir_map = {
                    A = "up", B = "down", C = "right", D = "left",
                    H = "home", F = "end",
                }
                local dir = dir_map[c]
                if dir and mod_n then
                    local prefix = ""
                    -- mod_n: 2=shift, 3=alt, 4=shift+alt, 5=ctrl, etc.
                    if mod_n == 2 then prefix = "shift+"
                    elseif mod_n == 3 then prefix = "alt+"
                    elseif mod_n == 5 then prefix = "ctrl+"
                    elseif mod_n == 6 then prefix = "ctrl+shift+"
                    end
                    events_ch:send({kind = "key", key = prefix .. dir})
                end
                return
            end

            -- SS3 function keys: ESC[OP..ESC[OS → F1..F4
            -- (Some terminals send ESC O P instead, handled below)
            return
        else
            -- Intermediate byte — skip
            buf = buf .. c
        end
    end
end

--- Parse an SS3 sequence after ESC O.
local function parse_ss3(events_ch)
    local b = read_byte()
    if not b then return end
    local ss3_map = {
        [0x50] = "f1", [0x51] = "f2", [0x52] = "f3", [0x53] = "f4",
        [0x41] = "up", [0x42] = "down", [0x43] = "right", [0x44] = "left",
        [0x48] = "home", [0x46] = "end",
    }
    local key = ss3_map[b]
    if key then
        events_ch:send({kind = "key", key = key})
    end
end

--- Spawn a coroutine that reads stdin byte-by-byte in raw mode
--- and pushes structured key/mouse events.
local function spawn_input_reader(events_ch)
    coroutine.spawn(function()
        while _running do
            local b = read_byte()
            if not b then break end

            -- Ctrl+letter (0x01–0x1A, except special cases)
            if b >= 1 and b <= 26 then
                if b == 9 then
                    events_ch:send({kind = "key", key = "tab"})
                elseif b == 13 then
                    events_ch:send({kind = "key", key = "enter"})
                elseif b == 10 then
                    events_ch:send({kind = "key", key = "enter"})
                else
                    local letter = string.char(b + 96) -- 1→a, 2→b, etc.
                    events_ch:send({kind = "key", key = "ctrl+" .. letter})
                end

            -- Escape (0x1B) — start of escape sequence or standalone
            elseif b == 27 then
                local next_b = read_byte()
                if not next_b then
                    events_ch:send({kind = "key", key = "escape"})
                elseif next_b == 91 then
                    -- CSI: ESC[
                    parse_csi(events_ch)
                elseif next_b == 79 then
                    -- SS3: ESC O
                    parse_ss3(events_ch)
                elseif next_b == 27 then
                    -- Double escape
                    events_ch:send({kind = "key", key = "escape"})
                elseif next_b >= 32 and next_b <= 126 then
                    -- Alt+key: ESC followed by printable char
                    events_ch:send({kind = "key", key = "alt+" .. string.char(next_b)})
                else
                    events_ch:send({kind = "key", key = "escape"})
                end

            -- Backspace (0x7F)
            elseif b == 127 then
                events_ch:send({kind = "key", key = "backspace"})

            -- Space
            elseif b == 32 then
                events_ch:send({kind = "key", key = " "})

            -- Printable ASCII
            elseif b >= 33 and b <= 126 then
                events_ch:send({kind = "key", key = string.char(b)})

            -- UTF-8 multi-byte sequences (pass through as character)
            elseif b >= 0xC0 and b <= 0xFD then
                local seq = string.char(b)
                local remaining = 0
                if b >= 0xC0 and b <= 0xDF then remaining = 1
                elseif b >= 0xE0 and b <= 0xEF then remaining = 2
                elseif b >= 0xF0 and b <= 0xF7 then remaining = 3
                end
                for _ = 1, remaining do
                    local cb = read_byte()
                    if not cb then break end
                    seq = seq .. string.char(cb)
                end
                events_ch:send({kind = "key", key = seq})
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Main app loop
---------------------------------------------------------------------------

--- Run the TUI application. Blocks until quit is requested.
---
--- Options:
---   init: function() → Model                          (required)
---   update: function(model, msg) → Model              (required)
---   view: function(model) → string                    (required)
---   alt_screen: boolean (default false)
---   mouse: boolean (default false)
---   fps: integer (default 60)
---   on_quit: function() — cleanup callback
function app.run(opts)
    assert(opts.init, "app.run: init function required")
    assert(opts.update, "app.run: update function required")
    assert(opts.view, "app.run: view function required")

    local fps = opts.fps or 60
    local frame_budget_ms = math.floor(1000 / fps)

    -- Reset state
    _quit_requested = false
    _cmd_ch = channel.new(64)
    _tick_ch = nil
    _prev_lines = nil
    _frame_height = 0
    _running = true

    -- Setup terminal (raw mode, alt screen)
    setup_terminal(opts)

    -- Query terminal size (must happen after raw mode, before input reader and init)
    query_terminal_size()

    -- Initialize model (after terminal size is known, so app.width()/height() work)
    local model = opts.init()

    -- Event sources
    local proc_events = process.events()
    local proc_inbox = process.inbox()

    -- Terminal events channel.
    -- Try Go-side tui.events() first; fall back to line-based reader.
    local events_ch = channel.new(64)
    local has_tui = false

    -- Try to get native tui events (will work when Stage 1 Go-side is done)
    -- For now, fall back to the io.readline() reader
    spawn_input_reader(events_ch)

    -- Render initial frame
    local ok_view, initial_frame = pcall(opts.view, model)
    if not ok_view then
        restore_terminal(opts)
        _running = false
        error(initial_frame)
    end
    render_full(initial_frame)

    -- Main event loop
    local dirty = false     -- whether model changed since last render
    local last_render = 0   -- timestamp of last render (ms)

    while not _quit_requested do
        -- Build select cases
        local cases = {
            events_ch:case_receive(),
            _cmd_ch:case_receive(),
            proc_events:case_receive(),
            proc_inbox:case_receive(),
        }
        if _tick_ch then
            table.insert(cases, _tick_ch:case_receive())
        end

        local r = channel.select(cases)

        -- Translate event to tui message
        local msg = nil

        if r.channel == proc_events then
            local event = r.value
            if event.kind == process.event.CANCEL then
                msg = {kind = "quit"}
                _quit_requested = true
            end
        elseif r.channel == proc_inbox then
            msg = {kind = "inbox", value = r.value}
        elseif _tick_ch and r.channel == _tick_ch then
            msg = {kind = "tick"}
            _tick_ch = nil  -- one-shot; user calls tick() again if needed
        elseif r.channel == _cmd_ch then
            msg = r.value  -- already a message table
        elseif r.channel == events_ch then
            msg = r.value  -- key/mouse/resize event
        end

        -- Dispatch to update()
        if msg then
            local ok_update, new_model = pcall(opts.update, model, msg)
            if not ok_update then
                restore_terminal(opts)
                _running = false
                error(new_model)
            end
            model = new_model
            dirty = true
        end

        -- Render if dirty (with FPS throttle)
        if dirty then
            local ok_render, frame = pcall(opts.view, model)
            if not ok_render then
                restore_terminal(opts)
                _running = false
                error(frame)
            end
            render_diff(frame)
            dirty = false
        end
    end

    -- Cleanup
    if opts.on_quit then
        local ok_quit, quit_err = pcall(opts.on_quit)
        if not ok_quit then
            restore_terminal(opts)
            _running = false
            error(quit_err)
        end
    end

    restore_terminal(opts)
    _running = false

    return 0
end

---------------------------------------------------------------------------
-- Convenience: is the app currently running?
---------------------------------------------------------------------------

function app.is_running(): boolean
    return _running
end

return app
