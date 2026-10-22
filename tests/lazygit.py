"""Real lazygit lifecycle through its configured native shortcut."""


import json
import os
import signal
import stat
from pathlib import Path


def lazygit_launches(log):
    if not log.exists():
        return []
    return [
        (fields[0], int(fields[2]))
        for line in log.read_text().splitlines()
        if len(fields := line.split("\t", 2)) == 3 and not fields[1]
    ]


def process_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def bridge_from_calls(log, start=0):
    for line in log.read_text().splitlines()[start:]:
        fields = line.split("\t", 1)
        if len(fields) == 2:
            candidate = Path(fields[0].split(":", 1)[0])
            if candidate.name.startswith("tern-kiku-git-"):
                return candidate
    raise AssertionError("No fixture Git invocation used a private lazygit bridge")


def close_tool_natively(h, pane):
    h.lua(f"cx.layout:close({pane}); return true")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({pane})") is None,
               "native close removes its tool pane")

def open_real_lazygit(h):
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key alt+g")
    opened = {}

    def real_ui(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in before]
        if not new:
            return False
        assert len(new) == 1, new
        pane = new[0]
        if pane.get("floating") is not True or pane.get("focused") is not True:
            return False
        output = h.lua_json(
            f"cx.session:read({pane['pane']}, {{lines = 2000, max_chars = 64000}})"
        )
        if "README.md" not in str(output) or "uncommitted" not in str(output):
            return False
        opened.update(pane)
        return True

    h.wait_for(real_ui, "shortcut opens the real lazygit repository UI")
    return opened

