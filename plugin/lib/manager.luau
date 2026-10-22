local tern = require("tern")
local jsonNull = tern.json.null
local M = {}


-- Tern's session pane/tab APIs expose all sessions at once. Session comes from
-- TabInfo.session; host comes from ManagedHost.panes. A parked pane has no tab
-- and therefore no provable session, but its host association is still kept.
function M.visiblePanes(cx)
    local tabSessions, tabNames, sessionNames, sessionHosts, paneHosts = {}, {}, {}, {}, {}
    for _, session in ipairs(cx.sessions:list()) do
        sessionNames[session.id] = session.name
        sessionHosts[session.id] = session.host
    end
    for _, tab in ipairs(cx.session:tabs()) do
        tabSessions[tab.id] = tab.session
        tabNames[tab.id] = tab.name or tab.title
    end
    for _, host in ipairs(cx.hosts:list()) do
        for _, paneId in ipairs(host.panes) do
            local previous = paneHosts[paneId]
            if previous and previous.id ~= host.id then
                paneHosts[paneId] = false
            elseif previous ~= false then
                paneHosts[paneId] = { id = host.id, kind = host.kind }
            end
        end
    end
    return M.paneRecords(cx.session:panes(), paneHosts, tabSessions, tabNames, sessionNames, sessionHosts)
end

function M.paneRecords(panes, paneHosts, tabSessions, tabNames, sessionNames, sessionHosts)
    local result = {}
    for _, pane in ipairs(panes) do
        local host = paneHosts[pane.pane]
        local hostId, hostKind = nil, "unknown"
        if host and host ~= false then
            hostId, hostKind = host.id, host.kind
        end
        local sessionId
        if pane.tab then sessionId = tabSessions[pane.tab] end
        table.insert(result, {
            pane = pane.pane,
            path = pane.path,
            cwd = pane.cwd,
            url = pane.url,
            kind = pane.kind,
            tab = pane.tab,
            floating = pane.floating,
            parked = pane.parked,
            busy = pane.busy,
            at_prompt = pane.at_prompt,
            running = pane.running,
            error = pane.error,
            alert = pane.alert,
            sessionId = sessionId,
            sessionHost = sessionId and sessionHosts[sessionId] or nil,
            last = pane.last,
            sessionName = sessionId and sessionNames[sessionId] or nil,
            hostId = hostId,
            hostKind = hostKind,
            tabName = pane.tab and tabNames[pane.tab] or nil,
        })
    end
    return result
end

function M.sameWorktree(leftRoot, leftCommonDir, rightRoot, rightCommonDir)
    return leftRoot == rightRoot and leftCommonDir == rightCommonDir
end

function M.tabCandidates(panes, targetRoot, targetCommonDir, gitRoots, hostId)
    local candidates, seen = {}, {}
    for _, pane in ipairs(panes) do
        local identity = gitRoots[pane.pane]
        if pane.hostId == hostId and pane.sessionHost == hostId and pane.sessionId and pane.tab and identity
            and M.sameWorktree(identity.root, identity.commonDir, targetRoot, targetCommonDir) then
            local key = tostring(pane.sessionId) .. ":" .. tostring(pane.tab)
            if not seen[key] then
                seen[key] = true
                table.insert(candidates, {
                    sessionId = pane.sessionId,
                    sessionName = pane.sessionName,
                    tab = pane.tab,
                    tabName = pane.tabName,
                    pane = pane.pane,
                    cwd = pane.cwd,
                })
            end
        end
    end
    return candidates
end

function M.worktreeLabel(worktree)
    local name
    if worktree.branch then
        name = worktree.branch:gsub("^refs/heads/", "")
    elseif worktree.detached then
        name = "Detached"
    else
        name = "Bare repository"
    end
    local summary = name
    if worktree.head then summary ..= " · HEAD " .. worktree.head:sub(1, 8) end
    local flags = {}
    if worktree.locked then
        table.insert(flags, "LOCKED" .. (worktree.lockReason ~= "" and (": " .. worktree.lockReason) or ""))
    end
    if worktree.prunable then
        table.insert(flags, "PRUNABLE" .. (worktree.prunableReason ~= "" and (": " .. worktree.prunableReason) or ""))
    end
    if #flags > 0 then summary ..= " · " .. table.concat(flags, " · ") end
    -- Keep the complete path filterable, after safety-critical facts.
    return summary .. " · " .. worktree.path
end

-- 安全拒绝直接展示给用户，不附加会挤占原生提示空间的源码前缀。
local function requireSafe(condition, message)
    if not condition then error(message, 0) end
end

