-- Run in Tern's actual Luau runtime; M is provided by the integration runner.
return function(M)
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
    local args = M.addArgs({mode = "new", name = "topic", path = "/a/has ' quote", base = "abc"})
    eq(table.concat(args, "|"), "worktree|add|-b|topic|--|/a/has ' quote|abc")
    local remote = M.addArgs({mode = "remote", name = "topic", path = "/a", base = "refs/remotes/origin/topic"})
    eq(remote[3], "--track")
    local detached = M.addArgs({mode = "detached", path = "/a", base = "abc"})
    eq(detached[3], "--detach")
    return checks
end
