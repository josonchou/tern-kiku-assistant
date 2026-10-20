"""Real Git pending-operation protection through native removal interactions."""


from pathlib import Path

from dangerous_removal import _authorize_to_external_confirmation, _confirm_dangerous
from management import _has_error_alert
from removal import _checkout_contents, _registrations, _select_remove


_PROTECTED_FIELDS = ("head", "index", "refs", "status", "untracked", "ignored")


def _snapshot(h, target):
    return {
        "head": h.git("rev-parse", "HEAD", cwd=target),
        "index": h.git("ls-files", "--stage", "-v", "-z", cwd=target),
        "refs": h.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", cwd=target),
        "status": h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=target),
        "untracked": h.git("ls-files", "--others", "--exclude-standard", "-z", cwd=target),
        "ignored": h.git("ls-files", "--others", "--ignored", "--exclude-standard", "-z", cwd=target),
    }


def _root_refs(h, target):
    return h.git(
        "for-each-ref", "--include-root-refs",
        "--format=%(refname)%00%(objectname)%00%(symref)", cwd=target,
    )


def _root_ref_ids(root_refs):
    refs = {}
    for record in root_refs.splitlines():
        name, oid, _symref = record.split("\0")
        refs[name] = oid
    return refs


def _add_clean_target(h, target, branch):
    h.git("worktree", "add", "-b", branch, str(target), "HEAD")
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=target) == ""
    return target


def _start_pending_operation(h, target, incoming_message):
    before = _snapshot(h, target)
    assert before["status"] == "" and before["untracked"] == "" and before["ignored"] == ""
    saved_content = "uncommitted content held only by autostash\n"
    (target / "README.md").write_text(saved_content)
    incoming = h.git(
        "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", incoming_message, cwd=target,
    )
    h.git("merge", "--autostash", "--no-commit", "--no-ff", incoming, cwd=target)

    pending = _snapshot(h, target)
    for field in _PROTECTED_FIELDS:
        assert pending[field] == before[field], (field, before[field], pending[field])
    root_refs = _root_refs(h, target)
    root_ref_ids = _root_ref_ids(root_refs)
    merge_oid = h.git("rev-parse", "--verify", "MERGE_HEAD", cwd=target)
    autostash_oid = root_ref_ids["MERGE_AUTOSTASH"]
    assert merge_oid == incoming
    assert autostash_oid
    assert h.git("cat-file", "-t", autostash_oid, cwd=target) == "commit"
    assert h.git("show", autostash_oid + ":README.md", cwd=target) == saved_content.rstrip("\n")
    assert (target / "README.md").read_text() == "committed\n"
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=target) == ""
    return {
        "target": target,
        "snapshot": pending,
        "registrations": _registrations(h),
        "contents": _checkout_contents(target),
        "root_refs": root_refs,
        "merge_oid": merge_oid,
        "autostash_oid": autostash_oid,
        "saved_content": saved_content,
    }


def _prepare_pending_operation(h, target, branch, incoming_message):
    _add_clean_target(h, target, branch)
    return _start_pending_operation(h, target, incoming_message)


def _assert_pending_preserved(h, fixture):
    target = fixture["target"]
    assert target.is_dir() and not target.is_symlink()
    assert _checkout_contents(target) == fixture["contents"]
    assert _registrations(h) == fixture["registrations"]
    current_snapshot = _snapshot(h, target)
    assert current_snapshot == fixture["snapshot"], (current_snapshot, fixture["snapshot"])
    merge_oid = h.git("rev-parse", "--verify", "MERGE_HEAD", cwd=target)
    assert merge_oid == fixture["merge_oid"]
    root_refs = _root_refs(h, target)
    root_ref_ids = _root_ref_ids(root_refs)
    assert root_ref_ids["MERGE_AUTOSTASH"] == fixture["autostash_oid"]
    assert root_refs == fixture["root_refs"]
    assert h.git(
        "show", fixture["autostash_oid"] + ":README.md", cwd=target,
    ) == fixture["saved_content"].rstrip("\n")

