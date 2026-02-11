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

---------------------------------------------------------------------------
-- Frame renderer with line-level diffing
---------------------------------------------------------------------------

local _prev_lines = nil   -- previous frame's lines (for diffing)
local _frame_height = 0   -- how many lines the previous frame occupied

--- Render initial frame (full draw).
local function render_full(frame: string)
    local lines = ansi.lines(frame)
    _prev_lines = lines
    _frame_height = #lines

    io_mod.write(ansi.CURSOR_HIDE)
    for i, line in ipairs(lines) do
        io_mod.write(line)
        if i < #lines then
            io_mod.write("\n")
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
    -- We're at the end of the previous frame, so go up (_frame_height - 1) lines.
    if _frame_height > 1 then
        io_mod.write(ansi.cursor_up(_frame_height - 1))
    end
    io_mod.write("\r")

    for i = 1, max_lines do
        local new_line = lines[i] or ""
        local old_line = prev[i] or ""

        if new_line ~= old_line then
            io_mod.write(ansi.CLEAR_LINE)
            io_mod.write(new_line)
        end

        if i < max_lines then
            io_mod.write("\n")
        end
    end

    -- If new frame is shorter, clear remaining old lines
    if #lines < #prev then
        for _ = #lines + 1, #prev do
            io_mod.write("\n" .. ansi.CLEAR_LINE)
        end
        -- Move back up to the end of the new frame
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
    if opts.alt_screen then
        io_mod.write(ansi.ALT_SCREEN_ON)
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
end

---------------------------------------------------------------------------
-- Input reader (fallback when Go-side tui module is not available)
---------------------------------------------------------------------------

--- Spawn a coroutine that reads stdin line-by-line and pushes key messages.
--- This is the cooked-mode fallback — each line produces a message.
--- When the Go-side tui module exists, this is replaced by tui.events().
local function spawn_input_reader(events_ch)
    coroutine.spawn(function()
        while _running do
            local line, err = io_mod.readline()
            if err or not line then
                break
            end

            -- Parse simple commands from line input
            line = line:match("^%s*(.-)%s*$") or "" -- trim

            if #line == 0 then
                -- Empty enter → "enter" key
                events_ch:send({kind = "key", key = "enter"})
            elseif #line == 1 then
                -- Single character
                events_ch:send({kind = "key", key = line})
            else
                -- Multi-character: treat as line input message
                events_ch:send({kind = "key", key = "line", value = line})
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

    -- Initialize model
    local model = opts.init()

    -- Setup terminal
    setup_terminal(opts)

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
