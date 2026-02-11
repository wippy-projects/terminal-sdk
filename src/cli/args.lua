--- CLI argument & option parser.
---
--- Parses command-line arguments against a definition table.
--- Supports positional arguments, short/long options, type coercion,
--- validation (required, choices), and `--help` auto-detection.
---
--- Usage:
---   local args = require("args")
---   local io = require("io")
---
---   local def = args.define({
---       name = "deploy",
---       description = "Deploy the application to a target environment",
---       usage = "deploy <environment> [flags]",
---       arguments = {
---           { name = "environment", description = "Target environment", required = true,
---             choices = {"staging", "production"} },
---       },
---       options = {
---           { name = "force",   short = "f", description = "Skip confirmation", type = "boolean" },
---           { name = "tag",     short = "t", description = "Docker image tag",  type = "string", default = "latest" },
---           { name = "replicas",short = "r", description = "Number of replicas", type = "number", default = 1 },
---           { name = "verbose", short = "v", description = "Verbose output",     type = "boolean" },
---       },
---       examples = {
---           "deploy staging",
---           "deploy production --tag v2.1.0 --replicas 3 -f",
---       },
---   })
---
---   local parsed, err = args.parse(def, io.args())
---   if err then
---       io.eprint("Error: " .. err)
---       io.print(args.help(def))
---       return 1
---   end
---
---   local env = parsed.arguments.environment  -- "staging"
---   local force = parsed.options.force         -- true/false
---   local tag = parsed.options.tag             -- "v2.1.0"

local args = {}

---------------------------------------------------------------------------
-- Definition builder
---------------------------------------------------------------------------

--- Create a command definition from a spec table.
--- Returns the definition unchanged (validation happens in parse).
function args.define(spec)
    spec.arguments = spec.arguments or {}
    spec.options = spec.options or {}
    spec.examples = spec.examples or {}
    return spec
end

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------

