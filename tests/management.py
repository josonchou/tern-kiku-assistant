"""User-visible worktree management scenarios on the shared Tern/Git harness."""

import json
from pathlib import Path


def _select_worktree(h, target, action="打开／切换", candidate=None):
    h.ctl("plugins run plugin.kiku.manage_worktrees")
    listing = h.picker()
    h.type_text(str(target))
    listing = h.picker(selected=str(target))
    assert str(target) in (listing["selected"] or ""), listing
    h.ctl("picker enter")
    h.picker(selected="打开／切换")
    if action != "打开／切换":
        h.type_text(action)
    selected_action = h.picker(selected=action)
    assert action in (selected_action["selected"] or ""), selected_action
    h.ctl("picker enter")
    if candidate:
        picker = _candidate_picker(h)
        h.type_text(candidate)
        picker = h.picker(selected=candidate)
        assert candidate in (picker["selected"] or ""), picker
        h.ctl("picker enter")


def _candidate_picker(h):
    return h.wait_for(
        lambda s: s["picker"] and s["picker"]["mode"] == "pick" and s["picker"]["rows"] > 1,
        "multiple matching worktree tabs",
    )["picker"]


def _has_rendered_text(node, message):
    if isinstance(node, dict):
        text = node.get("text")
        if isinstance(text, str) and message in text:
            return True
        return any(_has_rendered_text(value, message) for value in node.values())
    if isinstance(node, list):
        return any(_has_rendered_text(value, message) for value in node)
    return False


def _wait_management_rejection(h, message):
    return h.wait_for(
        lambda state: not state["picker"] and _has_rendered_text(h.ctl("tree"), message),
        "management rejection: " + message,
    )


def _tab_ids(h):
    return {tab["id"] for tab in h.lua_json("cx.session:tabs()")}


def _pane_ids(h):
    return {pane["pane"] for pane in h.lua_json("cx.session:panes()")}


