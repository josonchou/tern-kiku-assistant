local tern = require("tern")
local git = require("./lib/worktree")
local manager = require("./lib/manager")

local config = { defaultPath = "", keybinding = "", manageKeybinding = "" }
local configError
do
    local ok, result = pcall(function()
        local path = tern.plugin.dir .. "/config.json"
        if not tern.fs.exists(path) then return config end
        local value = tern.json.decode(tern.fs.read(path, 65536))
        assert(type(value) == "table", "config.json 必须是 JSON 对象")
        for key, item in pairs(value) do
            assert(key == "defaultPath" or key == "keybinding" or key == "manageKeybinding",
                "未知配置项：" .. tostring(key))
            assert(type(item) == "string", key .. " 必须是字符串")
            config[key] = item
        end
        return config
    end)
    if not ok then configError = tostring(result) end
end

local active
local chooseMode, chooseLocation, promptPath, promptName, chooseBranch, chooseBase, create, manage

local function finish(flow)
    if active == flow then active = nil end
end

local function fail(cx, flow, message)
    finish(flow)
    local title = flow.kind == "manage" and "Kiku：管理未完成" or "Kiku：创建未完成"
    cx:toast("error", title, message)
end

local function guarded(cx, flow, fn)
    if active ~= flow then return end
    local ok, err = pcall(fn)
    if not ok then fail(cx, flow, tostring(err)) end
end

local function pick(cx, flow, opts, callback)
    cx:pick(opts):next(function(item, err, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function()
            if err then fail(nextCx, flow, err)
            elseif not item then finish(flow)
            else callback(nextCx, item) end
        end)
    end)
end

local function prompt(cx, flow, opts, callback)
    cx:prompt(opts):next(function(value, err, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function()
            if err then fail(nextCx, flow, err)
            elseif value == nil then finish(flow)
            else callback(nextCx, value) end
        end)
    end)
end

local function runGit(cx, flow, args, callback)
    local argv = { "git", "-C", flow.root or flow.cwd }
    for _, arg in ipairs(args) do table.insert(argv, arg) end
    tern.process.run(argv, { timeout_ms = 120000 }, function(result, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function() callback(nextCx, result) end)
    end)
end

local function gitError(result)
    local detail = result.stderr ~= "" and result.stderr or result.stdout
    if result.timed_out then detail = "Git 执行超时；请检查 git worktree list 后重试。\n" .. detail end
    if detail == "" then detail = "Git 退出码：" .. tostring(result.status) end
    return detail:sub(1, 3000)
end
local function failOpen(cx, flow, path, message)
    if flow.kind == "create" then
        finish(flow)
        cx:toast("error", "Worktree 已创建，打开标签页失败", path .. "\n" .. message)
    else
        fail(cx, flow, message)
    end
end

local function readGit(cx, flow, args, callback)
    runGit(cx, flow, args, function(nextCx, result)
        if result.status ~= 0 then fail(nextCx, flow, gitError(result))
        else callback(nextCx, result.stdout) end
    end)
end

local function runGitAt(cx, flow, cwd, args, callback)
    local argv = { "git", "-C", cwd }
    for _, arg in ipairs(args) do table.insert(argv, arg) end
    tern.process.run(argv, { timeout_ms = 120000 }, function(result, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function() callback(nextCx, result) end)
    end)
end

local function readGitAt(cx, flow, cwd, args, callback)
    runGitAt(cx, flow, cwd, args, function(nextCx, result)
        if result.status ~= 0 then failOpen(nextCx, flow, flow.path or cwd, gitError(result))
        else callback(nextCx, result.stdout) end
    end)
end

local function readWorktrees(cx, flow, callback)
    readGit(cx, flow, { "worktree", "list", "--porcelain", "-z" }, function(nextCx, output)
        flow.worktrees = git.worktrees(output)
        callback(nextCx)
    end)
end

local function readBranches(cx, flow, callback)
    readGit(cx, flow, {
        "for-each-ref", "--sort=-committerdate", "--format=%(refname)%00%(symref)%00",
        "refs/heads", "refs/remotes",
    }, function(nextCx, output)
        flow.branches = git.branches(output)
        callback(nextCx)
    end)
end

