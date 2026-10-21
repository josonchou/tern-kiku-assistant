local tern = require("tern")
local M = {}

function M.read()
    local config = {
        defaultPath = "", keybinding = "", manageKeybinding = "",
        lazygitKeybinding = "ctrl+b>alt+g", terminalKeybinding = "ctrl+b>t",
        hideToolKeybinding = "ctrl+b>q", endToolKeybinding = "ctrl+b>shift+q",
        executables = { git = "", lazygit = "", realpath = "" },
    }
    local ok, err = pcall(function()
        local path = tern.plugin.dir .. "/config.json"
        if not tern.fs.exists(path) then return end
        local value = tern.json.decode(tern.fs.read(path, 65536))
        assert(type(value) == "table" and value ~= tern.json.null, "config.json 必须是 JSON 对象")
        for key, item in pairs(value) do
            assert(config[key] ~= nil, "未知配置项：" .. tostring(key))
            if key == "executables" then
                assert(type(item) == "table" and item ~= tern.json.null, "executables 必须是 JSON 对象")
                for name, executable in pairs(item) do
                    assert(config.executables[name] ~= nil, "未知配置项：executables." .. tostring(name))
                    assert(type(executable) == "string", "executables." .. name .. " 必须是字符串")
                    assert(not executable:find("\0", 1, true), "executables." .. name .. " 不得包含 NUL")
                    config.executables[name] = executable
                end
            else
                assert(type(item) == "string", key .. " 必须是字符串")
                config[key] = item
            end
        end
    end)
    return config, not ok and tostring(err) or nil
end

return M