def run(h):
    from management import _has_error_alert
    from tools import _has_info_toast

    private_config = h.root / "lazygit config"
    private_config.mkdir(parents=True, exist_ok=True)
    (private_config / "config.yml").write_text("disableStartupPopups: true\n")
    h.open_repo()
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    source = h.lua_json('cx.session:pane("@focused")')
    configured = json.loads((h.plugin / "config.json").read_text())
    keybinding = configured.get("lazygitKeybinding") or "ctrl+b>alt+g"
    for chord in keybinding.split(">"):
        h.ctl("key " + chord)

    opened = {}

    def lazygit_opened(_state):
        panes = h.lua_json("cx.session:panes()")
        new = [pane for pane in panes if pane["pane"] not in before]
        if not new:
            return False
        assert len(new) == 1, panes
        pane = new[0]
        assert pane.get("kind") == "terminal", pane
        if pane.get("floating") is not True or pane.get("focused") is not True:
            return False
        output = h.lua_json(
            f"cx.session:read({pane['pane']}, {{lines = 2000, max_chars = 64000}})"
        )
        text = str(output)
        if "README.md" not in text or "uncommitted" not in text:
            return False
        opened.update(pane)
        return True
    h.wait_for(lazygit_opened, "Ctrl+B then Option+G opens the real lazygit repository UI")
    h.ctl("shot lazygit-real-tui")
    assert opened["cwd"] == source["cwd"], (source, opened)
    assert opened["tab"] == source["tab"], (source, opened)
    git_log = h.root / "configured git invocations"
    git_invocations = [
        line.rstrip("\n").split("\t", 1)
        for line in git_log.read_text().splitlines()
        if "\t" in line
        and Path(line.rstrip("\n").split("\t", 1)[0].split(":", 1)[0]).name.startswith(
            "tern-kiku-git-"
        )
    ]
    assert git_invocations, "lazygit did not invoke the configured Git executable"
    invocation_path = git_invocations[0][0]
    bridge = Path(invocation_path.split(":", 1)[0])
    assert bridge.parent == Path("/tmp") and bridge.name.startswith("tern-kiku-git-"), bridge
    assert stat.S_IMODE(bridge.stat().st_mode) == 0o700, oct(bridge.stat().st_mode)
    assert (bridge / "git").is_symlink(), bridge
    configured_git = Path(configured["executables"]["git"])
    assert (bridge / "git").resolve() == configured_git.resolve(), bridge
    assert all(Path(entry) == bridge or Path(entry).is_relative_to(h.root)
               for entry in invocation_path.split(":")), invocation_path
    private_config = h.root / "lazygit config"
    state_file = private_config / "state.yml"
    state = state_file.read_text()
    assert "recentrepos:" in state and str(h.repo.resolve()) in state, (
        "real lazygit did not record this fixture repository in its private state", state
    )
    lazygit_log = h.root / "lazygit executable invocations"
    launches = lazygit_launches(lazygit_log)
    assert [path for path, _ in launches] == [str(configured["executables"]["lazygit"])], (
        "lazygit did not execute the selected configured wrapper exactly once", launches
    )
    lazygit_pid = launches[0][1]
    assert process_alive(lazygit_pid), lazygit_pid
    injection = "kiku-injected"
    assert not (Path(source["cwd"]) / injection).exists()
    assert not (h.plugin / injection).exists()
    h.record("configured lazygit shortcut displays real repository UI using its selected Git executable")
    lazygit_pane = opened["pane"]
    h.open_repo(h.repo)
    moved_to_tab = h.lua_json('cx.session:pane("@focused")')
    h.lua(
        f"local ok, err = cx.layout:move_to_tab({lazygit_pane}, "
        f"{moved_to_tab['tab']}, {{focus = true}}); assert(ok, err); return true"
    )
    h.lua(f"cx.layout:focus({source['pane']}); return true")
    for chord in keybinding.split(">"):
        h.ctl("key " + chord)
    h.wait_for(
        lambda _: bool(
            (pane := h.lua_json(f"cx.session:pane({lazygit_pane})"))
            and pane.get("tab") == source["tab"]
            and pane.get("floating") is True and pane.get("focused") is True
        ),
        "opening from origin tab brings manually moved lazygit back without restart",
    )
    assert process_alive(lazygit_pid) and bridge.exists()
    alternate_source = int(h.lua(
        f"return cx.layout:split({source['pane']}, 'right', {{cwd={json.dumps(source['cwd'], ensure_ascii=False)}}})"
    ))
    panes_before_same_directory_open = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.lua(f"cx.layout:focus({alternate_source}); return true")
    for chord in keybinding.split(">"):
        h.ctl("key " + chord)
    h.wait_for(
        lambda _: bool(
            (pane := h.lua_json(f"cx.session:pane({lazygit_pane})"))
            and pane.get("tab") == source["tab"] and pane.get("focused") is True
        ),
        "same-tab same-directory different source reuses lazygit",
    )
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == \
        panes_before_same_directory_open
    panes_before_scratch = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    scratch = {}
    def scratch_opened(_state):
        panes = h.lua_json("cx.session:panes()")
        new = [pane for pane in panes if pane["pane"] not in panes_before_scratch]
        if not new:
            return False
        assert len(new) == 1, panes
        scratch.update(new[0])
        lazygit = h.lua_json(f"cx.session:pane({lazygit_pane})")
        return bool(new[0].get("floating") is True and new[0].get("focused") is True
                    and lazygit and lazygit.get("parked") is not True)
    h.wait_for(scratch_opened, "same-source scratch coexists with floating lazygit")
    h.lua(f"cx.layout:float({lazygit_pane}, {source['pane']}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key alt+g")
    h.wait_for(
        lambda _: bool(
            (pane := h.lua_json(f"cx.session:pane({lazygit_pane})"))
            and pane.get("floating") is True and pane.get("focused") is True
            and pane.get("parked") is not True
            and h.lua_json(f"cx.session:pane({scratch['pane']})").get("parked") is not True
        ),
        "same-source lazygit open restores floating layout without parking scratch",
    )
    h.ctl("key q")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({lazygit_pane})") is None,
        "normal lazygit quit closes its owned pane",
    )
    h.wait_for(lambda _: not bridge.exists(), "lazygit exit cleans up only its private Git bridge")
    h.record("same-source terminal and lazygit switch without duplication; lazygit normal exit closes its pane")
    h.open_repo(h.repo)
    other_source = h.lua_json('cx.session:pane("@focused")')
    other_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key alt+g")
    other_open = {}

    def other_lazygit_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in other_before]
        if not new:
            return False
        assert len(new) == 1, new
        other_open.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)

    h.wait_for(other_lazygit_opened, "a second tab with the same cwd gets its own lazygit instance")
    assert other_open["pane"] != lazygit_pane
    assert other_open["tab"] == other_source["tab"]
    h.ctl("key q")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({other_open['pane']})") is None,
               "second-source lazygit exits independently")
    h.record("different tabs with the same directory never reuse each other's lazygit pane")
    fallback_config = json.loads((h.plugin / "config.json").read_text())
    fallback_config["executables"] = {
        "git": str(h.root / "missing configured git"),
        "lazygit": str(h.root / "missing configured lazygit"),
    }
    (h.plugin / "config.json").write_text(json.dumps(fallback_config))
    h.ctl("plugins fixtures")
    lazygit_log = h.root / "lazygit executable invocations"
    git_log = h.root / "configured git invocations"
    lazygit_launches_before = len(lazygit_launches(lazygit_log))
    git_calls_before = len(git_log.read_text().splitlines())
    h.open_repo(h.repo)
    fallback_source = h.lua_json('cx.session:pane("@focused")')
    fallback_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key alt+g")
    fallback_open = {}
    def fallback_lazygit_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in fallback_before]
        if not new:
            return False
        assert len(new) == 1, new
        output = h.lua_json(
            f"cx.session:read({new[0]['pane']}, {{lines = 2000, max_chars = 64000}})"
        )
        if "README.md" not in str(output) or "uncommitted" not in str(output):
            return False
        fallback_open.update(new[0])
        return new[0].get("focused") is True and new[0].get("floating") is True
    h.wait_for(fallback_lazygit_opened, "invalid explicit executable paths fall back to the real launch PATH")
    assert fallback_open["tab"] == fallback_source["tab"]
    h.wait_for(
        lambda _: len(lazygit_launches(lazygit_log)) > lazygit_launches_before,
        "PATH fallback invokes the private lazygit wrapper",
    )
    new_launches = lazygit_launches(lazygit_log)[lazygit_launches_before:]
    assert [path for path, _ in new_launches] == [str(h.path_tools / "lazygit")], new_launches
    h.wait_for(
        lambda _: len(git_log.read_text().splitlines()) > git_calls_before,
        "PATH fallback invokes the private Git wrapper from lazygit",
    )
    git_calls = git_log.read_text().splitlines()[git_calls_before:]
    fallback_git_calls = [line.split("\t", 1) for line in git_calls if "\t" in line]
    assert any(
        Path(fields[0].split(":", 1)[0]).name.startswith("tern-kiku-git-")
        and os.readlink(Path(fields[0].split(":", 1)[0]) / "git") == str(h.path_tools / "git")
        for fields in fallback_git_calls
    ), fallback_git_calls
    h.ctl("key q")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({fallback_open['pane']})") is None,
               "PATH-fallback lazygit exits normally")
    h.record("invalid executable config uses both isolated PATH wrappers, which execute the real tools")
    run_non_git(h, str(h.path_tools / "lazygit"))

    h.open_repo(h.repo)
    orphan_source = h.lua_json('cx.session:pane("@focused")')
    orphan_git_start = len((h.root / "configured git invocations").read_text().splitlines())
    orphan_lazygit = open_real_lazygit(h)
    orphan_lazygit_pane = orphan_lazygit["pane"]
    orphan_before_terminal = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    orphan_terminal = {}
    def orphan_terminal_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in orphan_before_terminal]
        if not new:
            return False
        assert len(new) == 1, new
        orphan_terminal.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True
                    and h.lua_json(f"cx.session:pane({orphan_lazygit_pane})").get("parked") is not True)
    h.wait_for(orphan_terminal_opened, "same-source scratch coexists with a second live lazygit")
    orphan_terminal_pane = orphan_terminal["pane"]
    h.lua(f"cx.layout:focus({orphan_source['pane']}); return true")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({orphan_source['pane']})"))
                       and pane.get("at_prompt") is True),
        "two-tool orphan source is at its prompt before closing",
    )
    h.type_text("exit 0")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({orphan_source['pane']})") is None
        and bool((lazy := h.lua_json(f"cx.session:pane({orphan_lazygit_pane})"))
                 and lazy.get("parked") is not True)
        and bool((scratch := h.lua_json(f"cx.session:pane({orphan_terminal_pane})"))
                 and scratch.get("parked") is not True),
        "source closure leaves both independently owned live tools visible",
    )
    orphan_bridge = bridge_from_calls(
        h.root / "configured git invocations", orphan_git_start
    )
    assert orphan_bridge.exists(), orphan_bridge
    h.ctl("shot lazygit-and-terminal-source-closed")
    h.lua(f"cx.layout:focus({orphan_lazygit_pane}); return true")
    h.ctl("key q")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({orphan_lazygit_pane})") is None,
               "lazygit exits normally after source pane closes")
    h.wait_for(lambda _: not orphan_bridge.exists(), "orphan lazygit exit removes only its bridge")
    close_tool_natively(h, orphan_terminal_pane)

    h.open_repo(h.repo)
    failure_source = h.lua_json('cx.session:pane("@focused")')
    failure_git_start = len(git_log.read_text().splitlines())
    failure_launch_count = len(lazygit_launches(lazygit_log))
    failure_open = open_real_lazygit(h)
    failure_pane = failure_open["pane"]
    failure_launches = lazygit_launches(lazygit_log)[failure_launch_count:]
    assert len(failure_launches) == 1, failure_launches
    failure_pid = failure_launches[0][1]
    failure_bridge = bridge_from_calls(git_log, failure_git_start)
    assert failure_bridge.exists() and process_alive(failure_pid)
    os.kill(failure_pid, signal.SIGKILL)
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failure_pane})"))
                       and pane.get("exited") is not None),
        "a real lazygit process failure remains in its native pane",
    )
    failed_pane = h.lua_json(f"cx.session:pane({failure_pane})")
    assert failed_pane.get("exited") is not None, failed_pane
    failed_view = h.lua_json(
        f"cx.session:read({failure_pane}, {{lines = 2000, max_chars = 64000}})"
    )
    assert "README.md" in str(failed_view), failed_view
    assert failure_bridge.exists(), "Unconfirmed failed instance removed its live-process bridge"
    h.ctl("shot lazygit-failure-retained")
    failed_panes_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.lua(f"cx.layout:focus({failure_pane}); return true")
    h.ctl("plugins run plugin.kiku.open_terminal")
    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "failed lazygit identity refuses to become a terminal source")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == failed_panes_before
    assert h.lua_json(f"cx.session:pane({failure_pane})").get("exited") is not None
    assert failure_bridge.exists()
    h.lua(f"cx.layout:close({failure_pane}); return true")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({failure_pane})") is None,
               "native Tern close disposes only the failed lazygit fixture")
    h.wait_for(lambda _: not failure_bridge.exists(),
               "confirmed native pane close cleans the ended lazygit bridge")
    h.record("real failure remains viewable and cannot be adopted as a terminal owner")

    h.open_repo(h.repo)
    reload_source = h.lua_json('cx.session:pane("@focused")')
    reload_git_start = len(git_log.read_text().splitlines())
    reload_launch_count = len(lazygit_launches(lazygit_log))
    reload_open = open_real_lazygit(h)
    reload_pane = reload_open["pane"]
    reload_launches = lazygit_launches(lazygit_log)[reload_launch_count:]
    assert len(reload_launches) == 1, reload_launches
    reload_pid = reload_launches[0][1]
    reload_bridge = bridge_from_calls(git_log, reload_git_start)
    assert reload_bridge.exists() and process_alive(reload_pid)
    h.ctl("shot lazygit-before-plugin-reload")
    reload_before = h.lua_json(f"cx.session:pane({reload_pane})")
    reload_panes_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    launch_count_before_reload = len(lazygit_launches(lazygit_log))
    h.ctl("plugins run reload_plugins")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({reload_pane})"))
                       and pane.get("exited") is None and reload_bridge.exists()
                       and process_alive(reload_pid)),
        "plugin reload leaves the real lazygit pane and bridge alive",
    )
    reload_after = h.lua_json(f"cx.session:pane({reload_pane})")
    assert all(reload_after.get(key) == reload_before.get(key)
               for key in ("pane", "tab", "cwd", "floating", "parked")), (
        reload_before, reload_after
    )
    h.wait_for(
        lambda _: h.lua_json(
            'cx.actions:describe("plugin.kiku.open_lazygit")'
        ).get("available") is True,
        "lazygit dependency state refreshes after plugin reload",
    )
    h.lua(f"cx.layout:focus({reload_source['pane']}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key alt+g")
    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "post-reload shortcut refuses duplicate ownership of the preserved lazygit")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == reload_panes_before
    reload_after_refusal = h.lua_json(f"cx.session:pane({reload_pane})")
    assert all(reload_after_refusal.get(key) == reload_before.get(key)
               for key in ("pane", "tab", "cwd", "floating", "parked")), (
        reload_before, reload_after_refusal
    )
    assert reload_bridge.exists() and process_alive(reload_pid)
    assert len(lazygit_launches(lazygit_log)) == launch_count_before_reload, \
        "Plugin reload or shortcut started a duplicate lazygit process"
    h.wait_for(lambda _: not _has_error_alert(h.ctl("tree")),
               "duplicate-open refusal clears before restore check")
    h.ctl("plugins run plugin.kiku.restore_tools")
    h.wait_for(
        lambda state: not state.get("picker") and _has_info_toast(h.ctl("tree")),
        "reloaded plugin does not expose old lazygit as a current-VM restorable tool",
    )
    h.ctl("shot lazygit-after-plugin-reload")
    assert reload_bridge.exists() and process_alive(reload_pid)
    h.lua(f"cx.layout:close({reload_pane}); return true")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({reload_pane})") is None,
               "native Tern close ends the unclaimed post-reload lazygit")
    h.wait_for(lambda _: not process_alive(reload_pid),
               "native close confirms the old lazygit process has exited")
    assert reload_bridge.exists(), "reloaded plugin improperly cleaned an unclaimed old bridge"
    reload_link = reload_bridge / "git"
    assert reload_link.is_symlink(), reload_link
    reload_link.unlink()
    reload_bridge.rmdir()
    assert not reload_bridge.exists(), reload_bridge
    h.record("plugin reload preserves the old lazygit and bridge without taking ownership or duplicating it")

    h.open_repo(h.repo)
    dependency_git_start = len(git_log.read_text().splitlines())
    dependency_launch_count = len(lazygit_launches(lazygit_log))
    dependency_source = h.lua_json('cx.session:pane("@focused")')
    dependency_open = open_real_lazygit(h)
    dependency_pane = dependency_open["pane"]
    dependency_launches = lazygit_launches(lazygit_log)[dependency_launch_count:]
    assert len(dependency_launches) == 1, dependency_launches
    dependency_path, dependency_pid = dependency_launches[0]
    dependency_executable = Path(dependency_path)
    assert dependency_executable == h.path_tools / "lazygit", dependency_executable
    dependency_bridge = bridge_from_calls(git_log, dependency_git_start)
    assert dependency_bridge.exists() and process_alive(dependency_pid)
    dependency_executable.unlink()
    assert not dependency_executable.exists(), dependency_executable
    h.ctl("key ctrl+b")
    h.ctl("key q")
    assert not h.state().get("picker"), "q on lazygit opened an unexpected picker"
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({dependency_pane})"))
                       and pane.get("parked") is True),
        "q parks lazygit after executable removal without restarting it",
    )
    assert process_alive(dependency_pid) and dependency_bridge.exists()
    h.lua(f"cx.layout:focus({dependency_source['pane']}); return true")
    h.ctl("plugins run plugin.kiku.open_lazygit")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({dependency_pane})"))
                       and pane.get("parked") is not True
                       and pane.get("floating") is True and pane.get("focused") is True),
        "opening an existing lazygit after executable removal reuses its process",
    )
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda state: bool(state.get("picker")), "Shift+Q on lazygit opens the end confirmation")
    h.ctl("key esc")
    h.wait_for(lambda state: not state.get("picker"), "canceling the end confirmation closes it")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({dependency_pane})"))
                       and pane.get("parked") is not True and pane.get("exited") is None),
        "canceling the end confirmation keeps lazygit running",
    )
    assert process_alive(dependency_pid) and dependency_bridge.exists()
    assert len(lazygit_launches(lazygit_log)) == dependency_launch_count + 1, \
        "Management keys attempted to run the removed executable again"
    dependency_panes = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == dependency_panes
    assert process_alive(dependency_pid) and dependency_bridge.exists()
    assert len(lazygit_launches(lazygit_log)) == dependency_launch_count + 1, \
        "Reusing a live instance attempted to run the removed executable again"
    h.lua(f"cx.layout:close({dependency_pane}); return true")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({dependency_pane})") is None,
               "native close removes the lazygit pane")
    h.wait_for(lambda _: not process_alive(dependency_pid),
               "native close ends the same verified lazygit process")
    h.wait_for(lambda _: not dependency_bridge.exists(),
               "native close removes the confirmed lazygit bridge")
    h.record("management keys hide and confirm lazygit without rerunning a removed executable; native close ends its process")

