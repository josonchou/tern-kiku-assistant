"""Real Tern scratch-terminal lifecycle through native keyboard shortcuts."""

import json
import os
from pathlib import Path
import shlex
import subprocess

from management import _has_error_alert

def _has_info_toast(node):
    if isinstance(node, dict):
        classes = node.get("class", "").split()
        rect = node.get("rect")
        if (
            node.get("role") == "status"
            and "toast" in classes and "info" in classes
            and isinstance(rect, list) and len(rect) == 4
            and rect[2] > 0 and rect[3] > 0
        ):
            return True
        return any(_has_info_toast(value) for value in node.values())
    if isinstance(node, list):
        return any(_has_info_toast(value) for value in node)
    return False

def run(h):
    source_directory = h.root / "non Git 工具 source with spaces"
    source_directory.mkdir()
    assert h.git("rev-parse", "--show-toplevel", cwd=source_directory, check=False).returncode != 0
    h.open_repo(source_directory)
    source = h.lua_json('cx.session:pane("@focused")')
    assert source and source["kind"] == "terminal", source
    source_id = source["pane"]
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    assert h.lua_json(f"cx.session:pane({source_id})"), \
        "End action on an ordinary source pane removed that pane"
    assert not h.state().get("picker"), "End action on an ordinary pane opened a tool confirmation"
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}

    h.ctl("key ctrl+b")
    h.ctl("key t")
    opened = {}

    def tool_opened(_state):
        panes = h.lua_json("cx.session:panes()")
        new = [pane for pane in panes if pane["pane"] not in before]
        if not new:
            return False
        assert len(new) == 1, panes
        opened.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)

    h.wait_for(tool_opened, "Ctrl+B then t creates a scratch-terminal tool pane")
    tool_id = opened["pane"]
    assert opened["kind"] == "terminal", opened
    assert opened.get("floating") is True, opened
    assert opened.get("focused") is True, opened
    assert opened.get("parked") is not True, opened
    assert opened["tab"] == source["tab"], (source, opened)
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({tool_id})").get("at_prompt") is True,
        "scratch terminal reaches its real shell prompt",
    )

    # The real foreground task reports its own cwd/PID, then exec preserves that
    # PID as a system sleep process. No shell integration metadata substitutes
    # for observing the running process and its actual working directory.
    cwd_file = h.root / "tool actual cwd.txt"
    pid_file = h.root / "tool task pid.txt"
    script = (
        f"/bin/pwd -P > {shlex.quote(str(cwd_file))}; "
        f"printf '%s\\n' \"$$\" > {shlex.quote(str(pid_file))}; "
        "exec /bin/sleep 300"
    )
    h.type_text("/bin/sh -c " + shlex.quote(script))
    h.ctl("key enter")

    def task_alive():
        if not pid_file.exists() or not pid_file.read_text().strip():
            return False
        pid = int(pid_file.read_text().strip())
        process = subprocess.run(
            ["/bin/ps", "-p", str(pid), "-o", "comm="],
            capture_output=True, text=True, timeout=5,
        )
        if process.returncode != 0 or Path(process.stdout.strip()).name != "sleep":
            return False
        os.kill(pid, 0)
        return True

    h.wait_for(lambda _: task_alive(), "real foreground system task starts in the tool")
    task_pid = int(pid_file.read_text().strip())
    assert Path(cwd_file.read_text().strip()).resolve() == source_directory.resolve()
    assert not (source_directory / ".git").exists()

    second_origin_id = int(h.lua(
        f"return cx.layout:split({source_id}, 'right', {{cwd={json.dumps(str(source_directory), ensure_ascii=False)}}})"
    ))
    h.lua(f"cx.layout:focus({second_origin_id}); return true")
    h.lua('cx.actions:run("plugin.kiku.open_terminal")')
    h.wait_for(
        lambda _: bool(
            h.lua_json(f"cx.session:pane({tool_id})")
            and h.lua_json(f"cx.session:pane({tool_id})").get("focused") is True
        ),
        "same-tab same-directory different source reuses scratch",
    )
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before | {
        tool_id, second_origin_id
    }
    other_directory = h.root / "same-tab different launch directory"
    other_directory.mkdir()
    other_origin_id = int(h.lua(
        f"return cx.layout:split({source_id}, 'right', {{cwd={json.dumps(str(other_directory), ensure_ascii=False)}}})"
    ))
    panes_before_other_cwd = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.lua(f"cx.layout:focus({other_origin_id}); return true")
    h.lua('cx.actions:run("plugin.kiku.open_terminal")')
    other_cwd_tool = {}
    def other_cwd_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in panes_before_other_cwd]
        if not new:
            return False
        assert len(new) == 1, new
        other_cwd_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(other_cwd_opened, "same-tab different launch directory creates a distinct scratch")
    assert other_cwd_tool["pane"] != tool_id
    assert Path(other_cwd_tool["cwd"]).resolve() == other_directory.resolve()
    h.lua(f"cx.layout:close({other_cwd_tool['pane']}); return true")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({other_cwd_tool['pane']})") is None,
        "different-directory scratch closes natively after isolation check",
    )
    h.lua(f"cx.layout:focus({second_origin_id}); return true")
    h.lua('cx.actions:run("plugin.kiku.open_terminal")')
    h.wait_for(
        lambda _: bool(h.lua_json(f"cx.session:pane({tool_id})")
                       and h.lua_json(f"cx.session:pane({tool_id})").get("focused") is True),
        "returning to the original launch directory reuses its scratch",
    )
    h.ctl("key ctrl+b")
    h.ctl("key q")

    def hidden(_state):
        panes = {pane["pane"]: pane for pane in h.lua_json("cx.session:panes()")}
        tool = panes.get(tool_id)
        return bool(tool and tool.get("parked") is True
                    and panes.get(second_origin_id, {}).get("focused") is True)

    h.wait_for(hidden, "hide parks the tool and restores source-pane focus")
    assert task_alive(), "Hiding the tool ended its real foreground task"
    assert int(pid_file.read_text().strip()) == task_pid
    h.ctl("shot scratch-terminal-parked")

    h.ctl("key ctrl+b")
    h.ctl("key t")

    def restored(_state):
        pane = h.lua_json(f"cx.session:pane({tool_id})")
        return bool(pane and pane.get("focused") is True
                    and pane.get("floating") is True and pane.get("parked") is not True)
    h.wait_for(restored, "open restores the same floating scratch-terminal pane")

    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == \
        before | {tool_id, second_origin_id, other_origin_id}
    assert task_alive(), "Restoring the tool lost its original foreground task"
    assert int(pid_file.read_text().strip()) == task_pid
    assert Path(cwd_file.read_text().strip()).resolve() == source_directory.resolve()
    h.ctl("shot scratch-terminal-restored")
    h.record("non-Git source opens a tool float and hide/restore preserves its pane, cwd and real task")
    # The cancel-first end action must leave both the real task and terminal
    # intact when accepted without moving the picker selection.
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda state: bool(state.get("picker")), "end confirmation opens")
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool(h.lua_json(f"cx.session:pane({tool_id})")),
        "default end choice keeps the tool pane",
    )
    assert task_alive(), "Default end choice interrupted the running task"

    second_source = source_directory
    h.open_repo(second_source)
    second = h.lua_json('cx.session:pane("@focused")')
    assert second and second["pane"] != source_id
    second_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    # Exercise the real async random-token callback: focus changes synchronously
    # before it returns, so the stale invocation must not split a new pane.
    h.lua(
        'cx.actions:run("plugin.kiku.open_terminal"); '
        f'cx.layout:focus({source_id}); return true'
    )
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "async open refuses to continue after its source focus changes",
    )
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == second_before, \
        "Async open created a tool after its source pane lost focus"
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "async source-change refusal clears before normal open")
    h.lua(f"cx.layout:focus({second['pane']}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key t")
    second_tool = {}

    def second_opened(_state):
        panes = h.lua_json("cx.session:panes()")
        new = [pane for pane in panes if pane["pane"] not in second_before]
        if not new:
            return False
        assert len(new) == 1, panes
        second_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)

    h.wait_for(second_opened, "a different tab gets an isolated tool")
    assert second_tool["pane"] != tool_id
    assert second_tool["tab"] == second["tab"]
    background_pid_file = h.root / "tool background pid.txt"
    background_script = (
        f"printf '%s\\n' \"$$\" > {shlex.quote(str(background_pid_file))}; "
        "exec /bin/sleep 300"
    )
    h.type_text("/bin/sh -c " + shlex.quote(background_script) + " &")
    h.ctl("key enter")
    h.wait_for(lambda _: background_pid_file.exists(), "real background task starts in second tool")
    background_pid = int(background_pid_file.read_text().strip())
    def background_alive():
        result = subprocess.run(
            ["/bin/ps", "-p", str(background_pid), "-o", "comm="],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0 and Path(result.stdout.strip()).name == "sleep"
    h.wait_for(lambda _: background_alive(), "second tool background process is observable")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda state: bool(state.get("picker")), "background-task end confirmation opens")
    h.ctl("key enter")
    assert background_alive(), "Canceling end interrupted a background task"
    assert h.lua_json(f"cx.session:pane({second_tool['pane']})"), \
        "Canceling end removed the background-task terminal"
    h.lua(f"cx.layout:focus({second_tool['pane']}); return true")
    h.type_text(f"kill {background_pid}")
    h.ctl("key enter")
    h.wait_for(lambda _: not background_alive(), "background task is explicitly cleaned up")
    h.lua(f"cx.layout:focus({second_tool['pane']}); return true")
    h.type_text("exit 0")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({second_tool['pane']})") is None,
        "normal shell exit closes its tool pane",
    )
    assert h.lua_json(f"cx.session:pane({second['pane']})"), \
        "Normal tool exit closed its source pane"
    h.lua(f"cx.layout:focus({second['pane']}); return true")
    remaining = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    failed_tool = {}
    def failed_tool_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in remaining]
        if not new:
            return False
        failed_tool.update(new[0])
        assert len(new) == 1, new
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(failed_tool_opened, "new terminal opens after normal exit")
    failed_tool_id = failed_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({failed_tool_id})").get("at_prompt") is True,
        "replacement tool shell reaches its prompt",
    )
    parked_exit = h.root / "parked tool exit trigger.txt"
    h.type_text(
        "while [ ! -f " + shlex.quote(str(parked_exit))
        + " ]; do /bin/sleep 0.05; done; exit 7"
    )
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("busy") is True),
        "parked-exit test shell starts its real foreground wait task",
    )
    h.ctl("key ctrl+b")
    h.ctl("key q")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("parked") is True),
        "tool can be parked while its real shell task is running",
    )
    parked_exit.write_text("exit")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("exited") == 7),
        "parked tool records its real failed shell exit",
    )
    # A failed shell generation is no longer owned; plugin controls must not
    # reuse its prior identity. Close it through Tern and start a fresh tool.
    h.lua(f"cx.layout:focus({failed_tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda _state: _has_error_alert(h.ctl("tree")),
               "plugin refuses to end an unconfirmed failed shell")
    assert h.lua_json(f"cx.session:pane({failed_tool_id})")
    h.lua(f"cx.layout:close({failed_tool_id}); return true")
    h.wait_for(lambda _: h.lua_json(f"cx.session:pane({failed_tool_id})") is None,
               "Tern natively closes the failed unconfirmed tool")
    h.lua(f"cx.layout:focus({source_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key t")
    def original_tool_focused(_state):
        pane = h.lua_json(f"cx.session:pane({tool_id})")
        return bool(pane and pane.get("focused") is True)

    h.wait_for(original_tool_focused, "the original source reuses its own tool")
    assert task_alive()
    h.ctl("shot scratch-terminal-source-isolation")
    h.record("same-tab/cwd reuse, cross-tab isolation and cancel-by-default end safety")
    h.lua(f"cx.layout:focus({source_id}); return true")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({source_id})"))
                       and pane.get("focused") is True and pane.get("at_prompt") is True),
        "source terminal is focused at its prompt before user exit",
    )
    h.type_text("exit 0")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({source_id})") is None,
        "source terminal exits normally through its real shell",
    )
    def unchanged_after_source_close(_state):
        pane = h.lua_json(f"cx.session:pane({tool_id})")
        return bool(pane and pane.get("parked") is not True)
    h.wait_for(unchanged_after_source_close, "source closure leaves its live tool visible")
    assert task_alive(), "Closing the source ended the tool task"
    h.record("closing a source leaves the live tool visible and preserves its process")
    h.lua(f"cx.layout:focus({tool_id}); return true")
    h.ctl("key ctrl+z")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({tool_id})"))
                       and pane.get("at_prompt") is True and task_alive()),
        "foreground sleep is suspended and the original shell prompt returns",
    )
    output_done = h.root / "tool long output finished.txt"
    h.type_text(
        "i=0; while [ $i -lt 2500 ]; do printf 'long-output-%s\\n' \"$i\"; "
        "i=$((i+1)); done; printf done > " + shlex.quote(str(output_done))
    )
    h.ctl("key enter")
    h.wait_for(
        lambda _: output_done.exists() and output_done.read_text() == "done"
        and bool((pane := h.lua_json(f"cx.session:pane({tool_id})"))
                 and pane.get("at_prompt") is True
                 and pane.get("last", {}).get("status") == 0),
        "terminal completes a real 2500-line shell command",
    )
    scrollback = h.lua_json(f"cx.session:read({tool_id}, {{lines = 2000}})")
    assert "KIKU_TOOL_" not in str(scrollback), scrollback
    assert "/bin/sh -c 'printf" not in str(scrollback), scrollback
    h.lua('cx.actions:run("clear")')
    assert task_alive(), "Long shell output ended the suspended original task"
    h.type_text("fg")
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({tool_id})"))
                       and pane.get("at_prompt") is False and task_alive()),
        "fg restores the same original task to the foreground",
    )
    h.lua(f"cx.layout:focus({tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda state: bool(state.get("picker")), "confirmed end action opens")
    h.ctl("picker down 1")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({tool_id})") is None,
        "confirmed end closes only its owned tool terminal",
    )
    h.wait_for(lambda _: not task_alive(), "confirmed end stops its foreground process")
    assert h.lua_json(f"cx.session:pane({second['pane']})"), \
        "Ending an orphan tool closed an unrelated source pane"
    h.record("confirmed end closes only the selected tool and stops its foreground process")

    cmdw_directory = h.root / "native Cmd-W source"
    cmdw_directory.mkdir()
    h.open_repo(cmdw_directory)
    cmdw_source = h.lua_json('cx.session:pane("@focused")')
    cmdw_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    cmdw_tool = {}
    def cmdw_tool_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in cmdw_before]
        if not new:
            return False
        assert len(new) == 1, new
        cmdw_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(cmdw_tool_opened, "native Cmd+W source test opens a real tool")
    cmdw_tool_id = cmdw_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({cmdw_tool_id})").get("at_prompt") is True,
        "native Cmd+W test tool reaches its shell prompt",
    )
    cmdw_pid_file = h.root / "native Cmd-W task pid.txt"
    cmdw_cwd_file = h.root / "native Cmd-W task cwd.txt"
    cmdw_script = (
        f"/bin/pwd -P > {shlex.quote(str(cmdw_cwd_file))}; "
        f"printf '%s\\n' \"$$\" > {shlex.quote(str(cmdw_pid_file))}; "
        "exec /bin/sleep 300"
    )
    h.type_text("/bin/sh -c " + shlex.quote(cmdw_script))
    h.ctl("key enter")
    def cmdw_task_alive():
        if not cmdw_pid_file.exists() or not cmdw_pid_file.read_text().strip():
            return False
        pid = int(cmdw_pid_file.read_text().strip())
        process = subprocess.run(
            ["/bin/ps", "-p", str(pid), "-o", "comm="],
            capture_output=True, text=True, timeout=5,
        )
        if process.returncode != 0 or Path(process.stdout.strip()).name != "sleep":
            return False
        os.kill(pid, 0)
        return True
    h.wait_for(lambda _: cmdw_task_alive(), "Cmd+W tool process and PID become observable")
    cmdw_pid = int(cmdw_pid_file.read_text().strip())
    assert Path(cmdw_cwd_file.read_text().strip()).resolve() == cmdw_directory.resolve()
    h.lua(f"cx.layout:focus({cmdw_source['pane']}); return true")
    h.ctl("key cmd+w")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({cmdw_source['pane']})") is None,
        "native Cmd+W closes the source pane",
    )
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({cmdw_tool_id})"))
                       and pane.get("parked") is not True),
        "native source closure leaves the live tool visible",
    )
    assert cmdw_task_alive(), "Native Cmd+W source closure ended the tool process"
    preserved_tool = h.lua_json(f"cx.session:pane({cmdw_tool_id})")
    assert Path(preserved_tool["cwd"]).resolve() == cmdw_directory.resolve(), \
        "Cmd+W source closure changed the original tool cwd"
    os.kill(cmdw_pid, 15)
    h.wait_for(lambda _: not cmdw_task_alive(), "Cmd+W regression task is cleaned up")
    h.record("native Cmd+W source closure leaves the same live process visible")
    stale_source_directory = h.root / "stale identity source"
    stale_source_directory.mkdir()
    h.open_repo(stale_source_directory)
    stale_source = h.lua_json('cx.session:pane("@focused")')
    stale_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    stale_tool = {}
    def stale_tool_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in stale_before]
        if not new:
            return False
        assert len(new) == 1, new
        stale_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(stale_tool_opened, "stale-record scenario creates its real terminal")
    stale_tool_id = stale_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({stale_tool_id})").get("at_prompt") is True,
        "stale-record terminal reaches its real shell prompt",
    )
    stale_pid_file = h.root / "stale-record task pid.txt"
    h.type_text(
        "/bin/sh -c " + shlex.quote(
            "printf '%s\\n' \"$$\" > " + shlex.quote(str(stale_pid_file))
            + "; exec /bin/sleep 300"
        )
    )
    h.ctl("key enter")
    h.wait_for(
        lambda _: stale_pid_file.exists() and stale_pid_file.read_text().strip(),
        "stale-record task reports its real PID",
    )
    stale_pid = int(stale_pid_file.read_text().strip())
    def stale_pid_alive():
        result = subprocess.run(
            ["/bin/ps", "-p", str(stale_pid), "-o", "pid="],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0 and result.stdout.strip() == str(stale_pid)
    h.wait_for(lambda _: stale_pid_alive(), "stale-record task is alive before reload")
    h.ctl("key ctrl+b")
    h.ctl("key q")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({stale_tool_id})"))
                       and pane.get("parked") is True),
        "managed stale-record tool parks before reload",
    )
    h.ctl("plugins fixtures")
    panes_after_reload = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    assert stale_tool_id in panes_after_reload
    h.lua(f"cx.layout:focus({stale_source['pane']}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key t")
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "same-key parked legacy pane blocks duplicate startup",
    )
    assert stale_pid_alive(), "Parked legacy refusal ended its task"
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == panes_after_reload
    assert h.lua_json(f"cx.session:pane({stale_tool_id})").get("parked") is True
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "parked legacy refusal clears before native terminal close")
    h.lua(f"cx.layout:unpark({stale_tool_id}, {{ focus = true }}); return true")
    h.ctl("key ctrl+c")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({stale_tool_id})"))
                       and pane.get("at_prompt") is True),
        "native Ctrl+C stops the legacy process and returns its shell prompt",
    )
    assert not stale_pid_alive(), "Native Ctrl+C left the legacy process alive"
    h.type_text("exit 0")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({stale_tool_id})") is None,
        "native shell exit removes the legacy pane while retaining its old record",
    )
    h.lua(f"cx.layout:focus({stale_source['pane']}); return true")
    new_after_stale = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    replacement_tool = {}
    def replacement_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in new_after_stale]
        if not new:
            return False
        assert len(new) == 1, new
        replacement_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(replacement_opened, "closed-pane history no longer blocks a new source tool")
    replacement_id = replacement_tool["pane"]
    assert replacement_id != stale_tool_id
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({replacement_id})").get("at_prompt") is True,
        "replacement terminal reaches its own real shell prompt",
    )
    h.type_text("exit 0")
    h.ctl("key enter")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({replacement_id})") is None,
        "replacement terminal closes without touching the old history record",
    )
    h.record("present parked legacy pane refuses ownership, closed legacy pane no longer blocks explicit startup")


    unknown_source_directory = h.root / "unknown reload source"
    unknown_source_directory.mkdir()
    h.open_repo(unknown_source_directory)
    unknown_source = h.lua_json('cx.session:pane("@focused")')
    unknown_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    unknown_tool = {}
    def unknown_tool_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in unknown_before]
        if not new:
            return False
        assert len(new) == 1, new
        unknown_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(unknown_tool_opened, "independent source opens a tool for reload rejection")
    unknown_tool_id = unknown_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({unknown_tool_id})").get("at_prompt") is True,
        "reload rejection tool reaches its shell prompt",
    )
    unknown_pid_file = h.root / "unknown reload shell pid.txt"
    h.type_text("printf '%s\\n' \"$$\" > " + shlex.quote(str(unknown_pid_file)))
    h.ctl("key enter")
    h.wait_for(
        lambda _: unknown_pid_file.exists() and unknown_pid_file.read_text().strip(),
        "reload rejection shell reports its real PID",
    )
    unknown_pid = int(unknown_pid_file.read_text().strip())
    unknown_pid_alive = lambda: subprocess.run(
        ["/bin/ps", "-p", str(unknown_pid), "-o", "pid="],
        capture_output=True, text=True, timeout=5,
    ).returncode == 0
    # The shell records its identity in the private launch directory, so the
    # pane's own output must never expose an internal handshake or its token.
    unknown_scrollback = h.lua_json(f"cx.session:read({unknown_tool_id}, {{lines = 2000}})")
    assert "KIKU_TOOL" not in str(unknown_scrollback), unknown_scrollback
    assert "/bin/sh -c 'printf" not in str(unknown_scrollback), unknown_scrollback
    unknown_records = [json.loads(path.read_text()) for path in
                       h.root.rglob("plugin-data/kiku/tools/*.json")]
    unknown_record = next(record for record in unknown_records
                          if record.get("pane") == unknown_tool_id)
    marker_token = unknown_record["token"]
    assert len(marker_token) == 32 and all(char in "0123456789abcdef" for char in marker_token)
    assert marker_token not in str(unknown_scrollback), unknown_scrollback
    unknown_output_done = h.root / "unknown reload output finished.txt"
    h.type_text(
        "i=0; while [ $i -lt 2500 ]; do printf 'unknown-output-%s\\n' \"$i\"; "
        "i=$((i+1)); done; printf done > " + shlex.quote(str(unknown_output_done))
    )
    h.ctl("key enter")
    h.wait_for(
        lambda _: unknown_output_done.exists() and unknown_output_done.read_text() == "done"
        and bool((pane := h.lua_json(f"cx.session:pane({unknown_tool_id})"))
                 and pane.get("at_prompt") is True and pane.get("last", {}).get("status") == 0),
        "independent tool completes long output that removes its old identity marker",
    )
    marker_source_directory = h.root / "marker-only ordinary source"
    marker_source_directory.mkdir()
    h.open_repo(marker_source_directory)
    marker_source = h.lua_json('cx.session:pane("@focused")')
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({marker_source['pane']})").get("at_prompt") is True,
        "ordinary marker-display source reaches its real prompt",
    )
    h.type_text("printf '%s\\n' " + shlex.quote(f"KIKU_TOOL_V1:{marker_token}:%s"))
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({marker_source['pane']})"))
                       and pane.get("at_prompt") is True and pane.get("last", {}).get("status") == 0),
        "ordinary source only prints the copied prefix text",
    )
    marker_source_before = h.lua_json(f"cx.session:pane({marker_source['pane']})")
    marker_tool_before = h.lua_json(f"cx.session:pane({unknown_tool_id})")
    marker_panes_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "previous warning clears before marker-only adoption probe")
    h.ctl("plugins fixtures")
    h.ctl("plugins run plugin.kiku.restore_tools")
    h.wait_for(
        lambda state: not state.get("picker") and _has_info_toast(h.ctl("tree")),
        "post-reload restore visibly reports no current-VM tools",
    )
    assert not h.state().get("picker"), \
        "Plain prefix text in an ordinary pane was accepted as tool identity"
    marker_source_after = h.lua_json(f"cx.session:pane({marker_source['pane']})")
    marker_tool_after = h.lua_json(f"cx.session:pane({unknown_tool_id})")
    assert marker_source_after and all(
        marker_source_after.get(key) == marker_source_before.get(key)
        for key in ("pane", "tab", "floating", "parked")
    ), (marker_source_before, marker_source_after)
    assert marker_tool_after and all(
        marker_tool_after.get(key) == marker_tool_before.get(key)
        for key in ("pane", "tab", "floating", "parked")
    ), (marker_tool_before, marker_tool_after)
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == marker_panes_before
    assert unknown_pid_alive(), "Marker-only discovery ended the recorded tool shell"
    h.record("plain prefix text in another native pane cannot claim or park the live recorded tool")
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "marker-only rejection alert clears before unknown-tool controls")
    h.lua(f"cx.layout:focus({unknown_tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key t")
    h.wait_for(lambda _state: _has_error_alert(h.ctl("tree")),
               "open from an unknown post-reload tool pane visibly refuses nesting")
    assert unknown_pid_alive(), "Rejected open ended the unknown tool shell"
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == marker_panes_before
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "open refusal alert clears before hide check")
    h.ctl("key ctrl+b")
    h.ctl("key q")
    h.wait_for(lambda _state: _has_error_alert(h.ctl("tree")),
               "hide from an unknown post-reload pane visibly refuses")
    assert unknown_pid_alive(), "Rejected hide ended the unknown tool shell"
    h.wait_for(lambda _state: not _has_error_alert(h.ctl("tree")),
               "hide refusal alert clears before end check")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(lambda _state: _has_error_alert(h.ctl("tree")),
               "end from an unknown post-reload pane visibly refuses")
    assert unknown_pid_alive(), "Rejected end ended the unknown tool shell"
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == marker_panes_before
    moved_session = h.lua_json(
        'cx.sessions:create({name="moved unknown tool",cwd='
        f'cx.session:pane({unknown_source["pane"]}).cwd' + '})'
    )
    h.lua(
        f"local tab, err = cx.layout:move_to_new_tab({unknown_tool_id}, "
        f"{moved_session['id']}, {{focus=true}}); assert(tab, err); return tab"
    )
    moved_tool_before = h.lua_json(f"cx.session:pane({unknown_tool_id})")
    moved_panes_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    h.wait_for(lambda _state: _has_error_alert(h.ctl("tree")),
               "moving an unknown tool to another session does not authorize nesting")
    assert unknown_pid_alive(), "Cross-session refusal ended the unknown tool shell"
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == moved_panes_before
    moved_tool_after = h.lua_json(f"cx.session:pane({unknown_tool_id})")
    assert all(moved_tool_after.get(key) == moved_tool_before.get(key)
               for key in ("pane", "tab", "cwd", "floating", "parked"))
    h.record("native cross-session movement does not turn an unknown legacy tool into a new source")
    h.lua(f"cx.layout:close({unknown_tool_id}); return true")
    assert h.lua_json(f"cx.session:pane({unknown_source['pane']})"), \
        "Unknown-tool cleanup closed its independent source pane"
    h.record("post-reload markerless tool pane is rejected as an owner without nesting or termination")
    orphan_directory = h.root / "orphan scratch origin"
    orphan_directory.mkdir()
    h.open_repo(orphan_directory)
    orphan_source = h.lua_json('cx.session:pane("@focused")')
    orphan_source_tab = orphan_source["tab"]
    orphan_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    orphan_tool = {}
    def orphan_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in orphan_before]
        if not new:
            return False
        assert len(new) == 1, new
        orphan_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(orphan_opened, "isolated origin opens scratch for tab-loss recovery")
    orphan_tool_id = orphan_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({orphan_tool_id})").get("at_prompt") is True,
        "orphan recovery shell reaches its prompt",
    )
    orphan_pid_file = h.root / "orphan recovery task pid.txt"
    orphan_cwd_file = h.root / "orphan recovery task cwd.txt"
    orphan_script = (
        f"/bin/pwd -P > {shlex.quote(str(orphan_cwd_file))}; "
        f"printf '%s\\n' \"$$\" > {shlex.quote(str(orphan_pid_file))}; "
        "exec /bin/sleep 300"
    )
    h.type_text("/bin/sh -c " + shlex.quote(orphan_script))
    h.ctl("key enter")
    h.wait_for(lambda _: orphan_pid_file.exists(), "orphan recovery task reports a real PID")
    orphan_pid = int(orphan_pid_file.read_text().strip())
    def orphan_task_alive():
        result = subprocess.run(
            ["/bin/ps", "-p", str(orphan_pid), "-o", "comm="],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0 or Path(result.stdout.strip()).name != "sleep":
            return False
        os.kill(orphan_pid, 0)
        return True
    h.wait_for(lambda _: orphan_task_alive(), "orphan recovery task is a live native process")
    assert Path(orphan_cwd_file.read_text().strip()).resolve() == orphan_directory.resolve()
    h.ctl("key ctrl+b")
    h.ctl("key q")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({orphan_tool_id})").get("parked") is True,
        "scratch parks before its origin tab closes",
    )
    h.open_repo(h.repo)
    destination = h.lua_json('cx.session:pane("@focused")')
    destination_tab = destination["tab"]
    h.lua(f"cx.layout:close({orphan_source['pane']}); return true")
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({orphan_source['pane']})") is None,
        "closing the last tiled origin pane removes the origin tab",
    )
    assert all(
        pane["tab"] != orphan_source_tab
        for pane in h.lua_json("cx.session:panes()")
        if pane["pane"] != orphan_tool_id
    )
    assert orphan_task_alive(), "Closing the origin tab ended the parked scratch task"
    h.ctl("plugins run plugin.kiku.restore_tools")
    h.wait_for(lambda state: bool(state.get("picker")), "orphan scratch restore picker opens")
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({orphan_tool_id})"))
                       and pane.get("parked") is not True and pane.get("tab") == destination_tab),
        "explicit restore rekeys parked scratch into the current tab",
    )
    assert orphan_task_alive(), "Rekeying orphan scratch ended its real task"
    assert Path(h.lua_json(f"cx.session:pane({orphan_tool_id})")["cwd"]).resolve() == \
        orphan_directory.resolve()
    assert Path(orphan_cwd_file.read_text().strip()).resolve() == orphan_directory.resolve()
    h.lua(f"cx.layout:close({orphan_tool_id}); return true")
    h.wait_for(lambda _: not orphan_task_alive(), "orphan recovery process is cleaned up natively")
    h.record("parked scratch survives origin-tab closure and explicit restore rekeys it to the current tab")
    run_remote_guard(h)