def _refresh_pending_expectations(h, fixtures, excluded_path):
    registrations = _registrations(h)
    expected_registrations = {
        path: record for path, record in registrations.items() if path != excluded_path
    }
    for fixture in fixtures:
        target = fixture["target"]
        current = _snapshot(h, target)
        for field in _PROTECTED_FIELDS:
            if field != "refs":
                assert current[field] == fixture["snapshot"][field], field
        root_refs = _root_refs(h, target)
        root_ref_ids = _root_ref_ids(root_refs)
        assert h.git("rev-parse", "--verify", "MERGE_HEAD", cwd=target) == fixture["merge_oid"]
        assert root_ref_ids["MERGE_AUTOSTASH"] == fixture["autostash_oid"]
        assert h.git(
            "show", fixture["autostash_oid"] + ":README.md", cwd=target,
        ) == fixture["saved_content"].rstrip("\n")
        fixture["snapshot"] = current
        fixture["root_refs"] = root_refs
        fixture["registrations"] = expected_registrations
    return expected_registrations



def _wait_for_pending_outcome(h, target, label):
    h.wait_for(
        lambda state: not target.exists()
        or (not state["picker"] and _has_error_alert(h.ctl("tree"))),
        label + " rejects a pending Git operation or exposes an unsafe removal immediately",
    )


def _authorize_normal_removal(h, target):
    _select_remove(h, target, action="正常移除 worktree")
    initial = h.picker(selected="取消")
    assert "取消" in (initial["selected"] or ""), initial
    h.type_text("查看完整目标路径…")
    h.picker(selected="查看完整目标路径")
    h.ctl("picker enter")
    preview = h.picker("prompt")
    assert str(target) in (preview["query"] or ""), preview
    h.ctl("key enter")
    confirmation = h.picker(selected="取消")
    assert "取消" in (confirmation["selected"] or ""), confirmation
    return confirmation


def _confirm_normal_removal(h):
    h.type_text("确认无外部使用并移除")
    h.picker(selected="确认无外部使用并移除")
    h.ctl("picker enter")


def _assert_audit_unchanged(before, after):
    for field in _PROTECTED_FIELDS:
        assert after[field] == before[field], (field, before[field], after[field])



def _remove_clean_target_with_pending_checkouts(h, repo, name, branch, fixtures, *options):
    target = repo.parent / name
    h.git("worktree", "add", *options, "-b", branch, str(target), "HEAD")
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=target) == ""
    branch_head = h.git("rev-parse", "refs/heads/" + branch)
    git_dir = Path(h.git("rev-parse", "--absolute-git-dir", cwd=target))
    if "--relative-paths" in options:
        backpointer = (git_dir / "gitdir").read_text().strip()
        assert not Path(backpointer).is_absolute(), backpointer
        assert (git_dir / backpointer).resolve() == (target / ".git").resolve(), backpointer
    if branch == "MERGE_HEAD":
        assert not (git_dir / "MERGE_HEAD").exists()
        assert h.git("rev-parse", "--verify", "--quiet", "MERGE_HEAD", cwd=target) == branch_head

    expected_registrations = _refresh_pending_expectations(h, fixtures, excluded_path=target)
    _authorize_normal_removal(h, target)
    _confirm_normal_removal(h)
    h.wait_for(
        lambda state: not state["picker"] and not target.exists()
        and target not in _registrations(h),
        "a clean target with " + name + " remains removable while other checkouts have pending operations",
    )
    assert _registrations(h) == expected_registrations
    assert h.git("rev-parse", "refs/heads/" + branch) == branch_head
    for fixture in fixtures:
        _assert_pending_preserved(h, fixture)
    h.record("a clean target with " + name + " is removable while all other checkouts and pending recovery data remain")


