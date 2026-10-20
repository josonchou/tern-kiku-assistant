local tern = require("tern")
local git = require("./lib/worktree")

local config = { defaultPath = "", keybinding = "" }
local configError
do
    local ok, result = pcall(function()
        local path = tern.plugin.dir .. "/config.json"
        if not tern.fs.exists(path) then return config end
        local value = tern.json.decode(tern.fs.read(path, 65536))
        assert(type(value) == "table", "config.json 必须是 JSON 对象")
        for key, item in pairs(value) do
            assert(key == "defaultPath" or key == "keybinding", "未知配置项：" .. tostring(key))
            assert(type(item) == "string", key .. " 必须是字符串")
            config[key] = item
        end
        return config
    end)
    if not ok then configError = tostring(result) end
end

-- Each window owns one flow. Never retain a WindowCx across asynchronous calls.
local active
local chooseMode, chooseLocation, promptPath, promptName, chooseBranch, chooseBase, create

local function finish(flow)
    if active == flow then active = nil end
end

local function fail(cx, flow, message)
    finish(flow)
    cx:toast("error", "Kiku：创建未完成", message)
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

local function readGit(cx, flow, args, callback)
    runGit(cx, flow, args, function(nextCx, result)
        if result.status ~= 0 then fail(nextCx, flow, gitError(result))
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

local function openTab(cx, flow)
    -- A user may switch sessions while Git checks out files. Open in the source
    -- local session, never in whichever remote session happens to be selected.
    local ok, err = pcall(function()
        local found = false
        for _, session in ipairs(cx.sessions:list()) do
            if session.id == flow.sessionId then found = true; break end
        end
        assert(found, "来源会话已关闭")
        cx.sessions:switch(flow.sessionId)
        assert(cx.hosts:current().kind == "local", "来源会话不是本机会话")
        local title = flow.mode == "detached" and (flow.name .. " (detached)") or flow.name
        local tab, launchError = cx.layout:tab({ name = title, launch = { cwd = flow.path } })
        assert(tab and not launchError, launchError or "Tern 未返回新标签页")
    end)
    finish(flow)
    if ok then cx:toast("success", "Worktree 已创建", flow.path)
    else cx:toast("error", "Worktree 已创建，打开标签页失败", flow.path .. "\n" .. tostring(err)) end
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
    if active then cx:toast("info", "Kiku 创建流程正在进行", "请完成或按 Esc 取消当前选择。 "); return end
    if configError then cx:toast("error", "Kiku 配置错误", configError); return end
    if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
        cx:toast("error", "Kiku 首版支持 macOS / Linux 本机仓库"); return
    end
    if cx.hosts:current().kind ~= "local" then
        cx:toast("error", "Kiku 首版仅支持本机仓库", "请切换到本机终端后使用。 "); return
    end
    local focused = cx.session:focused()
    local pane = focused and cx.session:pane(focused)
    if not pane or not pane.cwd or pane.cwd == "" then
        cx:toast("error", "无法确定当前项目目录", "请聚焦已报告工作目录的终端。 "); return
    end
    local flow = { cwd = pane.cwd, sessionId = cx.sessions:current().id }
    active = flow
    guarded(cx, flow, function()
        readGit(cx, flow, { "rev-parse", "--show-toplevel" }, function(rootCx, root)
            flow.root = git.chomp(root)
            readGit(rootCx, flow, { "rev-parse", "--verify", "HEAD^{commit}" }, function(headCx, head)
                flow.head = git.chomp(head)
                runGit(headCx, flow, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(branchCx, result)
                    if result.status ~= 0 and result.status ~= 1 then fail(branchCx, flow, gitError(result)); return end
                    flow.sourceBranch = result.status == 0 and git.chomp(result.stdout) or "HEAD"
                    chooseMode(branchCx, flow)
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
