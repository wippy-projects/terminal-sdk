--- Shell completion generator — generates bash, zsh, and fish completions from args definitions.
---
--- Usage:
---   local completion = require("completion")
---   local args = require("args")
---
---   local def = args.define({
---       name = "deploy",
---       description = "Deploy the application",
---       arguments = {
---           { name = "environment", choices = {"staging", "production"} },
---       },
---       options = {
---           { name = "force", short = "f", type = "boolean", description = "Skip confirmation" },
---           { name = "tag",   short = "t", type = "string",  description = "Docker image tag" },
---       },
---   })
---
---   -- Generate completion script
---   local bash_script = completion.bash(def, "myapp")
---   local zsh_script  = completion.zsh(def, "myapp")
---   local fish_script  = completion.fish(def, "myapp")
---
---   -- For multi-command CLIs, pass an array of definitions
---   local script = completion.bash_multi({deploy_def, build_def, test_def}, "myapp")

local completion = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function escape_single(s: string): string
    return s:gsub("'", "'\\''")
end

local function option_flags(opt): (string?, string?)
    local long = opt.name and ("--" .. opt.name) or nil
    local short = opt.short and ("-" .. opt.short) or nil
    return long, short
end

local function choices_str(items: {string}?): string
    if not items or #items == 0 then return "" end
    return table.concat(items, " ")
end

---------------------------------------------------------------------------
-- Bash completions
---------------------------------------------------------------------------

--- Generate bash completion script for a single command.
function completion.bash(def, program: string): string
    local lines = {}
    local fn_name = "_" .. program:gsub("[^%w]", "_") .. "_completions"

    table.insert(lines, "# Bash completion for " .. program)
    table.insert(lines, fn_name .. "()")
    table.insert(lines, "{")
    table.insert(lines, '    local cur="${COMP_WORDS[COMP_CWORD]}"')
    table.insert(lines, '    local prev="${COMP_WORDS[COMP_CWORD-1]}"')
    table.insert(lines, "")

    -- Collect all options
    local all_opts = {}
    for _, opt in ipairs(def.options or {}) do
        local long, short = option_flags(opt)
        if long then table.insert(all_opts, long) end
        if short then table.insert(all_opts, short) end
    end
    table.insert(all_opts, "--help")
    table.insert(all_opts, "-h")

    -- Option value completions
    for _, opt in ipairs(def.options or {}) do
        if opt.choices then
            local long, short = option_flags(opt)
            local conds = {}
            if long then table.insert(conds, '"' .. long .. '"') end
            if short then table.insert(conds, '"' .. short .. '"') end
            if #conds > 0 then
                table.insert(lines, '    case "$prev" in')
                table.insert(lines, "        " .. table.concat(conds, "|") .. ")")
                table.insert(lines, '            COMPREPLY=($(compgen -W "' .. choices_str(opt.choices) .. '" -- "$cur"))')
                table.insert(lines, "            return 0")
                table.insert(lines, "            ;;")
                table.insert(lines, "    esac")
                table.insert(lines, "")
            end
        end
    end

    -- File-type options get default file completion (no special handling needed)

    -- Option flag completion
    table.insert(lines, '    if [[ "$cur" == -* ]]; then')
    table.insert(lines, '        COMPREPLY=($(compgen -W "' .. table.concat(all_opts, " ") .. '" -- "$cur"))')
    table.insert(lines, "        return 0")
    table.insert(lines, "    fi")
    table.insert(lines, "")

    -- Positional argument completions
    local has_positional_choices = false
    for _, arg in ipairs(def.arguments or {}) do
        if arg.choices then
            has_positional_choices = true
            break
        end
    end

    if has_positional_choices then
        -- Determine which positional argument we're completing
        table.insert(lines, "    # Positional argument completions")
        table.insert(lines, "    local arg_idx=0")
        table.insert(lines, "    for ((i=1; i<COMP_CWORD; i++)); do")
        table.insert(lines, '        case "${COMP_WORDS[i]}" in')
        table.insert(lines, "            -*) ;; # skip options")
        table.insert(lines, "            *) ((arg_idx++)) ;;")
        table.insert(lines, "        esac")
        table.insert(lines, "    done")
        table.insert(lines, "")

        for i, arg in ipairs(def.arguments or {}) do
            if arg.choices then
                table.insert(lines, "    if [[ $arg_idx -eq " .. (i - 1) .. " ]]; then")
                table.insert(lines, '        COMPREPLY=($(compgen -W "' .. choices_str(arg.choices) .. '" -- "$cur"))')
                table.insert(lines, "        return 0")
                table.insert(lines, "    fi")
            end
        end
    end

    table.insert(lines, "}")
    table.insert(lines, "complete -F " .. fn_name .. " " .. program)
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Zsh completions
---------------------------------------------------------------------------

