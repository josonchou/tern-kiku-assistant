-- Only the Tern SDK boundary is replaced; production identity and tool logic run unchanged.
local state = {
    runtime = { os = "linux" }, plugin = { data = "/virtual/plugin-data" },
    commands = {}, events = {}, panes = {}, tabs = {}, layouts = {}, focus = 1,
    runCallbacks = {}, samples = 0, nextPane = 30, nextPid = 100, nextToken = 0,
    processByPid = {}, processCallbacks = {}, pickChoices = {}, identityFiles = {}, timers = {},
    deferProcess = false, deferPromises = false, promiseCallbacks = {}, currentSession = 9,
    processInvalid = false, splitMode = nil, shellProgram = "/bin/zsh", css = {},
    isGitRepo = true, repoChecks = 0,
    directories = {}, existingPaths = {},
    env = { PATH = "/usr/bin:/bin", SHELL = "/bin/zsh" },
    loginPath = nil, loginProbes = 0,
    deferParentFind = false, parentCallbacks = {},
}
local cx = {}
state.cx = cx
local function promise(value, err)
    return { next = function(_, callback)
        if state.deferPromises then
            table.insert(state.promiseCallbacks, function() callback(value, err, cx) end)
        else
            callback(value, err, cx)
        end
    end }
end
function state.flushProcess()
    local queued = state.processCallbacks
    state.processCallbacks = {}
    for _, run in ipairs(queued) do run() end
end
function state.flushPromises()
    local queued = state.promiseCallbacks
    state.promiseCallbacks = {}
    for _, run in ipairs(queued) do run() end
end
function state.flushParentFind()
    local queued = state.parentCallbacks
    state.parentCallbacks = {}
    for _, run in ipairs(queued) do run() end
end
function state.tick()
    local queued = state.timers
    state.timers = {}
    for _, timer in ipairs(queued) do
        if not timer.cancelled then timer.callback(cx) end
    end
end
function state.addPane(id, pane)
    pane.title = pane.title or "terminal"
    pane.kind = pane.kind or "terminal"
    pane.cwd = pane.cwd or "/work/project"
    pane.tab = pane.tab or 11
    state.panes[id] = pane
end
local function firstLeaf(tree)
    if not tree then return nil end
    return tree.pane or firstLeaf(tree[1]) or firstLeaf(tree[2])
end
local function removeLeaf(tree, pane)
    if not tree then return nil end
    if tree.pane then
        if tree.pane == pane then return nil end
        return tree
    end
    tree[1], tree[2] = removeLeaf(tree[1], pane), removeLeaf(tree[2], pane)
    if not tree[1] then return tree[2] end
    if not tree[2] then return tree[1] end
    return tree
end
local function detach(pane)
    for _, layout in pairs(state.layouts) do
        layout.root = removeLeaf(layout.root, pane)
        for index = #layout.floats, 1, -1 do
            if layout.floats[index].pane == pane then table.remove(layout.floats, index) end
        end
    end
end
local function insertLeaf(tree, pane, target, direction)
    if not tree then return nil, false end
    if tree.pane == target then
        local added, old = { pane = pane }, tree
        local first, second = old, added
        if direction == "left" or direction == "up" then first, second = added, old end
        local split = "right"
        if direction == "down" or direction == "up" then split = "down" end
        return { split = split, [1] = first, [2] = second }, true
    end
    if tree.pane then return tree, false end
    local changed
    tree[1], changed = insertLeaf(tree[1], pane, target, direction)
    if not changed then tree[2], changed = insertLeaf(tree[2], pane, target, direction) end
    return tree, changed
end
local function targetPane(target)
    local pane = state.panes[target]
    if pane and pane.tab and not pane.floating and not pane.parked then return pane end
    return nil
end
local function tile(pane, target, direction)
    local current, owner = state.panes[pane], targetPane(target)
    if not current or not owner or pane == target then return false end
    local layout = state.layouts[owner.tab]
    if not layout then return false end
    detach(pane)
    local inserted
    layout.root, inserted = insertLeaf(layout.root, pane, target, direction)
    assert(inserted, "SDK fixture target is absent from the split tree")
    current.tab, current.floating, current.parked = owner.tab, false, false
    return true
end
local function reveal(pane, options)
    if not options or options.focus ~= false then state.focus = pane end
