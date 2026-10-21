local tern = require("tern")
local identity = require("./tool_identity")
local lazygitLaunch = require("./lazygit_launch")
local M = {}
local executables
local tools = {}
local byPane = {}
local pending = {}
local sourceFlights = {}
local watcher
local watcherScheduled = false

local function sourceKey(host, session, pane)
    return tostring(host) .. ":" .. tostring(session) .. ":" .. tostring(pane)
end

local function toolKey(ownerKey, kind)
    return ownerKey .. ":" .. kind
end

local function sourcePane(cx, paneId)
    if not paneId then return nil end
    return cx.session:pane(paneId)
end

local function liveTool(cx, tool)
    local pane = cx.session:pane(tool.pane)
    if not pane or pane.kind ~= "terminal" then return nil end
    return pane
end

local function verifyManaged(cx, tool, callback)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local pane = liveTool(cx, tool)
    if session.id ~= tool.session or host.id ~= tool.host or host.kind ~= "local"
        or not pane or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
        or not tool.identityVerified then
        callback(false, cx)
        return
    end
    if pane.exited ~= nil then
        callback(false, cx)
        return
    end
    identity.verifyProcess(cx, tool, tool.pane, function(verified, nextCx)
        if not nextCx then return end
        local currentHost = nextCx.hosts:current()
        local currentSession = nextCx.sessions:current()
        local currentPane = liveTool(nextCx, tool)
        callback(verified and currentSession.id == tool.session
            and currentHost.id == tool.host and currentHost.kind == "local"
            and tools[tool.key] == tool and byPane[tool.pane] == tool
            and currentPane ~= nil and currentPane.exited == nil, nextCx)
    end)
end

local function focusTool(cx, tool, source, done)
    local function complete()
        if done then done() end
    end
    if not liveTool(cx, tool) or not source or not sourcePane(cx, source.pane) then
        cx:toast("error", "来源窗格已关闭", "工具保留；请使用恢复收起的工具。")
        complete()
        return false
    end
    local focused = cx.session:focused()
    local previous = focused and byPane[focused]
    if not previous or previous == tool then
        for _, candidate in pairs(tools) do
            local candidatePane = liveTool(cx, candidate)
            if candidate ~= tool and candidate.sourceKey == tool.sourceKey
                and candidatePane and candidatePane.parked ~= true then
                previous = candidate
                break
            end
        end
    end
    if previous and previous.sourceKey ~= tool.sourceKey then previous = nil end
    if previous == tool then previous = nil end
    local function display(nextCx, expectedFocus)
        local current = liveTool(nextCx, tool)
        if not current or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
            or nextCx.session:focused() ~= expectedFocus
            or not sourcePane(nextCx, source.pane) then
            complete()
            return
        end
        if current.parked then
            local ok, err = nextCx.layout:unpark(tool.pane, { focus = false })
            if not ok then nextCx:toast("error", "无法恢复工具", err); complete(); return end
        end
        local ok, err = nextCx.layout:float(tool.pane, source.pane, "br", { focus = true })
        if not ok then
            nextCx:toast("error", "工具已恢复但浮动失败", tostring(err))
            complete()
            return
        end
        nextCx.layout:focus(tool.pane)
        complete()
    end
    verifyManaged(cx, tool, function(targetVerified, targetCx)
        if not targetCx then complete(); return end
        if not targetVerified then
            targetCx:toast("error", "目标工具身份未确认", "未显示或操作任何窗格。")
            complete()
            return
        end
        if targetCx.session:focused() ~= focused or tools[tool.key] ~= tool
            or byPane[tool.pane] ~= tool then complete(); return end
        if not previous then display(targetCx, focused); return end
        verifyManaged(targetCx, previous, function(previousVerified, previousCx)
            if not previousCx then complete(); return end
            if previousCx.session:focused() ~= focused or tools[tool.key] ~= tool
                or byPane[tool.pane] ~= tool or tools[previous.key] ~= previous
                or byPane[previous.pane] ~= previous then complete(); return end
            if not previousVerified then
                previousCx:toast("error", "当前工具身份未确认", "未切换或收起任何窗格。")
                complete()
                return
            end
            verifyManaged(previousCx, tool, function(stillVerified, finalCx)
                if not finalCx then complete(); return end
                if not stillVerified or finalCx.session:focused() ~= focused
                    or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
                    or tools[previous.key] ~= previous or byPane[previous.pane] ~= previous then
                    finalCx:toast("error", "工具身份已变化", "未收起当前工具。")
                    complete()
                    return
                end
                local ok, err = finalCx.layout:park(previous.pane)
                if not ok then
                    finalCx:toast("error", "无法收起当前工具", err)
                    complete()
                    return
                end
                display(finalCx, source.pane)
            end)
        end)
    end)
    return true
