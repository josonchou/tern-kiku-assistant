-- Shared normal-removal review and confirmation invariants. No Git/process calls here.
local M = {}
local OUTPUT_LIMIT = 16 * 1024 * 1024

local function requireSafe(condition, message)
    if not condition then error(message, 0) end
end

function M.require(condition, message)
    requireSafe(condition, message)
end

function M.result(result, label)
    requireSafe(result and not result.timed_out,
        label .. "超时，无法确认结果；请手动核查当前状态。")
    requireSafe(type(result.stdout) == "string" and type(result.stderr) == "string"
        and #result.stdout < OUTPUT_LIMIT and #result.stderr < OUTPUT_LIMIT,
        label .. "输出达到 16 MiB 上限，无法确认完整结果；请手动核查。")
    requireSafe(result.status == 0,
        label .. "失败，无法确认结果；请手动核查当前状态。\n"
            .. (result.stderr ~= "" and result.stderr or result.stdout):sub(1, 1800))
    requireSafe(result.stderr == "",
        label .. "标准错误非空，无法确认结果；请手动核查当前状态。\n"
            .. result.stderr:sub(1, 1800))
    return result.stdout
end

function M.nulRecords(output, label)
    requireSafe(type(output) == "string" and (output == "" or output:sub(-1) == "\0"),
        label .. "的 NUL 记录不完整；拒绝移除。")
    local records = {}
    for record in output:gmatch("([^%z]*)%z") do
        if record ~= "" then table.insert(records, record) end
    end
    return records
end

function M.validateRefSnapshot(output)
    if output == "" then return end
    requireSafe(output:sub(-1) == "\n", "Git refs 输出不完整；拒绝移除。")
    for line in output:gmatch("([^\n]*)\n") do
        local ref, oid, symbolic = line:match("^([^%z]+)%z([^%z]+)%z([^%z]*)$")
        requireSafe(ref and oid and symbolic ~= nil, "Git refs NUL 记录不完整；拒绝移除。")
    end
end


function M.requireRegistered(worktree, mainRoot)
    requireSafe(worktree and worktree.path and worktree.path ~= "",
        "目标 worktree 登记已变化；请重新选择。")
    requireSafe(not worktree.bare, "Bare repository 不能移除。")
    requireSafe(not worktree.locked,
        "目标 worktree 已锁定；请先由操作者手动解锁并重新检查。")
    requireSafe(not worktree.prunable,
        "目标 worktree 登记已失效或可清理；请手动检查 Git 状态。")
    requireSafe(worktree.path ~= mainRoot, "主工作树不可移除。")
end

function M.requireRemovable(worktree, mainRoot, sourceCommon)
    M.requireRegistered(worktree, mainRoot)
    requireSafe(worktree.root == worktree.path and worktree.commonDir == sourceCommon,
        "目标 worktree 的实际 root 或 common-dir 与来源仓库不符；拒绝移除。")
end

function M.requireCompleteFiles(untracked, ignored, indexFlags)
    for _, records in ipairs({ M.nulRecords(untracked, "Git untracked 文件列表"),
        M.nulRecords(ignored, "Git ignored 文件列表") }) do
        for _, path in ipairs(records) do
            requireSafe(path:sub(-1) ~= "/",
                "存在无法完整展开的嵌套仓库或目录清单；拒绝移除。")
        end
    end
    for _, record in ipairs(M.nulRecords(indexFlags, "索引标记")) do
        local flag, mode, oid, stage, path = record:match("^([^ ]) ([0-7]+) ([0-9a-fA-F]+) ([0-3])\t(.+)$")
        requireSafe(flag ~= nil, "目标 worktree 索引状态无法确认；拒绝移除。")
        requireSafe(flag ~= "S" and flag:lower() ~= flag,
            "目标 worktree 存在 assume-unchanged 或 skip-worktree 等隐藏索引标记；请手动检查。")
        requireSafe(path ~= "", "目标 worktree 索引状态无法确认；拒绝移除。")
        requireSafe(flag == "H", "目标 worktree 索引标记未知；拒绝移除。")
        requireSafe(mode == "100644" or mode == "100755" or mode == "120000",
            mode == "160000" and "目标 worktree 含有子模块；其内部文件无法完整审查，正常移除已拒绝。"
                or "目标 worktree 索引文件模式未知；拒绝移除。")
        requireSafe(oid ~= "" and stage == "0", "目标 worktree 索引状态无法确认；拒绝移除。")
    end
end

