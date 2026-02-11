--- Timer component — countdown timer with start/stop/toggle.
---
--- Usage within a tui.app:
---   local timer = require("timer")
---
---   init = function()
---       return { t = timer.new({ duration = "5m" }) }
---   end,
---   update = function(model, msg)
---       model.t = timer.update(model.t, msg)
---       if timer.is_done(model.t) then
---           -- timer finished
---       end
---       return model
---   end,
---   view = function(model)
---       return timer.view(model.t)
---   end
---
--- The timer decrements on {kind = "tick"} messages.
--- Call `app.tick(timer.interval(model))` to keep it running.

local timer = {}

---------------------------------------------------------------------------
-- Duration parsing
---------------------------------------------------------------------------

--- Parse a duration string into milliseconds.
--- Supports: "30s", "5m", "1h", "1m30s", "90000" (ms), or number (ms).
local function parse_duration(d): integer
    if type(d) == "number" then return math.floor(d) end
    local s = tostring(d)

    -- Try combined format: 1h2m3s
    local total = 0
    local found = false

    local h = s:match("(%d+)h")
    if h then total = total + tonumber(h) * 3600000; found = true end

    local m = s:match("(%d+)m")
    if m then total = total + tonumber(m) * 60000; found = true end

    local sec = s:match("(%d+)s")
    if sec then total = total + tonumber(sec) * 1000; found = true end

    local ms = s:match("(%d+)ms")
    if ms then total = total + tonumber(ms); found = true end

    if found then return total end

    -- Fallback: raw number as ms
    local num = tonumber(s)
    if num then return math.floor(num) end

    return 0
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new countdown timer model.
---
--- Options:
---   duration: string|number — countdown duration (e.g. "5m", "30s", 60000)
---   interval: string — tick interval (default: "1s")
---   auto_start: boolean — start immediately (default: false)
---   style: style for the time display
---   done_style: style when timer reaches zero
---   format: string — "hms" (default), "ms", "s", or custom format function
function timer.new(opts)
    opts = opts or {}
    local dur = parse_duration(opts.duration or "0s")

    return {
        _type = "timer",
        _duration = dur,           -- total duration in ms
        _remaining = dur,          -- remaining ms
        _interval = opts.interval or "1s",
        _interval_ms = parse_duration(opts.interval or "1s"),
        _running = opts.auto_start or false,
        _done = dur == 0,
        _style = opts.style or nil,
        _done_style = opts.done_style or nil,
        _format = opts.format or "hms",
    }
end

---------------------------------------------------------------------------
-- Time formatting
---------------------------------------------------------------------------

local function format_hms(ms: integer): string
    local total_s = math.floor(ms / 1000)
    local h = math.floor(total_s / 3600)
    local m = math.floor((total_s % 3600) / 60)
    local s = total_s % 60

    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

local function format_ms(ms: integer): string
    local total_s = math.floor(ms / 1000)
    local m = math.floor(total_s / 60)
    local s = total_s % 60
    return string.format("%d:%02d", m, s)
end

local function format_seconds(ms: integer): string
    return string.format("%d", math.floor(ms / 1000))
end

local function format_time(ms: integer, fmt): string
    if type(fmt) == "function" then
        return fmt(ms)
    elseif fmt == "ms" then
        return format_ms(ms)
    elseif fmt == "s" then
        return format_seconds(ms)
    end
    return format_hms(ms)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

--- Start the timer.
function timer.start(model)
    if not model._done then
        model._running = true
    end
    return model
end

--- Stop (pause) the timer.
function timer.stop(model)
    model._running = false
    return model
end

--- Toggle start/stop.
function timer.toggle(model)
    if model._running then
        return timer.stop(model)
    else
        return timer.start(model)
    end
end

--- Reset timer to original duration.
function timer.reset(model)
    model._remaining = model._duration
    model._running = false
    model._done = false
    return model
end

--- Set a new duration and reset.
function timer.set_duration(model, duration)
    local dur = parse_duration(duration)
    model._duration = dur
    model._remaining = dur
    model._running = false
    model._done = false
    return model
end

--- Is the timer running?
function timer.is_running(model): boolean
    return model._running