def run_non_git(h, expected_wrapper=None):
    from management import _has_error_alert

    private_config = h.root / "lazygit config"
    private_config.mkdir(parents=True, exist_ok=True)
    (private_config / "config.yml").write_text("disableStartupPopups: true\n")
    source_path = h.root / "non-git source"
    source_path.mkdir()
    h.open_repo(source_path)
    source = h.lua_json('cx.session:pane("@focused")')
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    configured = json.loads((h.plugin / "config.json").read_text())
    lazygit_log = h.root / "lazygit executable invocations"
    launches_before = len(lazygit_launches(lazygit_log))
    keybinding = configured.get("lazygitKeybinding") or "ctrl+b>alt+g"
    for chord in keybinding.split(">"):
        h.ctl("key " + chord)

    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "lazygit refuses a non-Git source before creating a pane")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before, \
        "non-Git lazygit refusal created a pane"
    assert len(lazygit_launches(lazygit_log)) == launches_before, \
        "non-Git lazygit refusal started the lazygit executable"
    assert not (source_path / ".git").exists(), "plugin initialized a repository"
    h.lua(f"cx.layout:focus({source['pane']}); return true")
    h.ctl("plugins run plugin.kiku.open_terminal")
    h.wait_for(
        lambda _: bool((pane := h.lua_json('cx.session:pane("@focused")'))
                       and pane.get("floating") is True
                       and pane.get("cwd") == str(source_path)),
        "a scratch terminal still opens in the non-Git source directory",
    )
    h.ctl("shot lazygit-non-git-refusal")
    h.record("lazygit refuses a non-Git source before creating a pane; scratch terminal still opens there")