end

local function ownerFor(cx)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local pane = sourcePane(cx, focused)
    if not pane or pane.kind ~= "terminal" or not pane.cwd or pane.cwd == "" then
        return nil, "无法确定本机终端来源及其工作目录。"
    end
    local owner = byPane[focused]
    if owner then
        local source = owner.source and sourcePane(cx, owner.source)
        if not source then return nil, "原来源已关闭；请先恢复收起的工具。" end
        pane = source
        focused = owner.source
    end
    return {
        host = host.id, hostKind = host.kind, session = session.id,
        pane = focused, cwd = pane.cwd,
        key = sourceKey(host.id, session.id, focused),
    }
end

local function persist(tool)
    return identity.save({
        token = tool.token, pane = tool.pane, source = tool.originSource,
        host = tool.host, session = tool.session, cwd = tool.cwd,
        pid = tool.pid, started = tool.started,
        parent = tool.parent, parentStarted = tool.parentStarted,
    })
end



local finishStartup
local function presentTool(cx, tool)
    if tool.orphan or not tool.source or not sourcePane(cx, tool.source) then
        tool.source = nil
        tool.orphan = true
        tool.sourceParkPending = nil
        local pane = liveTool(cx, tool)
        if pane and not pane.parked then cx.layout:park(tool.pane) end
        persist(tool)
        finishStartup(tool)
        return
    end
    if cx.session:focused() ~= (tool.requestedPane or tool.source) then
        finishStartup(tool)
        return
    end
    focusTool(cx, tool, { pane = tool.source }, function() finishStartup(tool) end)
end
finishStartup = function(tool)
    if tool.programs and not tool.launchSent and tool.programs.gitDirectory then
        lazygitLaunch.cleanup(tool.programs.gitDirectory)
        tool.programs.gitDirectory = nil
    end
    if tool.finish then tool.finish() end
end

