local cmp_source = require "cmd-snippet.cmp-source"
local luasnip = require "luasnip"
local CmdItem = require "cmd-snippet.cmd-item"

local M = {}

M.initialized = false
M.cmd_head_char = "::"
M.cmd_tail_char = ";"

local cmd_map = {}

---@param segments string[]
local function filter_empty_str(segments)
    for i = #segments, 1, -1 do
        if segments[i] == "" then
            table.remove(segments, i)
        end
    end
end

---@param segments string[]
---@param item CmdItem
local function register_new_snip(segments, item)
    local tail = table.remove(segments)
    if not tail then return end

    local tbl = cmd_map
    for _, seg in ipairs(segments) do
        tbl = cmd_map[seg]
        if not tbl then
            tbl = {}
            cmd_map[seg] = tbl
        end
    end

    tbl[tail] = CmdItem:new(item)
end

---@param map table<string, CmdItem>
function M.register(map)
    for cmd, item in pairs(map) do
        cmd = cmd:gsub("%s+", "\n")

        local segments = vim.split(cmd, "\n", { plain = true })
        filter_empty_str(segments)

        register_new_snip(segments, item)
    end
end

-- ----------------------------------------------------------------------------

local function command_snip_func(_, snip)
    local cmd = snip.captures[1] ---@type string
    local segments = vim.split(cmd, "%s+")
    filter_empty_str(segments)
    cmd = table.concat(segments, " ")

    local target ---@type CmdItem | nil
    local args ---@type string[]

    ---@type table
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

    local nodes
    if not target then
        vim.notify("no matching command", vim.log.levels.WARN)
    elseif target.args and target:get_required_arg_cnt() > 0 and #args == 0 then
        nodes = target:gen_signature_snip()
        table.insert(nodes, 1, luasnip.text_node(M.cmd_head_char .. cmd .. " "))
    else
        local err = target:check_args(args)
        if err then
            vim.notify(err, vim.log.levels.WARN)
        else
            nodes = target:make_snippet(args)
        end
    end

    local ok, result = false, nil
    if nodes then
        ok, result = pcall(luasnip.snippet_node, nil, nodes)
    end
    return ok and result or luasnip.snippet_node(nil, { luasnip.text_node(M.cmd_head_char .. cmd) })
end

function M.setup()
    if M.initialized then return end

    local cmd_snip = luasnip.snippet(
        {
            trig = M.cmd_head_char .. "(.+)" .. M.cmd_tail_char,
            regTrig = true,
        },
        luasnip.dynamic_node(1, command_snip_func)
    )
    luasnip.add_snippets("all", { cmd_snip }, { type = "autosnippets" })

    cmp_source.init(M.cmd_head_char)
    cmp_source.set_cmd_map(cmd_map)

    M.initialized = true
end

return M