def run_config_errors(h):
    from management import _has_error_alert

    cases = (
        ("unknown field", {"reviewOnlyUnknownKey": True}),
        ("invalid type", {"terminalKeybinding": False}),
    )
    for case_name, invalid_config in cases:
        for action in ("open_terminal", "open_lazygit"):
            (h.plugin / "config.json").write_text(json.dumps(invalid_config))
            h.ctl("plugins fixtures")
            source_path = h.root / f"config error {case_name} {action}"
            source_path.mkdir()
            h.open_repo(source_path)
            before_panes = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
            before_launches = len(lazygit_launches(h.root / "lazygit executable invocations"))
            keybinding = "ctrl+b>t" if action == "open_terminal" else "ctrl+b>alt+g"
            for chord in keybinding.split(">"):
                h.ctl("key " + chord)

            alert = {}

            def config_rejection(_state):
                tree = h.ctl("tree")
                if not _has_error_alert(tree):
                    return False
                alert["tree"] = tree
                return True

            h.wait_for(config_rejection, f"{case_name} rejects {action} with a visible error")
            message = json.dumps(alert["tree"], ensure_ascii=False)
            assert "配置" in message or "config" in message.lower(), message
            assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before_panes, \
                f"{case_name} {action} created a tool pane"
            assert len(lazygit_launches(h.root / "lazygit executable invocations")) == before_launches, \
                f"{case_name} {action} launched lazygit"
    h.record("invalid config rejects both new tool actions before pane or lazygit launch")