-- Closing is permissioned by the complete tab, never just its binding pane.
-- All reads and raw closes are synchronous in the final window callback.
function M.closeSnapshot(cx, candidate, hostId)
    local session, tab
    for _, item in ipairs(cx.sessions:list()) do
        if item.id == candidate.sessionId then session = item end
    end
    requireSafe(session and session.host == hostId and session.locked == false,
        "目标会话已锁定或归属不明；请手动检查会话。")
    for _, item in ipairs(cx.session:tabs()) do
        if item.id == candidate.tab then tab = item end
    end
    requireSafe(tab and tab.session == session.id, "目标标签页归属已变化；请重新选择。")
    local panes = {}
    local bindingFound = false
    local tiledCount = 0
    for _, pane in ipairs(M.visiblePanes(cx)) do
        if pane.tab == candidate.tab then
            requireSafe(type(pane.floating) == "boolean", "目标 pane 浮动状态不明；请手动处理。")
            if not pane.floating then tiledCount += 1 end
            requireSafe(pane.sessionId == session.id and pane.sessionHost == hostId
                and pane.hostId == hostId and pane.hostKind == "local" and pane.parked == false,
                "目标 pane 的会话或主机归属不明；请手动处理。")
            requireSafe(not pane.error and pane.alert == false, "目标 pane 存在错误或未读告警；请手动处理。")
            local state = ""
            if pane.kind == "terminal" or pane.kind == "agent" then
                requireSafe(pane.busy == false and pane.at_prompt == true and pane.running == nil,
                    "终端或 agent 未明确空闲；请等待命令结束并返回提示符。")
                local last = pane.last or {}
                state = table.concat({
                    tostring(pane.busy), tostring(pane.at_prompt),
                    tostring(pane.running and pane.running.line), tostring(pane.running and pane.running.ms),
                    tostring(last.line), tostring(last.status), tostring(last.took_ms),
                }, ":")
            elseif pane.kind == "file" then
                local read = cx.session:read(pane.pane, { lines = 1 })
                requireSafe(type(read) == "table" and read.kind == "file"
                    and read.info and read.info.pane == pane.pane and read.info.tab == candidate.tab
                    and read.dirty == false and read.load == "ready"
                    and type(read.path) == "string" and read.path ~= "",
                    "文件未加载完成、归属不明或有未保存内容；请先保存并检查。")
                state = table.concat({
                    read.path, tostring(read.mode), tostring(read.size),
                }, ":")
            elseif pane.kind == "notebook" then
                local read = cx.session:read(pane.pane, { rows = 1 })
                requireSafe(type(read) == "table" and read.kind == "notebook"
                    and read.info and read.info.pane == pane.pane and read.info.tab == candidate.tab
                    and read.dirty == false and read.phase == "ready",
                    "Notebook 未就绪、归属不明或有未保存内容；请先保存并检查。")
                local kernel = cx.notebook:kernel_status(pane.pane)
                requireSafe((kernel.status == "idle" or kernel.status == "not_started")
                    and kernel.running == 0 and kernel.waiting == 0
                    and (kernel.input == nil or kernel.input == jsonNull)
                    and (kernel.dead == nil or kernel.dead == jsonNull),
                    "Notebook kernel 正在运行、等待输入或状态不明；请手动处理。")
                state = tostring(read.path) .. ":" .. kernel.status .. ":"
                    .. tostring(kernel.running) .. ":" .. tostring(kernel.waiting)
                for _, cell in ipairs(cx.notebook:cells(pane.pane)) do
                    state = state .. ":" .. tostring(cell.id) .. ":" .. cell.state
                    requireSafe(cell.state == "idle", "Notebook 仍有运行或排队的 cell；请等待完成。")
                end
            else
                error("无法确认 " .. tostring(pane.kind) .. " pane 的运行和保存状态；请手动关闭。", 0)
            end
            table.insert(panes, {
                pane = pane.pane, cwd = pane.cwd, path = pane.path, kind = pane.kind,
                floating = pane.floating, state = state,
            })
            if pane.pane == candidate.pane then
                requireSafe(candidate.cwd and pane.cwd == candidate.cwd, "绑定 pane 目录已变化；请重新选择。")
                bindingFound = true
            end
        end
    end
    requireSafe(bindingFound and #panes > 0 and tiledCount == tab.panes,
        "目标 pane 集合不完整或绑定已变化；请重新选择。")
    table.sort(panes, function(a, b)
        if a.floating ~= b.floating then return a.floating == true end
        return a.pane < b.pane
    end)
    return { tab = tab.id, session = session.id, host = hostId, panes = panes }
end

function M.sameCloseSnapshot(before, after)
    if before.tab ~= after.tab or before.session ~= after.session or before.host ~= after.host
        or #before.panes ~= #after.panes then return false end
    for index, pane in ipairs(before.panes) do
        local other = after.panes[index]
        if pane.pane ~= other.pane or pane.cwd ~= other.cwd or pane.path ~= other.path
            or pane.kind ~= other.kind or pane.floating ~= other.floating or pane.state ~= other.state then
            return false
        end
    end
    return true
end

function M.closeEnvironment(cx, snapshot)
    local closed = {}
    for _, pane in ipairs(snapshot.panes) do
        local ok, err = pcall(function() cx.layout:close(pane.pane) end)
        requireSafe(ok, "关闭部分失败；已关闭 pane：" .. table.concat(closed, ", ")
            .. "；失败 pane：" .. tostring(pane.pane)
            .. "；其余 pane 未继续操作，请手动检查现场。\n" .. tostring(err))
        requireSafe(cx.session:pane(pane.pane) == nil,
            "Tern 未确认 pane 已关闭；此前已关闭 pane：" .. table.concat(closed, ", ")
                .. "；状态未确认 pane：" .. tostring(pane.pane)
                .. "；已停止后续关闭，请手动检查现场。")
        table.insert(closed, tostring(pane.pane))
    end
end

return M
