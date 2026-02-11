--- Spinner component — animated activity indicator.
---
--- Usage within a tui.app:
---   local spinner = require("spinner")
---
---   init = function()
---       return { spin = spinner.new() }
---   end,
---   update = function(model, msg)
---       model.spin = spinner.update(model.spin, msg)
---       return model
---   end,
---   view = function(model)
---       return spinner.view(model.spin) .. " Loading..."
---   end
---
--- The spinner auto-advances on {kind = "tick"} messages.
--- Call `app.tick(spinner.interval(model))` in update when you receive a tick
--- to keep the animation running.

local spinner = {}

---------------------------------------------------------------------------
-- Animation presets
---------------------------------------------------------------------------

spinner.DOTS = {
    frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
    interval = "80ms",
}

spinner.LINE = {
    frames = {"|", "/", "-", "\\"},
    interval = "130ms",
}

spinner.MINI_DOTS = {
    frames = {"⠋", "⠙", "⠸", "⠴", "⠦", "⠇"},
    interval = "100ms",
}

spinner.JUMP = {
    frames = {"⢄", "⢂", "⢁", "⡁", "⡈", "⡐", "⡠"},
    interval = "100ms",
}

spinner.PULSE = {
    frames = {"█", "▓", "▒", "░", "▒", "▓"},
    interval = "120ms",
}

spinner.GLOBE = {
    frames = {"🌍", "🌎", "🌏"},
    interval = "180ms",
}

spinner.MOON = {
    frames = {"🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"},
    interval = "120ms",
}

spinner.MONKEY = {
    frames = {"🙈", "🙉", "🙊"},
    interval = "200ms",
}

spinner.METER = {
    frames = {"▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱"},
    interval = "120ms",
}

spinner.HAMBURGER = {
    frames = {"☱", "☲", "☴", "☲"},
    interval = "100ms",
}

spinner.ELLIPSIS = {
    frames = {"   ", ".  ", ".. ", "..."},
    interval = "300ms",
}

spinner.POINTS = {
    frames = {"∙∙∙", "●∙∙", "∙●∙", "∙∙●"},
    interval = "200ms",
}

spinner.ARROW = {
    frames = {"←", "↖", "↑", "↗", "→", "↘", "↓", "↙"},
    interval = "100ms",
}

spinner.BOUNCING_BAR = {
    frames = {
        "[    ]", "[=   ]", "[==  ]", "[=== ]",
        "[ ===]", "[  ==]", "[   =]", "[    ]",
        "[   =]", "[  ==]", "[ ===]", "[====]",
        "[=== ]", "[==  ]", "[=   ]",
    },
    interval = "80ms",
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

--- Create a new spinner model.
---
--- Options:
---   preset: a spinner preset table (default: spinner.DOTS)
---   frames: custom frame array (overrides preset)
---   interval: tick interval string (overrides preset, e.g. "100ms")
---   style: a style object to apply to the spinner frame
function spinner.new(opts)
    opts = opts or {}
    local preset = opts.preset or spinner.DOTS

    return {
        _type = "spinner",
        frames = opts.frames or preset.frames,
        _interval = opts.interval or preset.interval,
        _style = opts.style or nil,
        _frame = 1,
    }
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

--- Update spinner state. Advances frame on {kind = "tick"} messages.
--- Returns the updated model.
function spinner.update(model, msg)
    if msg.kind == "tick" then
        model._frame = (model._frame % #model.frames) + 1
    end
    return model
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------

--- Render the current spinner frame.
function spinner.view(model): string
    local frame = model.frames[model._frame] or ""
    if model._style then
        return model._style:render(frame)
    end
    return frame
end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------

--- Get the tick interval for this spinner (pass to app.tick()).
function spinner.interval(model): string
    return model._interval
end

--- Set the style on the spinner model. Mutates and returns model.
function spinner.set_style(model, s)
    model._style = s
    return model
end

--- Reset the spinner to frame 1.
function spinner.reset(model)
    model._frame = 1
    return model
end

return spinner