local function handshake(cx, tool, remaining)
    -- settle observes OSC 133 or its deadline. A short observation window also
    -- handles the initial prompt, which has no preceding command completion.
    cx.session:settle(tool.pane, 100):next(function(_, err, nextCx)
        if not nextCx then finishStartup(tool); return end
        if tools[tool.key] ~= tool or byPane[tool.pane] ~= tool then
            finishStartup(tool)
            return
        end
        local host = nextCx.hosts:current()
        local session = nextCx.sessions:current()
        if host.kind ~= "local" or host.id ~= tool.host or session.id ~= tool.session
            or (nextCx.session:focused() ~= tool.requestedPane and sourcePane(nextCx, tool.source)) then
            finishStartup(tool)
            return
        end
        local pane = liveTool(nextCx, tool)
        if not pane then finishStartup(tool); return end
        if err or pane.exited ~= nil or remaining == 0 then
            finishStartup(tool)
            nextCx:toast("error", "工具身份未确认", "等待新 shell 或握手未完成；窗格仍保留，不重复启动。")
            return
        end
        if not tool.handshakeSent then
            if nextCx.session:focused() == tool.pane then
                finishStartup(tool)
                nextCx:toast("error", "工具身份未确认", "新窗格已被接管输入；未注入握手命令，窗格仍保留。")
                return
            end
            if pane.at_prompt == true and pane.busy ~= true and pane.running == nil then
                tool.handshakeSent = true
                nextCx:run(tool.pane, identity.command(tool.token) .. "\r")
            end
            handshake(nextCx, tool, remaining - 1)
            return
        end
        local marker = identity.marker(nextCx, tool.pane, tool.token)
        if not marker or not marker.pid then
            handshake(nextCx, tool, remaining - 1)
            return
        end
        identity.rememberProcess(nextCx, tool, marker.pid, tool.pane, function(ok, verifiedCx)
            if not verifiedCx or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool then
                finishStartup(tool)
                return
            end
            local currentHost = verifiedCx.hosts:current()
            local currentSession = verifiedCx.sessions:current()
            if currentHost.kind ~= "local" or currentHost.id ~= tool.host
                or currentSession.id ~= tool.session or not liveTool(verifiedCx, tool)
                or (verifiedCx.session:focused() ~= tool.requestedPane
                    and sourcePane(verifiedCx, tool.source)) then
                finishStartup(tool)
                return
            end
            if not ok then
                handshake(verifiedCx, tool, remaining - 1)
                return
            end
            tool.identityVerified = true
            local saved, saveError = persist(tool)
            if not saved then
                verifiedCx:toast("error", "工具身份无法持久化",
                    "重载后由 Tern 原生管理；插件不会认领旧实例。" .. tostring(saveError))
            end
            if tool.kind == "lazygit" and tool.programs and not tool.launchSent then
                tool.launchSent = true
                local command = lazygitLaunch.command(
                    tool.programs.gitDirectory, tool.programs.lazygit, tool.programs.pathEnv)
                verifiedCx:run(tool.pane, command .. "\r")
                verifiedCx.session:settle(tool.pane, 500):next(function(_, launchError, finalCx)
                    if not finalCx then if tool.finish then tool.finish() end; return end
                    local finalHost = finalCx.hosts:current()
                    local finalSession = finalCx.sessions:current()
                    local finalPane = liveTool(finalCx, tool)
                    if tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
                        or finalHost.kind ~= "local" or finalHost.id ~= tool.host
                        or finalSession.id ~= tool.session or not finalPane then
                        if tool.finish then tool.finish() end
                        return
                    end
                    if finalPane.exited ~= nil then
                        if tool.finish then tool.finish() end
                        lazygitLaunch.cleanup(tool.programs.gitDirectory)
                        tool.programs.gitDirectory = nil
                        finalCx:toast("error", "lazygit 启动失败", "窗格保留；可由 Tern 原生查看错误。")
                        return
                    end
                    if finalCx.session:focused() ~= tool.requestedPane
                        and sourcePane(finalCx, tool.source) then
                        if tool.finish then tool.finish() end
                        return
                    end
                    verifyManaged(finalCx, tool, function(stillVerified, verifiedCx)
                        if not verifiedCx then if tool.finish then tool.finish() end; return end
                        if not stillVerified then
                            if tool.finish then tool.finish() end
                            verifiedCx:toast("error", "lazygit 身份未确认", "窗格保留；请交由 Tern 原生管理。")
                            return
                        end
                        presentTool(verifiedCx, tool)
                    end)
                end)
            else
                presentTool(verifiedCx, tool)
            end
        end)
    end)
end

local function removeTool(tool, ended)
    if tools[tool.key] ~= tool then return end
    tools[tool.key] = nil
    if byPane[tool.pane] == tool then byPane[tool.pane] = nil end
    sourceFlights[tool] = nil
    identity.remove(tool.token)
    if tool.programs and (ended or not tool.launchSent) then
        lazygitLaunch.cleanup(tool.programs.gitDirectory)
    end
end

