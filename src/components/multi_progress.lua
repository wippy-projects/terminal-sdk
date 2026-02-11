--- Multi-worker progress tracker — aggregates progress from child processes.
---
--- Usage pattern:
---   -- In the TUI app process:
---   local mp = require("multi_progress")
---
---   init = function()
---       local tracker = mp.new()
---       -- Spawn workers that send progress via process.send()
---       for i = 1, 4 do
---           local pid = app.spawn("app:worker", "app:processes", i)
---           tracker = mp.register(tracker, pid, "Worker " .. i)
---       end
---       return { tracker = tracker }
---   end,
---   update = function(model, msg)
---       if msg.kind == "inbox" then
---           model.tracker = mp.handle_message(model.tracker, msg.value)
---       end
---       return model
---   end,
---   view = function(model)
---       return mp.view(model.tracker)
---   end
---
---   -- In the worker process:
---   local function main(task_id)
---       local parent = process.parent()
---       for i = 1, 100 do
---           do_work()
---           process.send(parent, "progress", {
---               percent = i / 100,
---               status = "Processing item " .. i,
---           })
---       end
---       process.send(parent, "progress", { percent = 1.0, done = true })
---   end

local multi_progress = {}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new multi-progress tracker.
---
--- Options:
---   width: integer — progress bar width per worker (default: 30)
---   show_percent: boolean — show percentage (default: true)
---   show_status: boolean — show status text (default: true)
---   show_label: boolean — show worker label (default: true)
---   label_width: integer — label column width (default: 15)
---   full_char: string — filled bar character (default: "█")
---   empty_char: string — empty bar character (default: "░")
---   topic: string — message topic to listen for (default: "progress")
---   done_text: string — text when worker finishes (default: "✓ Done")
---   style: style for progress bars
---   done_style: style for completed workers
---   label_style: style for worker labels
function multi_progress.new(opts)
    opts = opts or {}
    return {
        _type = "multi_progress",
        _workers = {},             -- ordered array of {pid, label, percent, status, done}
        _pid_index = {},           -- pid → index in _workers
        _width = opts.width or 30,
        _show_percent = opts.show_percent ~= false,
        _show_status = opts.show_status ~= false,
        _show_label = opts.show_label ~= false,
        _label_width = opts.label_width or 15,
        _full_char = opts.full_char or "█",
        _empty_char = opts.empty_char or "░",
        _topic = opts.topic or "progress",
        _done_text = opts.done_text or "✓ Done",
        _style = opts.style or nil,
        _done_style = opts.done_style or nil,
        _label_style = opts.label_style or nil,
    }
end

---------------------------------------------------------------------------
-- Worker management
---------------------------------------------------------------------------

--- Register a worker process to track.
function multi_progress.register(model, pid: string, label: string?)
    local entry = {
        pid = pid,
        label = label or pid,
        percent = 0,
        status = "",
        done = false,
        error = nil,
    }
    table.insert(model._workers, entry)
    model._pid_index[pid] = #model._workers
    return model
end

--- Remove a worker from tracking.
function multi_progress.unregister(model, pid: string)
    local idx = model._pid_index[pid]
    if idx then
        table.remove(model._workers, idx)
        model._pid_index[pid] = nil
        -- Rebuild index
        for i, w in ipairs(model._workers) do
            model._pid_index[w.pid] = i
        end
    end
    return model
end

---------------------------------------------------------------------------
-- Message handling
---------------------------------------------------------------------------

--- Handle an inbox message from a worker.
--- Expected payload: { percent: number, status?: string, done?: boolean, error?: string }
--- The message is matched by topic (default: "progress") and sender PID.
function multi_progress.handle_message(model, msg)
    local topic = msg:topic()
    if topic ~= model._topic then return model end

    local from = msg:from()
    if not from then return model end

    local idx = model._pid_index[from]
    if not idx then return model end

    local payload = msg:payload()
    if type(payload) ~= "table" then return model end

    local worker = model._workers[idx]

    if payload.percent ~= nil then
        worker.percent = math.max(0, math.min(1, payload.percent))
    end
    if payload.status ~= nil then
        worker.status = tostring(payload.status)
    end
    if payload.done then
        worker.done = true
        worker.percent = 1.0
    end
    if payload.error then
        worker.error = tostring(payload.error)
    end

    return model
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get overall progress (average of all workers, 0.0 to 1.0).
function multi_progress.overall_percent(model): number
    if #model._workers == 0 then return 0 end
    local total = 0
    for _, w in ipairs(model._workers) do
        total = total + w.percent
    end
    return total / #model._workers
end

--- Are all workers done?
function multi_progress.all_done(model): boolean
    for _, w in ipairs(model._workers) do
        if not w.done then return false end
    end
    return #model._workers > 0
end

--- Get worker count.
function multi_progress.worker_count(model): integer
    return #model._workers
end

--- Get done worker count.
function multi_progress.done_count(model): integer
    local count = 0
    for _, w in ipairs(model._workers) do
        if w.done then count = count + 1 end
    end
    return count
end

---------------------------------------------------------------------------
-- Update (passthrough — progress is driven by handle_message)
---------------------------------------------------------------------------

function multi_progress.update(model, msg)
    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render a single progress bar line.
local function render_bar(worker, model): string
    local parts = {}

    -- Label
    if model._show_label then
        local label = worker.label
        if #label > model._label_width then
            label = label:sub(1, model._label_width - 1) .. "…"
        else
            label = label .. string.rep(" ", model._label_width - #label)
        end
        if model._label_style then
            label = model._label_style:render(label)
        end
        table.insert(parts, label .. " ")
    end

    -- Error state
    if worker.error then
        local err_text = "✗ " .. worker.error
        table.insert(parts, "\027[31m" .. err_text .. "\027[0m")
        return table.concat(parts)
    end

    -- Done state
    if worker.done then
        if model._done_style then
            table.insert(parts, model._done_style:render(model._done_text))
        else
            table.insert(parts, "\027[32m" .. model._done_text .. "\027[0m")
        end
        return table.concat(parts)
    end

    -- Progress bar
    local w = model._width
    local filled = math.floor(w * worker.percent + 0.5)
    if filled > w then filled = w end
    local empty = w - filled

    local bar = string.rep(model._full_char, filled) .. string.rep(model._empty_char, empty)
    if model._style then
        bar = model._style:render(bar)
    end
    table.insert(parts, bar)

    -- Percentage
    if model._show_percent then
        table.insert(parts, string.format(" %3.0f%%", worker.percent * 100))
    end

    -- Status text
    if model._show_status and #worker.status > 0 then
        table.insert(parts, " \027[2m" .. worker.status .. "\027[0m")
    end

    return table.concat(parts)
end

--- Render all worker progress bars.
function multi_progress.view(model): string
    if #model._workers == 0 then
        return "\027[2mNo workers registered.\027[0m"
    end

    local lines = {}
    for _, worker in ipairs(model._workers) do
        table.insert(lines, render_bar(worker, model))
    end
    return table.concat(lines, "\n")
end

return multi_progress