def _wait_pane(h, pane_id, field, value, description, picker=False):
    expression = (
        f"(function() local pane = cx.session:pane({pane_id}); "
        f"return pane ~= nil and pane.{field} == {json.dumps(value)} end)()"
    )

    def ready(state):
        return bool(state["picker"]) == picker and h.lua_json(expression) is True

    return h.wait_for(ready, description)


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

    unbound_target = repo.parent / "external-unbound-close"
    unbound_branch = "external/unbound-close"
    h.git("worktree", "add", "-b", unbound_branch, str(unbound_target), "HEAD")
    h.open_repo(repo)
    unbound_tabs = {t["id"] for t in h.lua_json("cx.session:tabs()")}
    _select_worktree(h, unbound_target, action="关闭工作环境")
    _wait_management_rejection(h, "没有可安全识别的绑定标签页；未创建标签页，也未关闭环境。")
    assert {t["id"] for t in h.lua_json("cx.session:tabs()")} == unbound_tabs
    assert any(
        row == "worktree " + str(unbound_target)
        for row in h.git("worktree", "list", "--porcelain").splitlines()
    )
    h.record("closing an unbound worktree refuses without creating a tab")

    # Closing a bound environment is not removing its externally-created checkout.
    close_target = repo.parent / "external-close-environment"
    close_branch = "external/close-environment"
    h.git("worktree", "add", "-b", close_branch, str(close_target), "HEAD")
    notebook = close_target / "safe-close.ipynb"
    notebook_content = json.dumps({
        "cells": [{
            "cell_type": "code",
            "execution_count": None,
            "id": "close-safety-cell",
            "metadata": {},
            "outputs": [],
            "source": ["print('close safety probe')\n"],
        }],
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }, ensure_ascii=False, indent=2) + "\n"
    notebook.write_text(notebook_content)
    h.git("add", "safe-close.ipynb", cwd=close_target)
    h.git("commit", "-m", "Add clean notebook close fixture", cwd=close_target)
    notebook_bytes = notebook.read_bytes()
    close_head = h.git("rev-parse", "HEAD", cwd=close_target)
    close_registered = h.git("worktree", "list", "--porcelain")
    close_refs = h.git("show-ref", "--heads")
    h.open_repo(repo)
    _select_worktree(h, close_target)
    _ready(h, close_target, close_branch)
    h.ctl("ready")
    tabs_before_dirty = h.lua_json("cx.session:tabs()")
    primary = next(t for t in tabs_before_dirty if t.get("name") == close_branch)
    target_tab = primary["id"]
    primary_panes = h.lua_json("cx.session:panes()")
    terminal = next(p for p in primary_panes if p.get("tab") == primary["id"])
    tracked_file = close_target / "README.md"
    h.lua('cx.settings:set("files.auto_save", "off"); return true')
    file_pane = int(h.lua(
        "return cx.docs:open(" + json.dumps(str(tracked_file), ensure_ascii=False)
        + ", {how='beside'})"
    ))
    h.lua(
        "await(cx.docs:edit("
        + json.dumps(str(tracked_file), ensure_ascii=False)
        + ", {find='committed', replace='unsaved native probe'})); return true"
    )
    dirty_file = h.lua_json(f"cx.session:read({file_pane}, {{lines=1}})")
    assert dirty_file["kind"] == "file" and dirty_file["dirty"] is True, dirty_file
    _select_worktree(h, close_target, action="关闭工作环境")
    _wait_management_rejection(h, "文件未加载完成、归属不明或有未保存内容；请先保存并检查。")
    assert any(t["id"] == primary["id"] for t in h.lua_json("cx.session:tabs()"))
    assert h.lua_json(f"cx.session:read({file_pane}, {{lines=1}})")["dirty"] is True
    h.lua(
        "await(cx.docs:edit("
        + json.dumps(str(tracked_file), ensure_ascii=False)
        + ", {find='unsaved native probe', replace='committed'})); "
        "await(cx.docs:save("
        + json.dumps(str(tracked_file), ensure_ascii=False)
        + ")); return true"
    )
    assert h.lua_json(f"cx.session:read({file_pane}, {{lines=1}})")["dirty"] is False
    h.lua('cx.settings:set("notebook.start_on_open", false); return true')
    notebook_pane = int(h.lua(
        "return cx.notebook:open(" + json.dumps(str(notebook), ensure_ascii=False) + ")"
    ))
    notebook_ready = (
        "(function() "
        f"local pane = cx.session:read({notebook_pane}, {{rows=1}}); "
        f"local kernel = cx.notebook:kernel_status({notebook_pane}); "
        "return pane ~= nil and pane.phase == 'ready' and pane.dirty == false "
        "and kernel.status == 'not_started' and kernel.running == 0 and kernel.waiting == 0 "
        "end)()"
    )
    h.wait_for(
        lambda _state: h.lua_json(notebook_ready) is True,
        "clean notebook reaches ready without starting a kernel",
    )
    notebook_state = h.lua_json(f"cx.session:read({notebook_pane}, {{rows=1}})")
    assert notebook_state["phase"] == "ready" and notebook_state["dirty"] is False, notebook_state
    notebook_kernel = h.lua_json(f"cx.notebook:kernel_status({notebook_pane})")
    assert notebook_kernel["status"] == "not_started", notebook_kernel
    notebook_cells = h.lua_json(f"cx.notebook:cells({notebook_pane})")
    assert any(
        cell["nbformat_id"] == "close-safety-cell" and cell["state"] == "idle"
        for cell in notebook_cells
    ), notebook_cells
    split_pane = int(h.lua(
        f"return cx.layout:split({terminal['pane']}, 'right', {{cwd="
        + json.dumps(str(close_target), ensure_ascii=False) + "})"
    ))
    h.lua(f"cx.layout:float({split_pane}, {terminal['pane']}); return true")
    floating = h.lua_json(f"cx.session:pane({split_pane})")
    assert floating["floating"] is True and floating["tab"] == target_tab, floating
    _wait_pane(h, split_pane, "at_prompt", True, "floating terminal reaches its prompt")

    unknown_pane = int(h.lua("return cx.procs:open()"))
    unknown_state = next(p for p in h.lua_json("cx.session:panes()") if p["pane"] == unknown_pane)
    assert unknown_state["kind"] == "procs", unknown_state
    _select_worktree(h, close_target, action="关闭工作环境")
    _wait_management_rejection(h, "无法确认 procs pane 的运行和保存状态；请手动关闭。")
    assert h.lua_json("cx.session:pane(" + str(unknown_pane) + ") ~= nil") is True
    h.lua(f"cx.layout:close({unknown_pane}); return true")

    h.lua(f"cx.layout:focus({terminal['pane']}); return true")
    h.type_text("sleep 30")
    h.ctl("key enter")
    _wait_pane(h, terminal["pane"], "busy", True, "real terminal command is running")
    _select_worktree(h, close_target, action="关闭工作环境")
    _wait_management_rejection(h, "终端或 agent 未明确空闲；请等待命令结束并返回提示符。")
    assert h.lua_json("cx.session:pane(" + str(terminal["pane"]) + ") ~= nil") is True
    h.lua(f"cx.layout:focus({terminal['pane']}); return true")
    h.ctl("key ctrl+c")
    _wait_pane(h, terminal["pane"], "at_prompt", True, "terminal returns to its prompt after cancellation")

    source_session = primary["session"]
    locked_panes = {
        pane["pane"] for pane in h.lua_json("cx.session:panes()")
        if pane.get("tab") == target_tab
    }
    h.lua(f"cx.sessions:lock({primary['session']}); return true")
    _select_worktree(h, close_target, action="关闭工作环境")
    _wait_management_rejection(h, "目标会话已锁定或归属不明；请手动检查会话。")
    assert {
        pane["pane"] for pane in h.lua_json("cx.session:panes()")
        if pane.get("tab") == target_tab
    } == locked_panes
    h.lua(f"cx.sessions:unlock({primary['session']}); return true")
    unlocked_session = next(
        session for session in h.lua_json("cx.sessions:list()")
        if session["id"] == primary["session"]
    )
    assert unlocked_session["locked"] is False, unlocked_session
    preserved_session = int(h.lua(
        "return cx.sessions:create({name='management-close-secondary', cwd="
        + json.dumps(str(close_target), ensure_ascii=False) + "}).id"
    ))
    _select_worktree(h, close_target, action="关闭工作环境", candidate=close_branch)
    h.picker(selected="取消")
    view_label = (
        f"查看 pane {terminal['pane']} · {terminal['kind']} · "
        + ("floating" if terminal.get("floating") else "tiled")
    )
    h.type_text(view_label)
    h.picker(selected=view_label)
    h.ctl("picker enter")
    h.picker("prompt")
    h.ctl("shot management-close-pane")
    raced_pane = int(h.lua(
        f"return cx.layout:split({terminal['pane']}, 'right', {{cwd="
        + json.dumps(str(close_target), ensure_ascii=False) + "})"
    ))
    _wait_pane(
        h, raced_pane, "at_prompt", True,
        "new pane reaches its prompt while preview remains open", picker=True,
    )
    h.type_text("preview-only input")
    h.ctl("picker enter")
    h.picker(selected="取消")
    h.type_text("确认关闭")
    h.picker(selected="确认关闭")
    h.ctl("picker enter")
    _wait_management_rejection(h, "确认期间工作环境或 pane 状态已变化；未关闭任何 pane，请重新检查。")
    assert target_tab in _tab_ids(h)
    assert raced_pane in _pane_ids(h)
    assert h.git("worktree", "list", "--porcelain") == close_registered
    h.lua(f"cx.layout:close({raced_pane}); return true")
    assert h.lua_json(f"cx.session:pane({raced_pane}) == nil") is True
    h.lua(f"cx.sessions:switch({source_session}); return true")
    _select_worktree(h, close_target, action="关闭工作环境", candidate=close_branch)
    h.lua(
        f"cx:run({terminal['pane']}, "
        + json.dumps("sleep 30\r")
        + "); return true"
    )
    _wait_pane(
        h, terminal["pane"], "busy", True,
        "command starts while close confirmation is open", picker=True,
    )
    h.type_text("确认关闭")
    h.picker(selected="确认关闭")
    h.ctl("picker enter")
    _wait_management_rejection(h, "终端或 agent 未明确空闲；请等待命令结束并返回提示符。")
    assert h.lua_json(
        f"cx.session:pane({terminal['pane']}) ~= nil "
        f"and cx.session:pane({terminal['pane']}).busy == true"
    ) is True
    assert target_tab in _tab_ids(h)
    h.lua(f"cx.layout:focus({terminal['pane']}); return true")
    h.ctl("key ctrl+c")
    _wait_pane(
        h, terminal["pane"], "at_prompt", True,
        "terminal returns to its prompt after confirmation race",
    )

    h.lua(f"cx.sessions:switch({source_session}); return true")
    tabs_before = h.lua_json("cx.session:tabs()")
    panes_before = h.lua_json("cx.session:panes()")
    sessions_before = h.lua_json("cx.sessions:list()")
    target_tabs = [t for t in tabs_before if t.get("name") == close_branch]
    assert len(target_tabs) == 1, target_tabs
    target_tab = target_tabs[0]["id"]
    target_panes = {p["pane"] for p in panes_before if p.get("tab") == target_tab}
    assert len(target_panes) >= 3, panes_before
    other_tabs = {t["id"] for t in tabs_before if t["id"] != target_tab}
    other_panes = {p["pane"] for p in panes_before} - target_panes
    assert other_tabs and other_panes and preserved_session in {s["id"] for s in sessions_before}

    _select_worktree(
        h, close_target, action="关闭工作环境", candidate=close_branch
    )
    h.picker(selected="取消")
    h.ctl("picker enter")
    h.wait_for(lambda s: not s["picker"], "cancel confirmation preserves target environment")
    assert target_tab in _tab_ids(h)
    assert h.git("worktree", "list", "--porcelain") == close_registered
    _select_worktree(
        h, close_target, action="关闭工作环境", candidate=close_branch
    )
    h.picker(selected="取消")
    h.ctl("shot management-close-confirm")
    assert target_tab in _tab_ids(h)
    h.type_text("确认关闭")
    h.picker(selected="确认关闭")
    h.ctl("picker enter")
    h.wait_for(
        lambda s: not s["picker"] and target_tab not in _tab_ids(h),
        "confirmed target work environment closes",
    )
    tabs_after = h.lua_json("cx.session:tabs()")
    panes_after = h.lua_json("cx.session:panes()")
    sessions_after = h.lua_json("cx.sessions:list()")
    assert {t["id"] for t in tabs_after} == other_tabs, tabs_after
    assert {p["pane"] for p in panes_after} == other_panes, panes_after
    assert {s["id"] for s in sessions_after} == {s["id"] for s in sessions_before}
    assert close_target.is_dir()
    assert (close_target / "README.md").read_text() == "committed\n"
    assert notebook.read_bytes() == notebook_bytes
    assert h.git("worktree", "list", "--porcelain") == close_registered
    assert h.git("show-ref", "--heads") == close_refs
    assert h.git("symbolic-ref", "--short", "HEAD", cwd=close_target) == close_branch
    assert h.git("rev-parse", "HEAD", cwd=close_target) == close_head
    assert h.git("status", "--porcelain", cwd=close_target) == ""
    assert h.git("status", "--porcelain") == source_status
    tabs_after_close = {t["id"] for t in tabs_after}
    panes_after_close = {p["pane"] for p in panes_after}
    _select_worktree(h, close_target)
    _ready(h, close_target)
    assert {t["id"] for t in h.lua_json("cx.session:tabs()")} == tabs_after_close
    assert {p["pane"] for p in h.lua_json("cx.session:panes()")} == panes_after_close
    h.record("reopening a closed worktree reuses the retained secondary environment")
    h.record("confirmed close ends only the selected bound environment, preserving worktrees, branches and other sessions")