def run(h):
    repo = h.repo

    normal_target = repo.parent / "pending-operation-normal-final-race"
    _add_clean_target(h, normal_target, "external/pending-operation-normal-final-race")
    audited = _snapshot(h, normal_target)
    _authorize_normal_removal(h, normal_target)
    assert _snapshot(h, normal_target) == audited
    normal_race = _start_pending_operation(h, normal_target, "normal final pending merge")
    _assert_audit_unchanged(audited, normal_race["snapshot"])
    _confirm_normal_removal(h)
    _wait_for_pending_outcome(h, normal_target, "normal removal final-confirmation race")
    _assert_pending_preserved(h, normal_race)
    h.record("normal removal rejects a pending autostash created during final confirmation and preserves its recovery pointer")

    dangerous_target = repo.parent / "pending-operation-dangerous-final-race"
    _add_clean_target(h, dangerous_target, "external/pending-operation-dangerous-final-race")
    audited = _snapshot(h, dangerous_target)
    _authorize_to_external_confirmation(h, dangerous_target)
    assert _snapshot(h, dangerous_target) == audited
    dangerous_race = _start_pending_operation(h, dangerous_target, "dangerous final pending merge")
    _assert_audit_unchanged(audited, dangerous_race["snapshot"])
    _confirm_dangerous(h)
    _wait_for_pending_outcome(h, dangerous_target, "dangerous removal final-confirmation race")
    _assert_pending_preserved(h, dangerous_race)
    h.record("dangerous removal rejects a pending autostash created during final confirmation and preserves its recovery pointer")


    initial_pending = _prepare_pending_operation(
        h, repo.parent / "pending-operation-present-at-review",
        "external/pending-operation-present-at-review", "pending at initial review",
    )
    for action in ("正常移除 worktree", "危险移除 worktree"):
        for attempt in range(2):
            _select_remove(h, initial_pending["target"], action=action)
            _wait_for_pending_outcome(
                h, initial_pending["target"], action + " initial pending attempt " + str(attempt + 1),
            )
            _assert_pending_preserved(h, initial_pending)
        h.record(action + " rejects a pending autostash at initial review and allows a fresh retry")

    independent_clean = repo.parent / "pending-operation-independent-clean-target"
    h.git(
        "worktree", "add", "-b", "external/pending-operation-independent-clean-target",
        str(independent_clean), "HEAD",
    )
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=independent_clean) == ""
    (independent_clean / "README.md").write_text("committed content in independent target\n")
    h.git("add", "README.md", cwd=independent_clean)
    h.git("commit", "-m", "independent clean target commit", cwd=independent_clean)
    assert h.git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=independent_clean) == ""
    independent_branch_head = h.git(
        "rev-parse", "refs/heads/external/pending-operation-independent-clean-target",
    )
    pending_fixtures = [normal_race, dangerous_race, initial_pending]
    expected_registrations = _refresh_pending_expectations(
        h, pending_fixtures, excluded_path=independent_clean,
    )

    _authorize_normal_removal(h, independent_clean)
    _confirm_normal_removal(h)
    h.wait_for(
        lambda state: not state["picker"] and not independent_clean.exists()
        and independent_clean not in _registrations(h),
        "a clean checkout remains removable while a different checkout has a pending Git operation",
    )
    assert _registrations(h) == expected_registrations
    assert h.git(
        "rev-parse", "refs/heads/external/pending-operation-independent-clean-target",
    ) == independent_branch_head
    for fixture in pending_fixtures:
        _assert_pending_preserved(h, fixture)
    h.record("a pending operation in another checkout does not block removal of a clean target")

    _remove_clean_target_with_pending_checkouts(
        h, repo, "relative-backpointer-clean-target",
        "external/relative-backpointer-clean-target", pending_fixtures, "--relative-paths",
    )
    _remove_clean_target_with_pending_checkouts(
        h, repo, "merge-head-branch-clean-target",
        "MERGE_HEAD", pending_fixtures,
    )