local function handleSourceGone(cx, tool, closed)
    if not tool then return end
    if tool.source ~= nil then
        if tool.source ~= closed then return end
        tool.source = nil
        tool.originSource = nil
        tool.orphan = true
        tool.sourceParkPending = true
        persist(tool)
    elseif not tool.sourceParkPending then
        return
    end
    if sourceFlights[tool] then return end
    local host = cx.hosts:current()
    if host.kind ~= "local" or host.id ~= tool.host
        or cx.sessions:current().id ~= tool.session then return end
    local pane = liveTool(cx, tool)
    if not pane then
        removeTool(tool)
        return
    end
    if pane.exited ~= nil or pane.parked then
        tool.sourceParkPending = nil
        return
    end
    if not tool.identityVerified then return end
    sourceFlights[tool] = true
    verifyManaged(cx, tool, function(verified, nextCx)
        sourceFlights[tool] = nil
        if not nextCx or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
            or not tool.sourceParkPending or tool.source ~= nil or not tool.orphan then return end
        local currentHost = nextCx.hosts:current()
        local currentPane = liveTool(nextCx, tool)
        if currentHost.kind ~= "local" or currentHost.id ~= tool.host
            or nextCx.sessions:current().id ~= tool.session or not currentPane then return end
        tool.sourceParkPending = nil
        if not verified then
            nextCx:toast("error", "来源关闭，工具身份未确认",
                "工具保持原样；请使用 Tern 原生窗格查看或关闭。")
            return
        end
        if currentPane.exited ~= nil or currentPane.parked then return end
        local ok, err = nextCx.layout:park(tool.pane)
        if not ok then
            nextCx:toast("error", "来源已关闭但工具未能收起", err)
        end
    end)
end

local function observeSources(cx)
    for _, tool in pairs(tools) do
        local currentHost = cx.hosts:current()
        local currentSession = cx.sessions:current()
        if currentHost.kind == "local" and currentHost.id == tool.host
            and currentSession.id == tool.session then
            local pane = liveTool(cx, tool)
            if not pane then
                removeTool(tool)
            elseif tool.source and not sourcePane(cx, tool.source) then
                handleSourceGone(cx, tool, tool.source)
            elseif tool.sourceParkPending then
                handleSourceGone(cx, tool, nil)
            end
        end
    end
    if not next(tools) and watcher then
        watcher:cancel()
        watcher = nil
    end
end

local function scheduleWatcher(cx)
    if watcherScheduled or watcher then return end
    watcherScheduled = true
    watcher = tern.timer(250, function(freshCx)
        watcher = nil
        watcherScheduled = false
        if not freshCx then return end
        observeSources(freshCx)
        if next(tools) then scheduleWatcher(freshCx) end
    end)
end


local function create(cx, owner, token, finish, kind, requestedPane, programs)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local source = sourcePane(cx, owner.pane)
    if host.id ~= owner.host or host.kind ~= "local" or session.id ~= owner.session
        or focused ~= requestedPane or not source or source.cwd ~= owner.cwd then
        if programs then lazygitLaunch.cleanup(programs.gitDirectory) end
        finish()
        cx:toast("error", "Kiku 助手来源已变化", "请从原本机终端重新打开工具。")
        return
    end
    local pane, splitError = nil, nil
    local existing = {}
    for _, info in ipairs(cx.session:panes()) do existing[info.pane] = true end
    local ok, result = pcall(function()
        pane = cx.layout:split(owner.pane, "right", { cwd = owner.cwd }, { focus = false })
    end)
    if not ok then splitError = tostring(result) end
    if not pane then
        local created = {}
        for _, info in ipairs(cx.session:panes()) do
            if not existing[info.pane] and info.kind == "terminal" then
                table.insert(created, tostring(info.pane))
            end
        end
        local detail = splitError or "Tern 未返回新终端窗格。"
        if #created > 0 then detail ..= " 可能已创建且保留的pane：" .. table.concat(created, ", ") .. "。" end
        detail ..= " 未自动重试或关闭任何窗格。"
        if programs then lazygitLaunch.cleanup(programs.gitDirectory) end
        finish()
        cx:toast("error", "无法确认工具布局创建结果", detail)
        return
    end
    local key = toolKey(owner.key, kind)
    local tool = {
        pane = pane, source = owner.pane, originSource = owner.pane, key = key, sourceKey = owner.key,
        kind = kind, host = owner.host, session = owner.session, cwd = owner.cwd,
        token = token, programs = programs, requestedPane = requestedPane, finish = finish,
    }
    tools[key] = tool
    byPane[pane] = tool
    scheduleWatcher(cx)
    local saved, saveError = persist(tool)
    if not saved then
        tool.identityUnknown = true
        cx:toast("error", "工具身份无法持久化", tostring(saveError))
    end
    handshake(cx, tool, 200)