local function recover(cx, flow, message)
    cx:toast("error", "Kiku：请调整后重试", message)
    local items = {
        { label = "修改目标目录…", detail = flow.path or "", id = "path" },
        { label = flow.mode == "local" and "重新选择分支…" or "修改名称…", detail = flow.name or "", id = "name" },
        { label = "重新选择创建方式…", id = "mode" },
        { label = "取消", id = "cancel" },
    }
    pick(cx, flow, { placeholder = "创建未完成 · 已保留输入", items = items }, function(nextCx, item)
        if item.id == "path" then promptPath(nextCx, flow, flow.path or "")
        elseif item.id == "name" then
            if flow.mode == "local" then chooseBranch(nextCx, flow)
            else promptName(nextCx, flow, flow.name or "") end
        elseif item.id == "mode" then chooseMode(nextCx, flow)
        else finish(flow) end
    end)
end

local function collectVisiblePanes(cx, callback)
    local ok, records = pcall(manager.visiblePanes, cx)
    assert(ok, records)
    callback(cx, records)
end

local function worktreeTitle(worktree, flow)
    if worktree.branch then return worktree.branch:gsub("^refs/heads/", "") end
    if worktree.detached then
        local name
        if flow.kind == "create" then
            name = flow.name
        else
            name = worktree.path:match("([^/]+)$")
        end
        return name .. " (detached)"
    end
    return worktree.path:match("([^/]+)$")
end

local function focusWorktree(cx, flow, worktree, candidate)
    local sessionExists = false
    for _, session in ipairs(cx.sessions:list()) do
        if session.id == candidate.sessionId and session.host == flow.hostId then
            sessionExists = true
            break
        end
    end
    if not sessionExists then fail(cx, flow, "目标标签页所属的本机会话已关闭"); return end
    cx.sessions:switch(candidate.sessionId)
    local pane = cx.session:pane(candidate.pane)
    if not pane or pane.tab ~= candidate.tab or not pane.cwd or pane.cwd == "" then
        fail(cx, flow, "目标标签页已变化；请重新选择工作树。")
        return
    end
    runGitAt(cx, flow, pane.cwd, { "rev-parse", "--show-toplevel" }, function(rootCx, rootResult)
        if rootResult.status ~= 0 then
            fail(rootCx, flow, "目标标签页已不在可识别的 Git 工作树中。")
            return
        end
        local paneRoot = git.chomp(rootResult.stdout)
        runGitAt(rootCx, flow, pane.cwd, { "rev-parse", "--path-format=absolute", "--git-common-dir" },
            function(commonCx, commonResult)
                if commonResult.status ~= 0 or not manager.sameWorktree(
                    paneRoot, git.chomp(commonResult.stdout), flow.targetRoot, flow.targetCommonDir
                ) then
                    fail(commonCx, flow, "目标标签页的 Git 工作树身份已变化；请重新选择。")
                    return
                end
                local ok, err = pcall(function() commonCx.layout:focus(candidate.pane) end)
                finish(flow)
                if ok then commonCx:toast("success", "Worktree 已打开", worktree.path)
                else commonCx:toast("error", "Worktree 已登记，切换标签页失败",
                    worktree.path .. "\n" .. tostring(err)) end
            end)
    end)
end

local function openInSourceSession(cx, flow, worktree)
    local ok, err = pcall(function()
        local sourceSession
        for _, session in ipairs(cx.sessions:list()) do
            if session.id == flow.sessionId and session.host == flow.hostId then sourceSession = session; break end
        end
        assert(sourceSession, "来源本机会话已关闭")
        cx.sessions:switch(flow.sessionId)
        assert(cx.hosts:current().id == flow.hostId and cx.hosts:current().kind == "local",
            "来源会话不是原本机环境")
        local tab, launchError = cx.layout:tab({
            name = worktreeTitle(worktree, flow),
            launch = { cwd = worktree.path },
        })
        assert(tab and not launchError, launchError or "Tern 未返回新标签页")
    end)
    finish(flow)
    if ok then cx:toast("success", "Worktree 已打开", worktree.path)
    else cx:toast("error", "Worktree 已登记，打开标签页失败", worktree.path .. "\n" .. tostring(err)) end
end