function M.requireClean(status, untracked, ignored, indexFlags)
    M.requireCompleteFiles(untracked, ignored, indexFlags)
    requireSafe(status == "", "目标 worktree 存在 tracked 或 untracked 修改；正常移除已拒绝。")
    requireSafe(untracked == "", "目标 worktree 存在 untracked 文件；正常移除已拒绝。")
    requireSafe(ignored == "", "目标 worktree 存在 ignored 文件；正常移除已拒绝。")
end

function M.requireProtectedDetached(worktree, containedRefs)
    if worktree.detached then
        requireSafe(type(containedRefs) == "table" and #containedRefs > 0,
            "Detached HEAD 未受本地／远程分支或标签保护；正常移除已拒绝。")
    end
end

function M.contains(parent, candidate)
    if parent == "/" then return candidate:sub(1, 1) == "/" end
    return candidate == parent or candidate:sub(1, #parent + 1) == parent .. "/"
end

function M.requireNoNested(worktreePath, commonDir, registrations)
    for _, row in ipairs(registrations) do
        if row.path ~= worktreePath then
            requireSafe(not M.contains(worktreePath, row.path),
                "目标目录内仍登记有其他 worktree；拒绝连带移除。")
        end
    end
    requireSafe(not M.contains(worktreePath, commonDir),
        "公共 Git 目录位于目标目录内；拒绝移除。")

end
function M.fileURLPath(url)
    if type(url) ~= "string" or url:sub(1, 5):lower() ~= "file:" then return nil end
    requireSafe(url:sub(1, 7):lower() == "file://", "pane file URL 格式无法解析；拒绝移除。")
    local authority, rawPath = url:sub(8):match("^([^/]*)(/[^?#]*)")
    requireSafe(type(authority) == "string" and (authority == "" or authority:lower() == "localhost"),
        "pane file URL 指向非本机主机，无法核实实际路径；拒绝移除。")
    requireSafe(rawPath and rawPath:sub(1, 1) == "/", "pane file URL 路径无法解析；拒绝移除。")
    requireSafe(not rawPath:find("%z"), "pane file URL 含有 NUL；拒绝移除。")
    local path, index = {}, 1
    while index <= #rawPath do
        local char = rawPath:sub(index, index)
        if char == "%" then
            local hex = rawPath:sub(index + 1, index + 2)
            requireSafe(#hex == 2 and hex:match("^%x%x$"), "pane file URL 编码不完整；拒绝移除。")
            local byte = tonumber(hex, 16)
            requireSafe(byte ~= 0, "pane file URL 含有 NUL；拒绝移除。")
            table.insert(path, string.char(byte))
            index += 3
        else
            table.insert(path, char)
            index += 1
        end
    end
    return table.concat(path)
end

function M.requireNoVisibleUse(worktreePath, physicalLocations)
    for _, location in ipairs(physicalLocations) do
        if location.path and M.contains(worktreePath, location.path) then
            error("本机可见 pane 正在使用目标 worktree 或其子路径；请先手动处理 pane。", 0)
        end
    end
end

function M.requireKnownLocalLocations(pane, fields)
    if pane.hostKind == "unknown" then
        error("无法确认可见 pane 的主机归属；拒绝移除。", 0)
    end
    if pane.hostKind == "local" then
        local found = false
        for _, value in pairs(fields) do
            if type(value) == "string" and value ~= "" then found = true end
        end
        requireSafe(found, "本机可见 pane 没有可核实的位置；拒绝移除。")
    end
end

function M.sameSnapshot(before, after)
    if #before ~= #after then return false end
    for index, item in ipairs(before) do
        local other = after[index]
        if item.key ~= other.key or item.value ~= other.value then return false end
    end
    return true
end

function M.snapshot(
    worktree, registrations, paneLocations, head, branch, status, ignored, indexFlags, refs, untracked, paneSignature
)
    local values = {
        path = worktree.path, head = worktree.head or "", branch = worktree.branch or "",
        bare = tostring(worktree.bare), detached = tostring(worktree.detached),
        locked = tostring(worktree.locked), lockReason = worktree.lockReason or "",
        prunable = tostring(worktree.prunable), prunableReason = worktree.prunableReason or "",
        registrations = registrations, paneLocations = paneLocations, headValue = head,
        untracked = untracked or "", paneSignature = paneSignature or "",
        branchValue = branch or "", status = status, ignored = ignored, indexFlags = indexFlags, refs = refs,
    }
    local result = {}
    for key, value in pairs(values) do table.insert(result, { key = key, value = value }) end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

return M