end

local function openForOwner(cx, kind, owner, requestedPane)
    local key = toolKey(owner.key, kind)
    if pending[owner.key] then
        cx:toast("error", "来源工具正在启动", "保留当前操作；不会创建重复实例。")
        return
    end
    local existing = tools[key]
    if existing and liveTool(cx, existing) then
        if not existing.identityVerified then
            cx:toast("error", "工具身份未确认", "保留窗格；不接管或创建重复实例。")
            return
        end
        local reuseFlight = {}
        pending[owner.key] = reuseFlight
        local function release()
            if pending[owner.key] == reuseFlight then pending[owner.key] = nil end
        end
        verifyManaged(cx, existing, function(verified, finalCx)
            if not finalCx then release(); return end
            if finalCx.hosts:current().id ~= owner.host
                or finalCx.sessions:current().id ~= owner.session
                or finalCx.session:focused() ~= requestedPane
                or tools[key] ~= existing or byPane[existing.pane] ~= existing then
                release()
                return
            end
            if not verified then
                release()
                finalCx:toast("error", "工具身份未确认", "保留窗格且不执行恢复。")
                return
            end
            focusTool(finalCx, existing, owner, release)
        end)
        return
    end
    local records = identity.records()
    for _, record in ipairs(records) do
        if record.unreadable then
            cx:toast("error", "工具记录无法读取", "保留现有记录且不创建重复工具。")
            return
        end
        local currentInstance = false
        for _, managed in pairs(tools) do
            if managed.token == record.token then currentInstance = true; break end
        end
        if not currentInstance and record.host == owner.host
            and (record.source == owner.pane or record.pane == owner.pane)
            and sourcePane(cx, record.pane) then
            cx:toast("error", "工具身份未确认",
                "已有历史工具记录；请交由 Tern 原生查看或关闭，未创建重复工具。")
            return
        end
    end
    local flight = {}
    pending[owner.key] = flight
    local function finish()
        if pending[owner.key] == flight then pending[owner.key] = nil end
    end
    local function continueWith(programs)
        identity.newToken(function(token, tokenError, tokenCx)
            if not tokenCx then finish(); return end
            if tokenCx.hosts:current().id ~= owner.host
                or tokenCx.sessions:current().id ~= owner.session
                or tokenCx.session:focused() ~= requestedPane then
                finish()
                tokenCx:toast("error", "Kiku 助手来源已变化", "未创建工具；请从当前终端重新打开。")
                return
            end
            if not token then finish(); tokenCx:toast("error", "无法安全创建工具", tokenError); return end
            local function createWith(readyCx, readyPrograms)
                if not readyCx then finish(); return end
                if readyCx.hosts:current().id ~= owner.host
                    or readyCx.sessions:current().id ~= owner.session
                    or readyCx.session:focused() ~= requestedPane
                    or not sourcePane(readyCx, owner.pane) then
                    if readyPrograms then lazygitLaunch.cleanup(readyPrograms.gitDirectory) end
                    finish()
                    readyCx:toast("error", "Kiku 助手来源已变化", "未创建工具。")
                    return
                end
                create(readyCx, owner, token, finish, kind, requestedPane, readyPrograms)
            end
            if programs then
                lazygitLaunch.prepare(tokenCx, token, programs.git, function(directory, prepError, prepCx)
                    if not prepCx then finish(); return end
                    if not directory then finish(); prepCx:toast("error", "无法准备 lazygit", prepError); return end
                    programs.gitDirectory = directory
                    createWith(prepCx, programs)
                end)
            else
                createWith(tokenCx, nil)
            end
        end)
    end
    local function startNew()
    if kind == "lazygit" then
        executables:check(cx, { "git", "lazygit" }, function(nextCx, result, missing)
            if not nextCx then finish(); return end
            if nextCx.hosts:current().id ~= owner.host
                or nextCx.hosts:current().kind ~= "local"
                or nextCx.sessions:current().id ~= owner.session
                or nextCx.session:focused() ~= requestedPane or not sourcePane(nextCx, owner.pane) then
                finish()
                nextCx:toast("error", "Kiku 助手来源已变化", "未启动 lazygit。")
                return
            end
            if missing then
                finish()
                local reasons = { missing }
                for _, name in ipairs({ "git", "lazygit" }) do
                    if result.errors[name] then
                        table.insert(reasons,
                            name .. "（executables." .. name .. "）： " .. result.errors[name])
                    end
                end
                nextCx:toast("error", "无法打开 lazygit", table.concat(reasons, "；"))
                return
            end
            for name, fallback in pairs(result.fallbacks) do
                nextCx:toast("info", "Kiku 助手依赖回退",
                    name .. " 已使用 " .. fallback.path .. "（" .. fallback.reason .. "）")
            end
            tern.process.run({ result.paths.git, "-C", owner.cwd, "rev-parse", "--show-toplevel" },
                { timeout_ms = 3000, env = { PATH = result.pathEnv } }, function(check, checkedCx)
                    if not checkedCx then finish(); return end
                    if checkedCx.hosts:current().id ~= owner.host
                        or checkedCx.sessions:current().id ~= owner.session
                        or checkedCx.session:focused() ~= requestedPane
                        or not sourcePane(checkedCx, owner.pane) then
                        finish()
                        checkedCx:toast("error", "Kiku 助手来源已变化", "未启动 lazygit。")
                        return
                    end
                    if check.status ~= 0 or check.timed_out then
                        finish()
                        checkedCx:toast("error", "当前目录不是可用的 Git 仓库",
                            "未初始化仓库，也未创建工具窗格。")
                        return
                    end
                    continueWith({ git = result.paths.git, lazygit = result.paths.lazygit,
                        pathEnv = result.pathEnv })
                end)
            end)
    else
        continueWith(nil)
    end
    end
    local otherKind = kind == "lazygit" and "terminal" or "lazygit"
    local peer = tools[toolKey(owner.key, otherKind)]
    local peerPane = peer and liveTool(cx, peer)
    if not peerPane or peerPane.parked == true then
        startNew()
        return
    end
    verifyManaged(cx, peer, function(verified, nextCx)
        if not nextCx then finish(); return end
        local currentPeerPane = liveTool(nextCx, peer)
        if nextCx.hosts:current().id ~= owner.host
            or nextCx.sessions:current().id ~= owner.session
            or nextCx.session:focused() ~= requestedPane
            or tools[peer.key] ~= peer or byPane[peer.pane] ~= peer
            or not currentPeerPane or currentPeerPane.parked == true
            or not sourcePane(nextCx, owner.pane) then
            finish()
            return
        end
        if not verified then
            finish()
            nextCx:toast("error", "当前工具身份未确认", "未创建或切换任何窗格。")
            return
        end
        startNew()
    end)
