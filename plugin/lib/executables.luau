local tern = require("tern")

local M = {}

local LOGIN_MARKER = "KIKU_LOGIN_PATH:"

local function probe(name, cx, path, env, callback)
    local args = name == "realpath" and { path, "/" } or { path, "--version" }
    local ok = pcall(function()
        tern.process.run(args, { timeout_ms = 2000, env = { PATH = env } }, function(result, nextCx)
            if nextCx then callback(result.status == 0, nextCx) end
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
    local self = { configured = paths, state = {}, env = "", loginEnv = nil, loginTried = false }

    function self:ready(name)
        return self.state[name] == true
    end

    -- A daemon or GUI launch often inherits a minimal PATH, so a program the
    -- user's shell resolves (for example a Homebrew install) looks missing.
    -- The login shell is the only reliable source of the user's own PATH.
    local function loginPath(cx, callback)
        if self.loginTried then callback(self.loginEnv, cx); return end
        self.loginTried = true
        local shell = tern.getenv("SHELL") or ""
        if shell:sub(1, 1) ~= "/" or not tern.fs.exists(shell) then
            shell = tern.runtime.os == "macos" and "/bin/zsh" or "/bin/sh"
        end
        local command = 'printf "' .. LOGIN_MARKER .. '%s\\n" "$PATH"'
        local ok = pcall(function()
            tern.process.run({ shell, "-l", "-c", command }, { timeout_ms = 3000 },
                function(result, nextCx)
                    if result and not result.timed_out and result.status == 0 then
                        for line in (result.stdout or ""):gmatch("[^\r\n]+") do
                            local found = line:match("^" .. LOGIN_MARKER .. "(.+)$")
                            if found then self.loginEnv = found end
                        end
                    end
                    if self.loginEnv and (self.loginEnv:find("%z") or self.loginEnv:sub(1, 1) ~= "/") then
                        self.loginEnv = nil
                    end
                    callback(self.loginEnv, nextCx)
                end)
        end)
        if not ok then callback(nil, cx) end
    end

    -- Resolves `names` with one PATH. Explicit configured paths still win and
    -- still fall back to that PATH when the configured file is unusable.
    local function resolve(cx, names, env, result, callback)
        local index = 1
        local function nextTool(nextCx)
            local name = names[index]
            if not name then callback(nextCx, result); return end
            index += 1
            local explicit = self.configured[name] or ""
            if explicit ~= "" and explicit:sub(1, 1) ~= "/" then
                explicit = tern.plugin.dir .. "/" .. explicit
            end
            local function fallback(fallbackCx, reason)
                fromPath(name, fallbackCx, env, function(path, resolvedCx)
                    if path then
                        result.paths[name] = path
                        if explicit ~= "" then
                            result.fallbacks[name] = { path = path, reason = reason }
                        end
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

    local function finish(cx, names, result, callback)
        local missing = {}
        for _, name in ipairs(names) do
            self.state[name] = result.paths[name] ~= nil
            if not result.paths[name] then
                table.insert(missing, name .. "（executables." .. name .. " 与本机 PATH 均不可用）")
            end
        end
        callback(cx, result, #missing > 0 and table.concat(missing, "；") or nil)
    end

    function self:check(cx, names, callback)
        local env = tern.getenv("PATH") or ""
        local result = { paths = {}, pathEnv = env, fallbacks = {}, errors = {} }
        resolve(cx, names, env, result, function(firstCx, firstResult)
            local missingNames = {}
            for _, name in ipairs(names) do
                if not firstResult.paths[name] then table.insert(missingNames, name) end
            end
            if #missingNames == 0 then
                finish(firstCx, names, firstResult, callback)
                return
            end
            loginPath(firstCx, function(loginEnv, loginCx)
                local nextCx = loginCx or firstCx
                if not loginEnv or loginEnv == env then
                    finish(nextCx, names, firstResult, callback)
                    return
                end
                local retried = { paths = {}, pathEnv = loginEnv, fallbacks = {}, errors = {} }
                resolve(nextCx, missingNames, loginEnv, retried, function(finalCx, secondResult)
                    for name, path in pairs(secondResult.paths) do firstResult.paths[name] = path end
                    for name, entry in pairs(secondResult.fallbacks) do firstResult.fallbacks[name] = entry end
                    for name, message in pairs(secondResult.errors) do firstResult.errors[name] = message end
                    if next(secondResult.paths) ~= nil then
                        -- Keep both roots so programs found earlier still resolve
                        -- the same helpers their explicit directories expect.
                        firstResult.pathEnv = loginEnv .. ":" .. env
                        firstResult.loginPath = loginEnv
                    end
                    finish(finalCx, names, firstResult, callback)
                end)
            end)
        end)
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
