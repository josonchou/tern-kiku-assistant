"""One real-Tern worktree creation scenario for a configured Git path with spaces."""

from pathlib import Path


def run(h):
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
