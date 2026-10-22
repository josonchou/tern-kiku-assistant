local tern = require("tern")
local identity = require("./tool_identity")
local lazygitLaunch = require("./lazygit_launch")
local M = {}
local executables
local configError
local tools = {}
local byPane = {}
local pending = {}
local watcher
local watcherScheduled = false

local function tupleKey(tab, cwd, kind)
    local function part(value)
        value = tostring(value)
        return tostring(#value) .. ":" .. value
    end
    return part(tab) .. part(cwd) .. part(kind)
end

local function toolKey(owner, kind)
    return tupleKey(owner.tab, owner.cwd, kind)
end

local function sourcePane(cx, paneId)
    if not paneId then return nil end
    return cx.session:pane(paneId)
end

local function liveTool(cx, tool)
    local pane = cx.session:pane(tool.pane)
    if not pane then return nil end
    -- Terminal tools are interactive shells; a lazygit tool started with
    -- Launch.command is an agent pane. Both are native terminal surfaces.
    if pane.kind ~= "terminal" and pane.kind ~= "agent" then return nil end
    return pane
end

-- Ownership is the recorded pane ID plus its recorded host, session, tab and
-- launch directory. Process generation, PID and pane content are deliberately
-- not consulted: a natively restarted shell keeps the same pane ID and stays the
-- same tool under this contract.
local function managedNow(cx, tool)
    local host = cx.hosts:current()
    local pane = liveTool(cx, tool)
    return host.kind == "local" and host.id == tool.host
        and cx.sessions:current().id == tool.session
        and pane ~= nil
        and tools[tool.key] == tool and byPane[tool.pane] == tool
end

local function requestValid(cx, request)
    local host = cx.hosts:current()
    local pane = sourcePane(cx, request.pane)
    return host.kind == "local" and host.id == request.host
        and cx.sessions:current().id == request.session
        and cx.session:focused() == request.pane
        and pane ~= nil and pane.cwd == request.cwd
        and (pane.tab or cx.session:tab_of(request.pane)) == request.tab
end

local function tiledTarget(cx, tab, excluding, preferred)
    local layout = cx.session:layout(tab)
    if not layout then return nil end
    local function eligible(id)
        local pane = id and sourcePane(cx, id)
        return pane and id ~= excluding and pane.tab == tab
            and pane.floating ~= true and pane.parked ~= true
    end
    if eligible(preferred) then return preferred end
    for _, float in ipairs(layout.floats or {}) do
        if float.pane == preferred and eligible(float.over) then return float.over end
    end
    local function leaf(tree)
        if not tree then return nil end
        if eligible(tree.pane) then return tree.pane end
        return leaf(tree[1]) or leaf(tree[2])
    end
    return leaf(layout.root)
end

local function displayTool(cx, tool, request)
    if not requestValid(cx, request) then return false end
    local current = liveTool(cx, tool)
    local preferred = request.anchor or tool.anchor
    local target = tiledTarget(cx, tool.originTab, tool.pane, preferred)
    if not current or not target then
        cx:toast("error", "无法确定工具布局目标", "工具保留原状；请在归属标签页恢复后重试。")
        return false
    end
    if current.parked then
        local ok, err = cx.layout:unpark(tool.pane, { focus = false })
        if not ok then cx:toast("error", "无法恢复工具", err); return false end
        current = liveTool(cx, tool)
    end
    if not current then return false end
    if current.tab ~= tool.originTab then
        local ok, err = cx.layout:move_to_tab(tool.pane, tool.originTab, { focus = false })
        if not ok then cx:toast("error", "无法将工具带回归属标签页", err); return false end
    end
    -- Both tool kinds use the same floating presentation, so reuse follows the
    -- scratch-terminal path even after a manual dock or move.
    local ok, err = cx.layout:float(tool.pane, target, "br", { focus = true })
    if not ok then
        cx:toast("error", "无法恢复工具默认布局", err)
        return false
    end
    tool.anchor = target
    if request.pane ~= tool.pane then tool.lastSource = request.pane end
    cx.layout:focus(tool.pane)
    return true
end

local function focusTool(cx, tool)
    local request = tool.request
    if not request or not requestValid(cx, request) then
        cx:toast("error", "来源已变化", "未恢复或移动任何窗格。")
        return false
    end
    return displayTool(cx, tool, request)
end

local function ownerFor(cx)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local pane = sourcePane(cx, focused)
    if not pane or type(pane.cwd) ~= "string" or pane.cwd:sub(1, 1) ~= "/" then
        return nil, "无法确定来源窗格及其工作目录。"
    end
    local tab = pane.tab or cx.session:tab_of(focused)
    if type(tab) ~= "number" then return nil, "无法确定当前工具标签页。" end
    return {
        host = host.id, hostKind = host.kind, session = session.id,
        pane = focused, cwd = pane.cwd, tab = tab,
    }
end

local function persist(tool)
    return identity.save({
        token = tool.token, pane = tool.pane,
        host = tool.host, session = tool.session, cwd = tool.cwd,
        originTab = tool.originTab, kind = tool.kind, pid = tool.pid,
    })
end



local function presentTool(cx, tool)
    focusTool(cx, tool)
    if tool.finish then tool.finish() end
end

-- Nothing is typed into tool panes any more: a terminal tool is the real shell
-- and a lazygit tool starts through Launch.command. The private launch
-- directory is read once for diagnostics only, so creation never awaits.
local function recordStartupDetails(cx, tool)
    if tool.kind ~= "terminal" then return end
    local marker, markerError = identity.marker(cx, tool.pane, tool.token)
    if markerError then
        cx:toast("error", "工具启动未完成", markerError)
        return
    end
    if marker and marker.pid then
        tool.pid = marker.pid
        persist(tool)
    end
end

local function removeTool(tool, _ended)
    if tools[tool.key] ~= tool then return end
    tools[tool.key] = nil
    if byPane[tool.pane] == tool then byPane[tool.pane] = nil end
    identity.remove(tool.token)
    if tool.programs then lazygitLaunch.cleanup(tool.programs.gitDirectory) end
end

local function needsObservation()
    if next(tools) then return true end
    for _, flight in pairs(pending) do
        if flight.ambiguousPanes then return true end
    end
    return false
end

local function observeTools(cx)
    for _, tool in pairs(tools) do
        local currentHost = cx.hosts:current()
        local currentSession = cx.sessions:current()
        if currentHost.kind == "local" and currentHost.id == tool.host
            and currentSession.id == tool.session and not liveTool(cx, tool) then
            removeTool(tool)
        end
    end
    for key, flight in pairs(pending) do
        if flight.ambiguousPanes then
            local remains = false
            for _, pane in ipairs(flight.ambiguousPanes) do
                if cx.session:pane(pane) then remains = true; break end
            end
            if not remains then
                if flight.token then identity.remove(flight.token) end
                pending[key] = nil
            end
        end
    end
    if not needsObservation() and watcher then
        watcher:cancel()
        watcher = nil
        watcherScheduled = false
    end
end

local function scheduleWatcher(cx)
    if not needsObservation() or watcherScheduled or watcher then return end
    watcherScheduled = true
    watcher = tern.timer(250, function(freshCx)
        watcher = nil
        watcherScheduled = false
        if not freshCx then return end
        observeTools(freshCx)
        if needsObservation() then scheduleWatcher(freshCx) end
    end)
end

-- The registry lives in this window VM, so a reload starts empty. Rebuild it
-- from the persisted records for panes that still exist: the record's host,
-- session, tab, launch directory and pane ID are the whole ownership proof.
-- Records whose pane is gone are ignored, and never deleted, because the same
-- record store is shared with other windows.
local hydrated = false

local function adoptRecords(cx)
    if hydrated then return end
    hydrated = true
    local host = cx.hosts:current()
    if host.kind ~= "local" then return end
    for _, record in ipairs(identity.records()) do
        if not record.unreadable and record.host == host.id
            and type(record.pane) == "number" and type(record.session) == "number"
            and type(record.cwd) == "string" and record.cwd:sub(1, 1) == "/" then
            local pane = cx.session:pane(record.pane)
            if pane and (pane.kind == "terminal" or pane.kind == "agent")
                and not byPane[record.pane] then
                local kind = record.kind or "terminal"
                local tab = record.originTab or pane.tab
                if type(tab) == "number" then
                    local key = tupleKey(tab, record.cwd, kind)
                    if not tools[key] then
                        local tool = {
                            pane = record.pane, key = key, originTab = tab,
                            kind = kind, host = record.host, session = record.session,
                            cwd = record.cwd, token = record.token, pid = record.pid,
                            adopted = true,
                        }
                        if kind == "lazygit" then
                            -- The private Git bridge path is derived from the token,
                            -- so a reloaded lazygit still cleans up on removal.
                            tool.programs = { gitDirectory = lazygitLaunch.directory(record.token) }
                        end
                        tools[key] = tool
                        byPane[tool.pane] = tool
                    end
                end
            end
        end
    end
    if next(tools) then scheduleWatcher(cx) end
end


local function create(cx, owner, token, finish, kind, requestedPane, programs)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local source = sourcePane(cx, owner.pane)
    if host.id ~= owner.host or host.kind ~= "local" or session.id ~= owner.session
        or focused ~= requestedPane or not source or source.cwd ~= owner.cwd
        or (source.tab or cx.session:tab_of(owner.pane)) ~= owner.tab
        or not owner.anchor or not cx.session:pane(owner.anchor) then
        if programs then lazygitLaunch.cleanup(programs.gitDirectory) end
        finish()
        cx:toast("error", "Kiku 助手来源已变化", "请从本机来源窗格重新打开工具。")
        return
    end
    local launchSpec
    if kind == "lazygit" then
        -- Starting the program through Launch.command means no command is typed
        -- into a shell, so creation never waits for a prompt. Tern runs the line
        -- through the login shell in place of an interactive one (agent pane).
        launchSpec = {
            cwd = owner.cwd,
            command = lazygitLaunch.command(
                programs.gitDirectory, programs.lazygit, programs.pathEnv),
        }
    else
        local launchDirectory, launchError = identity.launch(token, owner.cwd)
        if not launchDirectory then
            if programs then lazygitLaunch.cleanup(programs.gitDirectory) end
            finish()
            cx:toast("error", "无法准备工具启动", launchError)
            return
        end
        launchSpec = { cwd = launchDirectory }
    end
    local flight = pending[toolKey(owner, kind)]
    if flight then flight.token = token end
    local pane, splitError = nil, nil
    local existing = {}
    for _, info in ipairs(cx.session:panes()) do existing[info.pane] = true end
    local ok, result = pcall(function()
        pane = cx.layout:split(owner.anchor, "right", launchSpec, { focus = false })
    end)
    if not ok then splitError = tostring(result) end
    if not pane then
        local created = {}
        for _, info in ipairs(cx.session:panes()) do
            if not existing[info.pane] and (info.kind == "terminal" or info.kind == "agent") then
                table.insert(created, info.pane)
            end
        end
        local display = {}
        for _, paneId in ipairs(created) do table.insert(display,tostring(paneId)) end
        local detail = splitError or "Tern 未返回新终端窗格。"
        if #created > 0 then
            detail ..= " 可能已创建且保留的pane：" .. table.concat(display, ", ") .. "。"
            if flight then flight.ambiguousPanes, flight.uncertain = created, true end
            scheduleWatcher(cx)
        elseif not ok then
            if flight then flight.uncertain = true end
            detail ..= " 暂未观察到新窗格，但异常不保证未创建；请原生检查后重载插件。"
        else
            identity.remove(token)
            finish()
        end
        detail ..= " 未自动重试或关闭任何窗格。"
        if programs then lazygitLaunch.cleanup(programs.gitDirectory) end
        cx:toast("error", "无法确认工具布局创建结果", detail)
        return
    end
    -- Float before the shell or command starts so the tool never sits in the
    -- split it was created in, then present it at once. Ownership is the pane
    -- ID, so creation has nothing to verify and never waits.
    local floated, floatError = false, nil
    local floatCalled, floatResult, floatReason = pcall(function()
        return cx.layout:float(pane, owner.anchor, "br", { focus = false })
    end)
    if floatCalled then
        floated, floatError = floatResult, floatReason
    else
        floatError = tostring(floatResult)
    end
    if not floated then
        cx:toast("error", "工具已创建但未能浮动",
            floatError or "再次打开时会尝试恢复浮动。")
    end
    local key = toolKey(owner, kind)
    local tool = {
        pane = pane, key = key,
        originTab = owner.tab, kind = kind, host = owner.host,
        session = owner.session, cwd = owner.cwd,
        token = token, programs = programs,
        lastSource = requestedPane, request = owner, anchor = owner.anchor, finish = finish,
    }
    tools[key] = tool
    byPane[pane] = tool
    scheduleWatcher(cx)
    local saved, saveError = persist(tool)
    if not saved then
        cx:toast("error", "工具身份无法持久化", tostring(saveError))
    end
    recordStartupDetails(cx, tool)
    presentTool(cx, tool)
end

local function openForOwner(cx, kind, owner, requestedPane)
    local key = toolKey(owner, kind)
    if pending[key] then
        if pending[key].uncertain then
            cx:toast("error", "工具创建结果未确认", "未重复启动；请原生检查，必要时重载插件。")
        else
            cx:toast("error", "工具正在启动", "保留当前操作；不会创建重复实例。")
        end
        return
    end
    local existing = tools[key]
    if existing and liveTool(cx, existing) then
        existing.request = owner
        focusTool(cx, existing)
        return
    end
    if existing then removeTool(existing, true) end
    if configError then
        cx:toast("error", "Kiku 配置错误", configError)
        return
    end
    local flight = {}
    pending[key] = flight
    local function finish()
        if pending[key] == flight then pending[key] = nil end
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
                if not requestValid(readyCx, owner) then
                    if readyPrograms then lazygitLaunch.cleanup(readyPrograms.gitDirectory) end
                    finish()
                    readyCx:toast("error", "Kiku 助手来源已变化", "未创建工具。")
                    return
                end
                if not owner.sourceTool then
                    create(readyCx, owner, token, finish, kind, requestedPane, readyPrograms)
                    return
                end
                if not managedNow(readyCx, owner.sourceTool)
                    or byPane[owner.pane] ~= owner.sourceTool then
                    if readyPrograms then lazygitLaunch.cleanup(readyPrograms.gitDirectory) end
                    finish()
                    readyCx:toast("error", "来源工具身份已变化", "未创建新工具。")
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
            if not requestValid(nextCx, owner)
                or nextCx.hosts:current().id ~= owner.host
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
            -- Refuse a non-repository before creating any pane, so lazygit is
            -- not started just to show its own "not a git repository" error.
            tern.process.run(
                { result.paths.git, "-C", owner.cwd, "rev-parse", "--is-inside-work-tree" },
                { timeout_ms = 5000, env = { PATH = result.pathEnv } },
                function(checkResult, checkCx)
                    if not checkCx then finish(); return end
                    if not requestValid(checkCx, owner)
                        or checkCx.hosts:current().id ~= owner.host
                        or checkCx.hosts:current().kind ~= "local"
                        or checkCx.sessions:current().id ~= owner.session
                        or checkCx.session:focused() ~= requestedPane
                        or not sourcePane(checkCx, owner.pane) then
                        finish()
                        checkCx:toast("error", "Kiku 助手来源已变化", "未启动 lazygit。")
                        return
                    end
                    local stdout = type(checkResult.stdout) == "string" and checkResult.stdout or ""
                    local inside = not checkResult.timed_out and checkResult.status == 0
                        and stdout:gsub("%s+", "") == "true"
                    if not inside then
                        finish()
                        local reason
                        if checkResult.timed_out then
                            reason = "检查 Git 仓库超时；未打开 lazygit。"
                        else
                            local detail = type(checkResult.stderr) == "string"
                                and checkResult.stderr or ""
                            if detail == "" then detail = stdout end
                            detail = detail:gsub("[\r\n]+", " "):sub(1, 300)
                            if detail:lower():find("not a git repository", 1, true) then
                                detail = ""
                            end
                            reason = "当前目录不是 Git 仓库：" .. owner.cwd
                            if detail ~= "" then reason ..= " · " .. detail end
                        end
                        checkCx:toast("error", "无法打开 lazygit", reason)
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
    startNew()
end


local function open(cx, kind)
    if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
        cx:toast("error", "Kiku 工具仅支持 macOS / Linux 本机。")
        return
    end
    local requestedPane = cx.session:focused()
    local owner, err = ownerFor(cx)
    if not owner or owner.hostKind ~= "local" then
        cx:toast("error", "无法打开工具", err or "当前来源不是本机窗格。")
        return
    end
    local function start(nextCx)
        if not nextCx or not requestValid(nextCx, owner) then return end
        local existing = tools[toolKey(owner, kind)]
        owner.anchor = tiledTarget(nextCx, owner.tab, existing and existing.pane, requestedPane)
        if not owner.anchor then
            nextCx:toast("error", "无法确定工具布局目标", "当前标签页没有可承载工具的普通窗格。")
            return
        end
        openForOwner(nextCx, kind, owner, requestedPane)
    end
    adoptRecords(cx)
    local sourceTool = byPane[requestedPane]
    owner.sourceTool = sourceTool
    if sourceTool and not managedNow(cx, sourceTool) then
        cx:toast("error", "当前工具身份未确认", "未恢复、移动或创建任何工具。")
        return
    end
    start(cx)
end

-- Tern drops a picture-in-picture tool from focus to glance when the window
-- loses focus, so the focused pane is no longer the tool. Fall back to the one
-- visible floating tool of this tab, and refuse to guess between several
-- candidates.
local function leaderTool(cx)
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local direct = focused and byPane[focused]
    if direct or host.kind ~= "local" then return direct, false end
    local tab = focused and cx.session:tab_of(focused)
    if not tab then return nil, false end
    local candidate, ambiguous
    for paneId, tool in pairs(byPane) do
        if tool.host == host.id and tool.session == session.id then
            local pane = cx.session:pane(paneId)
            if pane and (pane.kind == "terminal" or pane.kind == "agent")
                and pane.floating == true
                and pane.tab == tab and pane.parked ~= true and pane.exited == nil then
                if candidate then ambiguous = true; break end
                candidate = tool
            end
        end
    end
    return (not ambiguous) and candidate or nil, ambiguous == true
end

local function hide(cx)
    adoptRecords(cx)
    local tool, ambiguous = leaderTool(cx)
    if not tool then
        if ambiguous then
            cx:toast("error", "工具身份未确认", "当前标签页有多个浮层；请先点击要收起的浮层。")
            return
        end
        cx:toast("error", "工具身份未确认", "未识别当前窗格；未执行收起操作。")
        return
    end
    if not managedNow(cx, tool) then
        cx:toast("error", "工具身份未确认", "保留当前窗格；未执行收起操作。")
        return
    end
    local ok, err = cx.layout:park(tool.pane)
    if not ok then cx:toast("error", "无法收起工具", err); return end
    local returnPane = tool.lastSource
    if returnPane and returnPane ~= tool.pane and sourcePane(cx, returnPane) then
        cx.layout:focus(returnPane)
    end
end

-- The confirmation describes the pane as it is now, not the program the tool
-- was created for: ownership comes from the pane ID alone.
local function describePane(pane)
    local parts = {}
    if type(pane.title) == "string" and pane.title ~= "" then
        table.insert(parts, "标题 " .. pane.title)
    end
    if type(pane.cwd) == "string" and pane.cwd ~= "" then
        table.insert(parts, "目录 " .. pane.cwd)
    end
    if type(pane.running) == "table" and type(pane.running.line) == "string" then
        table.insert(parts, "前台命令 " .. pane.running.line)
    elseif pane.busy == true then
        table.insert(parts, "正在运行前台命令")
    else
        table.insert(parts, "无前台命令")
    end
    return table.concat(parts, " · ")
end

local function endTool(cx)
    adoptRecords(cx)
    local tool, ambiguous = leaderTool(cx)
    if not tool then
        if ambiguous then
            cx:toast("error", "工具身份未确认", "当前标签页有多个浮层；请先点击要结束的浮层。")
            return
        end
        cx:toast("error", "工具身份未确认", "未识别当前窗格；未执行结束操作。")
        return
    end
    if not managedNow(cx, tool) then
        cx:toast("error", "工具身份未确认", "保留当前窗格；未显示结束确认，也未执行结束操作。")
        return
    end
    local detail = describePane(liveTool(cx, tool))
    cx:pick({ placeholder = "确认结束工具？未知或运行中的任务可能一并结束。", items = {
        { label = "取消", id = "cancel", current = true, detail = detail },
        { label = "结束此窗格", id = "end", detail = detail },
    } }):next(function(item, err, nextCx)
        if not nextCx or err or not item or item.id ~= "end" then return end
        if tools[tool.key] ~= tool or byPane[tool.pane] ~= tool then return end
        if not nextCx.session:pane(tool.pane) then removeTool(tool, true); return end
        local closed, closeError = pcall(function() nextCx.layout:close(tool.pane) end)
        if not closed then
            nextCx:toast("error", "无法结束工具", tostring(closeError))
            return
        end
        if not nextCx.session:pane(tool.pane) then removeTool(tool, true) end
    end)
end

local function restore(cx)
    adoptRecords(cx)
    local request, requestError = ownerFor(cx)
    if not request or request.hostKind ~= "local" then
        cx:toast("error", "无法恢复工具", requestError or "当前来源不是本机窗格。")
        return
    end
    local items = {}
    for _, tool in pairs(tools) do
        local pane = liveTool(cx, tool)
        if tool.host == request.host and tool.session == request.session
            and pane and pane.exited == nil and pane.parked == true then
            local kind = tool.kind == "lazygit" and "lazygit" or "终端"
            table.insert(items, { label = "本机 · " .. kind .. " · " .. tool.cwd, tool = tool })
        end
    end
    if #items == 0 then cx:toast("info", "没有可恢复的收起工具。"); return end
    cx:pick({ placeholder = "选择恢复的工具", items = items }):next(function(item, err, pickedCx)
        if not pickedCx or err or not item or not requestValid(pickedCx, request) then return end
        local tool = item.tool
        local destination = request.tab
        for _, tab in ipairs(pickedCx.session:tabs()) do
            if tab.id == tool.originTab and tab.session == tool.session then
                destination = tool.originTab
                break
            end
        end
        local key = tupleKey(destination, tool.cwd, tool.kind)
        local conflict = tools[key]
        if conflict and conflict ~= tool and liveTool(pickedCx, conflict) then
            pickedCx:pick({ placeholder = "该归属已有同类工具", items = {
                { label = "打开现有工具", detail = "所选收起实例保持不变", id = "existing" },
                { label = "取消", id = "cancel", current = true },
            } }):next(function(choice, choiceError, choiceCx)
                if not choiceCx or choiceError or not choice or choice.id ~= "existing"
                    or not requestValid(choiceCx, request) or tools[key] ~= conflict then return end
                conflict.request = request
                focusTool(choiceCx, conflict)
            end)
            return
        end
        local oldKey = tool.key
        if not managedNow(pickedCx, tool) or not requestValid(pickedCx, request) then return end
        local current = liveTool(pickedCx, tool)
        if not current or current.exited ~= nil or current.parked ~= true
            or (tools[key] and tools[key] ~= tool)
            or not tiledTarget(pickedCx, destination, tool.pane, request.pane) then return end
        if key ~= oldKey then
            tools[oldKey] = nil
            tool.key, tool.originTab = key, destination
            tools[key] = tool
        end
        tool.request = request
        displayTool(pickedCx, tool, request)
        persist(tool)
    end)
end

function M.register(config, executableResolver, loadConfigError)
    executables = executableResolver
    configError = loadConfigError
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
    tern.command({ id = "hide_tool", title = "Kiku：收起工具浮窗", group = "Kiku 助手", keys = { config.hideToolKeybinding }, run = hide })
    tern.command({ id = "end_tool", title = "Kiku：结束工具浮窗", group = "Kiku 助手", keys = { config.endToolKeybinding }, run = endTool })
    tern.command({ id = "restore_tools", title = "Kiku：恢复收起的工具", group = "Kiku 助手", run = restore })
    tern.on("pane_closed", function(ev, cx)
        local closed = ev and ev.pane
        if not closed then return end
        local closedTool = byPane[closed]
        if closedTool then
            removeTool(closedTool, true)
            return
        end
        observeTools(cx)
    end)
end

return M

