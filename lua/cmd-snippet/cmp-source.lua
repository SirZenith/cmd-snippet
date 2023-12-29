local cmp = require "cmp"

local CmdItem = require "cmd-snippet.cmd-item"

local M = {}

local EMPTY_SIGNAL_ITEM = {
    {
        label = "[empty]",
        insertText = "",
        kind = vim.lsp.protocol.CompletionItemKind.Text,
    },
}

---@alias CommandMap { [string]: (CommandMap | CmdItem) }

---@class CompletionItem
---@field label string
---@field insterText? string
---@field kind vim.lsp.protocol.CompletionItemKind

M.name = "cmd-snip-cmp"

---@type string[]
M.trigger_characters = { ":", " " }
M.cmd_head_char = ":"

---@type CommandMap | nil
local cmd_map = nil

function M.set_cmd_map(map)
    cmd_map = map
end

-- ----------------------------------------------------------------------------

---@return string[]
function M:get_trigger_characters()
    return M.trigger_characters
end

function M:is_available()
    return cmd_map ~= nil
end

---@param item CommandMap
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

---@param item CommandMap
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

---@param item CmdItem
---@return CompletionItem[]
local function gen_argument_list(item)
    local result = {}
    for i, name in ipairs(item:get_arg_names()) do
        table.insert(result, {
            label = ("#%d: %s"):format(i, name),
            insertText = name:gsub("-", "_"),
            kind = vim.lsp.protocol.CompletionItemKind.Field,
        })
    end
    return result
end

local function gen_empty_list()
    return EMPTY_SIGNAL_ITEM
end

---@return CompletionItem[] | nil
local function gen_completion(params)
    local items = {}
    if not cmd_map then return items end

    local line = params.context.cursor_before_line
    if not line then return items end

    local cmd = line:match(M.cmd_head_char .. "(.*)$")
    if not cmd then return items end

    cmd = cmd:gsub("%s+", "\n") .. "\n"
    local segments = vim.split(cmd, "\n", { plain = true })
    for i = #segments, 1, -1 do
        if segments[i] == "" then
            table.remove(segments, i)
        end
    end

    local result
    local walker = cmd_map
    local len = #segments
    for i, seg in ipairs(segments) do
        local next_step = walker[seg]
        local is_last = i == len

        if not next_step then
            result = is_last
                and gen_cmd_matching(walker, seg)
                or gen_empty_list()
            break
        elseif type(next_step) == "table" and CmdItem:is_instance(next_step) then
            result = gen_argument_list(next_step)
            break
        end

        walker = next_step
    end

    if not result then
        result = gen_cmd_list(walker)
    end

    return result
end

---@param params any
---@param callback fun(result: { items: CompletionItem[], isIncomplete: boolean } | nil)
function M:complete(params, callback)
    if not cmd_map then
        callback(nil)
        return
    end

    local items = gen_completion(params)
    if not items
        then callback(nil)
    else
        callback({ items = items, isIncomplete = true })
    end

end

-- ----------------------------------------------------------------------------

---@param cmd_head_char string
function M.init(cmd_head_char)
    cmp.register_source(M.name, M)

    M.cmd_head_char = cmd_head_char
end

return M