local function chooseBinding(cx, flow, worktree, candidates)
    local function choose(candidate, choiceCx)
        if flow.action ~= "close" then
            focusWorktree(choiceCx, flow, worktree, candidate)
            return
        end
        local ok, snapshot = pcall(manager.closeSnapshot, choiceCx, candidate, flow.hostId)
        if not ok then fail(choiceCx, flow, tostring(snapshot)); return end
        local function showConfirmation(confirmCx)
            local items = {
                { label = "取消", id = "cancel" },
                {
                    label = "确认关闭 · session " .. tostring(snapshot.session)
                        .. " · tab " .. tostring(snapshot.tab),
                    id = "confirm",
                },
            }
            for _, pane in ipairs(snapshot.panes) do
                local layout = pane.floating and "floating" or "tiled"
                table.insert(items, {
                    label = "查看 pane " .. tostring(pane.pane) .. " · " .. tostring(pane.kind)
                        .. " · " .. layout,
                    detail = pane.path or pane.cwd or "位置未知",
                    id = "pane",
                    pane = pane,
                })
            end
            pick(confirmCx, flow, {
                placeholder = "检查目标环境 · " .. worktree.path,
                items = items,
            }, function(itemCx, item)
                if item.id == "cancel" then
                    finish(flow)
                    return
                end
                if item.id == "pane" then
                    local pane = item.pane
                    local location = pane.path or pane.cwd or "位置未知"
                    local information = table.concat({
                        "位置: " .. tostring(location),
                        "session: " .. tostring(snapshot.session),
                        "tab: " .. tostring(snapshot.tab),
                        "pane: " .. tostring(pane.pane),
                        "类型: " .. tostring(pane.kind),
                        "布局: " .. (pane.floating and "floating" or "tiled"),
                    }, " · ")
                    prompt(itemCx, flow, {
                        placeholder = "仅查看；回车返回确认，Esc取消关闭",
                        value = information,
                        action = "返回确认（仅查看）",
                    }, function(previewCx, _value)
                        showConfirmation(previewCx)
                    end)
                    return
                end
                if item.id ~= "confirm" then
                    finish(flow)
                    return
                end
                local currentOk, current = pcall(manager.closeSnapshot, itemCx, candidate, flow.hostId)
                if not currentOk or not manager.sameCloseSnapshot(snapshot, current) then
                    fail(itemCx, flow, currentOk
                        and "确认期间工作环境或 pane 状态已变化；未关闭任何 pane，请重新检查。"
                        or tostring(current))
                    return
                end
                readWorktrees(itemCx, flow, function(listCx)
                    local registered
                    for _, itemWorktree in ipairs(flow.worktrees) do
                        if itemWorktree.path == worktree.path then registered = itemWorktree; break end
                    end
                    if not registered or registered.head ~= worktree.head or registered.branch ~= worktree.branch
                        or registered.detached ~= worktree.detached or registered.bare ~= worktree.bare
                        or registered.locked ~= worktree.locked or registered.prunable ~= worktree.prunable then
                        fail(listCx, flow, "确认期间目标 worktree 登记、身份或保护状态已变化；未关闭环境。")
                        return
                    end
                    readGitAt(listCx, flow, candidate.cwd, { "rev-parse", "--show-toplevel" },
                        function(rootCx, root)
                            readGitAt(rootCx, flow, candidate.cwd,
                                { "rev-parse", "--path-format=absolute", "--git-common-dir" },
                                function(commonCx, common)
                                    if not manager.sameWorktree(
                                        git.chomp(root), git.chomp(common), flow.targetRoot, flow.targetCommonDir
                                    ) or git.chomp(root) ~= worktree.path then
                                        fail(commonCx, flow, "确认期间目标 Git 身份已变化；未关闭环境。")
                                        return
                                    end
                                    local finalOk, final = pcall(manager.closeSnapshot,
                                        commonCx, candidate, flow.hostId)
                                    if not finalOk or not manager.sameCloseSnapshot(snapshot, final) then
                                        fail(commonCx, flow, finalOk
                                            and "执行前 pane 集合或安全状态已变化；未关闭任何 pane，请重新检查。"
                                            or tostring(final))
                                        return
                                    end
                                    local closeOk, closeErr = pcall(manager.closeEnvironment, commonCx, final)
                                    finish(flow)
                                    if closeOk then
                                        commonCx:toast("success", "工作环境已关闭", worktree.path)
                                    else
                                        commonCx:toast("error", "工作环境部分关闭", tostring(closeErr))
                                    end
                                end)
                        end)
                end)
            end)
        end
        showConfirmation(choiceCx)
    end
    if #candidates == 1 then
        choose(candidates[1], cx)
    elseif #candidates > 1 then
        local items = {}
        for _, candidate in ipairs(candidates) do
            table.insert(items, {
                label = tostring(candidate.sessionName or candidate.sessionId) .. " / "
                    .. (candidate.tabName or "标签页") .. " · tab " .. tostring(candidate.tab),
                detail = candidate.cwd,
                candidate = candidate,
            })
        end
        pick(cx, flow, {
            placeholder = "选择要操作的目标标签页 · " .. worktree.path,
            items = items,
        }, function(pickCx, item) choose(item.candidate, pickCx) end)
    elseif flow.action == "close" then
        fail(cx, flow, "没有可安全识别的绑定标签页；未创建标签页，也未关闭环境。")
    else
        openInSourceSession(cx, flow, worktree)
    end
