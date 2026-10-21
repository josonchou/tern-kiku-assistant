local tern = require("tern")
local git = require("./lib/worktree")
local manager = require("./lib/manager")
local removal = require("./lib/removal")
local configModule = require("./lib/config")
local executableModule = require("./lib/executables")
local toolsModule = require("./lib/tools")

local config, configError = configModule.read()
local executables = executableModule.new(config.executables)
-- Reload does not replay window_start; start the nonblocking probe at load.
executables:refresh(nil)

local active
local chooseMode, chooseLocation, promptPath, promptName, chooseBranch, chooseBase, create, start, manage

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
    local argv = { flow.programs.paths.git, "-C", flow.root or flow.cwd }
    for _, arg in ipairs(args) do table.insert(argv, arg) end
    tern.process.run(argv, { timeout_ms = 120000, env = { PATH = flow.programs.pathEnv } }, function(result, nextCx)
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
        local detail = message:gsub("[\r\n]+", " ")
        cx:toast("error", "Worktree 已创建，打开标签页失败", detail .. " · " .. path)
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
    local argv = { flow.programs.paths.git, "-C", cwd }
    for _, arg in ipairs(args) do table.insert(argv, arg) end
    tern.process.run(argv, { timeout_ms = 120000, env = { PATH = flow.programs.pathEnv } }, function(result, nextCx)
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

local function removalRun(cx, flow, cwd, args, callback)
    local argv = { flow.programs.paths.git, "-c", "core.fsmonitor=false", "-C", cwd }
    for _, arg in ipairs(args) do table.insert(argv, arg) end
    tern.process.run(argv, { timeout_ms = 120000, env = { PATH = flow.programs.pathEnv } }, function(result, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function() callback(nextCx, result) end)
    end)
end

local function physicalPath(cx, flow, path, callback)
    removal.require(type(path) == "string" and path:sub(1, 1) == "/",
        "无法确认路径是否为本机绝对路径；拒绝移除。")
    removal.require(flow.programs.paths.realpath ~= nil,
        "本机 realpath 不可用；请检查 executables.realpath 与 PATH。")
    tern.process.run({ flow.programs.paths.realpath, path }, {
        timeout_ms = 30000, env = { PATH = flow.programs.pathEnv },
    }, function(result, nextCx)
        if not nextCx or active ~= flow then return end
        guarded(nextCx, flow, function()
            local value = removal.result(result, "realpath 路径解析")
            callback(nextCx, git.chomp(value))
        end)
    end)
end

local function paneSignature(panes)
    local rows = {}
    for _, pane in ipairs(panes) do
        table.insert(rows, table.concat({
            tostring(pane.pane), tostring(pane.hostId), tostring(pane.hostKind),
            tostring(pane.sessionId), tostring(pane.sessionHost),
            tostring(pane.cwd), tostring(pane.path), tostring(pane.url),
            tostring(pane.kind), tostring(pane.tab),
            tostring(pane.floating), tostring(pane.parked),
        }, "\0"))
    end
    table.sort(rows)
    return table.concat(rows, "\1")
end
local function inspectPaneLocations(cx, flow, panes, callback)
    local locations, fields, paneIndex, fieldIndex = {}, nil, 1, 1
    local function advance(nextCx)
        while true do
            local pane = panes[paneIndex]
            if not pane then
                removal.requireNoVisibleUse(flow.reviewRoot, locations)
                table.sort(locations, function(a, b) return a.key < b.key end)
                local encoded = {}
                for _, location in ipairs(locations) do
                    table.insert(encoded, location.key .. "=" .. location.value)
                end
                callback(nextCx, locations, table.concat(encoded, "\n"))
                return
            end
            if not fields then
                local urlPath
                if pane.hostKind == "local" and pane.url then
                    urlPath = removal.fileURLPath(pane.url)
                end
                fields = { { "cwd", pane.cwd }, { "path", pane.path }, { "url", urlPath } }
                removal.requireKnownLocalLocations(pane, { pane.cwd, pane.path, urlPath })
                fieldIndex = 1
            end
            local field = fields[fieldIndex]
            if not field then
                paneIndex += 1
                fields = nil
            else
                fieldIndex += 1
                if pane.hostKind == "local" and field[2] and field[2] ~= "" then
                    physicalPath(nextCx, flow, field[2], function(realCx, resolved)
                        table.insert(locations, {
                            key = tostring(pane.pane) .. ":" .. field[1] .. ":" .. tostring(field[2]),
                            value = resolved,
                            path = resolved,
                        })
                        advance(realCx)
                    end)
                    return
                end
            end
        end
    end
    advance(cx)
end

local function reviewRemoval(cx, flow, selected, callback)
    local state = { selected = selected, rows = {}, paths = {}, panes = {} }
    local steps = {}
    local function step(fn)
        table.insert(steps, fn)
    end
    local function command(key, cwd, args, label, optional)
        step(function(currentCx, next)
            if type(cwd) == "function" then cwd = cwd() end
            if type(args) == "function" then args = args() end
            removalRun(currentCx, flow, cwd, args, function(resultCx, result)
                if optional and result.status == optional.status then
                    removal.require(not result.timed_out and result.stdout == "" and result.stderr == "",
                        label .. "无法确认目标状态；拒绝移除。")
                    state[key] = ""
                else
                    state[key] = removal.result(result, label)
                end
                next(resultCx)
            end)
        end)
    end
    command("listing", flow.root, { "worktree", "list", "--porcelain", "-z" }, "Git worktree list")
    step(function(currentCx, next)
        removal.require(state.listing == "" or state.listing:sub(-2) == "\0\0",
            "Git worktree 登记 NUL 输出不完整；拒绝移除。")
        state.rows = git.worktrees(state.listing)
        state.mainRoot = state.rows[1] and state.rows[1].path
        for _, row in ipairs(state.rows) do
            if row.path == selected.path then state.registered = row end
        end
        removal.require(state.registered ~= nil, "目标 worktree 已不再登记；请重新选择。")
        removal.requireRegistered(state.registered, state.mainRoot)
        next(currentCx)
    end)
    command("targetRoot", selected.path, { "rev-parse", "--show-toplevel" }, "目标 Git root")
    command("targetCommon", selected.path,
        { "rev-parse", "--path-format=absolute", "--git-common-dir" }, "目标 Git common-dir")
    command("targetGitDir", selected.path,
        { "rev-parse", "--absolute-git-dir" }, "目标 Git private-dir")
    step(function(currentCx, next)
        state.root, state.common = git.chomp(state.targetRoot), git.chomp(state.targetCommon)
        state.registered.root, state.registered.commonDir = state.root, state.common
        state.gitDir = git.chomp(state.targetGitDir)
        removal.requireRemovable(state.registered, state.mainRoot, flow.commonDir)
        flow.reviewRoot = state.root
        local locations = {
            { "target", selected.path, state.root },
            { "common", state.common, flow.commonDir },
        }
        local index = 1
        local function resolve(nextCx)
            local item = locations[index]
            if not item then
                local rowIndex = 1
                local function resolveRows(rowCx)
                    local row = state.rows[rowIndex]
                    if not row then
                        local physicalRows = {}
                        for _, registered in ipairs(state.rows) do
                            table.insert(physicalRows, {
                                path = state.paths[registered.path] or registered.path,
                            })
                        end
                        removal.requireNoNested(state.root, state.common, physicalRows)
                        next(rowCx)
                        return
                    end
                    rowIndex += 1
                    if not tern.fs.exists(row.path) then
                        removal.require(row.path ~= selected.path and row.prunable,
                            "其他 worktree 登记路径不存在且身份无法确认；拒绝移除。")
                        state.paths[row.path] = row.path
                        resolveRows(rowCx)
                        return
                    end
                    physicalPath(rowCx, flow, row.path, function(realCx, physical)
                        state.paths[row.path] = physical
                        removal.require(physical == row.path,
                            "其他 worktree 登记路径的物理身份已变化；拒绝移除。")
                        if row.path == selected.path then
                            removal.require(physical == state.root,
                                "目标登记路径的 realpath 身份已变化；拒绝移除。")
                        end
                        resolveRows(realCx)
                    end)
                end
                resolveRows(nextCx)
                return
            end
            index += 1
            physicalPath(nextCx, flow, item[2], function(realCx, physical)
                removal.require(physical == item[3],
                    item[1] == "target"
                        and "目标 worktree 的实际 root／realpath 与 Git 登记不符；拒绝移除。"
                        or "目标 worktree 的实际 common-dir 与来源仓库不符；拒绝移除。")
                resolve(realCx)
            end)
        end
        resolve(currentCx)
    end)
    step(function(currentCx, next)
        physicalPath(currentCx, flow, state.gitDir, function(gitCx, physicalGitDir)
            state.gitDir = physicalGitDir
            removal.requirePrivateGitDir(state.common, state.gitDir)
            local pointerFile = state.gitDir .. "/gitdir"
            physicalPath(gitCx, flow, pointerFile, function(pointerCx, physicalPointerFile)
                removal.require(physicalPointerFile == pointerFile,
                    "目标 private Git 目录 backpointer 不能是符号链接；拒绝移除。")
                local readOk, backpointer = pcall(tern.fs.read, pointerFile, 4096)
                removal.require(readOk and type(backpointer) == "string" and backpointer ~= ""
                    and not backpointer:find("%z"),
                    "目标 private Git 目录 backpointer 文件无法安全读取；拒绝移除。")
                local backpointerPath = git.chomp(backpointer)
                removal.require(backpointerPath ~= "" and not backpointerPath:find("%z"),
                    "目标 private Git 目录 backpointer 格式无法确认；拒绝移除。")
                if backpointerPath:sub(1, 1) ~= "/" then
                    backpointerPath = state.gitDir .. "/" .. backpointerPath
                end
                physicalPath(pointerCx, flow, backpointerPath, function(backpointerCx, physicalBackpointer)
                    physicalPath(backpointerCx, flow, selected.path .. "/.git", function(dotGitCx, physicalDotGit)
                        removal.require(physicalBackpointer == physicalDotGit,
                            "目标 private Git 目录 backpointer 与 worktree 登记路径不符；拒绝移除。")
                        state.registered.gitDir = state.gitDir
                        local listOk, entries = pcall(tern.fs.list, state.gitDir)
                        removal.require(listOk and type(entries) == "table",
                            "请先保存内容，再手动完成或中止相关操作；无法确认未完成Git操作目录状态，拒绝移除。")
                        state.gitDirEntries = entries
                        next(dotGitCx)
                    end)
                end)
            end)
        end)
    end)
    step(function(currentCx, next)
        local ok, panes = pcall(manager.visiblePanes, currentCx)
        removal.require(ok, "无法完整枚举本机可见 panes；拒绝移除。")
        state.panes = panes
        inspectPaneLocations(currentCx, flow, panes, function(locCx, locations, encoded)
            state.paneLocations = encoded
            state.paneSignature = paneSignature(panes)
            next(locCx)
        end)
    end)
    command("status", function() return state.root end,
        { "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none" },
        "Git status")
    command("ignored", function() return state.root end,
        { "ls-files", "--others", "--ignored", "--exclude-standard", "-z" }, "Git ignored 文件列表")
    command("untracked", function() return state.root end,
        { "ls-files", "--others", "--exclude-standard", "-z" }, "Git untracked 文件列表")
    command("indexFlags", function() return state.root end,
        { "ls-files", "-v", "--stage", "-z" }, "Git 索引标记")
    step(function(currentCx, next)
        removal.require(state.status == "" or state.status:sub(-1) == "\0",
            "Git status NUL 输出不完整；拒绝移除。")
        removal.nulRecords(state.ignored, "Git ignored 文件列表")
        removal.nulRecords(state.untracked, "Git untracked 文件列表")
        removal.requireCompleteFiles(state.untracked, state.ignored, state.indexFlags)
        next(currentCx)
    end)
    command("head", function() return state.root end,
        { "rev-parse", "--verify", "HEAD^{commit}" }, "Git HEAD")
    command("branch", function() return state.root end,
        { "symbolic-ref", "--quiet", "HEAD" }, "Git 完整 symbolic-ref", { status = 1 })
    command("protectedRefs", function() return state.root end, function()
        return {
            "for-each-ref", "--contains=" .. git.chomp(state.head),
            "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags",
        }
    end, "Detached HEAD 保护分支")
    command("refs", function() return state.root end,
        { "for-each-ref", "--include-root-refs", "--format=%(refname)%00%(objectname)%00%(symref)" },
        "Git refs（包含根引用）")
    step(function(currentCx, next)
        state.head = git.chomp(state.head)
        state.branch = git.chomp(state.branch)
        local registeredDetached = state.registered.detached == true
        removal.require(state.registered.head == state.head
            and registeredDetached == (state.branch == "")
            and ((registeredDetached and state.branch == "")
                or (not registeredDetached and state.registered.branch == state.branch)),
            "Git worktree 登记 HEAD／branch 与实际状态不一致；拒绝移除。")
        state.protected = {}
        local refsOutput = state.protectedRefs
        removal.require(refsOutput == "" or refsOutput:sub(-1) == "\n",
            "Detached HEAD 保护refs输出不完整；拒绝移除。")
        for ref in refsOutput:gmatch("[^\r\n]+") do table.insert(state.protected, ref) end
        removal.requireNoPendingOperation(state.gitDirEntries, state.refs)
        next(currentCx)
    end)
    step(function(currentCx, next)
        runGitAt(currentCx, flow, flow.cwd, { "rev-parse", "--show-toplevel" }, function(sourceCx, result)
            state.sourceRoot = git.chomp(removal.result(result, "来源 Git root"))
            runGitAt(sourceCx, flow, flow.cwd, {
                "rev-parse", "--path-format=absolute", "--git-common-dir",
            }, function(commonCx, commonResult)
                state.sourceCommon = git.chomp(removal.result(commonResult, "来源 Git common-dir"))
                removal.require(state.sourceRoot == flow.root and state.sourceCommon == flow.commonDir,
                    "来源仓库 root 或 common-dir 已变化；拒绝移除。")
                next(commonCx)
            end)
        end)
    end)
    step(function(currentCx, next)
        local panesOk, latest = pcall(manager.visiblePanes, currentCx)
        removal.require(panesOk and paneSignature(latest) == state.paneSignature,
            "最终复查期间可见 pane 身份或位置已变化；拒绝移除。")
        inspectPaneLocations(currentCx, flow, latest, function(locCx, _, locationsText)
            removal.require(locationsText == state.paneLocations,
                "最终复查期间可见 pane 物理位置已变化；拒绝移除。")
            next(locCx)
        end)
    end)
    step(function(currentCx)
        local snapshot = removal.snapshot(state.registered, state.listing, state.paneLocations,
            state.head, state.branch, state.status, state.ignored, state.indexFlags, state.refs,
            state.untracked, state.paneSignature)
        callback(currentCx, {
            paneSignature = state.paneSignature,
            snapshot = snapshot,
            risks = {
                worktree = state.registered, head = state.head, symbolicRef = state.branch,
                status = state.status, untracked = state.untracked, ignored = state.ignored,
                indexFlags = state.indexFlags, protectedRefs = state.protected,
                snapshot = snapshot, paneSignature = state.paneSignature,
            },
        })
    end)
    local function runStep(index, currentCx)
        local currentStep = steps[index]
        if currentStep then
            currentStep(currentCx, function(nextCx) runStep(index + 1, nextCx) end)
        end
    end
    runStep(1, cx)
end



local function requireNormalRemoval(review)
    removal.requireClean(review.risks.status, review.risks.untracked,
        review.risks.ignored, review.risks.indexFlags)
    removal.requireProtectedDetached(review.risks.worktree, review.risks.protectedRefs)
end

local function dangerousRiskItems(review)
    local risks = review.risks
    local statusRecords = removal.nulRecords(risks.status, "Git status")
    local untrackedRecords = removal.nulRecords(risks.untracked, "Git untracked 文件列表")
    local ignoredRecords = removal.nulRecords(risks.ignored, "Git ignored 文件列表")
    local total = #untrackedRecords + #ignoredRecords
    local index = 1
    while index <= #statusRecords do
        local record = statusRecords[index]
        removal.require(#record >= 4 and record:sub(3, 3) == " ",
            "Git status 记录不完整；拒绝移除。")
        local code, path = record:sub(1, 2), record:sub(4)
        removal.require(path ~= "", "Git status 路径为空；拒绝移除。")
        if code ~= "??" then
            total += 1
            if code:find("R", 1, true) or code:find("C", 1, true) then
                index += 1
                removal.require(type(statusRecords[index]) == "string" and statusRecords[index] ~= "",
                    "Git status rename/copy 双路径记录不完整；拒绝移除。")
                total += 1
            end
        end
        index += 1
    end
    if risks.worktree.detached and #risks.protectedRefs == 0 then total += 1 end

    local limit = 40
    local truncated = total > limit
    local visibleLimit = truncated and limit - 1 or limit
    local items = {}
    local function add(label)
        if #items < visibleLimit then
            table.insert(items, { label = label, id = "risk", riskText = label })
        end
    end
    if total == 0 then
        add("未发现可丢弃的本地文件或提交风险")
    else
        index = 1
        while index <= #statusRecords do
            local record = statusRecords[index]
            local code, path = record:sub(1, 2), record:sub(4)
            if code ~= "??" then
                add("已修改文件（" .. code .. "）：" .. path)
                if code:find("R", 1, true) or code:find("C", 1, true) then
                    index += 1
                    add("原始路径：" .. statusRecords[index])
                end
            end
            index += 1
        end
        for _, path in ipairs(untrackedRecords) do
            add("未跟踪文件：" .. path)
        end
        for _, path in ipairs(ignoredRecords) do
            add("忽略文件：" .. path)
        end
        if risks.worktree.detached and #risks.protectedRefs == 0 then
            add("未受分支或标签保护的 Detached 提交：" .. risks.head)
        end
    end
    return { items = items, total = total, truncated = truncated }
end

local function removeWorktree(cx, flow, worktree, dangerous)
    if not flow.programs.paths.realpath then
        fail(cx, flow, "realpath 不可用；拒绝移除 worktree。")
        return
    end
    reviewRemoval(cx, flow, worktree, function(reviewCx, before)
        if not dangerous then requireNormalRemoval(before) end
        local function removeAfterReview(confirmCx)
            local function finalReview(finalCx)
                reviewRemoval(finalCx, flow, worktree, function(reviewCx, after)
                    if not dangerous then requireNormalRemoval(after) end
                    if not removal.sameSnapshot(before.snapshot, after.snapshot) then
                        fail(reviewCx, flow,
                            "确认期间 worktree、内容、refs 或可见 pane 状态已变化；未移除，请重新检查。")
                        return
                    end
                    local panesOk, currentPanes = pcall(manager.visiblePanes, reviewCx)
                    if not panesOk or paneSignature(currentPanes) ~= after.paneSignature then
                        fail(reviewCx, flow,
                            "最终复查期间可见 pane 身份或位置已变化；未移除，请重新检查。")
                        return
                    end
                    local args = { "worktree", "remove" }
                    if dangerous then table.insert(args, "--force") end
                    table.insert(args, "--")
                    table.insert(args, worktree.path)
                    removalRun(reviewCx, flow, flow.root, args, function(doneCx, result)
                        if result.status ~= 0 then
                            finish(flow)
                            doneCx:toast("error", "Kiku：worktree 移除失败",
                                "Git 移除失败；目录或登记可能已部分移除，请手动核查。未执行补救或重试。\n"
                                    .. gitError(result))
                            return
                        end
                        removalRun(doneCx, flow, flow.root, {
                            "worktree", "list", "--porcelain", "-z",
                        }, function(checkCx, checkResult)
                            local output = removal.result(checkResult, "移除后的 Git worktree list")
                            removal.require(output == "" or output:sub(-2) == "\0\0",
                                "Git 移除后登记 NUL 输出不完整；请手动核查结果。")
                            local remains = false
                            for _, row in ipairs(git.worktrees(output)) do
                                if row.path == worktree.path then remains = true end
                            end
                            removal.require(not remains and not tern.fs.exists(worktree.path),
                                "Git 已返回成功，但未能确认目标目录与登记均已移除；请手动核查。")
                            finish(flow)
                            checkCx:toast("success", "worktree 已移除，分支已保留", worktree.path)
                        end)
                    end)
                end)
            end
            finalReview(confirmCx)
        end
        if not dangerous then
            local function showConfirmation(confirmCx)
                pick(confirmCx, flow, {
                    placeholder = "确认移除 · 分支保留",
                    items = {
                        { label = "取消", id = "cancel" },
                        { label = "查看完整目标路径…", detail = worktree.path, id = "path" },
                        { label = "确认无外部使用并移除", id = "confirm" },
                    },
                }, function(itemCx, choice)
                    if choice.id == "cancel" then finish(flow); return end
                    if choice.id == "path" then
                        prompt(itemCx, flow, {
                            placeholder = "仅查看完整目标路径；回车返回确认，Esc取消",
                            value = worktree.path,
                            action = "返回确认（仅查看）",
                        }, function(previewCx) showConfirmation(previewCx) end)
                        return
                    end
                    if choice.id == "confirm" then removeAfterReview(itemCx)
                    else finish(flow) end
                end)
            end
            showConfirmation(reviewCx)
            return
        end

        local riskPreview = dangerousRiskItems(before)
        local riskMenuItems = {
            { label = "取消", id = "cancel" },
        }
        if riskPreview.truncated then
            table.insert(riskMenuItems, {
                label = "风险清单已截断；未展示项也会被丢弃（共 "
                    .. tostring(riskPreview.total) .. " 项）",
                id = "notice",
            })
        end
        for _, item in ipairs(riskPreview.items) do table.insert(riskMenuItems, item) end
        table.insert(riskMenuItems, {
            label = "查看完整目标路径…",
            detail = worktree.path,
            id = "path_preview",
        })
        table.insert(riskMenuItems, {
            label = "继续：输入完整目标路径",
            id = "enter_path",
        })

        local function showRiskPreview(previewCx)
            pick(previewCx, flow, {
                placeholder = "危险移除将丢弃目标内全部本地内容，包括未展示风险",
                items = riskMenuItems,
            }, function(itemCx, choice)
                if choice.id == "cancel" then finish(flow); return end
                if choice.id == "notice" then showRiskPreview(itemCx); return end
                if choice.id == "risk" then
                    prompt(itemCx, flow, {
                        placeholder = "只读风险项展示；编辑不会授权，回车返回预览，Esc取消",
                        value = choice.riskText,
                        action = "返回风险预览",
                    }, function(returnCx) showRiskPreview(returnCx) end)
                    return
                end
                if choice.id == "path_preview" then
                    prompt(itemCx, flow, {
                        placeholder = "只读路径预览；返回后仍需输入完整路径确认",
                        value = worktree.path,
                        action = "返回风险预览",
                    }, function(returnCx) showRiskPreview(returnCx) end)
                    return
                end
                if choice.id ~= "enter_path" then
                    finish(flow)
                    return
                end
                local function enterPath(pathCx)
                    prompt(pathCx, flow, {
                        placeholder = "重新输入完整目标路径；Esc取消",
                        value = "",
                        action = "确认完整路径",
                    }, function(typedCx, typedPath)
                        if typedPath ~= worktree.path then
                            pick(typedCx, flow, {
                                placeholder = "输入路径与目标不符",
                                items = {
                                    { label = "取消", id = "cancel" },
                                    { label = "重新输入完整路径", id = "retry" },
                                },
                            }, function(retryCx, correction)
                                if correction.id == "retry" then enterPath(retryCx)
                                else finish(flow) end
                            end)
                            return
                        end
                        pick(typedCx, flow, {
                            placeholder = "确认无外部环境仍在使用目标",
                            items = {
                                { label = "取消", id = "cancel" },
                                { label = "确认无外部使用并危险移除", id = "confirm" },
                            },
                        }, function(externalCx, confirmation)
                            if confirmation.id == "confirm" then
                                removeAfterReview(externalCx)
                            else
                                finish(flow)
                            end
                        end)
                    end)
                end
                enterPath(itemCx)
            end)
        end
        if dangerous then showRiskPreview(reviewCx) end
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
        if targetRoot ~= worktree.path then
            failOpen(rootCx, flow, worktree.path,
                "Git 实际 root 与登记路径不一致，请手动核查工作树登记及目标 .git 指针。")
            return
        end
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
                readGitAt(commonCx, flow, flow.path, { "rev-parse", "--show-prefix" },
                    function(prefixCx, prefix)
                        if git.chomp(prefix) ~= "" then
                            failOpen(prefixCx, flow, flow.path,
                                "Git 身份不符；请核查目标 .git 与登记。")
                            return
                        end
                        readWorktrees(prefixCx, flow, function(listCx)
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

start = function(cx, programs)
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
        hostId = host.id, programs = programs,
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

manage = function(cx, programs)
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
        hostId = host.id, programs = programs,
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
                            local actions = {
                                { label = "打开／切换", id = "open" },
                                { label = "关闭工作环境", id = "close" },
                            }
                            if flow.programs.paths.realpath then
                                table.insert(actions, { label = "正常移除 worktree", id = "remove" })
                                table.insert(actions, { label = "危险移除 worktree", id = "dangerous_remove" })
                            end
                            pick(selectCx, flow, {
                                placeholder = "选择操作 · " .. item.worktree.path,
                                items = actions,
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
                                        or current.bare ~= selected.bare or current.locked ~= selected.locked
                                        or current.lockReason ~= selected.lockReason
                                        or current.prunable ~= selected.prunable
                                        or current.prunableReason ~= selected.prunableReason then
                                        fail(refreshCx, flow, "所选工作树登记或身份已变化；请重新选择。")
                                        return
                                    end
                                    if action.id == "remove" or action.id == "dangerous_remove" then
                                        removeWorktree(refreshCx, flow, current, action.id == "dangerous_remove")
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
local function startWithGit(cx, names, entry)
    if active then cx:toast("info", "Kiku 工作树流程正在进行", "请完成或按 Esc 取消当前选择。"); return end
    if configError then cx:toast("error", "Kiku 配置错误", configError); return end
    local host = cx.hosts:current()
    local session = cx.sessions:current()
    local focused = cx.session:focused()
    local sourcePane = focused and cx.session:pane(focused)
    local sourceCwd = sourcePane and sourcePane.cwd
    if host.kind ~= "local" or (tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux") then
        cx:toast("error", "Kiku 助手仅支持 macOS / Linux 本机来源")
        return
    end
    if not sourceCwd or sourceCwd == "" then
        cx:toast("error", "无法确定当前项目目录", "请聚焦已报告工作目录的终端。")
        return
    end
    executables:check(cx, names, function(nextCx, result)
        if not nextCx then return end
        local currentHost = nextCx.hosts:current()
        local currentSession = nextCx.sessions:current()
        local currentFocused = nextCx.session:focused()
        local currentPane = currentFocused and nextCx.session:pane(currentFocused)
        if currentHost.id ~= host.id or host.kind ~= "local" or currentHost.kind ~= "local"
            or currentSession.id ~= session.id or currentFocused ~= focused
            or not sourceCwd or not currentPane or currentPane.cwd ~= sourceCwd then
            nextCx:toast("error", "Kiku 助手来源已变化", "请从原本机来源重新执行操作。")
            return
        end
        if not result.paths.git then
            nextCx:toast("error", "Kiku 助手缺少 Git",
                result.errors.git or "请检查本机 executables.git 配置与 PATH。")
            return
        end
        for name, fallback in pairs(result.fallbacks) do
            nextCx:toast("info", "Kiku 助手依赖回退",
                name .. " 已使用 " .. fallback.path .. "（" .. fallback.reason .. "）")
        end
        entry(nextCx, result)
    end)
end
local defaultKey = "ctrl+b>shift+g"
tern.command({
    id = "create_worktree", title = "Kiku: 新建 Git worktree", group = "Kiku 助手",
    keys = { config.keybinding ~= "" and config.keybinding or defaultKey },
    available = function() return executables:ready("git") end,
    run = function(cx) startWithGit(cx, { "git" }, start) end,
})
tern.command({
    id = "manage_worktrees", title = "Kiku: 管理 Git worktree", group = "Kiku 助手",
    keys = config.manageKeybinding ~= "" and { config.manageKeybinding } or {},
    available = function() return executables:ready("git") end,
    run = function(cx) startWithGit(cx, { "git", "realpath" }, manage) end,
})
toolsModule.register(config, executables)
