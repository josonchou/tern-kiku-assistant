"""Real Git removal through the shared native worktree-management interaction."""

import json
import shutil

from pathlib import Path

from management import _pane_ids, _select_worktree, _tab_ids, _wait_management_rejection

def _registrations(h):
    output = h.git("worktree", "list", "--porcelain", "-z")
    assert output.endswith("\0\0"), repr(output)
    registrations = {}
    for record in output[:-2].split("\0\0"):
        first = record.split("\0", 1)[0]
        assert first.startswith("worktree "), repr(record)
        path = Path(first.removeprefix("worktree "))
        assert path not in registrations, path
        registrations[path] = record
    return registrations


def _checkout_contents(root):
    contents = {}

    def visit(directory):
        for path in directory.iterdir():
            # The common Git directory changes its own administrative records
            # during removal. Linked checkouts' .git pointer files must survive.
            if path == root / ".git" and path.is_dir():
                continue
            relative = str(path.relative_to(root))
            if path.is_symlink():
                contents[relative] = ("symlink", str(path.readlink()))
            elif path.is_dir():
                contents[relative] = ("directory",)
                visit(path)
            else:
                contents[relative] = ("file", path.read_bytes())

    visit(root)
    return contents

def _select_remove(h, target, source=None):
    source = source or h.repo
    for pane in h.lua_json("cx.session:panes()"):
        if (pane.get("kind") == "terminal" and pane.get("cwd") == str(source)
                and pane.get("tab") is not None and not pane.get("parked")
                and pane.get("busy") is False and pane.get("at_prompt") is True):
            h.lua(f"cx.layout:focus({pane['pane']}); return true")
            break
    else:
        h.open_repo(source)
    _select_worktree(h, target, action="正常移除 worktree")

def _expect_rejection(h, target, message, expected_exists=True):
    _select_remove(h, target)
    _wait_management_rejection(h, message)
    assert target.is_dir() is expected_exists
    assert target in _registrations(h)

def _add_checkout(h, path, branch):
    h.git("worktree", "add", "-b", branch, str(path), "HEAD")


def _remove_fixture(h, path):
    h.git("worktree", "remove", "--", str(path))


def _reject_dirty_checkout(h, path, branch, label, prepare, cleanup, message):
    _add_checkout(h, path, branch)
    prepare()
    contents = _checkout_contents(path)
    before = h.git("show-ref", "--heads")
    registrations = _registrations(h)
    _expect_rejection(h, path, message)
    assert h.git("show-ref", "--heads") == before
    assert _registrations(h) == registrations
    assert _checkout_contents(path) == contents
    cleanup()
    assert h.git("status", "--porcelain", cwd=path) == ""
    _remove_fixture(h, path)
    h.record(label)