end

local function discoverBindings(cx, flow, worktree, targetRoot, targetCommonDir)
    collectVisiblePanes(cx, function(nextCx, panes)
        flow.visiblePanes = panes
        local gitRoots = {}
        local function inspect(index, inspectCx)
            if index > #panes then
                local candidates = manager.tabCandidates(
                    panes, targetRoot, targetCommonDir, gitRoots, flow.hostId
                )
                chooseBinding(inspectCx, flow, worktree, candidates)
                return
            end
            local pane = panes[index]
            if pane.hostId ~= flow.hostId or not pane.cwd or pane.cwd == "" then
                inspect(index + 1, inspectCx)
                return
            end
            runGitAt(inspectCx, flow, pane.cwd, { "rev-parse", "--show-toplevel" }, function(rootCx, rootResult)
                if rootResult.status ~= 0 then inspect(index + 1, rootCx); return end
                local paneRoot = git.chomp(rootResult.stdout)
                runGitAt(rootCx, flow, pane.cwd, { "rev-parse", "--path-format=absolute", "--git-common-dir" },
                    function(commonCx, commonResult)
                        if commonResult.status == 0 then
                            gitRoots[pane.pane] = {
                                root = paneRoot,
                                commonDir = git.chomp(commonResult.stdout),
                            }
                        end
                        inspect(index + 1, commonCx)
                    end)
            end)
        end
        inspect(1, nextCx)
    end)
end

local function openWorktree(cx, flow, worktree)
    if worktree.bare then fail(cx, flow, "Bare repository 没有可打开的工作目录：" .. worktree.path); return end
    readGitAt(cx, flow, worktree.path, { "rev-parse", "--show-toplevel" }, function(rootCx, root)
        local targetRoot = git.chomp(root)
        readGitAt(rootCx, flow, worktree.path,
            { "rev-parse", "--path-format=absolute", "--git-common-dir" }, function(commonCx, common)
                local targetCommonDir = git.chomp(common)
                if targetCommonDir ~= flow.commonDir then
                    failOpen(commonCx, flow, worktree.path, "目标工作树属于其他 Git 仓库。")
                    return
                end
                local sourceFound = false
                for _, session in ipairs(commonCx.sessions:list()) do
                    if session.id == flow.sessionId and session.host == flow.hostId then
                        sourceFound = true
                        break
                    end
                end
                if not sourceFound then
                    failOpen(commonCx, flow, worktree.path, "来源本机会话已关闭。")
                    return
                end
                flow.targetRoot, flow.targetCommonDir = targetRoot, targetCommonDir
                discoverBindings(commonCx, flow, worktree, targetRoot, targetCommonDir)
            end)
    end)
end

local function openTab(cx, flow)
    readGitAt(cx, flow, flow.path, { "rev-parse", "--show-toplevel" }, function(rootCx, root)
        local targetRoot = git.chomp(root)
        readGitAt(rootCx, flow, flow.path,
            { "rev-parse", "--path-format=absolute", "--git-common-dir" }, function(commonCx, common)
                local targetCommonDir = git.chomp(common)
                if targetCommonDir ~= flow.commonDir then
                    failOpen(commonCx, flow, flow.path, "创建结果属于其他 Git 仓库。")
                    return
                end
                readWorktrees(commonCx, flow, function(listCx)
                    for _, worktree in ipairs(flow.worktrees) do
                        if worktree.path == targetRoot then
                            openWorktree(listCx, flow, worktree)
                            return
                        end
                    end
                    failOpen(listCx, flow, flow.path, "Git 未登记刚创建的工作树。")
                end)
            end)
    end)
