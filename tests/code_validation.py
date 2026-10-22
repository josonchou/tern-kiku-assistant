#!/usr/bin/env python3
"""Run production Luau tool modules against a narrow Tern SDK boundary fixture."""
import argparse
import pathlib
import subprocess
import tempfile
import sys

CASES = [
    "same_tab_different_source_reuses",
    "single_flight_same_key",
    "stale_focus_aborts_creation",
    "reuse_restores_layout_without_process_sampling",
    "restarted_shell_pane_remains_manageable",
    "end_confirmation_reports_live_pane",
    "restart_during_token_preparation_still_creates",
    "cwd_change_creates_distinct_instance",
    "tool_cd_keeps_origin_key",
    "different_tab_creates_distinct_instance",
    "cross_tab_reuse_returns_origin_tab",
    "tool_kinds_coexist",
    "scratch_hide_restore_and_end",
    "glance_pip_keeps_leader_actions",
    "glance_ambiguous_pip_refuses_to_guess",
    "glance_other_tab_keeps_pip",
    "parked_restore_returns_origin_tab",
    "orphan_restore_reassigns_tab",
    "orphan_conflict_preserves_both_instances",
    "source_close_keeps_tool",
    "reload_adopts_record_with_live_pane",
    "process_state_does_not_gate_management",
    "frozen_process_sample_never_blocks_actions",
    "ambiguous_split_blocks_retry",
    "definite_split_failure_releases_reservation",
    "default_layout_preserves_unrelated_split",
    "source_restart_does_not_block_target_reuse",
    "tool_current_cwd_drives_new_instance",
    "incomplete_process_inventory_does_not_block_reuse",
    "exception_without_observed_pane_blocks_retry",
    "native_block_sources_open_and_reuse_tools",
    "native_block_unknown_cwd_does_not_guess_path",
    "remote_native_block_stays_rejected",
    "native_block_cwd_change_aborts_creation",
    "lazygit_non_git_source_refuses",
    "lazygit_repo_check_aborts_on_source_change",
    "creation_presents_tool_without_typing",
    "lazygit_launches_through_launch_command",
    "silent_start_records_identity_without_typing",
    "unsupported_shell_reports_and_keeps_pane",
    "lazygit_falls_back_to_login_path",
    "missing_program_still_reports_failure",
]
ROOT = pathlib.Path(__file__).resolve().parents[1]


def lua_string(value):
    delimiter = "="
    while "]" + delimiter + "]" in value:
        delimiter += "="
    return "[" + delimiter + "[" + value + "]" + delimiter + "]"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau", required=True)
    parser.add_argument("--case")
    args = parser.parse_args()
    if args.case is None:
        for case_name in CASES:
            subprocess.run(
                [sys.executable, str(pathlib.Path(__file__).resolve()),
                 "--luau", args.luau, "--case", case_name],
                check=True,
            )
        return
    files = {
        "tools": "lib/tools.luau",
        "identity": "lib/tool_identity.luau",
        "launch": "lib/lazygit_launch.luau",
        "executables": "lib/executables.luau",
        "tests": "tests/tool_code.luau",
        "fixture": "tests/code_fixture.luau",
    }
    modules = {name: (ROOT / path).read_text(encoding="utf-8") for name, path in files.items()}
    module_table = "{\n" + ",\n".join(
        f"    {name}={lua_string(source)}" for name, source in modules.items()
    ) + "\n}"
    case = "nil" if args.case is None else lua_string(args.case)
    runner = f'''local sources = {module_table}
local loaded = {{}}
local function module(name)
    if loaded[name] then return loaded[name] end
    local env = setmetatable({{require=function(path)
        if path == "tern" then return loaded.tern end
        if path == "./code_fixture" then return module("fixture") end
        if path == "./tool_identity" then return module("identity") end
        if path == "./lazygit_launch" then return module("launch") end
        error("unsupported require " .. path)
    end}}, {{__index=_G}})
    local chunk,err=loadstring(sources[name], "@" .. name)
    assert(chunk,err)
    setfenv(chunk,env)
    local result=chunk()
    loaded[name]=result
    return result
end
local fixture = module("fixture")
local tern,state,cx = fixture.tern,fixture.state,fixture.cx
loaded.tern = tern
state.identity = module("identity")
local function fresh(name)
    loaded[name]=nil
    return module(name)
end
module("tests")(module("tools"),tern,state,cx,fresh,{case})
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", encoding="utf-8") as script:
        script.write(runner)
        script.flush()
        subprocess.run([args.luau, script.name], check=True)


if __name__ == "__main__":
    main()
