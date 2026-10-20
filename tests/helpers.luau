-- Run in Tern's actual Luau runtime; M and manager are provided by the integration runner.
return function(M, manager)
    local checks = 0
    local function eq(actual, expected)
        assert(actual == expected, tostring(actual) .. " != " .. tostring(expected))
        checks += 1
    end
    eq(M.branchName("feature/login page"), "feature/login-page")
    eq(M.parent("/repo"), "/")
    eq(M.parent("/a/b"), "/a")
    eq(M.absolute("../a/./b", "/repo", "/home/u"), "/a/b")
    eq(M.absolute("~/trees", "/repo", "/home/u"), "/home/u/trees")
    eq(M.absolute("~", "/repo", "/home/u"), "/home/u")
    eq(M.absolute("~other/trees", "/repo", "/home/u"), nil)
    eq(M.absolute("", "/repo", "/home/u"), nil)
    eq(M.absolute("x\ny", "/repo", "/home/u"), nil)
    local trees = M.worktrees("worktree /repos/main\0HEAD abcd\0branch refs/heads/main\0\0worktree /trees/a \"中文\"\npath\0HEAD abcd\0detached\0\0")
    eq(#trees, 2)
    eq(trees[2].path, "/trees/a \"中文\"\npath")
    eq(trees[2].detached, true)
    eq(trees[2].head, "abcd")
    local protected = M.worktrees("worktree /locked\0HEAD deadbeef\0branch refs/heads/locked\0locked operator maintenance\0\0worktree /stale\0HEAD feedface\0detached\0prunable missing directory\0\0")
    eq(protected[1].locked, true)
    eq(protected[1].lockReason, "operator maintenance")
    eq(protected[2].prunable, true)
    eq(protected[2].prunableReason, "missing directory")
    eq(M.occupied(trees)["refs/heads/main"], "/repos/main")
    local branches = M.branches("refs/heads/main\0\0\nrefs/remotes/origin/HEAD\0refs/remotes/origin/topic\0\nrefs/remotes/origin/feature/a\0\0\n")
    eq(#branches, 2)
    eq(branches[2].localName, "feature/a")
    local simple = {{path = "/repos/main"}}
    eq(M.targets(simple, "/repos/main", "", "feature/a", "/home/u")[1], "/repos/feature/a")
    local linked = {{path = "/repos/main"}, {path = "/trees/a"}, {path = "/other/b"}, {path = "/trees/c"}}
    local targets = M.targets(linked, "/other/b", "../trees", "feature/a", "/home/u")
    eq(#targets, 3)
    eq(targets[1], "/other/feature/a")
    eq(targets[2], "/trees/feature/a")
    eq(targets[3], "/repos/trees/feature/a")
    eq(#M.targets(linked, "/trees/a", "/trees", "a", "/home/u"), 2)
    eq(manager.sameWorktree("/repo/tree", "/repo/.git", "/repo/other", "/repo/.git"), false)
    local matches = manager.tabCandidates({
        {pane = 1, cwd = "/repo/tree/sub", tab = 11, sessionId = 1, sessionHost = 7, hostId = 7},
        {pane = 2, cwd = "/repo/tree", tab = 13, sessionId = 1, sessionHost = 8, hostId = 7},
        {pane = 3, cwd = "/repo/tree", tab = 12, sessionId = 2, sessionHost = 8, hostId = 8},
    }, "/repo/tree", "/repo/.git", {
        [1] = {root = "/repo/tree", commonDir = "/repo/.git"},
        [2] = {root = "/repo/tree", commonDir = "/repo/.git"},
        [3] = {root = "/repo/tree", commonDir = "/repo/.git"},
    }, 7)
    eq(#matches, 1)
    eq(matches[1].pane, 1)
    return checks
end