def run_restart(h):
    from management import _has_error_alert

    private_config = h.root / "lazygit config"
    private_config.mkdir(parents=True, exist_ok=True)
    (private_config / "config.yml").write_text("disableStartupPopups: true\n")
    h.open_repo()
    source = h.lua_json('cx.session:pane("@focused")')
    git_log = h.root / "configured git invocations"
    lazygit_log = h.root / "lazygit executable invocations"
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    git_start = 0
    if git_log.exists():
        git_start = len(git_log.read_text().splitlines())
    launch_start = len(lazygit_launches(lazygit_log))
    opened = open_real_lazygit(h)
    pane_id = opened["pane"]
    launches = lazygit_launches(lazygit_log)[launch_start:]
    assert len(launches) == 1, launches
    pid = launches[0][1]
    bridge = bridge_from_calls(git_log, git_start)
    assert bridge.exists() and process_alive(pid)

    os.kill(pid, signal.SIGKILL)
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({pane_id})"))
                       and pane.get("exited") is not None),
        "real lazygit process failure remains in its serve pane",
    )
    failed = h.lua_json(f"cx.session:pane({pane_id})")
    assert failed.get("exited") is not None, failed
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({pane_id})"))
                       and pane.get("exited") is None and pane.get("at_prompt") is True),
        "Tern Restart creates a new shell generation in the failed lazygit pane",
    )
    restarted = h.lua_json(f"cx.session:pane({pane_id})")
    launch_count = len(lazygit_launches(lazygit_log))
    h.lua(f"cx.layout:focus({pane_id}); return true")
    h.ctl("plugins run plugin.kiku.open_lazygit")
    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "lazygit open refuses the unverified restarted generation")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before | {pane_id}, \
        "Refusing an unknown peer must not create a terminal pane"
    after = h.lua_json(f"cx.session:pane({pane_id})")
    assert all(after.get(key) == restarted.get(key)
               for key in ("pane", "tab", "cwd", "floating", "parked")), (restarted, after)
    assert after.get("at_prompt") is True and bridge.exists()
    assert len(lazygit_launches(lazygit_log)) == launch_count
    h.record("Restarted lazygit peer refusal creates no pane and leaves its generation untouched")