end


local function open(cx, kind)
    if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
        cx:toast("error", "Kiku 工具仅支持 macOS / Linux 本机。")
        return
    end
    local requestedPane = cx.session:focused()
    local owner, err = ownerFor(cx)
    if not owner or owner.hostKind ~= "local" then
        cx:toast("error", "无法打开工具", err or "当前来源不是本机终端。")
        return
    end
    local function start(nextCx)
        if not nextCx or nextCx.hosts:current().kind ~= "local"
            or nextCx.hosts:current().id ~= owner.host
            or nextCx.sessions:current().id ~= owner.session
            or nextCx.session:focused() ~= requestedPane then return end
        local currentSource = sourcePane(nextCx, owner.pane)
        if not currentSource or currentSource.cwd ~= owner.cwd then
            nextCx:toast("error", "Kiku 助手来源已变化", "请从原本机终端重新打开工具。")
            return
        end
        openForOwner(nextCx, kind, owner, requestedPane)
    end
    local sourceTool = byPane[requestedPane]
    if not sourceTool then start(cx); return end
    verifyManaged(cx, sourceTool, function(verified, nextCx)
        if not nextCx then return end
        local source = sourcePane(nextCx, owner.pane)
        if nextCx.hosts:current().kind ~= "local"
            or nextCx.hosts:current().id ~= owner.host
            or nextCx.sessions:current().id ~= owner.session
            or nextCx.session:focused() ~= requestedPane
            or byPane[requestedPane] ~= sourceTool
            or sourceTool.source ~= owner.pane or not source or source.cwd ~= owner.cwd then
            nextCx:toast("error", "工具来源关系已变化", "未启动另一个工具。")
            return
        end
        if not verified then
            nextCx:toast("error", "当前工具身份未确认", "未恢复、收起或创建任何工具。")
            return
        end
        start(nextCx)
    end)