end

create = function(cx, flow, path)
    local resolved, pathError = git.absolute(path, flow.root, tern.getenv("HOME"))
    if not resolved then recover(cx, flow, pathError); return end
    flow.path = resolved
    if tern.fs.exists(flow.path) then
        recover(cx, flow, "目标目录已存在：" .. flow.path)
        return
    end
    -- Re-read occupancy immediately before mutating. Git remains the final race guard.
    readWorktrees(cx, flow, function(nextCx)
        local occupied = git.occupied(flow.worktrees)
        if flow.mode == "local" and occupied["refs/heads/" .. flow.name] then
            recover(nextCx, flow, "分支已在工作树中检出：" .. occupied["refs/heads/" .. flow.name])
            return
        end
        local function add(addCx)
            addCx:toast("info", "正在创建 worktree…", flow.path)
            runGit(addCx, flow, git.addArgs(flow), function(doneCx, result)
                if result.status ~= 0 then recover(doneCx, flow, gitError(result))
                else openTab(doneCx, flow) end
            end)
        end
        if flow.mode == "new" or flow.mode == "remote" then
            runGit(nextCx, flow, { "show-ref", "--verify", "--quiet", "refs/heads/" .. flow.name }, function(checkCx, result)
                if result.status == 0 then
                    recover(checkCx, flow, "本地分支已存在：" .. flow.name .. "。可修改名称，或选择已有分支方式。")
                elseif result.status == 1 then add(checkCx)
                else fail(checkCx, flow, gitError(result)) end
            end)
        else add(nextCx) end
    end)
end

promptPath = function(cx, flow, initial)
    prompt(cx, flow, {
        placeholder = "新 worktree 路径 · 相对来源工作树根目录", value = initial,
        action = "创建并打开",
    }, function(nextCx, value)
        flow.path = value
        create(nextCx, flow, value)
    end)
end

chooseLocation = function(cx, flow)
    readWorktrees(cx, flow, function(nextCx)
        local targets, err = git.targets(flow.worktrees, flow.root, config.defaultPath, flow.name, tern.getenv("HOME"))
        if not targets then fail(nextCx, flow, err); return end
        local items = {}
        for _, target in ipairs(targets) do
            table.insert(items, { label = target, path = target })
        end
        table.insert(items, { label = "其他目录…", id = "other" })
        local description = flow.baseLabel or flow.base
        pick(nextCx, flow, {
            placeholder = "选择 worktree 目录 · " .. description,
            action = "创建并打开", items = items,
        }, function(pickCx, item)
            if item.id == "other" then promptPath(pickCx, flow, flow.path or targets[1])
            else create(pickCx, flow, item.path) end
        end)
    end)
end

promptName = function(cx, flow, initial)
    local label = flow.mode == "detached" and "游离工作树名称" or "新分支名称"
    if flow.mode == "remote" then label = "本地跟踪分支名称 · " .. flow.base end
    prompt(cx, flow, { placeholder = label, value = initial or "", action = "选择目录" }, function(nextCx, value)
        flow.name = git.branchName(value)
        if flow.name == "" or flow.name:sub(1, 1) == "-" or flow.name:find("[%z\r\n]") then
            nextCx:toast("error", "名称无效", "请输入有效的分支名称。")
            promptName(nextCx, flow, value)
            return
        end
        -- Validate as a ref, not Git's --branch shorthand (which accepts @{-1}).
        runGit(nextCx, flow, { "check-ref-format", "refs/heads/" .. flow.name }, function(checkCx, result)
            if result.status ~= 0 then
                checkCx:toast("error", "名称无效", "不能包含 ..、~、^、:、?、*、[、反斜杠等 Git 禁用字符。")
                promptName(checkCx, flow, value)
            else chooseLocation(checkCx, flow) end
        end)
    end)
end