def run(h):
    repo = h.repo
    target = repo.parent / '正常移除 "clean" worktree'
    branch = "external/normal-removal"
    neighbor = repo.parent / '正常移除 "clean" worktree suffix'
    h.git("worktree", "add", "-b", branch, str(target), "HEAD")
    h.git("worktree", "add", "-b", "external/removal-preserved", str(neighbor), "HEAD")
    assert h.git("status", "--porcelain", "--untracked-files=all", cwd=target) == ""
    assert h.git("ls-files", "--others", "--ignored", "--exclude-standard", "-z", cwd=target) == ""
    assert (target / "README.md").read_bytes() == b"committed\n"

    # Neither checkout has been opened in Tern. Start from the local main tree,
    # preserving every previously exercised worktree and visible environment.
    h.open_repo(repo)
    registered = _registrations(h)
    assert target in registered and neighbor in registered and repo in registered
    contents = {path: _checkout_contents(path) for path in registered}
    refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    source_head = h.git("rev-parse", "HEAD")
    source_status = h.git("status", "--porcelain")
    branch_head = h.git("rev-parse", "refs/heads/" + branch)
    common = Path(h.git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    common_config = (common / "config").read_bytes()
    tabs = _tab_ids(h)
    panes = _pane_ids(h)

    # The target is unbound and unopened; the action should be selected through
    # the same real native interaction used by the management regressions.
    _select_worktree(h, target, action="正常移除 worktree")
    confirmation = h.picker(selected="取消")
    assert "取消" in (confirmation["selected"] or ""), confirmation
    assert target.is_dir()
    assert _registrations(h) == registered
    assert _checkout_contents(target) == contents[target]
    h.ctl("picker enter")
    h.wait_for(lambda state: not state["picker"], "cancel default-selected removal confirmation")
    assert target.is_dir() and _registrations(h) == registered
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == refs
    _select_worktree(h, target, action="正常移除 worktree")
    confirmation = h.picker(selected="取消")
    assert "取消" in (confirmation["selected"] or ""), confirmation
    h.ctl("shot normal-removal-confirm")
    h.type_text("查看完整目标路径…")
    h.picker(selected="查看完整目标路径")
    h.ctl("picker enter")
    preview = h.picker("prompt")
    assert str(target) in (preview["query"] or ""), preview
    h.ctl("shot normal-removal-path-preview")
    h.ctl("key enter")
    confirmation = h.picker(selected="取消")
    assert "取消" in (confirmation["selected"] or ""), confirmation
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    h.wait_for(
        lambda state: not state["picker"]
        and not target.exists()
        and target not in _registrations(h),
        "confirmed normal removal deletes only the selected checkout and registration",
    )

    assert not target.exists() and not target.is_symlink()
    assert _registrations(h) == {
        path: record for path, record in registered.items() if path != target
    }
    for path, expected in contents.items():
        if path != target:
            assert path.is_dir(), path
            assert _checkout_contents(path) == expected, path
    assert common.is_dir()
    assert (common / "config").read_bytes() == common_config
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == refs
    assert h.git("rev-parse", "refs/heads/" + branch) == branch_head
    assert h.git("rev-parse", "HEAD") == source_head
    assert h.git("status", "--porcelain") == source_status
    assert _tab_ids(h) == tabs
    assert _pane_ids(h) == panes
    h.record("confirmed normal removal deletes only a clean unopened linked worktree, preserving refs and all other checkouts")

    # The source/main worktree is never a removal candidate.
    main_registration = _registrations(h)
    main_refs = h.git("show-ref")
    _expect_rejection(h, repo, "主工作树不可移除")
    assert _registrations(h) == main_registration
    assert h.git("show-ref") == main_refs
    h.record("normal removal refuses the main worktree without changing refs or registration")

    locked = repo.parent / "normal-removal-locked"
    _add_checkout(h, locked, "external/normal-removal-locked")
    h.git("worktree", "lock", "--reason", "operator maintenance", str(locked))
    locked_registration = _registrations(h)
    locked_refs = h.git("show-ref")
    _expect_rejection(h, locked, "已锁定")
    assert _registrations(h) == locked_registration
    assert h.git("show-ref") == locked_refs
    h.git("worktree", "unlock", str(locked))
    _remove_fixture(h, locked)
    h.record("normal removal refuses a locked checkout without changing Git state")

    tracked = repo.parent / "normal-removal-tracked"
    _reject_dirty_checkout(
        h, tracked, "external/normal-removal-tracked",
        "tracked modifications block normal removal without deleting bytes or refs",
        lambda: (tracked / "README.md").write_text("tracked local change\n"),
        lambda: (tracked / "README.md").write_text("committed\n"),
        "tracked 或 untracked 修改",
    )

    untracked = repo.parent / "normal-removal-untracked"
    untracked_file = untracked / "new local file.txt"
    _reject_dirty_checkout(
        h, untracked, "external/normal-removal-untracked",
        "untracked files block normal removal without deleting bytes or refs",
        lambda: untracked_file.write_text("keep me\n"),
        lambda: untracked_file.unlink(),
        "tracked 或 untracked 修改",
    )

    ignored = repo.parent / "normal-removal-ignored"
    common_dir = Path(h.git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    exclude = common_dir / "info" / "exclude"
    old_exclude = exclude.read_bytes()
    ignored_name = "normal-removal-ignored.bin"
    ignored_file = ignored / ignored_name
    _add_checkout(h, ignored, "external/normal-removal-ignored")
    exclude.write_bytes(old_exclude + (b"" if old_exclude.endswith(b"\n") else b"\n")
                        + ignored_name.encode() + b"\n")
    ignored_file.write_bytes(b"ignored data must survive\n")
    ignored_registration = _registrations(h)
    ignored_refs = h.git("show-ref")
    _expect_rejection(h, ignored, "ignored 文件")
    assert ignored_file.read_bytes() == b"ignored data must survive\n"
    assert _registrations(h) == ignored_registration and h.git("show-ref") == ignored_refs
    exclude.write_bytes(old_exclude)
    ignored_file.unlink()
    _remove_fixture(h, ignored)
    h.record("ignored files block normal removal without losing their bytes")

    for flag, set_flag, clear_flag in (
        ("assume-unchanged", "--assume-unchanged", "--no-assume-unchanged"),
        ("skip-worktree", "--skip-worktree", "--no-skip-worktree"),
    ):
        index_path = repo.parent / ("normal-removal-" + flag)
        branch_name = "external/normal-removal-" + flag
        _add_checkout(h, index_path, branch_name)
        h.git("update-index", set_flag, "README.md", cwd=index_path)
        (index_path / "README.md").write_text(flag + " hidden content\n")
        assert h.git("status", "--porcelain", cwd=index_path) == ""
        bytes_before = (index_path / "README.md").read_bytes()
        refs_before = h.git("show-ref")
        registrations_before = _registrations(h)
        _expect_rejection(h, index_path, "隐藏索引标记")
        assert (index_path / "README.md").read_bytes() == bytes_before
        assert h.git("show-ref") == refs_before and _registrations(h) == registrations_before
        (index_path / "README.md").write_text("committed\n")
        h.git("update-index", clear_flag, "README.md", cwd=index_path)
        _remove_fixture(h, index_path)
        h.record(flag + " index flags are detected even when Git status is clean")

    submodule = repo.parent / "normal-removal-submodule"
    _add_checkout(h, submodule, "external/normal-removal-submodule")
    submodule_oid = h.git("rev-parse", "HEAD")
    h.git("update-index", "--add", "--cacheinfo",
          "160000," + submodule_oid + ",embedded-submodule", cwd=submodule)
    submodule_refs = h.git("show-ref")
    _expect_rejection(h, submodule, "含有子模块")
    assert h.git("show-ref") == submodule_refs and submodule.is_dir()
    h.git("update-index", "--force-remove", "embedded-submodule", cwd=submodule)
    _remove_fixture(h, submodule)
    h.record("gitlink index entries are refused because submodule contents cannot be fully inspected")

    detached_oid = h.git("commit-tree", h.git("rev-parse", "HEAD^{tree}"),
                         "-p", h.git("rev-parse", "HEAD"), "-m", "unprotected detached removal fixture")
    detached = repo.parent / "normal-removal-unprotected-detached"
    h.git("worktree", "add", "--detach", str(detached), detached_oid)
    detached_refs = h.git("show-ref")
    detached_registration = _registrations(h)
    _expect_rejection(h, detached, "未受本地／远程分支或标签保护")
    assert h.git("show-ref") == detached_refs and _registrations(h) == detached_registration
    _remove_fixture(h, detached)
    h.record("unprotected detached commits are not considered safely removable")

    for kind, protected_ref in (
        ("local", "refs/heads/normal-removal-protected-local"),
        ("remote", "refs/remotes/origin/normal-removal-protected-remote"),
        ("tag", "refs/tags/normal-removal-protected-tag"),
    ):
        protected_oid = h.git("commit-tree", h.git("rev-parse", "HEAD^{tree}"),
                              "-p", h.git("rev-parse", "HEAD"), "-m", "protected detached " + kind)
        h.git("update-ref", protected_ref, protected_oid)
        protected = repo.parent / ("normal-removal-protected-" + kind)
        h.git("worktree", "add", "--detach", str(protected), protected_oid)
        assert h.git("for-each-ref", "--contains=" + protected_oid,
                     "--format=%(refname)") == protected_ref
        protected_refs = h.git("show-ref")
        _select_remove(h, protected)
        confirmation = h.picker(selected="取消")
        assert "取消" in (confirmation["selected"] or ""), confirmation
        h.type_text("确认无外部使用并移除")
        h.picker(selected="确认无外部使用并移除")
        h.ctl("picker enter")
        h.wait_for(
            lambda _state: not protected.exists() and protected not in _registrations(h),
            "detached worktree protected only by " + kind + " is removed after confirmation",
        )
        assert h.git("show-ref") == protected_refs
        assert h.git("rev-parse", protected_ref) == protected_oid
    h.record("local branches, remote refs and tags independently protect detached commits during normal removal")

    racing = repo.parent / "normal-removal-confirmation-race"
    _add_checkout(h, racing, "external/normal-removal-confirmation-race")
    _select_remove(h, racing)
    assert "取消" in (h.picker(selected="取消")["selected"] or "")
    race_file = racing / "created during confirmation.txt"
    race_file.write_text("must not be deleted\n")
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    _wait_management_rejection(h, "tracked 或 untracked 修改")
    assert race_file.read_text() == "must not be deleted\n"
    assert racing.is_dir() and racing in _registrations(h)
    race_file.unlink()
    _remove_fixture(h, racing)
    h.record("new untracked content during confirmation cancels removal and preserves bytes")
    linked_source = repo.parent / "normal-removal-linked-source"
    linked_target = repo.parent / "normal-removal-linked-source-target"
    _add_checkout(h, linked_source, "external/normal-removal-linked-source")
    _add_checkout(h, linked_target, "external/normal-removal-linked-target")
    _select_remove(h, linked_target, source=linked_source)
    h.picker(selected="取消")
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    h.wait_for(lambda _state: not linked_target.exists() and linked_target not in _registrations(h),
               "normal removal from a linked source checkout")
    assert repo in _registrations(h) and linked_source in _registrations(h)
    # 来源终端仍可见，保留其工作树，避免后续场景继承悬空 cwd。
    h.record("main worktree identity is independent of linked source checkout")

    nested_parent = repo.parent / "normal-removal-nested-current"
    nested_checkout = nested_parent / "child"
    _add_checkout(h, nested_parent, "external/normal-removal-nested-current")
    h.git("worktree", "add", "-b", "nested/current", str(nested_checkout), "HEAD")
    nested_registration = h.git("worktree", "list", "--porcelain", "-z")
    _expect_rejection(h, nested_parent, "目标目录内仍登记有其他 worktree")
    assert nested_checkout.is_dir() and nested_parent in _registrations(h)
    assert nested_registration == h.git("worktree", "list", "--porcelain", "-z")
    h.git("worktree", "remove", "--", str(nested_checkout))
    _remove_fixture(h, nested_parent)
    h.record("nested linked worktrees from the managed repository block parent removal")

    foreign_root = h.root / "foreign-nested-repository"
    foreign_checkout_parent = repo.parent / "normal-removal-foreign-nested"
    foreign_checkout = foreign_checkout_parent / "foreign-linked"
    foreign_root.mkdir()
    h.git("init", "-b", "main", cwd=foreign_root)
    h.git("config", "user.name", "Kiku Test", cwd=foreign_root)
    h.git("config", "user.email", "kiku@example.invalid", cwd=foreign_root)
    (foreign_root / "private.txt").write_text("foreign linked checkout\n")
    h.git("add", "private.txt", cwd=foreign_root)
    h.git("commit", "-m", "foreign linked root", cwd=foreign_root)
    _add_checkout(h, foreign_checkout_parent, "external/normal-removal-foreign-nested")
    h.git("worktree", "add", "-b", "foreign/linked", str(foreign_checkout), "HEAD", cwd=foreign_root)
    foreign_bytes = (foreign_checkout / "private.txt").read_bytes()
    foreign_registration = h.git("worktree", "list", "--porcelain", "-z", cwd=foreign_root)
    assert h.git(
        "status", "--porcelain=v1", "-z", "--untracked-files=all",
        "--ignore-submodules=none", cwd=foreign_checkout_parent,
    ) == "?? foreign-linked/\0"
    assert h.git("ls-files", "--others", "--exclude-standard", "-z",
                 cwd=foreign_checkout_parent) == "foreign-linked/\0"
    _expect_rejection(h, foreign_checkout_parent, "无法完整展开")
    assert (foreign_checkout / "private.txt").read_bytes() == foreign_bytes
    assert h.git("worktree", "list", "--porcelain", "-z", cwd=foreign_root) == foreign_registration
    h.git("worktree", "remove", "--", str(foreign_checkout), cwd=foreign_root)
    _remove_fixture(h, foreign_checkout_parent)
    h.record("foreign nested worktrees with unenumerable contents block parent removal")

    monitored = repo.parent / "normal-removal-fsmonitor"
    _add_checkout(h, monitored, "external/normal-removal-fsmonitor")
    monitor_hook = h.root / "fsmonitor-no-changes"
    monitor_hook.write_text("#!/bin/sh\nprintf 'probe-token\\000'\n")
    monitor_hook.chmod(0o755)
    h.git("config", "core.fsmonitor", str(monitor_hook))
    h.git("config", "core.fsmonitorHookVersion", "2")
    h.git("update-index", "--fsmonitor-valid", "--", "README.md", cwd=monitored)
    (monitored / "README.md").write_text("fsmonitor-hidden tracked edit\n")
    assert h.git("status", "--porcelain", cwd=monitored) == ""
    monitor_bytes = (monitored / "README.md").read_bytes()
    monitor_refs = h.git("show-ref")
    _expect_rejection(h, monitored, "tracked 或 untracked 修改")
    assert (monitored / "README.md").read_bytes() == monitor_bytes
    assert h.git("show-ref") == monitor_refs
    (monitored / "README.md").write_text("committed\n")
    h.git("update-index", "--no-fsmonitor", "--", "README.md", cwd=monitored)
    h.git("config", "--unset", "core.fsmonitorHookVersion")
    h.git("config", "--unset", "core.fsmonitor")
    _remove_fixture(h, monitored)
    h.record("Git fsmonitor-valid cache cannot hide tracked changes from removal review")

    changed_head = repo.parent / "normal-removal-head-race"
    _add_checkout(h, changed_head, "external/normal-removal-head-race")
    _select_remove(h, changed_head)
    assert "取消" in (h.picker(selected="取消")["selected"] or "")
    h.git("commit", "--allow-empty", "-m", "change HEAD during removal confirmation", cwd=changed_head)
    confirmed_head = h.git("rev-parse", "HEAD", cwd=changed_head)
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    _wait_management_rejection(h, "worktree、内容、refs 或可见 pane 状态已变化")
    assert changed_head.is_dir() and changed_head in _registrations(h)
    assert h.git("rev-parse", "HEAD", cwd=changed_head) == confirmed_head
    _remove_fixture(h, changed_head)
    h.record("HEAD changes during confirmation cancel removal and retain the new commit")

    locked_race = repo.parent / "normal-removal-lock-race"
    _add_checkout(h, locked_race, "external/normal-removal-lock-race")
    _select_remove(h, locked_race)
    assert "取消" in (h.picker(selected="取消")["selected"] or "")
    h.git("worktree", "lock", "--reason", "confirmation race", str(locked_race))
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    _wait_management_rejection(h, "已锁定")
    assert locked_race.is_dir() and locked_race in _registrations(h)
    h.git("worktree", "unlock", str(locked_race))
    _remove_fixture(h, locked_race)
    h.record("locking a worktree during confirmation cancels removal")

    stale = repo.parent / "normal-removal-prunable"
    _add_checkout(h, stale, "external/normal-removal-prunable")
    shutil.rmtree(stale)
    stale_registration = _registrations(h)
    assert "prunable" in stale_registration[stale]
    _expect_rejection(h, stale, "已失效或可清理", expected_exists=False)
    assert _registrations(h) == stale_registration and not stale.exists()
    h.git("worktree", "prune", "--expire", "now")
    h.record("prunable registrations are refused without pruning them")
    stale_other = repo.parent / "normal-removal-unrelated-prunable"
    _add_checkout(h, stale_other, "external/normal-removal-unrelated-prunable")
    shutil.rmtree(stale_other)
    safe_with_stale = repo.parent / "normal-removal-with-unrelated-prunable"
    _add_checkout(h, safe_with_stale, "external/normal-removal-with-unrelated-prunable")
    registrations_with_stale = _registrations(h)
    stale_record = registrations_with_stale[stale_other]
    _select_remove(h, safe_with_stale)
    h.picker(selected="取消")
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    h.wait_for(lambda _state: not safe_with_stale.exists()
               and safe_with_stale not in _registrations(h),
               "remove clean target despite an unrelated stale registration")
    assert _registrations(h)[stale_other] == stale_record
    assert not stale_other.exists()
    h.git("worktree", "prune", "--expire", "now")
    h.record("unrelated prunable registration does not block a clean target and remains untouched")

    replaced = repo.parent / "normal-removal-replaced-identity"
    moved = repo.parent / "normal-removal-original-identity"
    _add_checkout(h, replaced, "external/normal-removal-replaced-identity")
    original_bytes = _checkout_contents(replaced)
    replaced.rename(moved)
    replaced.mkdir()
    h.git("init", "-b", "replacement", cwd=replaced)
    _expect_rejection(h, replaced, "实际 root 或 common-dir 与来源仓库不符")
    assert _checkout_contents(moved) == original_bytes
    shutil.rmtree(replaced)
    moved.rename(replaced)
    _remove_fixture(h, replaced)
    h.record("a replaced path identity is refused without touching the original checkout")

    visible = repo.parent / "normal-removal-visible-pane"
    visible_subdir = visible / "terminal-subdirectory"
    _add_checkout(h, visible, "external/normal-removal-visible-pane")
    visible_subdir.mkdir()
    h.open_repo(repo)
    source_pane = int(h.lua("return cx.session:focused()"))
    visible_pane = int(h.lua(
        "return cx.layout:split(" + str(source_pane) + ", 'right', {cwd="
        + json.dumps(str(visible_subdir)) + "})"
    ))
    h.lua("cx.layout:float(" + str(visible_pane) + ", " + str(source_pane) + "); return true")
    _expect_rejection(h, visible, "正在使用目标 worktree")
    h.lua("cx.layout:close(" + str(visible_pane) + "); return true")
    _remove_fixture(h, visible)
    h.record("floating pane in a target subdirectory prevents normal removal")

    opened_during_confirmation = repo.parent / "normal-removal-pane-confirmation-race"
    opened_subdir = opened_during_confirmation / "newly-opened"
    _add_checkout(h, opened_during_confirmation, "external/normal-removal-pane-confirmation-race")
    opened_subdir.mkdir()
    _select_remove(h, opened_during_confirmation)
    assert "取消" in (h.picker(selected="取消")["selected"] or "")
    source_pane = int(h.lua("return cx.session:focused()"))
    raced_pane = int(h.lua(
        "return cx.layout:split(" + str(source_pane) + ", 'right', {cwd="
        + json.dumps(str(opened_subdir)) + "})"
    ))
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    _wait_management_rejection(h, "正在使用目标 worktree")
    assert opened_during_confirmation.is_dir()
    h.lua("cx.layout:close(" + str(raced_pane) + "); return true")
    _remove_fixture(h, opened_during_confirmation)
    h.record("newly opened subdirectory terminal during confirmation prevents removal")
    parked = repo.parent / "normal-removal-parked-pane"
    _add_checkout(h, parked, "external/normal-removal-parked-pane")
    h.lua("return cx.layout:new_tab({cwd=" + json.dumps(str(parked)) + "})")
    h.ctl("ready")
    parked_pane = next(
        pane["pane"] for pane in h.lua_json("cx.session:panes()")
        if Path(pane.get("cwd") or "").resolve() == parked.resolve()
    )
    h.lua("cx.layout:park(" + str(parked_pane) + "); return true")
    h.open_repo(repo)
    _expect_rejection(h, parked, "正在使用目标 worktree")
    h.lua("cx.layout:close(" + str(parked_pane) + "); return true")
    _remove_fixture(h, parked)
    h.record("parked pane cwd prevents normal removal")

    path_target = repo.parent / "normal-removal-native-file-path"
    _add_checkout(h, path_target, "external/normal-removal-native-file-path")
    path_alias = h.root / "normal-removal-file-alias"
    path_alias.symlink_to(path_target / "README.md")
    h.open_repo(repo)
    file_pane = int(h.lua(
        "return cx.docs:open(" + json.dumps(str(path_alias)) + ", {how='beside'})"
    ))
    h.open_repo(repo)
    _expect_rejection(h, path_target, "正在使用目标 worktree")
    h.lua("cx.layout:close(" + str(file_pane) + "); return true")
    path_alias.unlink()
    _remove_fixture(h, path_target)
    h.record("native file path symlink resolving into a worktree prevents normal removal")

    failed = repo.parent / "normal-removal-git-failure"
    _add_checkout(h, failed, "external/normal-removal-git-failure")
    _select_remove(h, failed)
    assert "取消" in (h.picker(selected="取消")["selected"] or "")
    git_dir = Path(h.git("rev-parse", "--absolute-git-dir", cwd=failed))
    index_path = git_dir / "index"
    original_index = index_path.read_bytes()
    original_readme = (failed / "README.md").read_bytes()
    index_path.write_bytes(b"not a git index")
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")
    _wait_management_rejection(h, "Git status 失败")
    assert failed.is_dir() and (failed / "README.md").read_bytes() == original_readme
    index_path.write_bytes(original_index)
    _remove_fixture(h, failed)
    h.record("real Git status failure preserves the checkout without a force retry")
