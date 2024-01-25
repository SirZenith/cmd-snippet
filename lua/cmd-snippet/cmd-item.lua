local luasnip = require "luasnip"
local ast_parser = require "luasnip.util.parser.ast_parser"
local parse = require "luasnip.util.parser.neovim_parser".parse
local Str = require "luasnip.util.str"

---@alias ArgType
---| "number"
---| "string"
---| "boolean"
---| "nil"
---| "table"
---| "function"
---| "thread"
---| "userdata"

---@class SnippetNode # node for LuaSnip
---@alias SnippetNodeInfoTable (string | number | Node)[]

---@class ArgItem
---@field [1] string # argument name
---@field type? ArgType
---@field is_varg? boolean
---@field is_optional? boolean

---@alias SnipParsable string | (string | SnippetNodeInfoTable)[]

---@class CmdItem
---@field args? string[] | ArgItem[]
---@field content SnipParsable | fun(...: string): SnipParsable | nil
local CmdItem = {}
CmdItem.__index = CmdItem

---@param obj table
---@return boolean
function CmdItem:is_instance(obj)
    return getmetatable(obj) == self
end

---@param opt table<string, any>
---@return CmdItem
function CmdItem:new(opt)
    local obj = {}
    for k, v in pairs(opt) do
        obj[k] = v
    end

    setmetatable(obj, CmdItem)

    return obj
end

-- ----------------------------------------------------------------------------

---@param body string
---@return string? err
---@return SnippetNode[]
function CmdItem.parse_string(body)
    if body == "" then
        return "empty body", {}
    end

    local opts = {}
    if opts.dedent == nil then
        opts.dedent = true
    end
    if opts.trim_empty == nil then
        opts.trim_empty = true
    end

    body = Str.sanitize(body)

    local lines = vim.split(body, "\n")
    Str.process_multiline(lines, opts)
    body = table.concat(lines, "\n")

    local ast = parse(body)

    local nodes = ast_parser.to_luasnip_nodes(ast, {
        var_functions = opts.variables,
    })

    return nil, nodes
end

---@param tbl SnippetNodeInfoTable
---@param index_set table<number, true>
---@return SnippetNode[]
function CmdItem.parse_line_element_table(tbl, index_set)
    local nodes = {}

    for i = 1, #tbl do
        local element = tbl[i]
        if type(element) == "string" then
            table.insert(nodes, luasnip.text_node(element))
        elseif type(element) == "number" then
            local new_node
            if not index_set[element] then
                new_node = luasnip.insert_node(element)
            else
                new_node = luasnip.function_node(function(args) return args[1][1] end, { element })
            end

            table.insert(nodes, new_node)
            index_set[element] = true
        elseif type(element) == "table" then
            table.insert(nodes, element)
        end
    end

    return nodes
end

---@param tbl (string | SnippetNodeInfoTable)[]
---@return string? err
---@return SnippetNode[]
function CmdItem.parse_table(tbl)
    local nodes = {}
    local index_set = {}
    local err

    local len = #tbl
    for i = 1, len do
        local line = tbl[i]
        if type(line) == "string" then
            table.insert(nodes, luasnip.text_node(line))
        elseif type(line) == "table" then
            vim.list_extend(nodes, CmdItem.parse_line_element_table(line, index_set))
        end

        if i < len then
            table.insert(nodes, luasnip.text_node({ "", "" }))
        end
    end

    err = err or CmdItem.check_index_continuity(index_set)

    return err, nodes
end

---@param index_set table<number, true>
---@return string? err
function CmdItem.check_index_continuity(index_set)
    local index_cnt = 0
    for _ in pairs(index_set) do
        index_cnt = index_cnt + 1
    end

    local err_index
    for i = 1, index_cnt do
        if not index_set[i] then
            err_index = i
            break
        end
    end

    if err_index then
        return "jump index is no continuous at #" .. tostring(err_index)
    end

    return nil
end

-- ----------------------------------------------------------------------------

---@param args string[]
---@return string | nil err
function CmdItem:check_args(args)
    if not self.args then return nil end

    local len = #self.args
    local last_item = self.args[len]
    local has_varg = last_item and last_item.is_varg
    if not has_varg and #args > len then
        return ("mismatch argument count: want %d got %d"):format(len, #args)
    end

    for i, item in ipairs(self.args) do
        local arg = args[i]
        if not arg and not item.is_optional then
            return ("argument is missing at %d: %q"):format(
                i, tostring(item[1])
            )
        elseif item.type and type(arg) ~= item.type then
            return ("type mismatch at #%d: expected %q got %q"):format(
                i, item.type, type(arg)
            )
        end
    end

    return nil
end

---@return number
function CmdItem:get_required_arg_cnt()
    local cnt = 0
    if not self.args then return cnt end

    for _, item in ipairs(self.args) do
        if not item.is_optional then
            cnt = cnt + 1
        end
    end

    return cnt
end

---@return string[]
function CmdItem:get_arg_names()
    local names = {}
    if not self.args then return names end

    for i, item in ipairs(self.args) do
        local name = item
        if type(item) == "table" then
            name = item[1] or ("arg" .. tostring(i))
        end
        table.insert(names, name)
    end

    return names
end

---@return SnippetNode[]
function CmdItem:gen_signature_snip()
    local nodes = {}
    for i, item in ipairs(self.args) do
        if i > 1 then
            table.insert(nodes, luasnip.text_node(" "))
        end

        local item_t = type(item)
        local arg_name = "arg" .. tostring(i)
        if item_t == "string" then
            arg_name = item
        elseif item_t == "table" then
            arg_name = item_t[1] or arg_name
        end

        table.insert(nodes, luasnip.insert_node(i, arg_name))
    end
    return nodes
end

---@param args string[]
---@return string? err
---@return SnippetNode[]?
function CmdItem:make_snippet(args)
    local err

    local content = self.content
    if type(content) == "function" then
        content, err = content(unpack(args))
    end

    local nodes

    if type(content) == "string" then
        err, nodes = CmdItem.parse_string(content)
    elseif type(content) == "table" and #content ~= 0 then
        err, nodes = CmdItem.parse_table(content)
    end

    return err, nodes
end

return CmdItem