end
local function processResult(argv)
    local stdout, stderr, status = "", "", 0
    local function argument(name)
        for _, value in ipairs(argv) do
            if value == name then return true end
        end
        return false
    end
    if argv[1] == "/usr/bin/od" then
        state.nextToken += 1
        stdout = string.format("%032x", state.nextToken)
    elseif argv[2] == "-l" and argv[3] == "-c" and tostring(argv[4]):find("KIKU_LOGIN_PATH:", 1, true) then
        state.loginProbes += 1
        stdout = "KIKU_LOGIN_PATH:" .. (state.loginPath or state.env.PATH) .. "\n"
    elseif argument("--is-inside-work-tree") then
        state.repoChecks += 1
        if state.isGitRepo then
            stdout = "true\n"
        else
            status, stderr = 128, "fatal: not a git repository (or any of the parent directories)\n"
        end
    end
    return { status = status, timed_out = false, stdout = stdout, stderr = stderr }
end
local tern = {
    runtime = state.runtime, plugin = state.plugin,
    getenv = function(name) return state.env[name] end,
    command = function(spec) state.commands[spec.id] = spec end,
    css = function(name, source) state.css[name] = source end,
    on = function(name, callback) state.events[name] = callback end,
    timer = function(_, callback)
        local timer = { callback = callback, cancelled = false }
        function timer:cancel() self.cancelled = true end
        table.insert(state.timers, timer)
        return timer
    end,
    json = { encode = function(value) return value end, decode = function(value) return value end },
    fs = {
        mkdir = function(path) state.directories[path] = true end,
        write = function(path, value) state.identityFiles[path] = value end,
        exists = function(path)
            return state.identityFiles[path] ~= nil or state.directories[path] == true
                or state.existingPaths[path] == true
        end,
        list = function(path)
            local names, prefix = {}, path .. "/"
            for file in pairs(state.identityFiles) do
                local name = file:sub(1, #prefix) == prefix and file:sub(#prefix + 1)
                if name and not name:find("/") then table.insert(names, name) end
            end
            return names
        end,
        read = function(path)
            local value = state.identityFiles[path]
            if value == nil then error("missing " .. path) end
            return value
        end,
        remove = function(path)
            state.identityFiles[path], state.directories[path] = nil, nil
            local prefix = path .. "/"
            for file in pairs(state.identityFiles) do
                if file:sub(1, #prefix) == prefix then state.identityFiles[file] = nil end
            end
            for directory in pairs(state.directories) do
                if directory:sub(1, #prefix) == prefix then state.directories[directory] = nil end
            end
        end,
    },
    process = { run = function(argv, _, callback)
        local run = function() callback(processResult(argv), cx) end
        if state.deferProcess then table.insert(state.processCallbacks, run) else run() end
    end },
}
cx.hosts = { current = function() return { id = 7, kind = "local" } end }
cx.sessions = { current = function() return { id = state.currentSession } end }
cx.session = {
    focused = function() return state.focus end,
    pane = function(_, id) return state.panes[id] end,
    tab_of = function(_, id) local pane = state.panes[id]; return pane and pane.tab end,
    panes = function()
        local result = {}
        for id, pane in pairs(state.panes) do
            table.insert(result, {
                pane = id, cwd = pane.cwd, kind = pane.kind, title = pane.title, tab = pane.tab,
                floating = pane.floating == true, parked = pane.parked == true, focused = state.focus == id,
                busy = pane.busy == true, at_prompt = pane.at_prompt == true, running = pane.running,
                exited = pane.exited,
            })
        end
        return result
    end,
    tabs = function() return state.tabs end,
    layout = function(_, tab) return state.layouts[tab] end,
    settle = function() return promise("", nil) end,
}
cx.procs = {
    list = function(_, options)
        state.samples += 1
        local processes = { { pid = 100, started = 50 } }
        for _, process in pairs(state.processByPid) do table.insert(processes, table.clone(process)) end
        local total = #processes
        while #processes > (options.limit or total) do table.remove(processes) end
        local more = total - #processes
        if state.inventoryIncomplete and options.limit > 1 then more += 1 end
        return promise({ sample = state.samples, ["local"] = true, more = more, processes = processes })
    end,
    find = function(_, pid)
        if pid == 100 then
            if state.deferParentFind then
                return { next = function(_, callback)
                    table.insert(state.parentCallbacks, function() callback({ pid = 100, started = 50 }, nil, cx) end)
                end }
            end
            return promise({ pid = 100, started = 50 })
        end
        local process = state.processByPid[pid]
        return promise(process and table.clone(process))
    end,
    children = function(_, parent)
        state.samples += 1
        local processes = {}
        for _, process in pairs(state.processByPid) do
            if process.parent == parent then table.insert(processes, table.clone(process)) end
        end
        return promise({ sample = state.samples, ["local"] = true, more = 0, processes = processes })
    end,
}
cx.layout = {
    split = function(_, target, direction, launch, options)
        if state.splitMode == "return_nil" then return nil end
        if state.splitMode == "throw_before_create" then error("split rejected") end
        local owner = assert(targetPane(target), "split target must be tiled")
        local requested = (launch and launch.cwd) or owner.cwd
        -- The host half runs the production spawn filter; only then does the
        -- shell start. A claimed launch records its first PID before exec.
        local spec = { program = state.shellProgram, args = { "-l" }, cwd = requested }
        local modified = (state.identity and state.identity.spawn(spec)) or spec
        state.nextPane += 1
        local pane = state.nextPane
        state.addPane(pane, { cwd = modified.cwd, tab = owner.tab, at_prompt = true, busy = false })
        if modified.args[1] ~= "-l"
            and state.identityFiles[requested .. "/error"] == nil then
            state.nextPid += 1
            if not state.processInvalid then
                state.processByPid[state.nextPid] = {
                    pid = state.nextPid, started = state.nextPid + 1000, parent = 100,
                }
            end
            state.identityFiles[requested .. "/pid"] = tostring(state.nextPid)
            state.panes[pane].shellPid = state.nextPid
        end
        assert(tile(pane, target, direction))
        reveal(pane, options)
        if state.splitMode == "throw_after_create" then error("split result unavailable") end
        return pane
    end,
    float = function(_, pane, over, corner, options)
        local current, owner = state.panes[pane], targetPane(over)
        if not current or not owner or pane == over then return false, "invalid float owner" end
        detach(pane)
        current.tab, current.floating, current.parked = owner.tab, true, false
        table.insert(state.layouts[owner.tab].floats, { pane = pane, over = over, corner = corner })
        reveal(pane, options)
        return true
    end,
    dock = function(_, pane, target, direction, options)
        if not tile(pane, target, direction) then return false, "invalid dock target" end
        reveal(pane, options)
        return true
    end,
    move = function(_, pane, target, direction, options)
        if not tile(pane, target, direction) then return false end
        reveal(pane, options)
        return true
    end,
    move_to_tab = function(_, pane, tab, options)
        local layout = state.layouts[tab]
        local target = layout and firstLeaf(layout.root)
        if not target or not tile(pane, target, "right") then return false, "invalid destination tab" end
        reveal(pane, options)
        return true
    end,
    park = function(_, pane)
        local current = state.panes[pane]
        local oldTab = current.tab
        detach(pane)
        current.parked, current.floating, current.tab = true, false, nil
        if state.focus == pane then state.focus = firstLeaf(state.layouts[oldTab].root) end
        return true
    end,
    unpark = function(_, pane, options)
        local focused = state.panes[state.focus]
        local layout = focused and state.layouts[focused.tab]
        local target = layout and firstLeaf(layout.root)
        if not target or not tile(pane, target, "right") then return false, "no current tiled pane" end
        reveal(pane, options)
        return true
    end,
    focus = function(_, pane) state.focus = pane end,
    close = function(_, pane)
        local current = state.panes[pane]
        detach(pane)
        if current and current.shellPid then state.processByPid[current.shellPid] = nil end
        state.panes[pane] = nil
    end,
}
cx.run = function(_, pane, text)
    table.insert(state.runCallbacks, { pane = pane, text = text })
    local current = state.panes[pane]
    if current then current.exited = nil end
end
cx.toast = function(_, level, title, detail)
    state.toasts = state.toasts or {}
    table.insert(state.toasts, { level = level, title = title, detail = detail })
end
cx.pick = function(_, options)
    state.lastPick = options
    local choice = table.remove(state.pickChoices, 1)
    if choice == nil and state.pickHandler then choice = state.pickHandler(options) end
    return promise(choice, nil)
end
return { tern = tern, state = state, cx = cx }