--- Generate zsh completion script for a single command.
function completion.zsh(def, program: string): string
    local lines = {}
    local fn_name = "_" .. program:gsub("[^%w]", "_")

    table.insert(lines, "#compdef " .. program)
    table.insert(lines, "")
    table.insert(lines, fn_name .. "() {")
    table.insert(lines, "    local -a args opts")
    table.insert(lines, "")

    -- Arguments
    for i, arg in ipairs(def.arguments or {}) do
        local desc = arg.description or arg.name
        if arg.choices then
            local choices = "(" .. table.concat(arg.choices, " ") .. ")"
            if arg.required then
                table.insert(lines, "    args+=('::" .. escape_single(desc) .. ":" .. choices .. "')")
            else
                table.insert(lines, "    args+=('::(" .. escape_single(desc) .. "):" .. choices .. "')")
            end
        else
            if arg.required then
                table.insert(lines, "    args+=('::" .. escape_single(desc) .. ": ')")
            else
                table.insert(lines, "    args+=('::(" .. escape_single(desc) .. "): ')")
            end
        end
    end

    -- Options
    for _, opt in ipairs(def.options or {}) do
        local long, short = option_flags(opt)
        local desc = escape_single(opt.description or opt.name)
        local spec

        if opt.type == "boolean" then
            -- Boolean flags: no argument
            if short then
                spec = "'(-" .. opt.short .. " " .. long .. ")'{-" .. opt.short .. "," .. long .. "}'[" .. desc .. "]'"
            else
                spec = "'" .. long .. "[" .. desc .. "]'"
            end
        else
            -- Value options
            local value_hint = ": :"
            if opt.choices then
                value_hint = ": :(" .. table.concat(opt.choices, " ") .. ")"
            end
            if short then
                spec = "'(-" .. opt.short .. " " .. long .. ")'{-" .. opt.short .. "," .. long .. "}'[" .. desc .. "]" .. value_hint .. "'"
            else
                spec = "'" .. long .. "[" .. desc .. "]" .. value_hint .. "'"
            end
        end

        table.insert(lines, "    opts+=(" .. spec .. ")")
    end

    -- Help
    table.insert(lines, "    opts+=('(-h --help)'{-h,--help}'[Show help]')")
    table.insert(lines, "")
    table.insert(lines, '    _arguments -s "$opts[@]" "$args[@]"')
    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, fn_name .. ' "$@"')
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Fish completions
---------------------------------------------------------------------------

--- Generate fish completion script for a single command.
function completion.fish(def, program: string): string
    local lines = {}

    table.insert(lines, "# Fish completion for " .. program)

    -- Options
    for _, opt in ipairs(def.options or {}) do
        local parts = {"complete -c " .. program}

        if opt.short then
            table.insert(parts, "-s " .. opt.short)
        end
        if opt.name then
            table.insert(parts, "-l " .. opt.name)
        end
        if opt.description then
            table.insert(parts, "-d '" .. escape_single(opt.description) .. "'")
        end
        if opt.type == "boolean" then
            -- No argument required for flags
        else
            table.insert(parts, "-r")  -- requires argument
            if opt.choices then
                table.insert(parts, "-f -a '" .. table.concat(opt.choices, " ") .. "'")
            end
        end

        table.insert(lines, table.concat(parts, " "))
    end

    -- Help
    table.insert(lines, "complete -c " .. program .. " -s h -l help -d 'Show help'")

    -- Positional argument completions with choices
    for _, arg in ipairs(def.arguments or {}) do
        if arg.choices then
            local desc = arg.description or arg.name
            table.insert(lines, "complete -c " .. program .. " -f -a '" ..
                table.concat(arg.choices, " ") .. "' -d '" .. escape_single(desc) .. "'")
        end
    end

    table.insert(lines, "")
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Multi-command support
---------------------------------------------------------------------------

