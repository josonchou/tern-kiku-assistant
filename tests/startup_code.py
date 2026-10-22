#!/usr/bin/env python3
"""Run the production Tern spawn filter against real shells, without starting Tern.

The Luau harness loads plugin/lib/tool_identity.luau with only the host boundary stubbed
(plugin data, fs, json pair). Each shell then executes the exact command line the
production filter produced, so quoting, PID continuity and silence are real.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "0123456789abcdef0123456789abcdef"
SHELLS = {
    "zsh": ("/bin/zsh", "$$", '"$0"'),
    "bash": ("/bin/bash", "$$", '"$0"'),
    "sh": ("/bin/sh", "$$", '"$0"'),
    "dash": ("/bin/dash", "$$", '"$0"'),
    "ksh": ("/bin/ksh", "$$", '"$0"'),
    "fish": ("/usr/local/bin/fish", "$fish_pid", '"$argv[1]"'),
}
HARNESS = r'''
local data, token, program, finalCommand = @@DATA@@, @@TOKEN@@, @@PROGRAM@@, @@FINAL@@
local files = {}
local tern = {
    plugin = { data = data },
    json = { encode = function(value) return value end, decode = function(value) return value end },
    fs = {
        exists = function(_) return false end,
        mkdir = function(_) end,
        write = function(path, value) files[path] = value end,
        read = function(path, _) return files[path] end,
        remove = function(path) files[path] = nil end,
    },
    process = { run = function() error("the spawn filter must not start processes") end },
}
local environment = setmetatable({ require = function(_) return tern end }, { __index = _G })
local identity = assert(loadstring(@@IDENTITY@@, "@tool_identity"))
setfenv(identity, environment)
identity = identity()
local requested = @@CWD@@
local directory, launchError = identity.launch(token, requested)
assert(directory, launchError)
local modified = identity.spawn({ program = program, args = { "-l", "-c", finalCommand, "kiku-name" }, cwd = directory })
assert(modified, "the launch directory must be claimed")
assert(modified.cwd == requested, "the filter must restore the requested directory")
print("program=" .. modified.program)
for index, value in ipairs(modified.args) do
    print(string.format("arg=%d:%d:%s", index, #value, value))
end
print("plain=" .. tostring(identity.spawn({ program = program, args = { "-l" }, cwd = requested })))
local unsupported = identity.spawn({ program = "/usr/bin/perl", args = { "-e", "1" }, cwd = directory })
print("unsupported=" .. tostring(unsupported and unsupported.program) ..
    ":" .. tostring(unsupported and unsupported.args[2]) ..
    ":" .. tostring(unsupported and unsupported.cwd == requested))
'''


def lua(value):
    return json.dumps(value, ensure_ascii=False)


def parse(output):
    program, args, extra = None, [], {}
    for line in output.splitlines():
        if line.startswith("program="):
            program = line.split("=", 1)[1]
        elif line.startswith("arg="):
            _, rest = line.split("=", 1)
            index, _, value = rest.split(":", 2)
            args.append((int(index), value))
        elif "=" in line:
            key, value = line.split("=", 1)
            extra[key] = value
    assert program, output
    assert [index for index, _ in args] == list(range(1, len(args) + 1)), output
    return program, [value for _, value in args], extra


def run_shell(root, luau, name):
    program_path, pid_expression, name_expression = SHELLS[name]
    requested = root / f"{name}工作 目录"
    requested.mkdir(parents=True, exist_ok=True)
    pid_two = requested / "final.pid"
    name_file = requested / "argv-name.txt"
    final = (f"printf '%s\\n' {pid_expression} > {shlex.quote(str(pid_two))}; "
             f"printf '%s' {name_expression} > {shlex.quote(str(name_file))}")
    script = (HARNESS
              .replace("@@IDENTITY@@", lua((ROOT / "plugin" / "lib" / "tool_identity.luau").read_text(encoding="utf-8")))
              .replace("@@DATA@@", lua(str(root)))
              .replace("@@TOKEN@@", lua(TOKEN))
              .replace("@@PROGRAM@@", lua(program_path))
              .replace("@@FINAL@@", lua(final))
              .replace("@@CWD@@", lua(str(requested))))
    harness = root / f"harness-{name}.luau"
    harness.write_text(script, encoding="utf-8")
    env = dict(os.environ)
    env.pop("KITTY_BASH_INJECT", None)
    env.pop("ENV", None)
    if name == "bash":
        # Tern installs bash integration as a POSIX shell with ENV set.
        env.update({"KITTY_BASH_INJECT": "1", "ENV": "/dev/null"})
    output = subprocess.run([luau, str(harness)], capture_output=True, text=True, env=env)
    assert output.returncode == 0, (name, output.stdout, output.stderr)
    program, args, extra = parse(output.stdout)
    launch_dir = root / "tool-start" / TOKEN
    launch_dir.mkdir(parents=True, exist_ok=True)
    (launch_dir / "pid").unlink(missing_ok=True)
    first = subprocess.run([program, *args], cwd=str(requested), capture_output=True, text=True, env=env)
    assert first.returncode == 0, (name, first.stdout, first.stderr)
    assert first.stdout == "" and first.stderr == "", (name, first.stdout, first.stderr)
    recorded = (launch_dir / "pid").read_text().strip()
    final_pid = pid_two.read_text().strip()
    assert recorded and recorded.isdigit(), (name, recorded)
    assert recorded == final_pid, (name, recorded, final_pid)
    assert name_file.read_text() == "kiku-name", (name, name_file.read_text())
    assert extra.get("plain") == "nil", (name, extra)
    assert extra.get("unsupported") == "/bin/sh:exit 125:true", (name, extra)
    # A native Restart re-runs the same spec; the first generation keeps its PID.
    second = subprocess.run([program, *args], cwd=str(requested), capture_output=True, text=True, env=env)
    assert second.returncode == 0, (name, second.stdout, second.stderr)
    assert second.stdout == "" and second.stderr == "", (name, second.stdout, second.stderr)
    assert (launch_dir / "pid").read_text().strip() == recorded, (name, "restart overwrote the first PID")
    return f"{name}: 静默启动，PID {recorded} 在重启后保持首代次"


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau")
    assert luau, "a Luau interpreter is required"
    root = Path(tempfile.mkdtemp(prefix="kiku-startup-code-"))
    labels = []
    for name, (path, _, _) in SHELLS.items():
        if not Path(path).is_file():
            labels.append(f"{name}: 未安装，未验证")
            continue
        labels.append(run_shell(root, luau, name))
    for label in labels:
        print(label)
    print("证据目录：" + str(root))


if __name__ == "__main__":
    main()