def run_restart(h):
    # Tern 0.9.5 currently reproduces native Restart in serve, not daemon mode.
    # Keep its process-generation regression separate from the full GUI suite.
    source_directory = h.root / "native restart source"
    source_directory.mkdir()
    h.open_repo(source_directory)
    restart_before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.lua(
        'cx.actions:run("plugin.kiku.open_terminal"); '
        'cx.actions:run("plugin.kiku.open_terminal")'
    )
    restarted_tool = {}
    def restarted_tool_opened(_state):
        new = [pane for pane in h.lua_json("cx.session:panes()")
               if pane["pane"] not in restart_before]
        if not new:
            return False
        assert len(new) == 1, new
        restarted_tool.update(new[0])
        return bool(new[0].get("floating") is True and new[0].get("focused") is True)
    h.wait_for(restarted_tool_opened, "a fresh shell opens for native Restart regression")
    failed_tool_id = restarted_tool["pane"]
    h.wait_for(
        lambda _: h.lua_json(f"cx.session:pane({failed_tool_id})").get("at_prompt") is True,
        "fresh restart-regression shell reaches its prompt",
    )
    h.type_text("exit 7")
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("exited") == 7),
        "fresh restart-regression shell exits with failure",
    )
    # Tern's native Enter restarts the exited terminal in place and clears
    # scrollback; the previous failed-tool record must not claim the new shell.
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("exited") is None and pane.get("at_prompt") is True),
        "native Enter restarts the failed tool in the same pane",
    )
    restarted_pid_file = h.root / "restarted tool shell pid.txt"
    h.type_text("printf '%s\\n' \"$$\" > " + shlex.quote(str(restarted_pid_file)))
    h.ctl("key enter")
    h.wait_for(
        lambda _: restarted_pid_file.exists() and restarted_pid_file.read_text().strip(),
        "restarted shell reports its real PID",
    )
    restarted_pid = int(restarted_pid_file.read_text().strip())
    def restarted_alive():
        result = subprocess.run(
            ["/bin/ps", "-p", str(restarted_pid), "-o", "pid="],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0 and result.stdout.strip() == str(restarted_pid)
    h.wait_for(lambda _: restarted_alive(), "restarted shell is a live native process")
    h.wait_for(
        lambda _state: not _has_error_alert(h.ctl("tree")),
        "previous terminal warning disappears before Restart checks",
    )
    h.ctl("key ctrl+b")
    h.ctl("key t")
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "open attempt after Restart reports its visible refusal",
    )
    assert restarted_alive(), "Open after native Restart ended the new shell"
    assert h.lua_json(f"cx.session:pane({failed_tool_id})"), \
        "Open after native Restart closed the new shell pane"
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == \
        restart_before | {failed_tool_id}, "Open after Restart created a duplicate tool pane"
    h.wait_for(
        lambda _state: not _has_error_alert(h.ctl("tree")),
        "open refusal alert clears before hide check",
    )
    h.lua(f"cx.layout:focus({failed_tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key q")
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "hide attempt after Restart reports its visible refusal",
    )
    assert restarted_alive(), "Hide after native Restart ended the new shell"
    assert h.lua_json(f"cx.session:pane({failed_tool_id})"), \
        "Hide after native Restart closed the new shell pane"
    h.wait_for(
        lambda _state: not _has_error_alert(h.ctl("tree")),
        "hide refusal alert clears before end confirmation",
    )
    h.lua(f"cx.layout:focus({failed_tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "unconfirmed restarted shell is rejected before end confirmation",
    )
    assert restarted_alive(), "End after native Restart killed the new shell generation"
    assert h.lua_json(f"cx.session:pane({failed_tool_id})"), \
        "End after native Restart closed the new shell pane"
    h.wait_for(
        lambda _state: not _has_error_alert(h.ctl("tree")),
        "end refusal alert clears before restarting shell",
    )
    h.type_text("exit 7")
    h.ctl("key enter")
    h.wait_for(
        lambda _: bool((pane := h.lua_json(f"cx.session:pane({failed_tool_id})"))
                       and pane.get("exited") == 7),
        "restarted shell can independently exit with failure",
    )
    h.lua(f"cx.layout:focus({failed_tool_id}); return true")
    h.ctl("key ctrl+b")
    h.ctl("key shift+q")
    h.wait_for(
        lambda _state: _has_error_alert(h.ctl("tree")),
        "failed restarted shell is rejected before end confirmation",
    )
    assert h.lua_json(f"cx.session:pane({failed_tool_id})"), \
        "old tool identity closed the restarted shell after its failure"
    h.wait_for(
        lambda _state: not _has_error_alert(h.ctl("tree")),
        "restarted-failure refusal alert clears before source reuse",
    )
    h.record("native Restart never authorizes the prior tool identity to open, hide or end the new shell")


def run_remote_guard(h):
    # A real in-process Tern host supplies a non-local SDK context without SSH.
    h.ctl("remote loopback kiku-remote-guard")
    host = h.lua_json("cx.hosts:current()")
    assert host["kind"] != "local", host
    before = {pane["pane"] for pane in h.lua_json("cx.session:panes()")}
    h.ctl("key ctrl+b")
    h.ctl("key t")
    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "remote terminal shortcut reports its visible refusal")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before
    h.ctl("plugins run plugin.kiku.open_terminal")
    h.wait_for(lambda _: _has_error_alert(h.ctl("tree")),
               "remote direct terminal action reports its visible refusal")
    assert {pane["pane"] for pane in h.lua_json("cx.session:panes()")} == before
    assert h.lua_json("cx.hosts:current()")["id"] == host["id"]
    h.record("managed non-local host refuses terminal shortcuts and direct actions without local fallback")
