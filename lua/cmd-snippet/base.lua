local luasnip = require "luasnip"

local config = require "cmd-snippet.config"
local CmdItem = require "cmd-snippet.cmd-item"
local util = require "cmd-snippet.util"

local M = {}

---@alias cmd-snippet.CmdMap table<string, cmd-snippet.CmdMap | cmd-snippet.CmdItem>

---@type table<string, cmd-snippet.CmdMap>
local cmd_map_root = {}

M.FALLBACK_FILETYPE = "all"

---@param filetype string
---@return table
function M.get_cmd_map_for_file_type(filetype)
    local cmd_map = cmd_map_root[filetype]
    if not cmd_map then
        cmd_map = {}
        cmd_map_root[filetype] = cmd_map
    end

    return cmd_map
end

-- Locate CmdItem by command segments in command map.
---@param cmd_map cmd-snippet.CmdMap
---@param segments string[]
---@return cmd-snippet.CmdItem?
---@return string[] args # all uncomsumed segments
local function get_cmd_item(cmd_map, segments)
    local target, args = nil, segments

    local walker = cmd_map
    for i, seg in ipairs(segments) do
        walker = walker[seg]
        if not walker then
            break
        elseif CmdItem:is_instance(walker) then
            target = walker
            args = { unpack(segments, i + 1) }
            break
        end
    end

    return target, args
end

-- Find CmdItem pointed by command segments under given filetype.
---@param filetype string
---@param segments string[]
---@return cmd-snippet.CmdItem?
---@return string[] args # all uncomsumed segments
local function get_cmd_item_for_filetype(filetype, segments)
    local type_list = vim.split(filetype, ".", { plain = true })

    local target, args
    for _, type in ipairs(type_list) do
        local cmd_map = M.get_cmd_map_for_file_type(type)
        target, args = get_cmd_item(cmd_map, segments)

        if target then
            break
        end
    end

    if not target then
        local fallback_cmd_map = M.get_cmd_map_for_file_type(M.FALLBACK_FILETYPE)
        target, args = get_cmd_item(fallback_cmd_map, segments)
    end

    return target, args
end

---@param filetype string
---@param segments string[]
---@param item cmd-snippet.CmdItemTable
function M.register_new_snip(filetype, segments, item)
    local tail = table.remove(segments)
    if not tail then return end

    local cmd_map = M.get_cmd_map_for_file_type(filetype)
    local tbl = cmd_map
    for _, seg in ipairs(segments) do
        tbl = tbl[seg]
        if not tbl then
            tbl = {}
            cmd_map[seg] = tbl
        end
    end

    tbl[tail] = CmdItem:new(item)
end

-- ----------------------------------------------------------------------------

---@param cmd string
---@param err string
---@return cmd-snippet.SnippetNode
local function make_error_snippet(cmd, err)
    vim.notify(err, vim.log.levels.WARN)
    return luasnip.snippet_node(nil, { luasnip.text_node(config.cmd_head_char .. cmd) })
end

function M.command_snip_func(_, snip)
    local cmd = snip.captures[1] ---@type string
    local segments = vim.split(cmd, "%s+")
    util.filter_empty_str(segments)
    cmd = table.concat(segments, " ")

    local target, args = get_cmd_item_for_filetype(vim.bo.filetype, segments)
    if not target then
        return make_error_snippet(cmd, "no matching command")
    end

    local err, nodes
    if target.args
        and target:get_required_arg_cnt() > 0
        and #args == 0
    then
        nodes = target:gen_signature_snip()
        table.insert(nodes, 1, luasnip.text_node(config.cmd_head_char .. cmd .. " "))
    else
        err = target:check_args(args)
        if not err then
            err, nodes = target:make_snippet(args)
        end
    end

    if err or not nodes then
        return make_error_snippet(cmd, err or "failed to convert snippet content to node list")
    end

    local ok, result = xpcall(function()
        return luasnip.snippet_node(nil, nodes)
    end, function(make_err)
        err = debug.traceback(make_err) or make_err
    end)

    if not ok then
        return make_error_snippet(cmd, err or "failed to generate snippet node with node list")
    end

    return result
end

return M
