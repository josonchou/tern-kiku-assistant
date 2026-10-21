"""Real Tern/Git scenarios for executable configuration and dependency isolation."""

import json
from pathlib import Path

from management import _has_error_alert


def run(h):
    h.wait_for(
        lambda _: h.lua_json('cx.actions:describe("plugin.kiku.create_worktree")')["available"],
        "configured dependency enables the command before first use",
    )
    h.open_repo()
    h.begin()
    h.name("configured-git-path")
    target = Path(h.picker(selected="/")["selected"])
    h.ctl("picker enter")
    created = h.created(target, "configured-git-path")
    registrations = h.git("worktree", "list", "--porcelain", "-z")
    records = registrations.split("\0\0")
    assert any(record.startswith("worktree " + str(target) + "\0") for record in records), registrations
    assert Path(created["focused"]["cwd"]) == target, created["focused"]
    assert h.git("symbolic-ref", "--short", "HEAD", cwd=target) == "configured-git-path"
    h.record("configured Git executable path containing spaces creates registered worktree")

    (h.path_tools / "git").symlink_to((h.configured_tools / "git").resolve())
    (h.plugin / "config.json").write_text(
        '{"defaultPath":"","keybinding":"","executables":{"git":"/missing/configured git"}}'
    )
    h.ctl("plugins fixtures")
    h.wait_for(
        lambda _: h.lua_json('cx.actions:describe("plugin.kiku.create_worktree")')["available"],
        "reloaded dependency enables the command without invoking it",
    )
    h.open_repo()
    h.begin()
    h.name("path-fallback-git")
    fallback_target = Path(h.picker(selected="/")["selected"])
    h.ctl("picker enter")
    fallback_created = h.created(fallback_target, "path-fallback-git")
    fallback_records = h.git("worktree", "list", "--porcelain", "-z").split("\0\0")
    assert any(record.startswith("worktree " + str(fallback_target) + "\0") for record in fallback_records)
    assert Path(fallback_created["focused"]["cwd"]) == fallback_target
    assert h.git("symbolic-ref", "--short", "HEAD", cwd=fallback_target) == "path-fallback-git"
    h.record("invalid configured Git path falls back to Git from the launch PATH")

    # Missing realpath must hide removal, not the whole management workflow.
    before_removal_gate = h.git("worktree", "list", "--porcelain", "-z")
    h.open_repo()
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    h.picker()
    h.type_text("configured-git-path")
    h.picker(selected="configured-git-path")
    h.ctl("picker enter")
    h.picker()
    offered = set()
    for _ in range(8):
        selected = h.state()["picker"]["selected"]
        if selected in offered:
            break
        offered.add(selected)
        h.ctl("picker down 1")
    assert not any("移除" in choice for choice in offered), offered
    assert any("打开" in choice for choice in offered), offered
    h.ctl("key escape")
    h.wait_for(lambda state: not state["picker"], "cancel dependency-filtered actions")
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    h.picker()
    h.type_text("configured-git-path")
    h.picker(selected="configured-git-path")
    h.ctl("picker enter")
    h.picker()
    h.ctl("picker enter")
    h.created(target, "configured-git-path")
    assert h.git("worktree", "list", "--porcelain", "-z") == before_removal_gate
    h.record("missing realpath disables removal but preserves real worktree opening")

    # A configured filename is one executable, never a shell expression.
    (h.path_tools / "git").unlink()
    special_directory = h.configured_tools / "$(touch KIKU_INJECTED) 'quoted'"
    special_directory.mkdir()
    special_git = special_directory / "git"
    special_git.symlink_to((h.configured_tools / "git").resolve())
    (h.plugin / "config.json").write_text(json.dumps({
        "executables": {"git": str(special_git)},
    }))
    h.ctl("plugins fixtures")
    h.open_repo()
    h.begin()
    h.name("literal-executable-path")
    literal_target = Path(h.picker(selected="/")["selected"])
    h.ctl("picker enter")
    h.created(literal_target, "literal-executable-path")
    assert h.git("symbolic-ref", "--short", "HEAD", cwd=literal_target) == "literal-executable-path"
    for directory in (h.plugin, h.repo, h.root, literal_target):
        assert not (directory / "KIKU_INJECTED").exists(), directory
    h.record("shell metacharacters in a configured executable path remain literal")

    # Make both resolution routes unavailable without changing the real Git binary.
    path_git = h.path_tools / "git"
    assert not path_git.exists()
    (h.plugin / "config.json").write_text(json.dumps({
        "executables": {"git": str(h.configured_tools / "missing git")},
    }))
    h.ctl("plugins fixtures")
    h.open_repo()
    before_refs = h.git("for-each-ref", "--format=%(refname) %(objectname)")
    before_worktrees = h.git("worktree", "list", "--porcelain", "-z")
    before_panes = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    action = h.lua_json('cx.actions:describe("plugin.kiku.create_worktree")')
    assert action["available"] is False, action
    h.ctl("key ctrl+b")
    h.ctl("key shift+g")
    h.wait_for(
        lambda state: not state["picker"] and _has_error_alert(h.ctl("tree")),
        "missing Git shortcut gives a visible rejection without opening a picker",
    )
    assert h.git("for-each-ref", "--format=%(refname) %(objectname)") == before_refs
    assert h.git("worktree", "list", "--porcelain", "-z") == before_worktrees
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before_panes
    h.record("unavailable Git hides startup and rejects the shortcut without mutations")

    # Re-detection on reload must restore a genuinely usable command.
    path_git.symlink_to((h.configured_tools / "git").resolve())
    h.ctl("plugins fixtures")
    h.open_repo()
    h.begin()
    h.ctl("key escape")
    h.wait_for(lambda state: not state["picker"], "cancel after dependency recovery")
    h.record("dependency recovery after reload re-enables the real creation workflow")