--- Parse raw argument list against a command definition.
---
--- Returns (result, nil) on success or (nil, error_string) on failure.
--- result = {
---     arguments = { name = value, ... },
---     options = { name = value, ... },
---     rest = { ... },   -- extra positional args
---     help = bool,       -- true if --help/-h was present
--- }
function args.parse(def, raw_args: {string})
    raw_args = raw_args or {}

    local result = {
        arguments = {},
        options = {},
        rest = {},
        help = false,
    }

    -- Build option lookup tables
    local long_opts = {}   -- "--name" → option def
    local short_opts = {}  -- "-x" → option def

    for _, opt in ipairs(def.options) do
        long_opts[opt.name] = opt
        if opt.short then
            short_opts[opt.short] = opt
        end
    end

    -- Apply defaults
    for _, opt in ipairs(def.options) do
        if opt.default ~= nil then
            result.options[opt.name] = opt.default
        elseif opt.type == "boolean" then
            result.options[opt.name] = false
        end
    end

    -- Parse args
    local positional = {}
    local i = 1
    local past_separator = false  -- after "--"

    while i <= #raw_args do
        local arg = raw_args[i]

        -- Separator: everything after "--" is positional
        if arg == "--" and not past_separator then
            past_separator = true
            i = i + 1
            goto continue
        end

        if past_separator then
            table.insert(positional, arg)
            i = i + 1
            goto continue
        end

        -- Help flag
        if arg == "--help" or arg == "-h" then
            result.help = true
            return result, nil
        end

        -- Long option: --name or --name=value
        if arg:sub(1, 2) == "--" then
            local name, value = arg:match("^%-%-([^=]+)=?(.*)")
            if not name then
                return nil, "invalid option: " .. arg
            end

            -- Handle --no-flag for booleans
            local negated = false
            local lookup_name = name
            if name:sub(1, 3) == "no-" then
                lookup_name = name:sub(4)
                negated = true
            end

            local opt = long_opts[lookup_name] or long_opts[name]
            if not opt then
                return nil, "unknown option: --" .. name
            end

            if opt.type == "boolean" then
                result.options[opt.name] = not negated
            else
                if value == "" then
                    -- Value is next arg
                    i = i + 1
                    if i > #raw_args then
                        return nil, "option --" .. opt.name .. " requires a value"
                    end
                    value = raw_args[i]
                end
                local coerced, cerr = coerce_value(value, opt)
                if cerr then return nil, cerr end
                result.options[opt.name] = coerced
            end

            i = i + 1
            goto continue
        end

        -- Short option: -f or -f value or combined -fv
        if arg:sub(1, 1) == "-" and #arg > 1 and arg:sub(2, 2) ~= "-" then
            local chars = arg:sub(2)
            local j = 1

            while j <= #chars do
                local ch = chars:sub(j, j)
                local opt = short_opts[ch]

                if not opt then
                    return nil, "unknown option: -" .. ch
                end

                if opt.type == "boolean" then
                    result.options[opt.name] = true
                    j = j + 1
                else
                    -- Non-boolean: rest of chars is the value, or next arg
                    local value
                    if j < #chars then
                        value = chars:sub(j + 1)
                    else
                        i = i + 1
                        if i > #raw_args then
                            return nil, "option -" .. ch .. " requires a value"
                        end
                        value = raw_args[i]
                    end
                    local coerced, cerr = coerce_value(value, opt)
                    if cerr then return nil, cerr end
                    result.options[opt.name] = coerced
                    break
                end
            end

            i = i + 1
            goto continue
        end

        -- Positional argument
        table.insert(positional, arg)
        i = i + 1

        ::continue::
    end

    -- Map positional args to defined arguments
    for idx, arg_def in ipairs(def.arguments) do
        if idx <= #positional then
            local value = positional[idx]

            -- Choices validation
            if arg_def.choices then
                local found = false
                for _, choice in ipairs(arg_def.choices) do
                    if value == choice then found = true; break end
                end
                if not found then
                    return nil, "argument '" .. arg_def.name .. "' must be one of: " ..
                           table.concat(arg_def.choices, ", ") .. " (got '" .. value .. "')"
                end
            end

            -- Type coercion for arguments
            if arg_def.type == "number" then
                local n = tonumber(value)
                if not n then
                    return nil, "argument '" .. arg_def.name .. "': expected number, got '" .. value .. "'"
                end
                value = n
            elseif arg_def.type == "integer" then
                local n = tonumber(value)
                if not n or n ~= math.floor(n) then
                    return nil, "argument '" .. arg_def.name .. "': expected integer, got '" .. value .. "'"
                end
                value = math.floor(n)
            end

            result.arguments[arg_def.name] = value
        elseif arg_def.required then
            return nil, "missing required argument: " .. arg_def.name
        elseif arg_def.default ~= nil then
            result.arguments[arg_def.name] = arg_def.default
        end
    end

    -- Collect rest (extra positional args beyond defined)
    for idx = #def.arguments + 1, #positional do
        table.insert(result.rest, positional[idx])
    end

    -- Validate required options
    for _, opt in ipairs(def.options) do
        if opt.required and result.options[opt.name] == nil then
            return nil, "missing required option: --" .. opt.name
        end
    end

    return result, nil
end

---------------------------------------------------------------------------
-- Type coercion (internal)
---------------------------------------------------------------------------

function coerce_value(value: string, opt)
    local t = opt.type or "string"

    if t == "number" then
        local n = tonumber(value)
        if not n then
            return nil, "option --" .. opt.name .. ": expected number, got '" .. value .. "'"
        end
        -- Choices validation
        if opt.choices then
            local found = false
            for _, c in ipairs(opt.choices) do
                if n == c then found = true; break end
            end
            if not found then
                return nil, "option --" .. opt.name .. " must be one of: " ..
                       table.concat(opt.choices, ", ")
            end
        end
        return n, nil
    end

    if t == "integer" then
        local n = tonumber(value)
        if not n or n ~= math.floor(n) then
            return nil, "option --" .. opt.name .. ": expected integer, got '" .. value .. "'"
        end
        return math.floor(n), nil
    end

    -- String
    if opt.choices then
        local found = false
        for _, c in ipairs(opt.choices) do
            if value == c then found = true; break end
        end
        if not found then
            return nil, "option --" .. opt.name .. " must be one of: " ..
                   table.concat(opt.choices, ", ") .. " (got '" .. value .. "')"
        end
    end

    return value, nil
