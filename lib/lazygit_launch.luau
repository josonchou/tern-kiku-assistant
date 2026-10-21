local tern = require("tern")

local M = {}

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.prepare(cx, token, gitPath, callback)
    local directory = "/tmp/tern-kiku-git-" .. token
    tern.process.run({ "/bin/mkdir", "-m", "700", "--", directory },
        { timeout_ms = 3000 }, function(mkdirResult, mkdirCx)
            if not mkdirCx then return end
            if mkdirResult.status ~= 0 or mkdirResult.timed_out then
                callback(nil, "无法原子创建私有 Git bridge 目录；未创建浮窗。", mkdirCx)
                return
            end
            tern.process.run({ "/bin/ln", "-s", "--", gitPath, directory .. "/git" },
                { timeout_ms = 3000 }, function(linkResult, linkCx)
                    if not linkCx then return end
                    if linkResult.status ~= 0 or linkResult.timed_out then
                        tern.process.run({ "/bin/rmdir", "--", directory },
                            { timeout_ms = 3000 }, function() end)
                        callback(nil, "无法创建指向已解析 Git 的私有 bridge；未创建浮窗。", linkCx)
                        return
                    end
                    callback(directory, nil, linkCx)
                end)
            end)
end

function M.cleanup(directory)
    if type(directory) ~= "string"
        or not directory:match("^/tmp/tern%-kiku%-git%-[0-9a-f]+$") then return end
    tern.process.run({ "/bin/rm", "--", directory .. "/git" }, { timeout_ms = 3000 },
        function(result, cx)
            if not cx or result.status ~= 0 then return end
            tern.process.run({ "/bin/rmdir", "--", directory }, { timeout_ms = 3000 }, function() end)
        end)
end

function M.command(directory, lazygitPath, originalPath)
    local path = directory
    if originalPath and originalPath ~= "" then path ..= ":" .. originalPath end
    return "exec /usr/bin/env PATH=" .. quote(path) .. " " .. quote(lazygitPath)
end

return M
