local tern = require("tern")

local M = {}
local store = tern.plugin.data .. "/tools"
local launchRoot = tern.plugin.data .. "/tool-start"

local function validToken(token)
    return type(token) == "string" and #token == 32 and token:match("^[0-9a-f]+$") ~= nil
end

local function path(token)
    assert(validToken(token), "无效工具记录标记")
    return store .. "/" .. token .. ".json"
end

local function launchPath(token)
    assert(validToken(token), "无效工具启动标记")
    return launchRoot .. "/" .. token
end

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function readText(file, limit)
    local ok, value = pcall(tern.fs.read, file, limit)
    if not ok or type(value) ~= "string" then return nil end
    return value
end

function M.launch(token, cwd)
    if not validToken(token) or type(cwd) ~= "string" or cwd:sub(1, 1) ~= "/" or cwd:find("%z") then
        return nil, "无法确认工具启动目录或标记。"
    end
    local directory = launchPath(token)
    local ok, err = pcall(function()
        if tern.fs.exists(directory) then error("工具启动标记已存在。") end
        tern.fs.mkdir(directory)
        tern.fs.write(directory .. "/request.json", tern.json.encode({ version = 1, token = token, cwd = cwd }))
    end)
    if not ok then return nil, tostring(err) end
    return directory
end

