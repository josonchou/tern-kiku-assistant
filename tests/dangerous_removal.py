"""Real Git dangerous removal through the native management interaction."""

import json
from pathlib import Path

from management import _select_worktree, _wait_management_rejection
from removal import _checkout_contents, _registrations, _select_remove

def _begin_dangerous(h, target, source=None):
    _select_remove(h, target, source=source, action="危险移除 worktree")
    preview = h.picker(selected="取消")
    assert "取消" in (preview["selected"] or ""), preview
    return preview


def _authorize_to_external_confirmation(h, target, source=None):
    _begin_dangerous(h, target, source=source)
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    path_prompt = h.picker("prompt")
    assert path_prompt["query"] == "", path_prompt
    h.type_text(str(target))
    h.ctl("key enter")
    confirmation = h.picker(selected="取消")
    assert "取消" in (confirmation["selected"] or ""), confirmation
    return confirmation


def _confirm_dangerous(h):
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")


def _registrations_at(h, repository):
    output = h.git("worktree", "list", "--porcelain", "-z", cwd=repository)
    assert output.endswith("\0\0"), repr(output)
    registrations = {}
    for record in output[:-2].split("\0\0"):
        first = record.split("\0", 1)[0]
        assert first.startswith("worktree "), repr(record)
        path = Path(first.removeprefix("worktree "))
        assert path not in registrations, path
        registrations[path] = record
    return registrations