end

---------------------------------------------------------------------------
-- Has option check
---------------------------------------------------------------------------

--- Check if a parsed result has a specific option set (non-default).
function args.has_option(result, name: string): boolean
    return result.options[name] ~= nil and result.options[name] ~= false
end

---------------------------------------------------------------------------
-- Help text generation
---------------------------------------------------------------------------

--- Generate formatted help text from a command definition.
function args.help(def): string
    local lines = {}

    -- Title
    if def.description then
        table.insert(lines, def.description)
        table.insert(lines, "")
    end

    -- Usage
    if def.usage then
        table.insert(lines, "Usage:")
        table.insert(lines, "  " .. (def.name or "command") .. " " .. def.usage)
    elseif def.name then
        local usage_parts = { def.name }
        for _, a in ipairs(def.arguments) do
            if a.required then
                table.insert(usage_parts, "<" .. a.name .. ">")
            else
                table.insert(usage_parts, "[" .. a.name .. "]")
            end
        end
        if #def.options > 0 then
            table.insert(usage_parts, "[flags]")
        end
        table.insert(lines, "Usage:")
        table.insert(lines, "  " .. table.concat(usage_parts, " "))
    end
    table.insert(lines, "")

    -- Arguments
    if #def.arguments > 0 then
        table.insert(lines, "Arguments:")
        local max_name = 0
        for _, a in ipairs(def.arguments) do
            if #a.name > max_name then max_name = #a.name end
        end
        for _, a in ipairs(def.arguments) do
            local line = "  " .. a.name .. string.rep(" ", max_name - #a.name + 2)
            if a.description then
                line = line .. a.description
            end
            if a.choices then
                line = line .. " [" .. table.concat(a.choices, "|") .. "]"
            end
            if a.default ~= nil then
                line = line .. " (default: " .. tostring(a.default) .. ")"
            end
            if a.required then
                line = line .. " (required)"
            end
            table.insert(lines, line)
        end
        table.insert(lines, "")
    end

    -- Options
    if #def.options > 0 then
        table.insert(lines, "Options:")
        local entries = {}
        local max_flag = 0

        for _, opt in ipairs(def.options) do
            local flag_parts = {}
            if opt.short then
                table.insert(flag_parts, "-" .. opt.short)
            end
            table.insert(flag_parts, "--" .. opt.name)
            local flag = table.concat(flag_parts, ", ")

            if opt.type and opt.type ~= "boolean" then
                flag = flag .. " <" .. opt.type .. ">"
            end

            if #flag > max_flag then max_flag = #flag end
            table.insert(entries, { flag = flag, opt = opt })
        end

        -- Add -h, --help
        local help_flag = "-h, --help"
        if #help_flag > max_flag then max_flag = #help_flag end

        for _, entry in ipairs(entries) do
            local line = "  " .. entry.flag .. string.rep(" ", max_flag - #entry.flag + 2)
            if entry.opt.description then
                line = line .. entry.opt.description
            end
            if entry.opt.default ~= nil and entry.opt.type ~= "boolean" then
                line = line .. " (default: " .. tostring(entry.opt.default) .. ")"
            end
            if entry.opt.choices then
                line = line .. " [" .. table.concat(entry.opt.choices, "|") .. "]"
            end
            if entry.opt.required then
                line = line .. " (required)"
            end
            table.insert(lines, line)
        end

        table.insert(lines, "  " .. help_flag ..
            string.rep(" ", max_flag - #help_flag + 2) .. "Show this help message")
        table.insert(lines, "")
    end

    -- Examples
    if #def.examples > 0 then
        table.insert(lines, "Examples:")
        for _, ex in ipairs(def.examples) do
            table.insert(lines, "  $ " .. ex)
        end
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

return args
