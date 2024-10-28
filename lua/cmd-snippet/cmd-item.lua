local luasnip = require "luasnip"
local ast_parser = require "luasnip.util.parser.ast_parser"
local parse = require "luasnip.util.parser.neovim_parser".parse
local Str = require "luasnip.util.str"

---@alias cmd-snippet.ArgType
---| "number"
---| "string"
---| "boolean"

---@class cmd-snippet.ArgItem
---@field [1] string # argument name
---@field type? cmd-snippet.ArgType
---@field is_varg? boolean
---@field is_optional? boolean

---@class cmd-snippet.SnippetNode # LuaSnip node

---@alias cmd-snippet.SnippetNodeInfoTable (string | number | Node)[]

---@alias cmd-snippet.SnipParsable string | (string | cmd-snippet.SnippetNodeInfoTable)[]

-- ----------------------------------------------------------------------------

-- Check if indexes in given index set distribute continuously start from 1.
---@param index_set table<number, true>
---@return string? err
local function check_index_continuity(index_set)
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

---@class cmd-snippet.CmdItemTable
---@field args? (string| cmd-snippet.ArgItem)[]
---@field content cmd-snippet.SnipParsable | fun(...: string): cmd-snippet.SnipParsable | nil

---@class cmd-snippet.CmdItem : cmd-snippet.CmdItemTable
local CmdItem = {}
CmdItem.__index = CmdItem

-- Check given value is an instance of CmdItem or not.
---@param obj any
---@return boolean
function CmdItem:is_instance(obj)
    return getmetatable(obj) == self
end

---@param opt cmd-snippet.CmdItemTable
---@return cmd-snippet.CmdItem
function CmdItem:new(opt)
    local obj = {}
    for k, v in pairs(opt) do
        obj[k] = v
    end

    setmetatable(obj, self)

    return obj
end

-- ----------------------------------------------------------------------------

-- Generate snippet node with plain text content.
---@param body string
---@return string? err
---@return cmd-snippet.SnippetNode[]
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

-- Parsing a single line of content table.
---@param tbl cmd-snippet.SnippetNodeInfoTable
---@param index_set table<number, true>
---@return cmd-snippet.SnippetNode[]
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

-- Generate snippet node by parsing content table.
---@param tbl (string | cmd-snippet.SnippetNodeInfoTable)[]
---@return string? err
---@return cmd-snippet.SnippetNode[]
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

    err = err or check_index_continuity(index_set)

    return err, nodes
end

-- ----------------------------------------------------------------------------

---@param value string
---@param target_type cmd-snippet.ArgType
---@return boolean
local function arg_type_check(value, target_type)
    if target_type == "number" then
        return tonumber(value) and true or false
    elseif target_type == "boolean" then
        local str = value:lower()
        return str == "true" or str == "false"
    end
    return true
end

-- Check if given argument list is valid for current command
---@param args string[]
---@return string? err
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

        if type(item) == "string" then
            -- string args are required by default
            if not arg then
                return ("argument is missing at %d: %q"):format(
                    i, tostring(item[1])
                )
            end
        elseif not arg and not item.is_optional then
            return ("argument is missing at %d: %q"):format(
                i, tostring(item[1])
            )
        elseif not arg_type_check(arg, item.type or "string") then
            return ("type mismatch at #%d: expected %q"):format(i, item.type)
        end
    end

    return nil
end

-- Get number of required arguments in current command.
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

---@param index integer
---@param item string | cmd-snippet.ArgItem
local function get_arg_item_name(index, item)
    local name = item
    if type(item) == "table" then
        name = item[1] or ("arg" .. tostring(index))
    end
    return name
end

-- Get a list of all argument's name in current command.
---@return string[]
function CmdItem:get_arg_names()
    local names = {}
    if not self.args then return names end

    for i, item in ipairs(self.args) do
        local name = get_arg_item_name(i, item)
        table.insert(names, name)
    end

    return names
end

-- Generate a place holder snippet by putting argument's name at each argument
-- position.
---@return cmd-snippet.SnippetNode[]
function CmdItem:gen_signature_snip()
    local nodes = {}
    for i, item in ipairs(self.args) do
        if i > 1 then
            table.insert(nodes, luasnip.text_node(" "))
        end

        local arg_name = get_arg_item_name(i, item)
        table.insert(nodes, luasnip.insert_node(i, arg_name))
    end
    return nodes
end

-- Generate snippet node defined in current command with given arguments.
---@param args string[]
---@return string? err
---@return cmd-snippet.SnippetNode[]?
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