-- The private cwd identifies this launch without changing its native terminal kind.
-- The final exec keeps the original shell's PID, arguments and integration environment.
function M.spawn(spec)
    local prefix = launchRoot .. "/"
    if type(spec.cwd) ~= "string" or spec.cwd:sub(1, #prefix) ~= prefix then return nil end
    local token = spec.cwd:sub(#prefix + 1)
    if not validToken(token) then return nil end
    local ok, request = pcall(function()
        return tern.json.decode(tern.fs.read(spec.cwd .. "/request.json", 4096))
    end)
    if not ok or type(request) ~= "table" or request.version ~= 1 or request.token ~= token
        or type(request.cwd) ~= "string" or request.cwd:sub(1, 1) ~= "/" or request.cwd:find("%z") then
        return nil
    end
    if type(spec.program) ~= "string" or type(spec.args) ~= "table" then return nil end
    local shell = spec.program:match("([^/]+)$")
    local initialArgs
    if shell == "zsh" then
        initialArgs = { "-f", "-c" }
    elseif shell == "fish" then
        initialArgs = { "--no-config", "-c" }
    elseif shell == "bash" or shell == "sh" or shell == "dash" or shell == "ksh" then
        initialArgs = { "-c" }
    else
        pcall(tern.fs.write, spec.cwd .. "/error",
            "当前默认 shell 不支持安全的静默工具启动，请交由 Tern 原生打开终端。")
        spec.program, spec.args, spec.cwd = "/bin/sh", { "-c", "exit 125" }, request.cwd
        return spec
    end
    -- $$ is the shell that runs this bootstrap and every exec keeps that PID,
    -- so the recorded process is the final shell. noclobber keeps the first
    -- generation's PID after a native Restart instead of claiming the new one.
    local bootstrap = 'pid=$1; shift; (umask 077; set -C; printf "%s\\n" "$$" > "$pid") 2>/dev/null || :; '
        .. 'case "${1##*/}" in bash) if [ -n "${KITTY_BASH_INJECT-}" ] && [ -n "${ENV-}" ]; then '
        .. 'shell=$1; shift; exec "$shell" --posix "$@"; fi;; esac; exec "$@"'
    local command = "exec /bin/sh -c " .. quote(bootstrap) .. " kiku-bootstrap "
        .. quote(spec.cwd .. "/pid") .. " " .. quote(spec.program)
    for _, arg in ipairs(spec.args) do
        if type(arg) ~= "string" then return nil end
        command ..= " " .. quote(arg)
    end
    table.insert(initialArgs, command)
    spec.args, spec.cwd = initialArgs, request.cwd
    return spec
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

function M.marker(cx, paneId, token)
    local pane = cx.session:pane(paneId)
    if not pane or pane.kind ~= "terminal" then return nil end
    local directory = launchPath(token)
    local reason = readText(directory .. "/error", 4096)
    if reason and reason ~= "" then return nil, reason end
    local text = readText(directory .. "/pid", 64)
    if not text then return nil end
    local pid = tonumber(text:match("^(%d+)\n?$"))
    if not pid or pid < 1 then return nil end
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
                and (record.source == nil or type(record.source) == "number")
                and (record.originTab == nil or type(record.originTab) == "number")
                and (record.kind == nil or record.kind == "terminal" or record.kind == "lazygit") then
                table.insert(records, record)
            else
                table.insert(records, { unreadable = true })
            end
        end
    end
    return records
end

-- A window call has a 50 ms budget, so waiting for a newer process sample must
-- never be one long await: settle() only returns at its deadline while a tool
-- runs a full-screen program such as lazygit. Poll in short slices instead,
-- each far below the budget, and stop as soon as the pane is gone.
local SAMPLE_POLL_MS = 10

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
        if remaining == 0 or not nextCx.session:pane(pane) then
            callback(nil, nextCx)
            return
        end
        nextCx.session:settle(pane, SAMPLE_POLL_MS):next(function(_, settleError, settleCx)
            if not settleCx or settleError then
                callback(nil, settleCx)
                return
            end
            freshSample(settleCx, pane, sample, remaining - 1, callback)
        end)
    end)
end

local function processInChildren(cx, pane, parent, pid, started, parentStarted, sample, callback)
    -- Check the parent first: no asynchronous parent lookup may outlive the
    -- final child-generation check used to authorize a layout or close.
    cx.procs:find(parent):next(function(parentProc, parentError, parentCx)
        if not parentCx then return end
        if parentError or not parentProc or parentProc.started ~= parentStarted then
            callback(false, parentCx)
            return
        end
        parentCx.procs:children(parent):next(function(list, err, finalCx)
            if not finalCx then return end
            if err or not list or list.sample == sample
                or list["local"] ~= true or type(list.more) ~= "number" or list.more > 0
                or type(list.processes) ~= "table" then
                callback(false, finalCx)
                return
            end
            local child
            for _, proc in ipairs(list.processes) do
                if proc.pid == pid then child = proc; break end
            end
            callback(child ~= nil and child.started == started and child.parent == parent, finalCx)
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

function M.verifyTogether(cx, first, second, pane, callback)
    local records = { first, second }
    for _, record in ipairs(records) do
        if not record.pid or not record.started or not record.parent or not record.parentStarted then
            callback(false, cx)
            return
        end
    end
    local wanted = {
        [first.pid] = true, [first.parent] = true,
        [second.pid] = true, [second.parent] = true,
    }
    cx.procs:list({ limit = 1 }):next(function(initial, err, nextCx)
        if not nextCx then return end
        if err or not initial or type(initial.sample) ~= "number" then callback(false, nextCx); return end
        freshSample(nextCx, pane, initial.sample, 200, function(sampled, sampledCx)
            if not sampledCx then return end
            if not sampled then callback(false, sampledCx); return end
            -- Source and target must be authorized by one final snapshot, not
            -- two asynchronous checks that can invalidate each other.
            sampledCx.procs:list({ limit = 4096 }):next(function(list, listError, finalCx)
                if not finalCx then return end
                if listError or not list or type(list.sample) ~= "number" or list.sample == initial.sample
                    or list["local"] ~= true or list.more ~= 0 or type(list.processes) ~= "table" then
                    callback(false, finalCx)
                    return
                end
                local observed = {}
                for _, process in ipairs(list.processes) do
                    if wanted[process.pid] then observed[process.pid] = process end
                end
                for _, record in ipairs(records) do
                    local child, parent = observed[record.pid], observed[record.parent]
                    if not child or not parent or child.started ~= record.started
                        or child.parent ~= record.parent or parent.started ~= record.parentStarted then
                        callback(false, finalCx)
                        return
                    end
                end
                callback(true, finalCx)
            end)
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
    if validToken(token) then pcall(tern.fs.remove, launchPath(token)) end
end

return M