chooseBranch = function(cx, flow)
    readWorktrees(cx, flow, function(nextCx)
        readBranches(nextCx, flow, function(branchCx)
            local occupied = git.occupied(flow.worktrees)
            local items = {}
            for _, branch in ipairs(flow.branches) do
                if not occupied[branch.ref] then
                    table.insert(items, {
                        label = branch.name, group = branch.remote and "远程跟踪分支" or "本地分支",
                        detail = branch.remote and "创建本地跟踪分支" or "检出已有分支",
                        branch = branch,
                    })
                end
            end
            if #items == 0 then
                branchCx:toast("info", "没有可用分支", "已在其他工作树检出的分支不会列出。")
                chooseMode(branchCx, flow)
                return
            end
            pick(branchCx, flow, { placeholder = "选择分支 · 输入筛选", items = items }, function(pickCx, item)
                local branch = item.branch
                flow.path = nil
                if branch.remote then
                    flow.mode, flow.base = "remote", branch.ref
                    promptName(pickCx, flow, branch.localName)
                else
                    flow.mode, flow.name, flow.base = "local", branch.name, branch.name
                    chooseLocation(pickCx, flow)
                end
            end)
        end)
    end)
end

chooseBase = function(cx, flow)
    readBranches(cx, flow, function(nextCx)
        local items = {
            { label = "当前 HEAD", detail = flow.sourceBranch .. " @ " .. flow.head:sub(1, 8), id = "head" },
        }
        for _, branch in ipairs(flow.branches) do
            table.insert(items, {
                label = branch.name, group = branch.remote and "远程跟踪分支" or "本地分支",
                detail = "仅作为创建起点 · " .. branch.ref, branch = branch,
            })
        end
        pick(nextCx, flow, { placeholder = "选择创建基准 · 输入筛选", items = items }, function(pickCx, item)
            local function selected(baseCx, oid, label)
                flow.base = oid
                flow.baseLabel = label .. " @ " .. oid:sub(1, 8)
                local initial = ""
                if flow.mode == "detached" then
                    if flow.sourceBranch ~= "HEAD" then initial = flow.sourceBranch
                    else initial = "detached-" .. flow.head:sub(1, 8) end
                end
                promptName(baseCx, flow, initial)
            end
            if item.id == "head" then selected(pickCx, flow.head, flow.sourceBranch)
            else
                readGit(pickCx, flow, { "rev-parse", "--verify", item.branch.ref .. "^{commit}" }, function(baseCx, output)
                    selected(baseCx, git.chomp(output), item.branch.name)
                end)
            end
        end)
    end)
end

chooseMode = function(cx, flow)
    pick(cx, flow, {
        placeholder = "新建 worktree · " .. flow.sourceBranch,
        items = {
            { label = "新分支 + worktree", detail = "选择 HEAD / 本地 / 远程分支作为起点", id = "new" },
            { label = "已有分支 + worktree", detail = "本地 / 远程跟踪分支", id = "local" },
            { label = "Detached worktree", detail = "选择创建起点，不创建分支", id = "detached" },
        },
    }, function(nextCx, item)
        flow.mode, flow.path, flow.base, flow.baseLabel = item.id, nil, nil, nil
        if item.id == "local" then chooseBranch(nextCx, flow)
        else chooseBase(nextCx, flow) end
    end)
end

local function start(cx)
    if active then cx:toast("info", "Kiku 工作树流程正在进行", "请完成或按 Esc 取消当前选择。 "); return end
    if configError then cx:toast("error", "Kiku 配置错误", configError); return end
    if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
        cx:toast("error", "Kiku 首版支持 macOS / Linux 本机仓库"); return
    end
    local host = cx.hosts:current()
    if host.kind ~= "local" then
        cx:toast("error", "Kiku 首版仅支持本机仓库", "请切换到本机终端后使用。 "); return
    end
    local focused = cx.session:focused()
    local pane = focused and cx.session:pane(focused)
    if not pane or not pane.cwd or pane.cwd == "" then
        cx:toast("error", "无法确定当前项目目录", "请聚焦已报告工作目录的终端。 "); return
    end
    local flow = {
        kind = "create", cwd = pane.cwd, sessionId = cx.sessions:current().id,
        hostId = host.id,
    }
    active = flow
    guarded(cx, flow, function()
        readGit(cx, flow, { "rev-parse", "--show-toplevel" }, function(rootCx, root)
            flow.root = git.chomp(root)
            readGit(rootCx, flow, { "rev-parse", "--path-format=absolute", "--git-common-dir" },
                function(commonCx, common)
                    flow.commonDir = git.chomp(common)
                    readGit(commonCx, flow, { "rev-parse", "--verify", "HEAD^{commit}" }, function(headCx, head)
                        flow.head = git.chomp(head)
                        runGit(headCx, flow, { "symbolic-ref", "--quiet", "--short", "HEAD" },
                            function(branchCx, result)
                                if result.status ~= 0 and result.status ~= 1 then fail(branchCx, flow, gitError(result)); return end
                                flow.sourceBranch = result.status == 0 and git.chomp(result.stdout) or "HEAD"
                                chooseMode(branchCx, flow)
                            end)
                    end)
                end)
        end)
    end)
