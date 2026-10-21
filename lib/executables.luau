local tern = require("tern")
local M = {}
local function pathEnv(cx)
    return cx.getenv("PATH") or ""
end
local function probe(name, cx, path, env, callback)
    local args = name == "realpath" and { path, "/" } or { path, "--version" }
    local ok = pcall(function()
        tern.process.run(args, { timeout_ms = 2000, env = { PATH = env } }, function(result, nextCx)
            callback(nextCx ~= nil and result.status == 0, nextCx)
        end)
    end)
    if not ok then callback(false, cx) end
end
local function fromPath(name, cx, env, callback)
    local index, paths = 1, {}
    for directory in (env .. ":"):gmatch("(.-):") do
        if directory == "" then directory = "." end
        local candidate = directory .. "/" .. name
        if candidate:sub(1, 1) ~= "/" then
            candidate = tern.plugin.dir .. "/" .. candidate
        end
        if tern.fs.exists(candidate) then table.insert(paths, candidate) end
    end
    local function tryNext(nextCx)
        local candidate = paths[index]
        if not candidate then callback(nil, nextCx); return end
        index += 1
        probe(name, nextCx, candidate, env, function(valid, checkedCx)
            if valid then callback(candidate, checkedCx or nextCx)
            else tryNext(checkedCx or nextCx) end
        end)
    end
    tryNext(cx)
end
function M.new(paths)
    local self = { configured = paths, state = {}, env = "" }
    function self:ready(name)
        return self.state[name] ~= false
    end
    function self:check(cx, names, callback)
        local env = pathEnv(cx)
        local result = { paths = {}, pathEnv = env, fallbacks = {}, errors = {} }
        local index = 1
        local function nextTool(nextCx)
            local name = names[index]
            if not name then
                local missing = {}
                for _, checkedName in ipairs(names) do
                    self.state[checkedName] = result.paths[checkedName] ~= nil
                    if not result.paths[checkedName] then
                        table.insert(missing, checkedName .. "（executables." .. checkedName .. " 与本机 PATH 均不可用）")
                    end
                end
                callback(nextCx, result, #missing > 0 and table.concat(missing, "；") or nil)
                return
            end
            index += 1
            local explicit = self.configured[name]
            if explicit ~= "" and explicit:sub(1, 1) ~= "/" then
                explicit = tern.plugin.dir .. "/" .. explicit
            end
            local function fallback(fallbackCx, reason)
                fromPath(name, fallbackCx, env, function(path, resolvedCx)
                    if path then
                        result.paths[name] = path
                        result.fallbacks[name] = { path = path, reason = reason }
                    else
                        result.errors[name] = reason .. "；本机 PATH 中也未找到可执行文件"
                    end
                    nextTool(resolvedCx or fallbackCx)
                end)
            end
            if explicit ~= "" then
                if explicit:sub(1, 1) == "/" and tern.fs.exists(explicit) then
                    probe(name, nextCx, explicit, env, function(valid, checkedCx)
                        if valid then result.paths[name] = explicit; nextTool(checkedCx or nextCx)
                        else fallback(checkedCx or nextCx, "显式路径不存在或不可执行：" .. explicit) end
                    end)
                else
                    fallback(nextCx, "显式路径不存在或不可执行：" .. explicit)
                end
            else fallback(nextCx, "未配置可用路径") end
        end
        nextTool(cx)
    end
    function self:refresh(cx)
        local names = { "git", "realpath", "lazygit" }
        self:check(cx, names, function(_, result)
            self.env = result.pathEnv
            for _, name in ipairs(names) do self.state[name] = result.paths[name] ~= nil end
        end)
    end
    return self
end
return M
