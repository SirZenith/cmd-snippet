local luasnip = require "luasnip"

local base = require "cmd-snippet.base"
local cmp_source = require "cmd-snippet.cmp-source"
local config = require "cmd-snippet.config"
local util = require "cmd-snippet.util"

local M = {}

M.initialized = false

---@param dst table
---@param src table
local function merge_options(dst, src)
    for k, v in pairs(src) do
        local old_value = dst[k]

        if old_value == nil then
            dst[k] = vim.deepcopy(v)
        elseif type(v) ~= "table" then
            dst[k] = v
        elseif type(old_value) ~= "table" then
            dst[k] = v
        else
            merge_options(old_value, v)
        end
    end
end

---@param filetype string
---@param map table<string, cmd-snippet.CmdItemTable>
function M.register(filetype, map)
    for cmd, item in pairs(map) do
        local segments = vim.split(cmd, "%s+")
        util.filter_empty_str(segments)

        base.register_new_snip(filetype, segments, item)
    end
end

---@param options? table
function M.setup(options)
    if M.initialized then return end

    M.initialized = true

    if options then
        merge_options(config, options)
    end

    luasnip.add_snippets("all", {
        luasnip.snippet(
            {
                trig = config.cmd_head_char .. "(.+)" .. config.cmd_tail_char,
                regTrig = true,
            },
            luasnip.dynamic_node(1, base.command_snip_func)
        )
    }, {
        type = "autosnippets",
    })

    cmp_source.init()
end

return M