end

manage = function(cx)
    if active then cx:toast("info", "Kiku 工作树流程正在进行", "请完成或按 Esc 取消当前选择。 "); return end
    if configError then cx:toast("error", "Kiku 配置错误", configError); return end
    if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
        cx:toast("error", "Kiku 首版支持 macOS / Linux 本机仓库"); return
    end
    local host = cx.hosts:current()
    if host.kind ~= "local" then
        cx:toast("error", "Kiku 首版仅支持本机仓库", "请切换到本机终端后使用。 "); return
    end
    local focused = cx.session:focused()
    local pane = focused and cx.session:pane(focused)
    if not pane or not pane.cwd or pane.cwd == "" then
        cx:toast("error", "无法确定当前项目目录", "请聚焦已报告工作目录的终端。 "); return
    end
    local flow = {
        kind = "manage", cwd = pane.cwd, sessionId = cx.sessions:current().id,
        hostId = host.id,
    }
    active = flow
    guarded(cx, flow, function()
        readGit(cx, flow, { "rev-parse", "--show-toplevel" }, function(rootCx, root)
            flow.root = git.chomp(root)
            readGit(rootCx, flow, { "rev-parse", "--path-format=absolute", "--git-common-dir" },
                function(commonCx, common)
                    flow.commonDir = git.chomp(common)
                    readWorktrees(commonCx, flow, function(listCx)
                        local items = {}
                        for _, worktree in ipairs(flow.worktrees) do
                            local name
                            if worktree.branch then
                                name = worktree.branch:gsub("^refs/heads/", "")
                            elseif worktree.detached then
                                name = "Detached"
                            else
                                name = "Bare"
                            end
                            local head = worktree.head
                            if not head then head = "no HEAD" end
                            local detail = name .. " · " .. head
                            table.insert(items, {
                                label = manager.worktreeLabel(worktree),
                                detail = detail,
                                worktree = worktree,
                            })
                        end
                        if #items == 0 then
                            fail(listCx, flow, "当前仓库没有 Git 登记的工作树。")
                            return
                        end
                        pick(listCx, flow, {
                            placeholder = "选择 Git worktree · 输入筛选路径",
                            items = items,
                        }, function(selectCx, item)
                            flow.selectedWorktree = item.worktree
                            pick(selectCx, flow, {
                                placeholder = "选择操作 · " .. item.worktree.path,
                                items = {
                                    { label = "打开／切换", id = "open" },
                                    { label = "关闭工作环境", id = "close" },
                                },
                            }, function(actionCx, action)
                                flow.action = action.id
                                readWorktrees(actionCx, flow, function(refreshCx)
                                    local current
                                    for _, worktree in ipairs(flow.worktrees) do
                                        if worktree.path == flow.selectedWorktree.path then
                                            current = worktree
                                            break
                                        end
                                    end
                                    local selected = flow.selectedWorktree
                                    if not current or current.head ~= selected.head
                                        or current.branch ~= selected.branch or current.detached ~= selected.detached
                                        or current.bare ~= selected.bare then
                                        fail(refreshCx, flow, "所选工作树登记或身份已变化；请重新选择。")
                                        return
                                    end
                                    openWorktree(refreshCx, flow, current)
                                end)
                            end)
                        end)
                    end)
                end)
        end)
    end)
end

local defaultKey = "ctrl+b>shift+g"
tern.command({
    id = "create_worktree", title = "Kiku: 新建 Git worktree", group = "Kiku Worktrees",
    keys = { config.keybinding ~= "" and config.keybinding or defaultKey }, run = start,
})
tern.command({
    id = "manage_worktrees", title = "Kiku: 管理 Git worktree", group = "Kiku Worktrees",
    keys = config.manageKeybinding ~= "" and { config.manageKeybinding } or {}, run = manage,
})
