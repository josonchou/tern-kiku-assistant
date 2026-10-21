local tern = require("tern")

local M = {}
local store = tern.plugin.data .. "/tools"
local commandPrefix = "KIKU_TOOL_V1:"

local function validToken(token)
    return type(token) == "string" and #token == 32 and token:match("^[0-9a-f]+$") ~= nil
end

local function path(token)
    assert(validToken(token), "无效工具记录标记")
    return store .. "/" .. token .. ".json"
end

function M.newToken(callback)
    tern.process.run({ "/usr/bin/od", "-An", "-N16", "-tx1", "/dev/urandom" },
        { timeout_ms = 3000 }, function(result, cx)
            if not cx then return end
            if result.status ~= 0 or result.timed_out then
                callback(nil, "无法读取本机随机源，未创建无法验证身份的终端。", cx)
                return
            end
            local token = result.stdout:gsub("%s", "")
            if #token ~= 32 or token:find("[^0-9a-fA-F]") then
                callback(nil, "本机随机源返回了无效标记，未创建终端。", cx)
                return
            end
            callback(token:lower(), nil, cx)
        end)
end

function M.command(token)
    return "/bin/sh -c 'printf \"" .. commandPrefix .. token .. ":%s\\n\" \"$PPID\"'"
end

function M.marker(cx, paneId, token)
    local pane = cx.session:pane(paneId)
    if not pane or pane.kind ~= "terminal" then return nil end
    local read = cx.session:read(paneId, { lines = 2000, max_chars = 64000 })
    local prefix = commandPrefix .. token .. ":"
    local pid
    if type(read) == "table" and read.lines then
        for _, line in ipairs(read.lines) do
            local value = line:match(prefix .. "([0-9]+)")
            if value then pid = tonumber(value); break end
        end
    end
    if not pid then
        local info = type(read) == "table" and read.info and read.info.last
        local line = type(info) == "table" and info.line or ""
        pid = tonumber(line:match(prefix .. "(%d+)"))
    end
    if not pid then return nil end
    return { pane = pane, pid = pid }
end

function M.save(record)
    local ok, err = pcall(function()
        tern.fs.mkdir(store)
        tern.fs.write(path(record.token), tern.json.encode(record))
    end)
    return ok, not ok and tostring(err) or nil
end

function M.records()
    local presentOk, present = pcall(tern.fs.exists, store)
    if not presentOk then return { { unreadable = true } } end
    if not present then return {} end
    local ok, names = pcall(tern.fs.list, store)
    if not ok then return { { unreadable = true } } end
    local records = {}
    for _, name in ipairs(names) do
        if name:match("^[0-9a-f]+%.json$") then
            local loaded, record = pcall(function()
                return tern.json.decode(tern.fs.read(store .. "/" .. name, 16384))
            end)
            if loaded and type(record) == "table" and validToken(record.token)
                and name == record.token .. ".json" and type(record.cwd) == "string"
                and type(record.pane) == "number" and type(record.host) == "number"
                and type(record.session) == "number"
                and (record.source == nil or type(record.source) == "number") then
                table.insert(records, record)
            else
                table.insert(records, { unreadable = true })
            end
        end
    end
    return records
end

local function freshSample(cx, pane, sample, remaining, callback)
    cx.procs:list({ limit = 1 }):next(function(list, err, nextCx)
        if not nextCx then return end
        if err or not list or not list.sample then
            callback(nil, nextCx)
            return
        end
        if list.sample ~= sample then
            callback(list, nextCx)
            return
        end
        if remaining == 0 then
            callback(nil, nextCx)
            return
        end
        nextCx.session:settle(pane, 100):next(function(_, settleError, settleCx)
            if not settleCx or settleError then
                callback(nil, settleCx)
                return
            end
            freshSample(settleCx, pane, sample, remaining - 1, callback)
        end)
    end)
end

local function processInChildren(cx, pane, parent, pid, started, parentStarted, sample, callback)
    cx.procs:children(parent):next(function(list, err, nextCx)
        if not nextCx then return end
        if err or not list or list.sample == sample
            or list["local"] ~= true or type(list.more) ~= "number" or list.more > 0
            or type(list.processes) ~= "table" then
            callback(false, nextCx)
            return
        end
        local child
        for _, proc in ipairs(list.processes) do
            if proc.pid == pid then child = proc; break end
        end
        if not child or child.started ~= started or child.parent ~= parent then
            callback(false, nextCx)
            return
        end
        nextCx.procs:find(parent):next(function(parentProc, parentError, finalCx)
            if not finalCx then return end
            callback(not parentError and parentProc ~= nil
                and parentProc.started == parentStarted, finalCx)
        end)
    end)
end

function M.verifyProcess(cx, record, pane, callback)
    if not record.pid or not record.started or not record.parent or not record.parentStarted then
        callback(false, cx)
        return
    end
    cx.procs:list({ limit = 1 }):next(function(initial, err, nextCx)
        if not nextCx then return end
        if err or not initial then callback(false, nextCx); return end
        freshSample(nextCx, pane, initial.sample, 200, function(sampled, sampledCx)
            if not sampledCx then return end
            if not sampled then callback(false, sampledCx); return end
            processInChildren(
                sampledCx, pane, record.parent, record.pid, record.started,
                record.parentStarted, initial.sample, callback
            )
        end)
    end)
end

function M.rememberProcess(cx, record, pid, pane, callback)
    cx.procs:list({ limit = 1 }):next(function(initial, err, nextCx)
        if not nextCx then return end
        if err or not initial then callback(false, nextCx); return end
        freshSample(nextCx, pane, initial.sample, 1, function(sampled, sampledCx)
            if not sampledCx then return end
            if not sampled then callback(false, sampledCx); return end
            sampledCx.procs:find(pid):next(function(proc, procError, procCx)
                if not procCx then return end
                if procError or not proc or not proc.parent or not proc.started then
                    callback(false, procCx)
                    return
                end
                procCx.procs:find(proc.parent):next(function(parent, parentError, parentCx)
                    if not parentCx then return end
                    if parentError or not parent then
                        callback(false, parentCx)
                        return
                    end
                    processInChildren(
                        parentCx, pane, proc.parent, proc.pid, proc.started,
                        parent.started, initial.sample, function(childVerified, childrenCx)
                            if not childrenCx then return end
                            if not childVerified then callback(false, childrenCx); return end
                            record.pid, record.started = proc.pid, proc.started
                            record.parent, record.parentStarted = parent.pid, parent.started
                            callback(true, childrenCx)
                        end
                    )
                end)
        end)
    end)
    end)
end


function M.remove(token)
    pcall(tern.fs.remove, path(token))
end

return M