def run_missing(h, missing):
    from management import _has_error_alert

    h.open_repo()
    config = json.loads((h.plugin / "config.json").read_text())
    unavailable = Path(config["executables"][missing])
    available_name = "lazygit" if missing == "git" else "git"
    available = Path(config["executables"][available_name])
    assert not unavailable.exists(), unavailable
    assert available.is_file() and os.access(available, os.X_OK), available
    source = h.lua_json('cx.session:pane("@focused")')
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    action = h.lua_json('cx.actions:describe("plugin.kiku.open_lazygit")')
    assert action["available"] is False, action
    h.ctl("plugins run plugin.kiku.open_lazygit")

    def rejected_for_target():
        tree = h.ctl("tree")
        return _has_error_alert(tree) and f"executables.{missing}" in str(tree)
    h.wait_for(lambda _: rejected_for_target(),
               f"missing {missing} produces a dependency-specific lazygit launch rejection")
    alert = h.ctl("tree")
    assert _has_error_alert(alert), alert
    assert f"executables.{missing}" in str(alert), alert
    assert missing in str(alert) and "PATH" in str(alert), alert
    assert f"executables.{available_name}" not in str(alert), alert
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before
    assert h.lua_json(f"cx.session:pane({source['pane']})")
    h.record(f"missing {missing} disables lazygit without creating a tool pane")
