local cmp = require "cmp"

local base = require "cmd-snippet.base"
local CmdItem = require "cmd-snippet.cmd-item"
local config = require "cmd-snippet.config"
local util = require "cmd-snippet.util"

local M = {}

---@class cmd-snippet.CompletionItem
---@field label string
---@field insterText? string
---@field kind number # see vim.lsp.protocol.CompletionItemKind

M.name = "cmd-snip-cmp"

-- ----------------------------------------------------------------------------

---@return string[]
function M:get_trigger_characters()
    return { config.cmd_head_char, " " }
end

function M:is_available()
    return true
end

---@param item cmd-snippet.CmdMap
local function gen_cmd_list(item)
    local result = {}
    for k in pairs(item) do
        table.insert(result, {
            label = k,
            kind = vim.lsp.protocol.CompletionItemKind.Method,
        })
    end
    return result
end

---@param item cmd-snippet.CmdMap
---@param seg string
local function gen_cmd_matching(item, seg)
    local result = {}
    for k in pairs(item) do
        if k:starts_with(seg) then
            table.insert(result, {
                label = k,
                kind = vim.lsp.protocol.CompletionItemKind.Method,
            })
        end
    end
    return result
end

---@param item cmd-snippet.CmdItem
---@param segments string[] # command segments
---@param index integer # index of last consumed segment
---@return cmd-snippet.CompletionItem[]
local function gen_argument_list(item, segments, index)
    local result = {}
    local names = item:get_arg_names()
    local st_index = #segments - index + 1

    for i = st_index, #names do
        local name = names[i]

        table.insert(result, {
            label = ("#%d: %s"):format(i, name),
            insertText = name:gsub("-", "_"),
            kind = vim.lsp.protocol.CompletionItemKind.Field,
        })
    end
    return result
end

---@param cmd_map cmd-snippet.CmdMap
---@param segments string[]
---@return cmd-snippet.CompletionItem[] | true
local function gen_completion_with_cmd_map(cmd_map, segments)
    local result
    local walker = cmd_map
    local len = #segments
    for i = 1, len do
        local seg = segments[i]
        local looking_at = walker[seg]

        if not looking_at then
            local is_last = i == len
            result = is_last and gen_cmd_matching(walker, seg) or true
            break
        elseif CmdItem:is_instance(looking_at) then
            result = gen_argument_list(looking_at, segments, i)
            break
        end

        walker = looking_at
    end

    if not result then
        result = gen_cmd_list(walker)
    end

    return result
end

---@return cmd-snippet.CompletionItem[]?
local function gen_completion(params)
    local line = params.context.cursor_before_line
    if not line then return nil end

    local cmd = line:match(config.cmd_head_char .. "(.*)$")
    if not cmd then return nil end

    local segments = vim.split(cmd, "%s+")
    util.filter_empty_str(segments)

    local type_list = vim.list_extend(
        { base.FALLBACK_FILETYPE },
        vim.split(vim.bo.filetype, ".", { plain = true })
    )

    local result = {}
    for _, filetype in ipairs(type_list) do
        local cmd_map = base.get_cmd_map_for_file_type(filetype)
        local type_result = gen_completion_with_cmd_map(cmd_map, segments)

        if type(type_result) == "table" then
            vim.list_extend(result, type_result)
        end
    end

    return result
end

---@param params any
---@param callback fun(result: { items: cmd-snippet.CompletionItem[], isIncomplete: boolean } | nil)
function M:complete(params, callback)
    local items = gen_completion(params)
    if not items then
        callback(nil)
    else
        callback({ items = items, isIncomplete = true })
    end
end

-- ----------------------------------------------------------------------------

function M.init()
    cmp.register_source(M.name, M)
end

return M
