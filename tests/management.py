"""User-visible worktree management scenarios on the shared Tern/Git harness."""

import json
from pathlib import Path


def _select_worktree(h, target):
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    listing = h.picker()
    h.type_text(str(target))
    listing = h.picker(selected=str(target))
    assert str(target) in (listing["selected"] or ""), listing
    h.ctl("picker enter")
    action = h.picker(selected="打开／切换")
    assert "打开／切换" in (action["selected"] or ""), action
    h.ctl("picker enter")


def _candidate_picker(h):
    return h.wait_for(
        lambda s: s["picker"] and s["picker"]["mode"] == "pick" and s["picker"]["rows"] > 1,
        "multiple matching worktree tabs",
    )["picker"]

def _ready(h, target, title=None, cwd=None):
    expected = Path(cwd or target).resolve()
    return h.wait_for(
        lambda s: not s["picker"]
        and Path((s.get("focused") or {}).get("cwd", "")).resolve() == expected
        and any(t["active"] and (title is None or t["title"] == title) for t in s["tabs"]),
        f"management target {expected}" + (f" / {title}" if title else ""),
    )


def run(h):
    repo = h.repo
    target = repo.parent / '外部 "managed" worktree'
    branch = "external/managed"
    source_head = h.git("rev-parse", "HEAD")
    source_status = h.git("status", "--porcelain")
    h.git("worktree", "add", "-b", branch, str(target), "HEAD")
    registered = h.git("worktree", "list", "--porcelain")

    # A neighboring repository with a similar path is not a binding for target.
    neighbor = repo.parent / '外部 "managed" worktree suffix'
    neighbor.mkdir()
    h.git("init", "-b", "other", cwd=neighbor)
    h.git("config", "user.name", "Kiku Test", cwd=neighbor)
    h.git("config", "user.email", "kiku@example.invalid", cwd=neighbor)
    (neighbor / "README.md").write_text("unrelated\n")
    h.git("add", "README.md", cwd=neighbor)
    h.git("commit", "-m", "unrelated", cwd=neighbor)
    h.open_repo(neighbor)
    h.open_repo(repo)
    before_tabs = len(h.state()["tabs"])

    # Git, not the plugin, registered this checkout. No matching tab exists yet.
    _select_worktree(h, target)
    opened = _ready(h, target, branch)
    assert len(opened["tabs"]) == before_tabs + 1, opened["tabs"]
    assert h.git("rev-parse", "--show-toplevel", cwd=target) == str(target)
    assert h.git("symbolic-ref", "--short", "HEAD", cwd=target) == branch
    assert h.git("rev-parse", "HEAD", cwd=target) == source_head
    assert (target / "README.md").read_text() == "committed\n"
    assert h.git("status", "--porcelain", cwd=target) == ""
    assert h.git("worktree", "list", "--porcelain") == registered
    assert h.git("status", "--porcelain") == source_status
    h.record("external Git worktree opens in its named tab; similar-prefix repository is not reused")

    # One valid binding is reused instead of adding another tab.
    h.open_repo(repo)
    before_tabs = len(h.state()["tabs"])
    _select_worktree(h, target)
    reused = _ready(h, target, branch)
    assert len(reused["tabs"]) == before_tabs, reused["tabs"]
    h.record("reopening a worktree reuses its existing tab")

    # A pane under a symlinked subdirectory still belongs to this exact worktree.
    subdir = target / "nested" / "source"
    subdir.mkdir(parents=True)
    alias = h.root / "worktree-alias"
    alias.symlink_to(target, target_is_directory=True)
    alias_cwd = alias / "nested" / "source"
    tab_code = (
        "return cx.layout:tab({name='symlink alias candidate', "
        "launch={cwd=" + json.dumps(str(alias_cwd), ensure_ascii=False) + "}})"
    )
    h.lua(tab_code)
    h.open_repo(repo)
    _select_worktree(h, target)
    _candidate_picker(h)
    h.type_text("symlink alias candidate")
    candidate = h.picker(selected="symlink alias candidate")
    assert "symlink alias candidate" in (candidate["selected"] or ""), candidate
    h.ctl("picker enter")
    selected = _ready(h, target, "symlink alias candidate", cwd=alias_cwd)
    assert Path(selected["focused"]["cwd"]).resolve() == subdir.resolve(), selected["focused"]
    h.record("subdirectory and symlink pane resolves to its target worktree; multiple tabs require selection")
    # A separate local session is a distinct valid candidate and can be selected.
    original_session = int(h.lua("return cx.sessions:current().id"))
    other_session = int(h.lua(
        "return cx.sessions:create({name='management-other-session', cwd="
        + json.dumps(str(target), ensure_ascii=False) + "}).id"
    ))
    h.lua(f"cx.sessions:switch({original_session}); return true")
    h.open_repo(repo)
    _select_worktree(h, target)
    _candidate_picker(h)
    h.type_text("management-other-session")
    other = h.picker(selected="management-other-session")
    assert "management-other-session" in (other["selected"] or ""), other
    h.ctl("picker enter")
    switched = _ready(h, target)
    session_name = h.lua("return cx.sessions:current().name")
    assert session_name == "management-other-session", (session_name, other_session)
    assert switched["focused"]["cwd"] == str(target), switched["focused"]
    h.record("management discovers and switches to a matching tab in another local session")

    # Git reports the canonical target when the user chooses a symlinked parent.
    h.lua(f"cx.sessions:switch({original_session}); return true")
    h.open_repo(repo)
    canonical_parent = h.root / "canonical-worktrees"
    canonical_parent.mkdir()
    parent_alias = h.root / "worktrees-alias"
    parent_alias.symlink_to(canonical_parent, target_is_directory=True)
    created_name = "symlink-parent-created"
    h.begin()
    h.name(created_name)
    h.type_text("其他目录")
    h.picker(selected="其他目录…")
    h.ctl("picker enter")
    h.picker("prompt")
    h.replace_text(str(parent_alias / created_name))
    h.ctl("key enter")
    canonical_target = canonical_parent / created_name
    h.created(canonical_target, created_name)
    assert h.git("rev-parse", "--show-toplevel", cwd=canonical_target) == str(canonical_target)
    assert any(
        row == "worktree " + str(canonical_target)
        for row in h.git("worktree", "list", "--porcelain").splitlines()
    )
    h.record("created worktree under symlink parent opens by Git canonical root identity")

    # Both list and action cancellation leave Git and the visible tabs untouched.
    h.lua(f"cx.sessions:switch({original_session}); return true")
    h.open_repo(repo)
    before_tabs = len(h.state()["tabs"])
    before_git = h.git("worktree", "list", "--porcelain")
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    h.picker()
    h.ctl("picker esc")
    h.wait_for(lambda s: not s["picker"], "cancel management worktree list")
    assert len(h.state()["tabs"]) == before_tabs
    assert h.git("worktree", "list", "--porcelain") == before_git
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    h.picker()
    h.type_text(str(target))
    h.picker(selected=str(target))
    h.ctl("picker enter")
    h.picker(selected="打开／切换")
    h.ctl("picker esc")
    h.wait_for(lambda s: not s["picker"], "cancel management actions")
    assert len(h.state()["tabs"]) == before_tabs
    assert h.git("worktree", "list", "--porcelain") == before_git
    h.record("cancelling worktree selection or action preserves tabs and Git state")

    # The management shortcut is independent and is not bound by default.
    config = json.loads((h.plugin / "config.json").read_text())
    config["manageKeybinding"] = ""
    (h.plugin / "config.json").write_text(json.dumps(config))
    h.ctl("plugins fixtures")
    action = h.lua('return cx.actions:describe("plugin.kiku.manage_worktrees")')
    assert "available = true" in action, action
    h.ctl("key ctrl+b")
    h.ctl("key shift+m")
    h.wait_for(lambda s: not s["picker"], "unbound management shortcut leaves UI unchanged")
    config["manageKeybinding"] = "ctrl+b>shift+m"
    (h.plugin / "config.json").write_text(json.dumps(config))
    h.ctl("plugins fixtures")
    h.ctl("key ctrl+b")
    h.ctl("key shift+m")
    h.picker()
    h.ctl("picker esc")
    h.wait_for(lambda s: not s["picker"], "custom management shortcut cancel")
    h.record("management shortcut is independently unbound by default and configurable")
