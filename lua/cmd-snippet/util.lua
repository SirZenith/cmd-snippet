local M = {}

---@param segments string[]
function M.filter_empty_str(segments)
    for i = #segments, 1, -1 do
        if segments[i] == "" then
            table.remove(segments, i)
        end
    end
end

return M