--- Generate bash completion for a multi-command CLI.
--- defs is an array of args.define() definitions.
function completion.bash_multi(defs, program: string): string
    local lines = {}
    local fn_name = "_" .. program:gsub("[^%w]", "_") .. "_completions"

    table.insert(lines, "# Bash completion for " .. program)
    table.insert(lines, fn_name .. "()")
    table.insert(lines, "{")
    table.insert(lines, '    local cur="${COMP_WORDS[COMP_CWORD]}"')
    table.insert(lines, '    local prev="${COMP_WORDS[COMP_CWORD-1]}"')
    table.insert(lines, "")

    -- Collect subcommand names
    local cmd_names = {}
    for _, def in ipairs(defs) do
        table.insert(cmd_names, def.name)
    end

    -- Level 1: subcommand completion
    table.insert(lines, "    if [[ $COMP_CWORD -eq 1 ]]; then")
    table.insert(lines, '        COMPREPLY=($(compgen -W "' .. table.concat(cmd_names, " ") .. ' help" -- "$cur"))')
    table.insert(lines, "        return 0")
    table.insert(lines, "    fi")
    table.insert(lines, "")

    -- Level 2+: per-subcommand completion
    table.insert(lines, '    local cmd="${COMP_WORDS[1]}"')
    table.insert(lines, '    case "$cmd" in')

    for _, def in ipairs(defs) do
        local opts = {"--help", "-h"}
        for _, opt in ipairs(def.options or {}) do
            local long, short = option_flags(opt)
            if long then table.insert(opts, long) end
            if short then table.insert(opts, short) end
        end

        table.insert(lines, "        " .. def.name .. ")")
        table.insert(lines, '            COMPREPLY=($(compgen -W "' .. table.concat(opts, " ") .. '" -- "$cur"))')
        table.insert(lines, "            return 0")
        table.insert(lines, "            ;;")
    end

    table.insert(lines, "    esac")
    table.insert(lines, "}")
    table.insert(lines, "complete -F " .. fn_name .. " " .. program)
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

--- Generate fish completion for a multi-command CLI.
function completion.fish_multi(defs, program: string): string
    local lines = {}
    table.insert(lines, "# Fish completion for " .. program)
    table.insert(lines, "")

    -- Subcommand names
    local cmd_names = {}
    for _, def in ipairs(defs) do
        table.insert(cmd_names, def.name)
    end

    -- Subcommands
    for _, def in ipairs(defs) do
        local desc = def.description or def.name
        table.insert(lines, "complete -c " .. program ..
            " -n '__fish_use_subcommand' -a " .. def.name ..
            " -d '" .. escape_single(desc) .. "'")
    end
    table.insert(lines, "complete -c " .. program ..
        " -n '__fish_use_subcommand' -a help -d 'Show help'")
    table.insert(lines, "")

    -- Per-subcommand options
    for _, def in ipairs(defs) do
        local subcond = "__fish_seen_subcommand_from " .. def.name

        for _, opt in ipairs(def.options or {}) do
            local parts = {"complete -c " .. program, "-n '" .. subcond .. "'"}
            if opt.short then table.insert(parts, "-s " .. opt.short) end
            if opt.name then table.insert(parts, "-l " .. opt.name) end
            if opt.description then table.insert(parts, "-d '" .. escape_single(opt.description) .. "'") end
            if opt.type ~= "boolean" then
                table.insert(parts, "-r")
                if opt.choices then
                    table.insert(parts, "-f -a '" .. table.concat(opt.choices, " ") .. "'")
                end
            end
            table.insert(lines, table.concat(parts, " "))
        end
    end

    table.insert(lines, "")
    return table.concat(lines, "\n")
end

return completion
