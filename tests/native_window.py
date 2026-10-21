"""Private real-Tern GUI and daemon lifecycle for native integration scenarios."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


TERN_APP = Path("/Applications/Tern.app/Contents/MacOS/tern")


def _osascript(source):
    return subprocess.run(["osascript", "-l", "JavaScript", "-e", source],
                          capture_output=True, text=True, check=True, timeout=10).stdout.strip()


class NativeWindow:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.control_root = Path(tempfile.mkdtemp(prefix="kas-", dir="/tmp")).resolve()
        self.socket = self.control_root / "c.sock"
        self.config = self.root / "cfg"
        self.logs = self.root / "logs"
        self.plugin = self.root / "plugin"
        self.daemon_socket = self.control_root / "d.sock"
        self.tern = str(TERN_APP) if TERN_APP.is_file() else shutil.which("tern")
        self.env = None
        self.extra_env = {}
        self.daemon = None
        self.gui = None
        self.log = None
        self.frontmost_pid = None

    def check_desktop(self):
        if not self.tern:
            raise RuntimeError("需要安装 Tern；未找到 /Applications/Tern.app 或 PATH 中的 tern")
        if os.uname().sysname != "Darwin":
            return
        session = json.loads(_osascript(
            'ObjC.import("CoreGraphics"); var d=ObjC.deepUnwrap(ObjC.castRefToObject('
            '$.CGSessionCopyCurrentDictionary())); JSON.stringify({locked:d.CGSSessionScreenIsLocked,'
            'onConsole:d.kCGSSessionOnConsoleKey});'
        ))
        if session.get("locked") or not session.get("onConsole"):
            raise RuntimeError("原生 Tern 验收需要已解锁且处于本机控制台的桌面；请解锁后重试")
        self.frontmost_pid = int(_osascript(
            'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier'
        ))

    def start(self):
        try:
            self._start()
        except BaseException:
            self.close(lambda command: subprocess.run(
                [self.tern, "ctl", "--control", str(self.socket), command],
                capture_output=True, text=True, timeout=5,
            ))
            raise

    def _start(self):
        self.config.mkdir()
        self.logs.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("TERN_")}
        self.env.update({"TERN_CONFIG_DIR": str(self.config),
                         "TERN_DAEMON_SOCKET": str(self.daemon_socket),
                         "STENCIL_LOG_DIR": str(self.logs),
                         **self.extra_env})
        self.log = open(self.root / "native-tern.log", "w")
        self.daemon = subprocess.Popen([self.tern, "daemon", "--socket", str(self.daemon_socket)],
                                       cwd=self.root, env=self.env, stdout=self.log, stderr=self.log)
        deadline = time.monotonic() + 20
        while not self.daemon_socket.exists():
            if self.daemon.poll() is not None:
                raise RuntimeError("私有 Tern daemon 提前退出：" + (self.root / "native-tern.log").read_text())
            if time.monotonic() >= deadline:
                raise RuntimeError("等待私有 Tern daemon socket 超时")
            time.sleep(0.1)
        (self.config / "plugins").mkdir(parents=True, exist_ok=True)
        link = subprocess.run([self.tern, "plugin", "link", str(self.plugin), "--json"],
                              cwd=self.root, env=self.env, capture_output=True, text=True, timeout=30)
        if link.returncode:
            raise RuntimeError("注册私有测试插件失败：" + link.stdout + link.stderr)
        self.gui = subprocess.Popen([self.tern, "--control", str(self.socket), str(self.root)],
                                    cwd=self.root, env=self.env, stdout=self.log, stderr=self.log)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if self.gui.poll() is not None:
                raise RuntimeError("原生 Tern GUI 提前退出：" + (self.root / "native-tern.log").read_text())
            try:
                result = subprocess.run([self.tern, "ctl", "--control", str(self.socket), "state"],
                                        capture_output=True, text=True, timeout=2)
                if result.returncode == 0 and json.loads(result.stdout).get("ok", True):
                    if os.uname().sysname == "Darwin":
                        _osascript('ObjC.import("AppKit"); var app=$.NSRunningApplication.'
                                   'runningApplicationWithProcessIdentifier(' + str(self.gui.pid) +
                                   '); app.unhide; app.activateWithOptions(2);')
                    return
            except (subprocess.TimeoutExpired, json.JSONDecodeError):
                pass
            time.sleep(0.1)
        raise RuntimeError("等待原生 Tern 控制连接超时")

    def reload_plugins(self, ctl):
        return ctl("plugins run reload_plugins")

    def close(self, ctl):
        try:
            if self.gui and self.gui.poll() is None:
                try:
                    ctl("quit")
                except Exception:
                    self.gui.terminate()
                try:
                    self.gui.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.gui.terminate()
                    try:
                        self.gui.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.gui.kill()
                        self.gui.wait()
        finally:
            if self.daemon and self.daemon.poll() is None:
                self.daemon.terminate()
                try:
                    self.daemon.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    # Reap only this explicit Popen child; never search or signal another Tern.
                    self.daemon.kill()
                    self.daemon.wait()
            if self.frontmost_pid and os.uname().sysname == "Darwin":
                try:
                    _osascript('ObjC.import("AppKit"); $.NSRunningApplication.'
                               'runningApplicationWithProcessIdentifier(' + str(self.frontmost_pid) +
                               ').activateWithOptions(2);')
                except subprocess.SubprocessError as error:
                    print("恢复原前台应用失败：" + str(error))
            if self.log:
                self.log.close()
            shutil.rmtree(self.control_root)
