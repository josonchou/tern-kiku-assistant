-- Window-visible worktree bindings shared by management and later safety flows.
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
            cwd = pane.cwd,
            kind = pane.kind,
            tab = pane.tab,
            floating = pane.floating,
            parked = pane.parked,
            busy = pane.busy,
            at_prompt = pane.at_prompt,
            running = pane.running,
            error = pane.error,
            sessionId = sessionId,
            sessionHost = sessionId and sessionHosts[sessionId] or nil,
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
        local head = worktree.head
        if not head then head = "unknown" end
        name = "Detached @ " .. head:sub(1, 8)
    else
        name = "Bare repository"
    end
    local flags = {}
    if worktree.locked then table.insert(flags, "locked" .. (worktree.lockReason ~= "" and (": " .. worktree.lockReason) or "")) end
    if worktree.prunable then table.insert(flags, "prunable" .. (worktree.prunableReason ~= "" and (": " .. worktree.prunableReason) or "")) end
    if #flags > 0 then name ..= " · " .. table.concat(flags, " · ") end
    -- Tern filters only the label, so keep the complete path searchable here.
    return worktree.path .. " · " .. name
end

return M