end

--- Has the timer finished?
function timer.is_done(model): boolean
    return model._done
end

--- Get remaining time in milliseconds.
function timer.remaining(model): integer
    return model._remaining
end

--- Get the tick interval (pass to app.tick()).
function timer.interval(model): string
    return model._interval
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update timer state. Decrements on {kind = "tick"} when running.
function timer.update(model, msg)
    if msg.kind == "tick" and model._running and not model._done then
        model._remaining = model._remaining - model._interval_ms
        if model._remaining <= 0 then
            model._remaining = 0
            model._running = false
            model._done = true
        end
    end
    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the timer display.
function timer.view(model): string
    local text = format_time(model._remaining, model._format)

    if model._done and model._done_style then
        return model._done_style:render(text)
    elseif model._style then
        return model._style:render(text)
    end
    return text
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Stopwatch — count-up timer
---------------------------------------------------------------------------
---------------------------------------------------------------------------

local stopwatch = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new stopwatch model (counts up from zero).
---
--- Options:
---   interval: string — tick interval (default: "100ms")
---   auto_start: boolean — start immediately (default: false)
---   style: style for the time display
---   format: string — "hms" (default), "ms", "s", "precise", or custom function
function stopwatch.new(opts)
    opts = opts or {}
    return {
        _type = "stopwatch",
        _elapsed = 0,              -- elapsed ms
        _interval = opts.interval or "100ms",
        _interval_ms = parse_duration(opts.interval or "100ms"),
        _running = opts.auto_start or false,
        _style = opts.style or nil,
        _format = opts.format or "hms",
        _laps = {},                -- lap times (array of ms)
    }
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

--- Start the stopwatch.
function stopwatch.start(model)
    model._running = true
    return model
end

--- Stop (pause) the stopwatch.
function stopwatch.stop(model)
    model._running = false
    return model
end

--- Toggle start/stop.
function stopwatch.toggle(model)
    if model._running then
        return stopwatch.stop(model)
    else
        return stopwatch.start(model)
    end
end

--- Reset to zero (stops if running).
function stopwatch.reset(model)
    model._elapsed = 0
    model._running = false
    model._laps = {}
    return model
end

--- Record a lap time.
function stopwatch.lap(model)
    table.insert(model._laps, model._elapsed)
    return model
end

--- Get laps array.
function stopwatch.laps(model): {integer}
    return model._laps
end

--- Is the stopwatch running?
function stopwatch.is_running(model): boolean
    return model._running
end

--- Get elapsed time in milliseconds.
function stopwatch.elapsed(model): integer
    return model._elapsed
end

--- Get the tick interval (pass to app.tick()).
function stopwatch.interval(model): string
    return model._interval
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update stopwatch state. Increments on {kind = "tick"} when running.
function stopwatch.update(model, msg)
    if msg.kind == "tick" and model._running then
        model._elapsed = model._elapsed + model._interval_ms
    end
    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

local function format_precise(ms: integer): string
    local total_s = math.floor(ms / 1000)
    local frac = ms % 1000
    local h = math.floor(total_s / 3600)
    local m = math.floor((total_s % 3600) / 60)
    local s = total_s % 60

    if h > 0 then
        return string.format("%d:%02d:%02d.%01d", h, m, s, math.floor(frac / 100))
    end
    return string.format("%d:%02d.%01d", m, s, math.floor(frac / 100))
end

--- Render the stopwatch display.
function stopwatch.view(model): string
    local text
    if model._format == "precise" then
        text = format_precise(model._elapsed)
    else
        text = format_time(model._elapsed, model._format)
    end

    if model._style then
        return model._style:render(text)
    end
    return text
end

-- Export both in a combined module
return {
    -- Timer (countdown)
    new = timer.new,
    start = timer.start,
    stop = timer.stop,
    toggle = timer.toggle,
    reset = timer.reset,
    set_duration = timer.set_duration,
    is_running = timer.is_running,
    is_done = timer.is_done,
    remaining = timer.remaining,
    interval = timer.interval,
    update = timer.update,
    view = timer.view,

    -- Stopwatch (count-up)
    stopwatch = stopwatch,
}