end

local function hide(cx)
    local focused = cx.session:focused()
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local tool = focused and byPane[focused]
    if not tool then
        cx:toast("error", "工具身份未确认", "未识别当前窗格；未执行收起操作。")
        return
    end
    local pane = liveTool(cx, tool)
    if not pane then return end
    verifyManaged(cx, tool, function(verified, nextCx)
        if not nextCx then return end
        local currentHost = nextCx.hosts:current()
        if currentHost.kind ~= "local" or currentHost.id ~= tool.host
            or nextCx.sessions:current().id ~= tool.session
            or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
            or nextCx.session:focused() ~= focused then return end
        if not verified then
            nextCx:toast("error", "临时终端身份未确认", "保留当前窗格；未执行收起操作。")
            return
        end
        local ok, err = nextCx.layout:park(tool.pane)
        if not ok then nextCx:toast("error", "无法收起临时终端", err); return end
        if tool.source and sourcePane(nextCx, tool.source) then nextCx.layout:focus(tool.source) end
    end)
end

local function endTool(cx)
    local focused = cx.session:focused()
    local tool = focused and byPane[focused]
    if not tool then
        cx:toast("error", "工具身份未确认", "未识别当前窗格；未执行结束操作。")
        return
    end
    verifyManaged(cx, tool, function(verified, checkedCx)
        if not checkedCx then return end
        if checkedCx.session:focused() ~= focused
            or tools[tool.key] ~= tool or byPane[tool.pane] ~= tool then return end
        if not verified then
            checkedCx:toast("error", "终端身份未确认", "保留当前窗格；未显示结束确认，也未执行结束操作。")
            return
        end
        local items = {
            { label = "取消", id = "cancel", current = true },
            { label = "结束此临时终端", id = "end" },
        }
        checkedCx:pick({ placeholder = "确认结束临时终端？未知或运行中的任务可能一并结束。", items = items }):next(
            function(item, err, nextCx)
                if not nextCx or err or not item or item.id ~= "end"
                    or nextCx.session:focused() ~= focused then return end
                verifyManaged(nextCx, tool, function(stillVerified, finalCx)
                    if not finalCx then return end
                    local host = finalCx.hosts:current()
                    local current = finalCx.session:pane(tool.pane)
                    if tools[tool.key] ~= tool or byPane[tool.pane] ~= tool
                        or not current or current.kind ~= "terminal"
                        or host.kind ~= "local" or host.id ~= tool.host
                        or finalCx.sessions:current().id ~= tool.session
                        or finalCx.session:focused() ~= focused then
                        finalCx:toast("error", "终端身份已变化", "保留当前窗格；未执行结束操作。")
                        return
                    end
                    if not stillVerified then
                        finalCx:toast("error", "终端身份未确认", "保留当前窗格；未执行结束操作。")
                        return
                    end
                    local closed, closeError = pcall(function() finalCx.layout:close(tool.pane) end)
                    if not closed then
                        finalCx:toast("error", "无法结束临时终端", tostring(closeError))
                        return
                    end
                    removeTool(tool, true)
                end)
            end)
    end)