def run(h):
    repo = h.repo
    target = repo.parent / "dangerous-removal-local-content"
    branch = "external/dangerous-removal-local-content"
    neighbor = repo.parent / "dangerous-removal-preserved-checkout"
    neighbor_branch = "external/dangerous-removal-preserved-checkout"
    h.git("worktree", "add", "-b", branch, str(target), "HEAD")
    h.git("worktree", "add", "-b", neighbor_branch, str(neighbor), "HEAD")
    changed = target / "README.md"
    changed.write_text("local content explicitly discarded\n")
    assert h.git("diff", "--name-only", cwd=target) == "README.md"

    h.open_repo(repo)
    registrations = _registrations(h)
    contents = {path: _checkout_contents(path) for path in registrations}
    refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    branch_head = h.git("rev-parse", "refs/heads/" + branch)
    neighbor_branch_head = h.git("rev-parse", "refs/heads/" + neighbor_branch)

    # Ordinary removal is deliberately not authorized to discard this change.
    _select_remove(h, target)
    _wait_management_rejection(h)
    assert target.is_dir() and target in _registrations(h)
    assert changed.read_text() == "local content explicitly discarded\n"

    # The separate action presents the risk review before any destructive choice.
    _select_worktree(h, target, action="危险移除 worktree")
    preview = h.picker(selected="取消")
    assert "取消" in (preview["selected"] or ""), preview
    assert target.is_dir() and target in _registrations(h)
    assert "README.md" in json.dumps(h.ctl("tree"), ensure_ascii=False)
    h.ctl("shot dangerous-removal-risk-preview")
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    path_prompt = h.picker("prompt")
    assert path_prompt["query"] == "", path_prompt
    h.type_text(str(target))
    assert h.picker("prompt")["query"] == str(target)
    h.ctl("key enter")

    external = h.picker(selected="取消")
    assert "取消" in (external["selected"] or ""), external
    assert target.is_dir() and target in _registrations(h)
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    h.wait_for(
        lambda state: not state["picker"] and not target.exists()
        and target not in _registrations(h),
        "confirmed dangerous removal deletes only the selected checkout and registration",
    )

    assert not target.exists() and target not in _registrations(h)
    assert _registrations(h) == {path: record for path, record in registrations.items() if path != target}
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == refs
    assert h.git("rev-parse", "refs/heads/" + branch) == branch_head
    assert h.git("rev-parse", "refs/heads/" + neighbor_branch) == neighbor_branch_head
    for path, expected in contents.items():
        if path != target:
            assert path.is_dir(), path
            assert _checkout_contents(path) == expected, path
    h.record("explicit dangerous removal discards acknowledged local content while preserving branch and other checkouts")

    # Re-create the same dirty checkout and exercise the authorization boundary.
    h.git("worktree", "add", str(target), branch)
    changed.write_text("content must survive every cancelled attempt\n")
    unchanged_registrations = _registrations(h)
    unchanged_contents = _checkout_contents(target)
    unchanged_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")

    def assert_retained():
        assert target.is_dir()
        assert _registrations(h) == unchanged_registrations
        assert _checkout_contents(target) == unchanged_contents
        assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == unchanged_refs

    def begin_dangerous():
        _select_worktree(h, target, action="危险移除 worktree")
        return h.picker(selected="取消")

    # Viewing and editing the full path is read-only; it does not authorize removal.
    begin_dangerous()
    h.type_text("查看完整目标路径…")
    h.picker(selected="查看完整目标路径")
    h.ctl("picker enter")
    preview_path = h.picker("prompt")
    assert preview_path["query"] == str(target), preview_path
    h.replace_text(str(target) + "-edited")
    h.ctl("key enter")
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    assert_retained()
    h.ctl("picker esc")
    h.wait_for(lambda state: not state["picker"], "cancel risk preview after read-only path view")
    assert_retained()

    # Cancelling the preview and the subsequent empty path prompt are independent.
    begin_dangerous()
    h.ctl("picker esc")
    h.wait_for(lambda state: not state["picker"], "cancel dangerous risk preview")
    assert_retained()

    begin_dangerous()
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    empty_path = h.picker("prompt")
    assert empty_path["query"] == "", empty_path
    h.ctl("picker esc")
    h.wait_for(lambda state: not state["picker"], "cancel full-path authorization input")
    assert_retained()

    # A wrong path can be corrected, but cannot advance to external-use confirmation.
    begin_dangerous()
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    assert h.picker("prompt")["query"] == ""
    h.type_text(str(target) + "-wrong")
    h.ctl("key enter")
    h.type_text("重新输入完整路径")
    correction = h.picker(selected="重新输入完整路径")
    assert "重新输入完整路径" in (correction["selected"] or ""), correction
    assert_retained()
    h.ctl("picker enter")
    retry_path = h.picker("prompt")
    assert retry_path["query"] == "", retry_path
    h.type_text(str(target))
    h.ctl("key enter")
    external = h.picker(selected="取消")
    assert "取消" in (external["selected"] or ""), external
    h.ctl("picker esc")
    h.wait_for(lambda state: not state["picker"], "cancel final external-use confirmation")
    assert_retained()

    # A fresh full authorization after all cancellations still works immediately.
    begin_dangerous()
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    assert h.picker("prompt")["query"] == ""
    h.type_text(str(target))
    h.ctl("key enter")
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    h.wait_for(
        lambda state: not state["picker"] and not target.exists()
        and target not in _registrations(h),
        "new dangerous-removal attempt succeeds after prior cancellations",
    )
    assert not target.exists()
    assert _registrations(h) == {
        path: record for path, record in unchanged_registrations.items() if path != target
    }
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == unchanged_refs
    h.record("read-only path preview and every cancelled authorization stage preserve data and release the flow lock")

    ignored_target = repo.parent / "dangerous-removal-ignored-only"
    ignored_branch = "external/dangerous-removal-ignored-only"
    ignored_name = "discard-ignored-only.bin"
    h.git("worktree", "add", "-b", ignored_branch, str(ignored_target), "HEAD")
    common = Path(h.git("rev-parse", "--path-format=absolute", "--git-common-dir"))
    exclude = common / "info" / "exclude"
    original_exclude = exclude.read_bytes()
    try:
        separator = b"" if original_exclude.endswith(b"\n") else b"\n"
        exclude.write_bytes(original_exclude + separator + ignored_name.encode() + b"\n")
        ignored_file = ignored_target / ignored_name
        ignored_file.write_bytes(b"ignored-only local content explicitly discarded\n")
        assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all",
                     cwd=ignored_target) == ""
        assert h.git("ls-files", "--others", "--exclude-standard", "-z",
                     cwd=ignored_target) == ""
        assert h.git("ls-files", "--others", "--ignored", "--exclude-standard", "-z",
                     cwd=ignored_target) == ignored_name + "\0"
        ignored_registrations = _registrations(h)
        ignored_contents = {
            path: _checkout_contents(path) for path in ignored_registrations
        }
        ignored_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
        _select_remove(h, ignored_target)
        _wait_management_rejection(h)
        assert _registrations(h) == ignored_registrations
        assert _checkout_contents(ignored_target) == ignored_contents[ignored_target]
        assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == ignored_refs

        _select_worktree(h, ignored_target, action="危险移除 worktree")
        preview = h.picker(selected="取消")
        assert "取消" in (preview["selected"] or ""), preview
        assert ignored_name in json.dumps(h.ctl("tree"), ensure_ascii=False)
        assert ignored_file.read_bytes() == b"ignored-only local content explicitly discarded\n"
        h.type_text("继续：输入完整目标路径")
        h.picker(selected="继续：输入完整目标路径")
        h.ctl("picker enter")
        assert h.picker("prompt")["query"] == ""
        h.type_text(str(ignored_target))
        h.ctl("key enter")
        external = h.picker(selected="取消")
        assert "取消" in (external["selected"] or ""), external
        assert _registrations(h) == ignored_registrations
        assert _checkout_contents(ignored_target) == ignored_contents[ignored_target]
        h.type_text("确认无外部使用并危险移除")
        h.picker(selected="确认无外部使用并危险移除")
        h.ctl("picker enter")
        h.wait_for(
            lambda state: not state["picker"] and not ignored_target.exists()
            and ignored_target not in _registrations(h),
            "ignored-only dangerous removal deletes the authorized checkout and registration",
        )
        assert not ignored_target.exists()
        assert _registrations(h) == {
            path: record for path, record in ignored_registrations.items()
            if path != ignored_target
        }
        assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == ignored_refs
        for path, expected in ignored_contents.items():
            if path != ignored_target:
                assert path.is_dir(), path
                assert _checkout_contents(path) == expected, path
    finally:
        exclude.write_bytes(original_exclude)
    assert exclude.read_bytes() == original_exclude
    h.record("ignored-only content is refused normally and explicitly discarded through dangerous removal while refs and other checkouts survive")

    detached_oid = h.git(
        "commit-tree", h.git("rev-parse", "HEAD^{tree}"),
        "-p", h.git("rev-parse", "HEAD"), "-m",
        "unprotected detached dangerous-removal fixture",
    )
    protected_refs = h.git(
        "for-each-ref", "--contains=" + detached_oid,
        "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags",
    )
    assert protected_refs == ""
    detached_target = repo.parent / "dangerous-removal-unprotected-detached"
    h.git("worktree", "add", "--detach", str(detached_target), detached_oid)
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all",
                 cwd=detached_target) == ""
    assert h.git("ls-files", "--others", "--exclude-standard", "-z",
                 cwd=detached_target) == ""
    detached_registrations = _registrations(h)
    detached_contents = {
        path: _checkout_contents(path) for path in detached_registrations
    }
    detached_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    _select_remove(h, detached_target)
    _wait_management_rejection(h)
    assert _registrations(h) == detached_registrations
    assert _checkout_contents(detached_target) == detached_contents[detached_target]
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == detached_refs

    _select_worktree(h, detached_target, action="危险移除 worktree")
    preview = h.picker(selected="取消")
    assert "取消" in (preview["selected"] or ""), preview
    assert detached_oid in json.dumps(h.ctl("tree"), ensure_ascii=False)
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    assert h.picker("prompt")["query"] == ""
    h.type_text(str(detached_target))
    h.ctl("key enter")
    external = h.picker(selected="取消")
    assert "取消" in (external["selected"] or ""), external
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    h.wait_for(
        lambda state: not state["picker"] and not detached_target.exists()
        and detached_target not in _registrations(h),
        "authorized unprotected detached removal deletes only its checkout and registration",
    )
    assert not detached_target.exists()
    assert _registrations(h) == {
        path: record for path, record in detached_registrations.items()
        if path != detached_target
    }
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == detached_refs
    for path, expected in detached_contents.items():
        if path != detached_target:
            assert path.is_dir(), path
            assert _checkout_contents(path) == expected, path
    assert h.git(
        "for-each-ref", "--contains=" + detached_oid,
        "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags",
    ) == ""
    h.record("unprotected detached commit is previewed and explicitly discarded without creating refs or changing other checkouts")

    many_target = repo.parent / "dangerous-removal-long-untracked-list"
    many_branch = "external/dangerous-removal-long-untracked-list"
    h.git("worktree", "add", "-b", many_branch, str(many_target), "HEAD")
    long_name = "a-000-" + "long-risk-filename-" * 10 + ".txt"
    many_files = {
        long_name: b"long untracked risk\n",
        **{
            f"b-{index:03d}-untracked.txt": f"untracked risk {index}\n".encode()
            for index in range(1, 200)
        },
    }
    for name, content in many_files.items():
        (many_target / name).write_bytes(content)
    status_records = h.git(
        "status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=many_target
    ).split("\0")
    assert {record[3:] for record in status_records if record} == set(many_files)
    assert h.git("diff", "--name-only", cwd=many_target) == ""
    assert h.git("ls-files", "--others", "--ignored", "--exclude-standard", "-z",
                 cwd=many_target) == ""
    many_registrations = _registrations(h)
    many_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    many_contents = {path: _checkout_contents(path) for path in many_registrations}

    _select_remove(h, many_target)
    _wait_management_rejection(h)
    assert _registrations(h) == many_registrations
    assert {name: (many_target / name).read_bytes() for name in many_files} == many_files

    def begin_many_dangerous():
        _select_worktree(h, many_target, action="危险移除 worktree")
        preview = h.picker(selected="取消")
        assert "取消" in (preview["selected"] or ""), preview
        return preview

    begin_many_dangerous()
    h.ctl("shot dangerous-removal-truncated-risk-preview")
    h.type_text("a-000-")
    long_risk = h.picker(selected="a-000-")
    assert "a-000-" in (long_risk["selected"] or ""), long_risk
    h.ctl("picker enter")
    risk_detail = h.picker("prompt")
    assert long_name in (risk_detail["query"] or ""), risk_detail
    h.replace_text("edited read-only risk preview")
    h.ctl("key enter")
    h.picker()
    assert {name: (many_target / name).read_bytes() for name in many_files} == many_files

    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    assert h.picker("prompt")["query"] == ""
    h.type_text(str(many_target))
    h.ctl("key enter")
    external = h.picker(selected="取消")
    assert "取消" in (external["selected"] or ""), external
    late_name = "zzzz-added-after-risk-preview.txt"
    late_file = many_target / late_name
    late_file.write_bytes(b"added after the complete risk preview\n")
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    _wait_management_rejection(h)
    assert many_target.is_dir() and late_file.read_bytes() == b"added after the complete risk preview\n"
    assert {name: (many_target / name).read_bytes() for name in many_files} == many_files
    assert _registrations(h) == many_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == many_refs

    # After rejecting the stale confirmation, a new complete authorization succeeds.
    begin_many_dangerous()
    h.type_text("继续：输入完整目标路径")
    h.picker(selected="继续：输入完整目标路径")
    h.ctl("picker enter")
    assert h.picker("prompt")["query"] == ""
    h.type_text(str(many_target))
    h.ctl("key enter")
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    h.wait_for(
        lambda state: not state["picker"] and not many_target.exists()
        and many_target not in _registrations(h),
        "fresh authorization removes the complete untracked-only checkout",
    )
    assert not many_target.exists()
    assert _registrations(h) == {
        path: record for path, record in many_registrations.items() if path != many_target
    }
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == many_refs
    for path, expected in many_contents.items():
        if path != many_target:
            assert path.is_dir(), path
            assert _checkout_contents(path) == expected, path
    h.record("long untracked risk entries are inspectable and hidden late changes invalidate authorization")

    # Dangerous removal keeps the same hard protections as normal removal.
    main_contents = {
        path: content for path, content in _checkout_contents(repo).items()
        if path != ".git" and not path.startswith(".git/")
    }
    hard_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    hard_registrations = _registrations(h)
    _select_remove(h, repo, action="危险移除 worktree")
    _wait_management_rejection(h)
    assert {
        path: content for path, content in _checkout_contents(repo).items()
        if path != ".git" and not path.startswith(".git/")
    } == main_contents
    assert _registrations(h) == hard_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == hard_refs
    h.record("dangerous removal refuses the main worktree without changing content, refs or registration")

    locked = repo.parent / "dangerous-removal-locked"
    h.git("worktree", "add", "-b", "external/dangerous-removal-locked", str(locked), "HEAD")
    h.git("worktree", "lock", "--reason", "operator maintenance", str(locked))
    locked_contents = _checkout_contents(locked)
    locked_registrations = _registrations(h)
    locked_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    _select_remove(h, locked, action="危险移除 worktree")
    _wait_management_rejection(h)
    assert locked.is_dir() and _checkout_contents(locked) == locked_contents
    assert _registrations(h) == locked_registrations
    assert "locked" in locked_registrations[locked]
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == locked_refs
    h.record("dangerous removal refuses a locked worktree without unlocking or changing its state")

    stale = repo.parent / "dangerous-removal-prunable"
    stale_moved = repo.parent / "dangerous-removal-prunable-preserved"
    h.git("worktree", "add", "-b", "external/dangerous-removal-prunable", str(stale), "HEAD")
    stale.rename(stale_moved)
    stale_contents = _checkout_contents(stale_moved)
    stale_registrations = _registrations(h)
    stale_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    assert "prunable" in stale_registrations[stale]
    _select_remove(h, stale, action="危险移除 worktree")
    _wait_management_rejection(h)
    assert not stale.exists() and stale_moved.is_dir()
    assert _checkout_contents(stale_moved) == stale_contents
    assert _registrations(h) == stale_registrations and "prunable" in _registrations(h)[stale]
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == stale_refs
    h.record("dangerous removal refuses a prunable registration without pruning or changing its checkout")

    for flag, set_flag in (
        ("assume-unchanged", "--assume-unchanged"),
        ("skip-worktree", "--skip-worktree"),
    ):
        hidden = repo.parent / ("dangerous-removal-" + flag)
        branch = "external/dangerous-removal-" + flag
        h.git("worktree", "add", "-b", branch, str(hidden), "HEAD")
        h.git("update-index", set_flag, "README.md", cwd=hidden)
        readme = hidden / "README.md"
        readme.write_text(flag + " content hidden from status\n")
        assert h.git("status", "--porcelain", cwd=hidden) == ""
        index_state = h.git("ls-files", "-v", "--stage", "-z", cwd=hidden)
        hidden_contents = _checkout_contents(hidden)
        hidden_registrations = _registrations(h)
        hidden_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
        _select_remove(h, hidden, action="危险移除 worktree")
        _wait_management_rejection(h)
        assert hidden.is_dir() and _checkout_contents(hidden) == hidden_contents
        assert h.git("ls-files", "-v", "--stage", "-z", cwd=hidden) == index_state
        assert _registrations(h) == hidden_registrations
        assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == hidden_refs
    h.record("dangerous removal refuses assume-unchanged and skip-worktree content without repairing the index")

    bare = repo.parent / "dangerous-removal-bare.git"
    bare_source = repo.parent / "dangerous-removal-bare-source"
    h.git("clone", "--bare", str(repo), str(bare))
    h.git("worktree", "add", "-b", "external/dangerous-removal-bare-source",
          str(bare_source), "HEAD", cwd=bare)
    h.open_repo(bare_source)
    bare_registrations = _registrations_at(h, bare)
    bare_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", cwd=bare)
    bare_contents = _checkout_contents(bare)
    _select_remove(h, bare, source=bare_source, action="危险移除 worktree")
    _wait_management_rejection(h)
    assert bare.is_dir() and bare_source.is_dir()
    assert _checkout_contents(bare) == bare_contents
    assert _registrations_at(h, bare) == bare_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", cwd=bare) == bare_refs
    h.record("dangerous removal refuses a bare main worktree when initiated from its linked source")

    # Reaching the external-use confirmation does not bypass the pane recheck.
    in_use = repo.parent / "dangerous-removal-confirmation-use"
    h.git("worktree", "add", "-b", "external/dangerous-removal-confirmation-use",
          str(in_use), "HEAD")
    in_use_registrations = _registrations(h)
    in_use_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    in_use_contents = _checkout_contents(in_use)
    _authorize_to_external_confirmation(h, in_use)
    subdirectory = in_use / "opened-during-confirmation"
    subdirectory.mkdir()
    source_pane = int(h.lua("return cx.session:focused()"))
    raced_pane = int(h.lua(
        "return cx.layout:split(" + str(source_pane) + ", 'right', {cwd="
        + json.dumps(str(subdirectory)) + "})"
    ))
    h.type_text("确认无外部使用并危险移除")
    h.picker(selected="确认无外部使用并危险移除")
    h.ctl("picker enter")
    _wait_management_rejection(h)
    assert in_use.is_dir() and subdirectory.is_dir()
    assert h.lua(f"return cx.session:pane({raced_pane}) ~= nil") == "true"
    assert _registrations(h) == in_use_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == in_use_refs
    assert _checkout_contents(in_use) == in_use_contents | {
        "opened-during-confirmation": ("directory",),
    }
    h.lua(f"cx.layout:close({raced_pane}); return true")
    h.git("worktree", "remove", "--", str(in_use))
    h.record("a pane opened under the target before confirmation prevents dangerous removal and preserves the pane")

    # A changed HEAD after path and external confirmation is retained, not reset.
    head_race = repo.parent / "dangerous-removal-confirmation-head-change"
    head_branch = "external/dangerous-removal-confirmation-head-change"
    h.git("worktree", "add", "-b", head_branch, str(head_race), "HEAD")
    head_contents = _checkout_contents(head_race)
    _authorize_to_external_confirmation(h, head_race)
    old_head = h.git("rev-parse", "HEAD", cwd=head_race)
    new_head = h.git(
        "commit-tree", h.git("rev-parse", "HEAD^{tree}", cwd=head_race),
        "-p", old_head, "-m", "head changed during dangerous-removal confirmation",
    )
    h.git("update-ref", "refs/heads/" + head_branch, new_head)
    changed_head_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    changed_head_registrations = _registrations(h)
    assert h.git("rev-parse", "HEAD", cwd=head_race) == new_head
    _confirm_dangerous(h)
    _wait_management_rejection(h)
    assert head_race.is_dir() and _checkout_contents(head_race) == head_contents
    assert h.git("rev-parse", "refs/heads/" + head_branch) == new_head
    assert _registrations(h) == changed_head_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == changed_head_refs
    h.record("a new HEAD during dangerous confirmation is preserved and invalidates the old authorization")

    # Symbolic branch state alone also invalidates the old confirmation.
    symbolic_race = repo.parent / "dangerous-removal-confirmation-symbolic-change"
    symbolic_branch = "external/dangerous-removal-confirmation-symbolic-change"
    h.git("worktree", "add", "-b", symbolic_branch, str(symbolic_race), "HEAD")
    symbolic_contents = _checkout_contents(symbolic_race)
    symbolic_head = h.git("rev-parse", "HEAD", cwd=symbolic_race)
    symbolic_before_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    symbolic_before_registrations = _registrations(h)
    _authorize_to_external_confirmation(h, symbolic_race)
    symbolic_before = h.git("symbolic-ref", "--quiet", "HEAD", cwd=symbolic_race)
    assert symbolic_before == "refs/heads/" + symbolic_branch
    h.git("checkout", "--detach", symbolic_head, cwd=symbolic_race)
    assert h.git("rev-parse", "HEAD", cwd=symbolic_race) == symbolic_head
    detached_state_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    detached_state_registrations = _registrations(h)
    assert detached_state_refs == symbolic_before_refs
    assert "branch " + "refs/heads/" + symbolic_branch in symbolic_before_registrations[symbolic_race]
    assert "detached" in detached_state_registrations[symbolic_race]
    assert detached_state_registrations[symbolic_race] != symbolic_before_registrations[symbolic_race]
    _confirm_dangerous(h)
    _wait_management_rejection(h)
    assert symbolic_race.is_dir() and _checkout_contents(symbolic_race) == symbolic_contents
    assert h.git("rev-parse", "HEAD", cwd=symbolic_race) == symbolic_head
    detached_symbolic = h.git("symbolic-ref", "--quiet", "HEAD", cwd=symbolic_race, check=False)
    assert detached_symbolic.returncode == 1 and detached_symbolic.stdout == ""
    assert _registrations(h) == detached_state_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == detached_state_refs
    h.record("a symbolic HEAD change with identical commit invalidates dangerous confirmation without restoring the branch")

    # Replacing the selected directory's Git identity during confirmation is retained.
    replaced = repo.parent / "dangerous-removal-confirmation-replaced-path"
    original_moved = repo.parent / "dangerous-removal-original-path-preserved"
    replacement_saved = repo.parent / "dangerous-removal-replacement-repository-preserved"
    replaced_branch = "external/dangerous-removal-confirmation-replaced-path"
    h.git("worktree", "add", "-b", replaced_branch, str(replaced), "HEAD")
    original_identity_contents = _checkout_contents(replaced)
    original_identity_regs = _registrations(h)
    original_identity_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    _authorize_to_external_confirmation(h, replaced)
    replaced.rename(original_moved)
    replaced.mkdir()
    h.git("init", "-b", "replacement", cwd=replaced)
    (replaced / "replacement.txt").write_text("replacement identity must remain\n")
    replacement_root = h.git("rev-parse", "--show-toplevel", cwd=replaced)
    replacement_common = h.git(
        "rev-parse", "--path-format=absolute", "--git-common-dir", cwd=replaced
    )
    replacement_config = (replaced / ".git" / "config").read_bytes()
    _confirm_dangerous(h)
    _wait_management_rejection(h)
    assert replaced.is_dir() and (replaced / "replacement.txt").read_text() == "replacement identity must remain\n"
    assert h.git("rev-parse", "--show-toplevel", cwd=replaced) == replacement_root
    assert h.git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=replaced) == replacement_common
    assert (replaced / ".git" / "config").read_bytes() == replacement_config
    assert original_moved.is_dir() and _checkout_contents(original_moved) == original_identity_contents
    assert _registrations(h) == original_identity_regs
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == original_identity_refs
    replaced.rename(replacement_saved)
    original_moved.rename(replaced)
    assert _checkout_contents(replaced) == original_identity_contents
    h.record("replacement Git identity at the selected path is refused without repairing either checkout")

    for kind, status_code in (("rename", "R "), ("copy", "C ")):
        protocol_target = repo.parent / ("dangerous-removal-staged-" + kind)
        protocol_branch = "external/dangerous-removal-staged-" + kind
        h.git("worktree", "add", "-b", protocol_branch, str(protocol_target), "HEAD")
        original_name = "README.md"
        destination_name = kind + ' 空格 "目标".txt'
        original_file = protocol_target / original_name
        destination_file = protocol_target / destination_name
        common_dir = Path(h.git("rev-parse", "--path-format=absolute", "--git-common-dir"))
        repository_config = common_dir / "config"
        original_config = repository_config.read_bytes()
        try:
            if kind == "copy":
                h.git("config", "--local", "status.renames", "copies")
                destination_file.write_bytes(original_file.read_bytes())
                original_file.write_text("modified original for genuine staged copy detection\n")
                h.git("add", "--", original_name, destination_name, cwd=protocol_target)
            else:
                h.git("mv", "--", original_name, destination_name, cwd=protocol_target)
            protocol_records = h.git(
                "status", "--porcelain=v1", "-z", "--untracked-files=all",
                cwd=protocol_target,
            ).split("\0")
            destination_record = status_code + " " + destination_name
            destination_index = protocol_records.index(destination_record)
            assert protocol_records[destination_index + 1] == original_name, protocol_records
            if kind == "copy":
                assert "M  " + original_name in protocol_records, protocol_records
            else:
                assert protocol_records == [destination_record, original_name, ""], protocol_records
            protocol_registrations = _registrations(h)
            protocol_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
            protocol_presence = {
                path: (path.exists(), path.is_symlink()) for path in protocol_registrations
            }
            protocol_contents = {
                path: _checkout_contents(path) for path in protocol_registrations
                if path.is_dir()
            }
            _begin_dangerous(h, protocol_target)
            h.type_text(destination_name)
            h.picker(selected=destination_name)
            h.ctl("picker enter")
            destination_preview = h.picker("prompt")
            assert destination_name in destination_preview["query"], destination_preview
            h.ctl("key enter")
            h.picker()
            # Selecting this explicit row proves that the extra R/C NUL path
            # was consumed, independently of a copy source's separate M record.
            h.type_text("原始路径：")
            original_risk = h.picker(selected="原始路径：")
            assert original_name in original_risk["selected"], original_risk
            h.ctl("picker enter")
            original_preview = h.picker("prompt")
            assert original_name in original_preview["query"], original_preview
            h.ctl("key enter")
            h.picker()
            h.type_text("继续：输入完整目标路径")
            h.picker(selected="继续：输入完整目标路径")
            h.ctl("picker enter")
            assert h.picker("prompt")["query"] == ""
            h.type_text(str(protocol_target))
            h.ctl("key enter")
            h.picker(selected="取消")
            _confirm_dangerous(h)
            h.wait_for(
                lambda state: not state["picker"] and not protocol_target.exists()
                and protocol_target not in _registrations(h),
                "authorized staged " + kind + " removal preserves other checkouts",
            )
            assert not protocol_target.exists()
            assert _registrations(h) == {
                path: record for path, record in protocol_registrations.items()
                if path != protocol_target
            }
            assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == protocol_refs
            for path, expected in protocol_presence.items():
                if path != protocol_target:
                    assert (path.exists(), path.is_symlink()) == expected, path
            for path, expected in protocol_contents.items():
                if path != protocol_target:
                    assert path.is_dir(), path
                    assert _checkout_contents(path) == expected, path
        finally:
            repository_config.write_bytes(original_config)
        assert repository_config.read_bytes() == original_config
        h.record("staged " + kind + " exposes both NUL-protocol paths and removes only the authorized checkout")

    late_locked = repo.parent / "dangerous-removal-locked-after-authorization"
    h.git("worktree", "add", "-b", "external/dangerous-removal-late-locked",
          str(late_locked), "HEAD")
    _authorize_to_external_confirmation(h, late_locked)
    late_lock_reason = "operator locked after complete path authorization"
    h.git("worktree", "lock", "--reason", late_lock_reason, str(late_locked))
    late_locked_registrations = _registrations(h)
    late_locked_refs = h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
    late_locked_contents = _checkout_contents(late_locked)
    assert "locked " + late_lock_reason in late_locked_registrations[late_locked]
    _confirm_dangerous(h)
    _wait_management_rejection(h)
    assert late_locked.is_dir() and _checkout_contents(late_locked) == late_locked_contents
    assert _registrations(h) == late_locked_registrations
    assert h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)") == late_locked_refs
    h.record("locking the target at final external confirmation prevents removal and preserves the operator lock")
