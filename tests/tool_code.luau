return function(tools, tern, state, cx, fresh, selectedCase)
    local checks=0
    local function eq(actual,expected)
        assert(actual==expected,tostring(actual).." != "..tostring(expected))
        checks+=1
    end
    local function resolver()
        return {
            ready=function() return true end,
            check=function(_,nextCx,_,callback)
                callback(nextCx,{errors={},fallbacks={},paths={git="/usr/bin/git",lazygit="/usr/bin/lazygit"},pathEnv="/usr/bin"},nil)
            end,
        }
    end
    local function setup()
        state.panes={}
        state.addPane(1,{cwd="/work/project",tab=11})
        state.addPane(2,{cwd="/work/project",tab=11})
        state.tabs={{id=11,session=9}}
        state.layouts={[11]={tab=11,root={split="right",[1]={pane=1},[2]={pane=2}},floats={},focus=1}}
        state.focus=1
        state.currentSession=9
        state.nextPane=30
        state.nextPid=100
        state.nextToken=0
        state.samples=0
        state.processByPid={}
        state.processCallbacks={}
        state.promiseCallbacks={}
        state.pickChoices={}
        state.pickHandler=nil
        state.identityFiles={}
        state.directories={}
        state.existingPaths={["/bin/zsh"]=true}
        state.env={PATH="/usr/bin:/bin",SHELL="/bin/zsh"}
        state.loginPath=nil
        state.loginProbes=0
        state.shellProgram="/bin/zsh"
        state.timers={}
        state.parentCallbacks={}
        state.deferParentFind=false
        state.commands={}
        state.events={}
        state.toasts={}
        state.deferProcess=false
        state.deferPromises=false
        state.processInvalid=false
        state.splitMode=nil
        state.isGitRepo=true
        state.repoChecks=0
        tools.register({terminalKeybinding="ctrl+b>q",lazygitKeybinding="",hideToolKeybinding="",endToolKeybinding=""},resolver(),nil)
    end
    local function toolPanes()
        local found={}
        for _,pane in ipairs(cx.session:panes()) do
            if pane.pane>=30 then table.insert(found,pane) end
        end
        table.sort(found,function(a,b) return a.pane<b.pane end)
        return found
    end
    local function openScratch()
        state.commands.open_terminal.run(cx)
        return toolPanes()
    end
    local function chooseFirst(opts) return opts.items[1] end

    if selectedCase=="same_tab_different_source_reuses" then
        setup()
        state.commands.open_terminal.run(cx)
        local first=toolPanes()
        eq(#first,1)
        local firstPane=first[1]
        eq(cx.session:focused(),firstPane.pane)
        eq(cx.session:pane(firstPane.pane).exited,nil)
        state.focus=2
        state.commands.open_terminal.run(cx)
        local after=toolPanes()
        eq(#after,1)
        eq(after[1].pane,firstPane.pane)
        eq(cx.session:focused(),firstPane.pane)
        eq(cx.session:pane(firstPane.pane).exited,nil)
        eq(cx.session:pane(firstPane.pane).floating,true)

    elseif selectedCase=="single_flight_same_key" then
        setup()
        state.deferProcess=true
        state.commands.open_terminal.run(cx)
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),0)
        state.deferProcess=false
        state.flushProcess()
        eq(#toolPanes(),1)
        eq(cx.session:focused(),toolPanes()[1].pane)

    elseif selectedCase=="stale_focus_aborts_creation" then
        setup()
        state.deferProcess=true
        state.commands.open_terminal.run(cx)
        state.focus=2
        state.deferProcess=false
        state.flushProcess()
        eq(#toolPanes(),0)
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].cwd,"/work/project")

    elseif selectedCase=="cwd_change_creates_distinct_instance" then
        setup()
        local first=openScratch()[1]
        state.focus=1
        state.panes[1].cwd="/work/other"
        state.commands.open_terminal.run(cx)
        local after=toolPanes()
        eq(#after,2)
        eq(after[1].cwd,"/work/project")
        eq(after[2].cwd,"/work/other")
        eq(after[1].pane,first.pane)

    elseif selectedCase=="tool_cd_keeps_origin_key" then
        setup()
        local first=openScratch()[1]
        state.panes[first.pane].cwd="/work/elsewhere"
        state.focus=1
        state.commands.open_terminal.run(cx)
        local after=toolPanes()
        eq(#after,1)
        eq(after[1].pane,first.pane)
        eq(after[1].cwd,"/work/elsewhere")

    elseif selectedCase=="different_tab_creates_distinct_instance" then
        setup()
        openScratch()
        state.tabs={{id=11,session=9},{id=12,session=9}}
        state.addPane(3,{cwd="/work/project",tab=12})
        state.layouts[12]={tab=12,root={pane=3},floats={},focus=3}
        state.focus=3
        state.commands.open_terminal.run(cx)
        local after=toolPanes()
        eq(#after,2)
        eq(after[1].cwd,"/work/project")
        eq(after[2].cwd,"/work/project")
        eq(after[1].tab,11)
        eq(after[2].tab,12)

    elseif selectedCase=="cross_tab_reuse_returns_origin_tab" then
        setup()
        local scratch=openScratch()[1]
        state.tabs={{id=11,session=9},{id=12,session=9}}
        state.addPane(3,{cwd="/work/project",tab=12})
        state.layouts[12]={tab=12,root={pane=3},floats={},focus=3}
        state.panes[scratch.pane].tab=12
        state.panes[scratch.pane].floating=false
        state.focus=1
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(cx.session:pane(scratch.pane).tab,11)
        eq(cx.session:pane(scratch.pane).floating,true)
        eq(cx.session:focused(),scratch.pane)

    elseif selectedCase=="tool_kinds_coexist" then
        setup()
        local scratch=openScratch()[1]
        state.focus=1
        state.commands.open_lazygit.run(cx)
        local after=toolPanes()
        eq(#after,2)
        eq(after[1].pane,scratch.pane)
        eq(after[1].floating,true)
        eq(after[2].floating,true)
        eq(cx.session:layout(11).floats[1].over,1)
        eq(cx.session:layout(11).floats[2].over,1)
        state.tick()
        state.commands.hide_tool.run(cx)
        eq(cx.session:pane(after[2].pane).parked,true)
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(after[2].pane).parked,false)
        eq(cx.session:pane(after[2].pane).floating,true)
        eq(cx.session:focused(),after[2].pane)
        state.pickHandler=function(opts)
            for _,item in ipairs(opts.items) do if item.id=="end" then return item end end
            return nil
        end
        state.commands.end_tool.run(cx)
        eq(cx.session:pane(after[2].pane),nil)

    elseif selectedCase=="scratch_hide_restore_and_end" then
        setup()
        local scratch=openScratch()[1]
        state.commands.hide_tool.run(cx)
        eq(cx.session:pane(scratch.pane).parked,true)
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(cx.session:focused(),scratch.pane)
        eq(cx.session:pane(scratch.pane).floating,true)
        state.pickHandler=function(opts)
            for _,item in ipairs(opts.items) do if item.id=="end" then return item end end
            return nil
        end
        state.commands.end_tool.run(cx)
        eq(cx.session:pane(scratch.pane),nil)

    elseif selectedCase=="glance_pip_keeps_leader_actions" then
        setup()
        local scratch=openScratch()[1]
        eq(cx.session:focused(),scratch.pane)
        -- Tern drops the PiP from focus to glance and returns focus to the owner.
        state.focus=1
        eq(cx.session:pane(scratch.pane).floating,true)
        eq(cx.session:pane(scratch.pane).parked==true,false)
        state.commands.hide_tool.run(cx)
        eq(#state.toasts,0)
        eq(cx.session:pane(scratch.pane).parked,true)
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(cx.session:focused(),scratch.pane)
        state.focus=1
        state.pickHandler=function(opts)
            for _,item in ipairs(opts.items) do if item.id=="end" then return item end end
            return nil
        end
        state.commands.end_tool.run(cx)
        eq(cx.session:pane(scratch.pane),nil)

    elseif selectedCase=="glance_ambiguous_pip_refuses_to_guess" then
        setup()
        openScratch()
        state.panes[1].cwd="/work/other"
        state.focus=1
        local all=openScratch()
        eq(#all,2)
        state.focus=1
        state.commands.hide_tool.run(cx)
        eq(state.toasts[#state.toasts].title,"工具身份未确认")
        for _,pane in ipairs(all) do eq(cx.session:pane(pane.pane).parked==true,false) end
        eq(cx.session:pane(all[1].pane).exited,nil)
        eq(cx.session:pane(all[2].pane).exited,nil)

    elseif selectedCase=="glance_other_tab_keeps_pip" then
        setup()
        local scratch=openScratch()[1]
        state.tabs={{id=11,session=9},{id=12,session=9}}
        state.addPane(3,{cwd="/work/project",tab=12})
        state.layouts[12]={tab=12,root={pane=3},floats={},focus=3}
        state.focus=3
        state.commands.hide_tool.run(cx)
        eq(cx.session:pane(scratch.pane).parked==true,false)
        eq(state.toasts[#state.toasts].title,"工具身份未确认")

    elseif selectedCase=="parked_restore_returns_origin_tab" then
        setup()
        local scratch=openScratch()[1]
        state.commands.hide_tool.run(cx)
        state.tabs={{id=11,session=9},{id=12,session=9}}
        state.addPane(3,{cwd="/work/project",tab=12})
        state.layouts[12]={tab=12,root={pane=3},floats={},focus=3}
        state.focus=3
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(scratch.pane).tab,11)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(cx.session:focused(),scratch.pane)

    elseif selectedCase=="orphan_restore_reassigns_tab" then
        setup()
        local scratch=openScratch()[1]
        state.commands.hide_tool.run(cx)
        state.tabs={{id=12,session=9}}
        state.panes[1].tab=12
        state.panes[2].tab=12
        state.layouts[12]={tab=12,root={split="right",[1]={pane=1},[2]={pane=2}},floats={},focus=1}
        state.focus=1
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(cx.session:pane(scratch.pane).tab,12)
        eq(cx.session:focused(),scratch.pane)
        state.focus=2
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].pane,scratch.pane)

    elseif selectedCase=="orphan_conflict_preserves_both_instances" then
        setup()
        local original=openScratch()[1]
        state.commands.hide_tool.run(cx)
        state.tabs={{id=12,session=9}}
        state.panes[1].tab=12
        state.panes[2].tab=12
        state.layouts[12]={tab=12,root={split="right",[1]={pane=1},[2]={pane=2}},floats={},focus=1}
        state.focus=1
        local instances=openScratch()
        eq(#instances,2)
        local existing=instances[2]
        eq(existing.pane~=original.pane,true)
        state.pickHandler=function(opts)
            if opts.placeholder=="选择恢复的临时终端" then
                for _,item in ipairs(opts.items) do if item.tool.pane==original.pane then return item end end
            end
            if opts.placeholder=="该归属已有临时终端" then return opts.items[1] end
            return chooseFirst(opts)
        end
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(original.pane).parked,true)
        eq(cx.session:pane(existing.pane).parked==true,false)
        eq(cx.session:focused(),existing.pane)
        eq(#toolPanes(),2)

    elseif selectedCase=="source_close_keeps_tool" then
        setup()
        local scratch=openScratch()[1]
        state.panes[1]=nil
        state.events.pane_closed({pane=1},cx)
        eq(cx.session:pane(scratch.pane).parked==true,false)
        eq(cx.session:pane(scratch.pane).exited,nil)
        eq(#toolPanes(),1)

    elseif selectedCase=="reload_record_is_not_reclaimed" then
        setup()
        local original=openScratch()[1]
        local freshTools=fresh("tools")
        freshTools.register({terminalKeybinding="ctrl+b>q",lazygitKeybinding="",hideToolKeybinding="",endToolKeybinding=""},resolver(),nil)
        state.focus=1
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].pane,original.pane)

    elseif selectedCase=="unknown_process_is_not_managed" then
        setup()
        state.processInvalid=true
        state.commands.open_terminal.run(cx)
        local first=toolPanes()
        eq(#first,1)
        state.processInvalid=false
        state.focus=1
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)

    elseif selectedCase=="stale_process_sample_never_awaits_shell" then
        setup()
        local scratch=openScratch()[1]
        eq(cx.session:focused(),scratch.pane)
        eq(state.settleMaxMs <= 10,true)
        -- The process sampler stops producing newer samples, the state a busy
        -- full-screen tool can create. Identity must not be assumed from the
        -- old sample, and no single wait may approach the 50 ms window budget.
        state.frozenSample=state.samples
        state.settleMaxMs=0
        state.commands.hide_tool.run(cx)
        eq(state.settleCalls>0,true)
        eq(state.settleMaxMs<=10,true)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(#state.toasts,1)
        eq(state.toasts[1].title,"工具身份未确认")
        eq(state.toasts[1].detail,"保留当前窗格；未执行收起操作。")
        state.frozenSample=nil
        state.commands.hide_tool.run(cx)
        eq(state.settleMaxMs<=10,true)
        eq(cx.session:pane(scratch.pane).parked,true)

    elseif selectedCase=="ambiguous_split_blocks_retry" then
        setup()
        state.splitMode="throw_after_create"
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        state.splitMode=nil
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        local uncertain=toolPanes()[1].pane
        cx.layout:close(uncertain)
        state.tick()
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].pane~=uncertain,true)
        eq(cx.session:focused(),toolPanes()[1].pane)

    elseif selectedCase=="stale_cwd_aborts_reuse" then
        setup()
        local original=openScratch()[1]
        state.panes[original.pane].floating=false
        state.focus=1
        state.deferPromises=true
        state.commands.open_terminal.run(cx)
        state.panes[1].cwd="/work/changed-while-verifying"
        state.deferPromises=false
        state.flushPromises()
        eq(cx.session:focused(),1)
        eq(cx.session:pane(original.pane).floating,false)
        eq(#toolPanes(),1)

    elseif selectedCase=="restarted_tool_cannot_launch_from_new_cwd" then
        setup()
        local original=openScratch()[1]
        local pane=cx.session:pane(original.pane)
        state.processByPid[pane.shellPid].started+=1
        pane.cwd="/work/restarted-shell"
        state.focus=original.pane
        state.commands.open_terminal.run(cx)
        state.commands.hide_tool.run(cx)
        state.commands.end_tool.run(cx)
        eq(#toolPanes(),1)
        eq(cx.session:focused(),original.pane)
        eq(cx.session:pane(original.pane).parked==true,false)
        eq(cx.session:pane(original.pane).cwd,"/work/restarted-shell")

    elseif selectedCase=="restart_during_final_parent_check_preserves_pane" then
        setup()
        local original=openScratch()[1]
        local pane=cx.session:pane(original.pane)
        state.pickHandler=function(options)
            state.deferParentFind=true
            for _,item in ipairs(options.items) do if item.id=="end" then return item end end
            return nil
        end
        state.commands.end_tool.run(cx)
        state.processByPid[pane.shellPid].started+=1
        state.deferParentFind=false
        state.flushParentFind()
        eq(cx.session:pane(original.pane)~=nil,true)
        eq(cx.session:focused(),original.pane)

    elseif selectedCase=="restart_during_token_preparation_aborts_creation" then
        setup()
        local original=openScratch()[1]
        local pane=cx.session:pane(original.pane)
        pane.cwd="/work/new-context"
        state.deferProcess=true
        state.commands.open_terminal.run(cx)
        state.processByPid[pane.shellPid].started+=1
        state.deferProcess=false
        state.flushProcess()
        eq(#toolPanes(),1)
        eq(cx.session:focused(),original.pane)
        eq(cx.session:pane(original.pane).cwd,"/work/new-context")

    elseif selectedCase=="definite_split_failure_releases_reservation" then
        setup()
        state.splitMode="return_nil"
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),0)
        state.splitMode=nil
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(cx.session:focused(),toolPanes()[1].pane)

    elseif selectedCase=="default_layout_preserves_unrelated_split" then
        setup()
        state.focus=2
        state.commands.open_lazygit.run(cx)
        local lazygit=toolPanes()[1].pane
        local root=cx.session:layout(11).root
        eq(root[1].pane,1)
        eq(root[2].pane,2)
        state.tick()
        eq(cx.session:pane(lazygit).floating,true)
        local float=cx.session:layout(11).floats[1]
        eq(float.pane,lazygit)
        eq(float.over,2)
        eq(float.corner,"br")
        cx.layout:float(lazygit,2,"tl")
        state.focus=2
        state.commands.open_lazygit.run(cx)
        local corner
        for _,entry in ipairs(cx.session:layout(11).floats) do
            if entry.pane==lazygit then corner=entry.corner end
        end
        eq(corner,"br")
        eq(#toolPanes(),1)
        state.commands.open_terminal.run(cx)
        local scratch=toolPanes()[2].pane
        local scratchOver
        for _,entry in ipairs(cx.session:layout(11).floats) do
            if entry.pane==scratch then scratchOver=entry.over end
        end
        eq(scratchOver,2)
        cx.layout:dock(scratch,2,"down")
        state.focus=2
        state.commands.open_terminal.run(cx)
        float=cx.session:layout(11).floats[1]
        for _,entry in ipairs(cx.session:layout(11).floats) do
            if entry.pane==scratch then float=entry end
        end
        eq(float.pane,scratch)
        eq(float.over,2)
        eq(float.corner,"br")
        root=cx.session:layout(11).root
        eq(root[1].pane,1)
        eq(root[2].pane,2)
        eq(#toolPanes(),2)

    elseif selectedCase=="source_restart_during_target_reuse_keeps_layout" then
        setup()
        local scratch=openScratch()[1].pane
        state.focus=1
        state.commands.open_lazygit.run(cx)
        local lazygit=toolPanes()[2].pane
        state.tick()
        cx.layout:float(lazygit,2,"tl")
        state.focus=scratch
        state.deferParentFind=true
        state.commands.open_lazygit.run(cx)
        state.deferPromises=true
        state.deferParentFind=false
        state.flushParentFind()
        state.processByPid[cx.session:pane(scratch).shellPid].started+=1
        state.deferPromises=false
        state.flushPromises()
        eq(cx.session:focused(),scratch)
        eq(cx.session:pane(lazygit).floating,true)
        local floats=cx.session:layout(11).floats
        local corner
        for _,float in ipairs(floats) do if float.pane==lazygit then corner=float.corner end end
        eq(corner,"tl")
        eq(#toolPanes(),2)

    elseif selectedCase=="tool_current_cwd_drives_new_instance" then
        setup()
        local original=openScratch()[1].pane
        cx.session:pane(original).cwd="/work/from-inside-tool"
        state.commands.open_terminal.run(cx)
        local instances=toolPanes()
        eq(#instances,2)
        eq(instances[1].pane,original)
        eq(instances[2].cwd,"/work/from-inside-tool")
        eq(cx.session:focused(),instances[2].pane)
        state.focus=1
        state.commands.open_terminal.run(cx)
        eq(cx.session:focused(),original)
        eq(cx.session:pane(original).cwd,"/work/from-inside-tool")
        eq(#toolPanes(),2)

    elseif selectedCase=="incomplete_joint_snapshot_refuses_reuse" then
        setup()
        local scratch=openScratch()[1].pane
        state.focus=1
        state.commands.open_lazygit.run(cx)
        local lazygit=toolPanes()[2].pane
        state.tick()
        cx.layout:float(lazygit,2,"tl")
        state.focus=scratch
        state.inventoryIncomplete=true
        state.commands.open_lazygit.run(cx)
        eq(cx.session:focused(),scratch)
        eq(cx.session:pane(lazygit).floating,true)
        eq(#toolPanes(),2)

    elseif selectedCase=="exception_without_observed_pane_blocks_retry" then
        setup()
        state.splitMode="throw_before_create"
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),0)
        state.splitMode=nil
        state.tick()
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),0)
        eq(cx.session:focused(),1)

    elseif selectedCase=="native_block_sources_open_and_reuse_tools" then
        setup()
        state.panes[1].kind="agent"
        state.panes[1].busy=true
        state.panes[1].running={line="omp",ms=500}
        state.panes[2].kind="git"
        state.panes[2].path="/another/repository"
        state.commands.open_terminal.run(cx)
        local scratch=toolPanes()[1]
        eq(#toolPanes(),1)
        eq(scratch.cwd,"/work/project")
        eq(scratch.floating,true)
        eq(cx.session:focused(),scratch.pane)
        eq(cx.session:layout(11).floats[1].over,1)
        state.focus=2
        state.commands.open_lazygit.run(cx)
        local lazygit=toolPanes()[2]
        eq(#toolPanes(),2)
        eq(lazygit.cwd,"/work/project")
        eq(lazygit.floating,true)
        state.tick()
        eq(cx.session:focused(),lazygit.pane)
        state.focus=1
        state.commands.open_lazygit.run(cx)
        eq(cx.session:focused(),lazygit.pane)
        state.focus=2
        state.commands.open_terminal.run(cx)
        eq(cx.session:focused(),scratch.pane)
        eq(#toolPanes(),2)
        eq(cx.session:pane(1).kind,"agent")
        eq(cx.session:pane(1).running.line,"omp")
        eq(cx.session:pane(2).kind,"git")
        state.commands.hide_tool.run(cx)
        eq(cx.session:pane(scratch.pane).parked,true)
        eq(cx.session:focused(),2)
        state.pickHandler=chooseFirst
        state.commands.restore_tools.run(cx)
        eq(cx.session:pane(scratch.pane).parked,false)
        eq(cx.session:focused(),scratch.pane)
        eq(#toolPanes(),2)

    elseif selectedCase=="native_block_unknown_cwd_does_not_guess_path" then
        setup()
        state.panes[1].kind="git"
        state.panes[1].cwd=""
        state.panes[1].path="/another/repository"
        state.commands.open_terminal.run(cx)
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),0)
        eq(cx.session:focused(),1)
        state.panes[1].kind="file"
        state.panes[1].cwd=nil
        state.panes[1].path="/work/project/notes.md"
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),0)
        state.panes[1].cwd="/work/project"
        state.commands.open_terminal.run(cx)
        local opened=toolPanes()[1]
        eq(#toolPanes(),1)
        eq(opened.cwd,"/work/project")
        eq(cx.session:focused(),opened.pane)

    elseif selectedCase=="remote_native_block_stays_rejected" then
        setup()
        state.panes[1].kind="agent"
        local localHost=cx.hosts.current
        cx.hosts.current=function() return {id=70,kind="remote"} end
        state.commands.open_terminal.run(cx)
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),0)
        eq(cx.session:focused(),1)
        cx.hosts.current=localHost
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].cwd,"/work/project")

    elseif selectedCase=="creation_floats_before_identity_handshake" then
        setup()
        state.deferPromises=true
        state.commands.open_terminal.run(cx)
        local during=toolPanes()[1]
        eq(#toolPanes(),1)
        eq(during.floating,true)
        eq(during.focused,false)
        eq(cx.session:focused(),1)
        eq(#state.toasts,0)
        local record
        for path,value in pairs(state.identityFiles) do
            if path:match("^/virtual/plugin%-data/tools/[0-9a-f]+%.json$") then record=value end
        end
        eq(record~=nil,true)
        eq(record.identityVerified,nil)
        state.deferPromises=false
        for _=1,10 do
            if #state.promiseCallbacks==0 then break end
            state.flushPromises()
        end
        local after=cx.session:pane(during.pane)
        eq(after.floating,true)
        eq(cx.session:focused(),during.pane)
        eq(#state.layouts[11].floats,1)
        eq(#state.toasts,0)

    elseif selectedCase=="silent_start_records_identity_without_typing" then
        setup()
        state.commands.open_terminal.run(cx)
        local opened=toolPanes()[1]
        eq(#toolPanes(),1)
        eq(opened.kind,"terminal")
        eq(opened.cwd,"/work/project")
        local typed=0
        for _,call in ipairs(state.runCallbacks) do
            if call.pane==opened.pane then typed+=1 end
        end
        eq(typed,0)
        local token
        for path in pairs(state.identityFiles) do
            local found=path:match("^/virtual/plugin%-data/tools/([0-9a-f]+)%.json$")
            if found and state.identityFiles[path].identityVerified==nil then token=found end
        end
        eq(token~=nil,true)
        eq(state.identityFiles["/virtual/plugin-data/tool-start/"..token.."/pid"],
            tostring(state.panes[opened.pane].shellPid))
        state.pickHandler=function(options)
            for _,item in ipairs(options.items) do if item.id=="end" then return item end end
            return nil
        end
        state.commands.end_tool.run(cx)
        eq(cx.session:pane(opened.pane),nil)
        eq(state.identityFiles["/virtual/plugin-data/tool-start/"..token.."/pid"],nil)
        eq(state.directories["/virtual/plugin-data/tool-start/"..token],nil)

    elseif selectedCase=="unsupported_shell_reports_without_adoption" then
        setup()
        state.shellProgram="/usr/bin/perl"
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        local last=state.toasts[#state.toasts]
        eq(last.level,"error")
        eq(last.detail:find("不支持")~=nil,true)
        state.commands.open_terminal.run(cx)
        eq(#toolPanes(),1)
        eq(state.toasts[#state.toasts].title,"工具身份未确认")

    elseif selectedCase=="lazygit_falls_back_to_login_path" then
        setup()
        state.env.PATH="/usr/bin:/bin"
        state.loginPath="/opt/homebrew/bin:/usr/bin:/bin"
        state.existingPaths={
            ["/bin/zsh"]=true,["/usr/bin/git"]=true,["/opt/homebrew/bin/lazygit"]=true,
        }
        tools.register({terminalKeybinding="",lazygitKeybinding="",hideToolKeybinding="",endToolKeybinding=""},
            fresh("executables").new({}),nil)
        state.commands.open_lazygit.run(cx)
        local opened=toolPanes()[1]
        eq(#toolPanes(),1)
        eq(opened.cwd,"/work/project")
        eq(state.loginProbes,1)
        local launched
        for _,call in ipairs(state.runCallbacks) do
            if call.pane==opened.pane then launched=call.text end
        end
        eq(launched~=nil,true)
        eq(launched:find("/opt/homebrew/bin/lazygit",1,true)~=nil,true)
        eq(launched:find("/opt/homebrew/bin:/usr/bin:/bin",1,true)~=nil,true)
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),1)
        eq(state.loginProbes,1)

    elseif selectedCase=="missing_program_still_reports_failure" then
        setup()
        state.existingPaths={["/bin/zsh"]=true,["/usr/bin/git"]=true}
        tools.register({terminalKeybinding="",lazygitKeybinding="",hideToolKeybinding="",endToolKeybinding=""},
            fresh("executables").new({}),nil)
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),0)
        local last=state.toasts[#state.toasts]
        eq(last.level,"error")
        eq(last.title,"无法打开 lazygit")
        eq(last.detail:find("executables.lazygit",1,true)~=nil,true)

    elseif selectedCase=="lazygit_non_git_source_refuses" then
        setup()
        state.isGitRepo=false
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),0)
        eq(state.repoChecks,1)
        local last=state.toasts[#state.toasts]
        eq(last.level,"error")
        eq(last.title,"无法打开 lazygit")
        eq(last.detail:find("不是 Git 仓库",1,true)~=nil,true)
        eq(cx.session:focused(),1)
        state.isGitRepo=true
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].floating,true)
        eq(state.repoChecks,2)

    elseif selectedCase=="lazygit_repo_check_aborts_on_source_change" then
        setup()
        state.deferProcess=true
        state.commands.open_lazygit.run(cx)
        state.panes[1].cwd="/work/changed-during-repo-check"
        state.deferProcess=false
        state.flushProcess()
        eq(#toolPanes(),0)
        eq(state.toasts[#state.toasts].title,"Kiku 助手来源已变化")
        eq(state.repoChecks,1)
        state.panes[1].cwd="/work/project"
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].floating,true)

    elseif selectedCase=="native_block_cwd_change_aborts_creation" then
        setup()
        state.panes[1].kind="git"
        state.deferProcess=true
        state.commands.open_lazygit.run(cx)
        state.panes[1].cwd="/work/changed-repository"
        state.deferProcess=false
        state.flushProcess()
        eq(#toolPanes(),0)
        eq(cx.session:focused(),1)
        state.commands.open_lazygit.run(cx)
        eq(#toolPanes(),1)
        eq(toolPanes()[1].cwd,"/work/changed-repository")
        eq(toolPanes()[1].floating,true)

    else
        error("unknown code validation case: "..tostring(selectedCase))
    end
    print(selectedCase..": "..tostring(checks).." checks")
end
