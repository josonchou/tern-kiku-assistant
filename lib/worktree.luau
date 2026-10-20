-- Pure Git-output and path helpers. No shell, filesystem or window state.
local M = {}

function M.chomp(value)
    return (value:gsub("\r?\n$", ""))
end

function M.branchName(value)
    -- Lazygit SanitizedBranchName preserves '/' and only changes ASCII spaces.
    return (value:gsub(" ", "-"))
end

function M.absolute(path, base, home)
    if path == "" or path:find("[%z\r\n]") then
        return nil, "目录不能为空或包含换行符。"
    end
    if path == "~" or path:sub(1, 2) == "~/" then
        if not home or home == "" then
            return nil, "无法确定 HOME，请输入绝对路径。"
        end
        path = home .. path:sub(2)
    elseif path:sub(1, 1) == "~" then
        return nil, "仅支持 ~ 或 ~/，请使用绝对路径。"
    end
    if path:sub(1, 1) ~= "/" then
        path = base .. "/" .. path
    end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    return "/" .. table.concat(parts, "/")
end

function M.parent(path)
    local parent = path:match("^(.*)/[^/]+$")
    return parent and parent ~= "" and parent or "/"
end

function M.worktrees(output)
    local rows, row = {}, nil
    -- --porcelain -z preserves spaces, quotes, tabs, newlines and Unicode in paths.
    for field in output:gmatch("([^%z]*)%z") do
        if field:sub(1, 9) == "worktree " then
            row = { path = field:sub(10) }
            table.insert(rows, row)
        elseif row then
            if field:sub(1, 7) == "branch " then
                row.branch = field:sub(8)
            elseif field == "bare" then
                row.bare = true
            elseif field == "detached" then
                row.detached = true
            end
        end
    end
    return rows
end

function M.branches(output)
    local rows = {}
    for ref, symbolic in output:gmatch("([^%z\n]+)%z([^%z]*)%z\n") do
        if symbolic == "" then
            if ref:sub(1, 11) == "refs/heads/" then
                table.insert(rows, { name = ref:sub(12), ref = ref, remote = false })
            elseif ref:sub(1, 13) == "refs/remotes/" then
                local name = ref:sub(14)
                table.insert(rows, {
                    name = name, ref = ref, remote = true,
                    localName = name:match("^[^/]+/(.+)$"),
                })
            end
        end
    end
    return rows
end

function M.occupied(worktrees)
    local result = {}
    for _, row in ipairs(worktrees) do
        if row.branch then result[row.branch] = row.path end
    end
    return result
end

function M.targets(worktrees, currentRoot, defaultPath, dirName, home)
    local mainRoot = worktrees[1] and worktrees[1].path or currentRoot
    local parents, seen = {}, {}
    local function add(path)
        if not seen[path] then
            seen[path] = true
            table.insert(parents, path)
        end
    end
    -- Lazygit's model shows the current tree first, including linked trees.
    for i, row in ipairs(worktrees) do
        if i > 1 and row.path == currentRoot then add(M.parent(row.path)) end
    end
    for i, row in ipairs(worktrees) do
        if i > 1 then add(M.parent(row.path)) end
    end
    if defaultPath ~= "" then
        local path, err = M.absolute(defaultPath, mainRoot, home)
        if not path then return nil, err end
        add(path)
    end
    if #parents == 0 then add(M.parent(mainRoot)) end
    local result = {}
    for _, parent in ipairs(parents) do
        local path, err = M.absolute(dirName, parent, home)
        if not path then return nil, err end
        table.insert(result, path)
    end
    return result
end

function M.addArgs(flow)
    local args = { "worktree", "add" }
    if flow.mode == "new" then
        table.insert(args, "-b")
        table.insert(args, flow.name)
    elseif flow.mode == "remote" then
        table.insert(args, "--track")
        table.insert(args, "-b")
        table.insert(args, flow.name)
    elseif flow.mode == "detached" then
        table.insert(args, "--detach")
    end
    table.insert(args, "--")
    table.insert(args, flow.path)
    table.insert(args, flow.base)
    return args
end

return M
