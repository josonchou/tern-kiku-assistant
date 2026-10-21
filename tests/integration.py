#!/usr/bin/env python3
"""Native Tern + real Git integration tests. Uses an isolated config and temp repos.

Requirements: Python 3, Git, Tern 0.9.5+, macOS (or a Tern-capable Linux display).
Run: python3 tests/integration.py
Artifacts stay in the printed temporary directory. No user Tern config is edited.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile
import time
from types import SimpleNamespace
from dangerous_removal import run as run_dangerous_removal_scenarios
from management import _has_error_alert, run as run_management_scenarios
from pending_removal import run as run_pending_removal_scenarios
from removal import run as run_removal_scenarios
from dependencies import run as run_dependency_scenarios

PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path(tempfile.mkdtemp(prefix="tern-kiku-test-")).resolve()
SOCKET = ROOT / "control.sock"
REPO = ROOT / "repos" / "项目 with spaces"
PLUGIN = ROOT / "plugin"
passed = []


def git(*args, cwd=REPO, check=True):
    result = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.rstrip("\n") if check else result


def ctl(command):
    result = subprocess.run(["tern", "ctl", "--control", str(SOCKET), command],
                            capture_output=True, text=True, timeout=20)
    try:
        data = json.loads(result.stdout)
    except Exception as exc:
        raise AssertionError(result.stdout + result.stderr) from exc
    assert data.get("ok", True), data
    return data


def state():
    return ctl("state")


def wait_for(predicate, description, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = state()
        if predicate(value):
            return value
        time.sleep(0.1)
    (ROOT / "failure-state.json").write_text(json.dumps(value, ensure_ascii=False, indent=2))
    (ROOT / "failure-tree.json").write_text(json.dumps(ctl("tree"), ensure_ascii=False, indent=2))
    raise AssertionError("Timed out: " + description)


def picker(mode="pick", selected=None):
    return wait_for(lambda s: s["picker"] and s["picker"]["mode"] == mode
                    and (selected is None or selected in (s["picker"]["selected"] or "")),
                    f"picker {mode} {selected}")["picker"]


def type_text(value):
    ctl("type " + json.dumps(value, ensure_ascii=False))


def replace_text(value):
    ctl("key " + ("cmd+a" if os.uname().sysname == "Darwin" else "ctrl+a"))
    type_text(value)


def lua(code):
    ctl("carly lua " + json.dumps(code, ensure_ascii=False))
    result = state()["carly"]["last_tool"]
    assert result and not result.get("error"), result
    ctl("carly close")
    text = result["text"]
    return text.removeprefix("→ ").strip()


def lua_json(expression):
    output = ROOT / "lua-query.json"
    lua(f"tern.fs.write({json.dumps(str(output))}, tern.json.encode({expression})); return true")
    return json.loads(output.read_text())


def open_repo(path=REPO):
    lua("return cx.layout:new_tab({cwd=" + json.dumps(str(path), ensure_ascii=False) + "})")
    ctl("ready")


def begin(mode="new", shortcut=False, base=None, stay_base=False):
    if shortcut:
        configured = json.loads((PLUGIN / "config.json").read_text()).get("keybinding") or "ctrl+b>shift+g"
        for chord in configured.split(">"):
            ctl("key " + chord)
    else:
        ctl("plugins run plugin.kiku.create_worktree")
    picker(selected="新分支 + worktree")
    if mode == "local": ctl("picker down 1")
    if mode == "detached": ctl("picker down 2")
    ctl("picker enter")
    if mode == "local": return picker()
    base_picker = picker(selected="当前 HEAD")
    if stay_base: return base_picker
    if base:
        type_text(base)
        selected = picker(selected=base)["selected"]
        seen = set()
        # Tern's selected text concatenates the row label and detail.
        refs = ("refs/heads/" + base, "refs/remotes/" + base)
        while not selected.endswith(refs):
            assert selected not in seen, f"Base branch not found: {base}"
            seen.add(selected)
            ctl("picker down 1")
            selected = picker()["selected"]
    ctl("picker enter")
    picker("prompt")


def name(value):
    replace_text(value)
    ctl("key enter")
    return picker(selected="/")


def created(path, title):
    def matches(s):
        focused = s.get("focused") or {}
        cwd = focused.get("cwd", "")
        active = [t for t in s["tabs"] if t["active"]]
        return not s["picker"] and Path(cwd).expanduser() == path and active and active[0]["title"] == title
    result = wait_for(matches, f"new tab {title}")
    assert not result["focused"].get("error"), result["focused"]
    return result


def record(label):
    passed.append(label)
    print("PASS " + label, flush=True)


def main(dependencies_only=False):
    REPO.mkdir(parents=True)
    git("init", "-b", "main")
    git("config", "user.name", "Kiku Test")
    git("config", "user.email", "kiku@example.invalid")
    (REPO / "README.md").write_text("committed\n")
    git("add", "README.md")
    git("commit", "-m", "initial")
    git("branch", "available")
    git("branch", "race-branch")
    git("remote", "add", "origin", str(REPO))
    git("update-ref", "refs/remotes/origin/remote-feature", "HEAD")
    git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/remote-feature")
    original_head = git("rev-parse", "HEAD")
    (REPO / "README.md").write_text("uncommitted\n")
    (REPO / ".env").write_text("TEST_FIXTURE=local-only\n")
    original_status = git("status", "--porcelain")
    shutil.copytree(PROJECT, PLUGIN, ignore=shutil.ignore_patterns(".git", ".test-artifacts", "tern.d.luau"))
    fixture = ROOT / "crates" / "plugins" / "fixtures"
    fixture.mkdir(parents=True)
    (ROOT / "crates" / "tern" / "goldens").mkdir(parents=True)
    (fixture / "kiku.path").write_text(str(PLUGIN) + "\n")
    configured_tools = ROOT / "configured tools with spaces"
    if dependencies_only:
        system_git = shutil.which("git")
        assert system_git, "Git is required; install it explicitly before running this scenario"
        configured_tools.mkdir()
        configured_git = configured_tools / "git executable"
        configured_git.symlink_to(system_git)
        (configured_tools / "git").symlink_to(system_git)
        (PLUGIN / "config.json").write_text(json.dumps({
            "defaultPath": "", "keybinding": "",
            "executables": {"git": str(configured_git)},
        }))
    env = dict(os.environ, TERN_CONFIG_DIR=str(ROOT / "config"),
               STENCIL_FIXTURE_ROOT=str(ROOT / "crates" / "tern"), STENCIL_LOG_DIR=str(ROOT / "logs"))
    if dependencies_only:
        env["PATH"] = str(configured_tools)
    tern = shutil.which("tern")
    assert tern, "Tern is required; install it explicitly before running this scenario"
    log = open(ROOT / "serve.log", "w")
    server = subprocess.Popen([tern, "serve", "--control", str(SOCKET), "--out", str(ROOT / "shots")],
                              cwd=ROOT, env=env, stdout=log, stderr=log)
    print("Artifacts: " + str(ROOT), flush=True)
    try:
        deadline = time.monotonic() + 20
        while not SOCKET.exists():
            assert server.poll() is None, (ROOT / "serve.log").read_text()
            assert time.monotonic() < deadline, "Tern startup timeout"
            time.sleep(0.1)
        ctl("plugins fixtures")
        if dependencies_only:
            harness = SimpleNamespace(
                repo=REPO, plugin=PLUGIN, root=ROOT, git=git, ctl=ctl, picker=picker,
                type_text=type_text, replace_text=replace_text, begin=begin, name=name,
                created=created, state=state, wait_for=wait_for, lua=lua, lua_json=lua_json,
                open_repo=open_repo, record=record,
            )
            run_dependency_scenarios(harness)
            return
        action = lua('return cx.actions:describe("plugin.kiku.create_worktree")')
        assert "available = true" in action and "kiku" in action, action
        management_action = lua('return cx.actions:describe("plugin.kiku.manage_worktrees")')
        assert "available = true" in management_action, management_action
        record("plugin load and shortcut registration")
        core = json.dumps(str(PLUGIN / "lib" / "worktree.luau"))
        manager_path = json.dumps(str(PLUGIN / "lib" / "manager.luau"))
        removal_path = json.dumps(str(PLUGIN / "lib" / "removal.luau"))
        tests = json.dumps(str(PLUGIN / "tests" / "helpers.luau"))
        helper_code = (
            f'local m = loadstring(tern.fs.read({core}))()'
            f'; local manager = loadstring(tern.fs.read({manager_path}))()'
            f'; local removal = loadstring(tern.fs.read({removal_path}))()'
            f'; return loadstring(tern.fs.read({tests}))()(m, manager, removal)'
        )
        lua(helper_code)
        record("Luau Git and worktree manager helpers in native runtime")
        open_repo()
        begin(shortcut=True)
        replace_text("../bad")
        ctl("key enter")
        picker("prompt")
        # Wait for validation to return a new prompt, retaining the rejected input.
        wait_for(lambda s: s["picker"] and s["picker"]["query"] == "../bad", "invalid name retained")
        name("feature/login test")
        target = REPO.parent / "feature" / "login-test"
        assert picker()["selected"] == str(target), picker()
        ctl("shot location-picker")
        ctl("picker enter")
        created(target, "feature/login-test")
        assert git("symbolic-ref", "--short", "HEAD", cwd=target) == "feature/login-test"
        assert git("rev-parse", "HEAD", cwd=target) == original_head
        assert git("status", "--porcelain") == original_status
        assert not (target / ".env").exists()
        record("shortcut, invalid-name retry, nested name, dirty source preserved, focused named tab")

        (target / "child.txt").write_text("linked tree commit\n")
        git("add", "child.txt", cwd=target)
        git("commit", "-m", "linked source", cwd=target)
        child_head = git("rev-parse", "HEAD", cwd=target)
        begin()
        name("child")
        child = target.parent / "child"
        assert picker()["selected"] == str(child)
        ctl("picker enter")
        created(child, "child")
        assert git("rev-parse", "HEAD", cwd=child) == child_head != original_head
        record("linked worktree source HEAD and parent candidates")

        before = git("worktree", "list", "--porcelain")
        ctl("plugins run plugin.kiku.create_worktree")
        picker(selected="新分支 + worktree")
        ctl("picker esc")
        begin()
        ctl("picker esc")
        begin()
        name("cancelled")
        ctl("picker esc")
        wait_for(lambda s: not s["picker"], "cancel")
        assert git("worktree", "list", "--porcelain") == before
        assert git("show-ref", "--verify", "refs/heads/cancelled", check=False).returncode != 0
        record("cancel mode, name and location without mutations")

        begin("local")
        type_text("available")
        picker(selected="available")
        ctl("picker enter")
        path = Path(picker(selected="/")["selected"])
        ctl("picker enter")
        created(path, "available")
        assert git("symbolic-ref", "--short", "HEAD", cwd=path) == "available"
        record("existing local branch stays attached")

        begin("local")
        type_text("origin/remote-feature")
        picker(selected="origin/remote-feature")
        ctl("picker enter")
        picker("prompt")
        ctl("key enter")
        path = Path(picker(selected="/")["selected"])
        ctl("picker enter")
        created(path, "remote-feature")
        assert git("config", "branch.remote-feature.remote") == "origin"
        assert git("config", "branch.remote-feature.merge") == "refs/heads/remote-feature"
        record("remote-tracking branch creates a local tracking branch without fetch")

        begin("detached")
        name("scratch")
        path = Path(picker()["selected"])
        ctl("picker enter")
        created(path, "scratch (detached)")
        assert git("symbolic-ref", "--quiet", "HEAD", cwd=path, check=False).returncode == 1
        assert git("show-ref", "--verify", "refs/heads/scratch", check=False).returncode != 0
        record("detached worktree does not create a branch")

        # The selected local ref is occupied and shares its short name with a tag.
        # Capture its OID, move the branch after selection, then verify the new tree
        # remains pinned to the captured commit.
        base_oid = git("commit-tree", git("rev-parse", "HEAD^{tree}"), "-p", original_head,
                       "-m", "alternate base")
        occupied_path = ROOT / "occupied-base-tree"
        git("worktree", "add", "-b", "occupied-base", str(occupied_path), base_oid)
        assert git("symbolic-ref", "HEAD", cwd=occupied_path) == "refs/heads/occupied-base"
        git("tag", "occupied-base", original_head)
        moved_base = git("commit-tree", git("rev-parse", "HEAD^{tree}"), "-p", base_oid,
                         "-m", "moved base")
        open_repo()
        begin(stay_base=True)
        ctl("shot base-picker")
        type_text("occupied-base")
        picker(selected="occupied-base")
        ctl("picker enter")
        picker("prompt")
        git("update-ref", "refs/heads/occupied-base", moved_base)
        name("from-occupied-base")
        based_path = Path(picker()["selected"])
        based_path.mkdir()
        ctl("picker enter")
        picker(selected="修改目标目录")
        ctl("picker enter")
        picker("prompt")
        based_path = ROOT / "base retry" / "from-occupied-base"
        based_path.parent.mkdir()
        replace_text(str(based_path))
        ctl("key enter")
        created(based_path, "from-occupied-base")
        assert git("rev-parse", "HEAD", cwd=based_path) == base_oid
        assert git("symbolic-ref", "--short", "HEAD", cwd=based_path) == "from-occupied-base"
        assert git("rev-parse", "refs/heads/occupied-base") == moved_base
        record("occupied local branch base is ref-disambiguated and pinned across ref movement and path retry")

        git("update-ref", "refs/remotes/origin/base-only", moved_base)
        remote_oid = git("rev-parse", "refs/remotes/origin/base-only^{commit}")
        assert remote_oid != base_oid
        begin(base="origin/base-only")
        name("from-remote-base")
        remote_path = Path(picker()["selected"])
        ctl("picker enter")
        created(remote_path, "from-remote-base")
        assert git("rev-parse", "HEAD", cwd=remote_path) == remote_oid
        assert git("symbolic-ref", "--short", "HEAD", cwd=remote_path) == "from-remote-base"
        assert git("config", "branch.from-remote-base.remote", check=False).returncode != 0
        assert git("show-ref", "--verify", "refs/heads/base-only", check=False).returncode != 0
        assert git("config", "branch.from-remote-base.merge", check=False).returncode != 0
        record("remote base creates from pinned commit without upstream side effects")

        before_cancel = git("worktree", "list", "--porcelain")
        before_refs = git("for-each-ref", "--format=%(refname) %(objectname)")
        for cancelled_mode in ("new", "detached"):
            begin(cancelled_mode, stay_base=True)
            ctl("picker esc")
            wait_for(lambda s: not s["picker"], "base picker cancel")
            assert git("worktree", "list", "--porcelain") == before_cancel
            assert git("for-each-ref", "--format=%(refname) %(objectname)") == before_refs
            begin(cancelled_mode)
            ctl("picker esc")
            wait_for(lambda s: not s["picker"], "restart after base cancel")
        record("base selection cancellation is mutation-free and restartable for both modes")

        detached_oid = git("rev-parse", "refs/heads/occupied-base^{commit}")
        begin("detached", base="occupied-base")
        name("detached-from-base")
        detached_path = Path(picker()["selected"])
        ctl("picker enter")
        created(detached_path, "detached-from-base (detached)")
        assert git("rev-parse", "HEAD", cwd=detached_path) == detached_oid
        assert git("symbolic-ref", "--quiet", "HEAD", cwd=detached_path, check=False).returncode == 1
        assert git("show-ref", "--verify", "refs/heads/detached-from-base", check=False).returncode != 0
        record("detached worktree uses chosen base without creating a branch")

        begin()
        name("collision")
        first = Path(picker()["selected"])
        first.mkdir()
        (first / "keep.txt").write_text("keep me")
        ctl("picker enter")
        picker(selected="修改目标目录")
        ctl("picker enter")
        picker("prompt")
        assert state()["picker"]["query"] == str(first)
        custom = ROOT / "custom space" / "has ' quote 中文"
        replace_text(str(custom))
        ctl("key enter")
        created(custom, "collision")
        assert (first / "keep.txt").read_text() == "keep me"
        record("path conflict retains input; custom space/quote/Unicode path succeeds")

        begin()
        name("main")
        ctl("picker enter")
        picker(selected="修改目标目录")
        ctl("picker down 1")
        ctl("picker enter")
        picker("prompt")
        assert state()["picker"]["query"] == "main"
        name("renamed-after-conflict")
        path = Path(picker()["selected"])
        ctl("picker enter")
        created(path, "renamed-after-conflict")
        record("existing branch conflict can be renamed and retried")

        # Race a competing worktree checkout after the branch was selected.
        begin("local")
        type_text("race-branch")
        picker(selected="race-branch")
        ctl("picker enter")
        picker(selected="/")
        race = ROOT / "raced"
        git("worktree", "add", str(race), "race-branch")
        ctl("picker enter")
        picker(selected="修改目标目录")
        ctl("picker esc")
        assert git("symbolic-ref", "--short", "HEAD", cwd=race) == "race-branch"
        record("branch occupancy is rechecked before creation")

        # A configured relative directory is resolved against the main tree.
        (PLUGIN / "config.json").write_text(json.dumps({"defaultPath": "../configured", "keybinding": ""}))
        ctl("plugins fixtures")
        begin()
        name("configured-test")
        type_text("configured/configured-test")
        configured = REPO.parent / "configured" / "configured-test"
        assert picker(selected="configured-test")["selected"] == str(configured)
        ctl("picker enter")
        created(configured, "configured-test")
        record("config relative path resolves against main repository from a linked tree")

        # Close the source session while Git's real checkout hook is running.
        # Creation must survive; Tern should report the path instead of opening
        # the result in an unrelated session or deleting the successful worktree.
        lua('kikuTestSession = cx.sessions:create({name="close-during-create", cwd='
            + json.dumps(str(REPO), ensure_ascii=False) + '}).id; return kikuTestSession')
        ctl("ready")
        marker = ROOT / "checkout-hook-started"
        hook = REPO / ".git" / "hooks" / "post-checkout"
        hook.write_text('#!/bin/sh\n: > "' + str(marker) + '"\nsleep 2\n')
        hook.chmod(0o755)
        begin()
        name("session-closed")
        path = Path(picker()["selected"])
        ctl("picker enter")
        deadline = time.monotonic() + 10
        while not marker.exists():
            assert time.monotonic() < deadline, "checkout hook did not run"
            time.sleep(0.05)
        lua('cx.sessions:close(kikuTestSession); return true')
        deadline = time.monotonic() + 10
        while True:
            tree_node = ctl("tree")
            tree = json.dumps(tree_node, ensure_ascii=False)
            if _has_error_alert(tree_node): break
            assert time.monotonic() < deadline, tree
            time.sleep(0.1)
        hook.unlink()
        assert str(path) in tree
        assert git("symbolic-ref", "--short", "HEAD", cwd=path) == "session-closed"
        record("successful worktree survives source-session closure and reports its path")

        empty = ROOT / "not-a-repo"
        empty.mkdir()
        open_repo(empty)
        ctl("plugins run plugin.kiku.create_worktree")
        wait_for(
            lambda s: not s["picker"] and _has_error_alert(ctl("tree")),
            "non-repository creation reports a visible error alert",
        )
        open_repo()
        begin()
        ctl("picker esc")
        record("non-repository error releases flow lock for next invocation")

        # Rebinding is driven by config.json, including chord sequences.
        (PLUGIN / "config.json").write_text(json.dumps({"defaultPath": "", "keybinding": "ctrl+b>shift+h"}))
        ctl("plugins fixtures")
        action = lua('return cx.actions:describe("plugin.kiku.create_worktree")')
        assert "ctrl+b>shift+h" in action and "ctrl+b>shift+g" not in action, action
        begin(shortcut=True)
        ctl("picker esc")
        wait_for(lambda s: not s["picker"], "custom shortcut cancel")
        record("custom key sequence from config triggers the command")
        harness = SimpleNamespace(
            repo=REPO, plugin=PLUGIN, root=ROOT, git=git, ctl=ctl, picker=picker,
            type_text=type_text, replace_text=replace_text, begin=begin, name=name,
            created=created, state=state, wait_for=wait_for, lua=lua, lua_json=lua_json,
            open_repo=open_repo, record=record,
        )
        run_management_scenarios(harness)
        run_removal_scenarios(harness)
        run_dangerous_removal_scenarios(harness)
        run_pending_removal_scenarios(harness)

        (PLUGIN / "config.json").write_text(json.dumps({"defaultPath": "", "keybinding": ""}))
        ctl("plugins fixtures")
        begin(shortcut=True)
        ctl("picker esc")
        wait_for(lambda s: not s["picker"], "default shortcut cancel")
        record("empty keybinding falls back to Ctrl+B then Shift+G")
        assert git("status", "--porcelain") == original_status
        report = {"passed": passed, "count": len(passed), "artifacts": str(ROOT),
                  "tern": subprocess.check_output(["tern", "--version"], text=True).strip()}
        (ROOT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps(report, ensure_ascii=False, indent=2))
    finally:
        try:
            (ROOT / "last-state.json").write_text(json.dumps(state(), ensure_ascii=False, indent=2))
            (ROOT / "last-tree.json").write_text(json.dumps(ctl("tree"), ensure_ascii=False, indent=2))
        except Exception:
            pass
        try: ctl("quit")
        except Exception: server.terminate()
        try: server.wait(timeout=10)
        except subprocess.TimeoutExpired: server.kill(); server.wait()
        log.close()


if __name__ == "__main__":
    main("--dependencies-only" in sys.argv)