end

local function restore(cx)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local items = {}
    for _, tool in pairs(tools) do
        local pane = liveTool(cx, tool)
        if pane and pane.exited == nil and pane.parked == true and tool.orphan
            and tool.identityVerified then
            local kindLabel = tool.kind == "lazygit" and "lazygit" or "临时终端"
            table.insert(items, {
                label = "本机 · " .. tool.cwd,
                detail = kindLabel .. " · 来源未确认",
                tool = tool,
            })
        end
    end
    if #items == 0 then
        cx:toast("info", "没有可恢复的收起工具。")
        return
    end
    cx:pick({ placeholder = "选择恢复为独立标签页的工具", items = items }):next(
        function(item, err, finalCx)
            if not finalCx or err or not item
                or finalCx.hosts:current().id ~= host.id
                or finalCx.sessions:current().id ~= session.id then return end
            local tool = item.tool
            verifyManaged(finalCx, tool, function(verified, verifiedCx)
                if not verifiedCx then return end
                local pane = liveTool(verifiedCx, tool)
                if verifiedCx.hosts:current().id ~= host.id
                    or verifiedCx.sessions:current().id ~= session.id
                    or not verified or tools[tool.key] ~= tool
                    or byPane[tool.pane] ~= tool or not pane
                    or pane.exited ~= nil or pane.parked ~= true then
                    verifiedCx:toast("error", "临时终端身份未确认",
                        "窗格保持原状；未执行恢复，也未重新运行 shell 命令。")
                    return
                end
                local tab, moveError = verifiedCx.layout:move_to_new_tab(
                    tool.pane, tool.session, { focus = false })
                if not tab then
                    verifiedCx:toast("error", "无法恢复工具标签页", moveError)
                    return
                end
                if tools[tool.key] == tool then tools[tool.key] = nil end
                tool.source = nil
                tool.orphan = true
                tool.sourceParkPending = nil
                tool.key = "orphan:" .. tool.token
                tools[tool.key] = tool
                persist(tool)
            end)
        end)
end

function M.register(config, executableResolver)
    executables = executableResolver
    tern.command({
        id = "open_terminal", title = "Kiku：打开临时终端", group = "Kiku 助手",
        keys = { config.terminalKeybinding }, run = function(cx) open(cx, "terminal") end,
    })
    tern.command({
        id = "open_lazygit", title = "Kiku：打开 lazygit", group = "Kiku 助手",
        keys = { config.lazygitKeybinding ~= "" and config.lazygitKeybinding or "ctrl+b>alt+g" },
        available = function() return executableResolver:ready("git") and executableResolver:ready("lazygit") end,
        run = function(cx) open(cx, "lazygit") end,
    })
    tern.command({ id = "hide_tool", title = "Kiku：收起工具", group = "Kiku 助手", keys = { config.hideToolKeybinding }, run = hide })
    tern.command({ id = "end_tool", title = "Kiku：结束工具", group = "Kiku 助手", keys = { config.endToolKeybinding }, run = endTool })
    tern.command({ id = "restore_tools", title = "Kiku：恢复收起的工具", group = "Kiku 助手", run = restore })
    tern.on("pane_closed", function(ev, cx)
        local closed = ev and ev.pane
        if not closed then return end
        local closedTool = byPane[closed]
        if closedTool then
            removeTool(closedTool, true)
            return
        end
        local affected = {}
        for _, tool in pairs(tools) do
            if tool.source == closed then affected[#affected + 1] = tool end
        end
        for _, tool in ipairs(affected) do
            handleSourceGone(cx, tool, closed)
        end
    end)
end

return M

