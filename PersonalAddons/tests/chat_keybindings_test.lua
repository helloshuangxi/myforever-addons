local checks = 0
local function check(value, label) checks=checks+1; assert(value,label) end
local base="_forever_/Interface/AddOns/MyForeverChat/"
local frames, overrides, timers={}, {}, {}
local combat, control, shift, alt, meta=false,false,false,false,false
local activated=0
local NS={QuickReply=function() activated=activated+1 end}
CreateFrame=function()
    local frame={events={},scripts={}}
    function frame:RegisterEvent(name) self.events[name]=true end
    function frame:UnregisterEvent(name) self.events[name]=nil end
    function frame:SetScript(name,fn) self.scripts[name]=fn end
    frames[#frames+1]=frame
    return frame
end
InCombatLockdown=function() return combat end
SetOverrideBinding=function(owner,priority,key,action)
    assert(not combat,"cannot modify bindings in combat")
    overrides[#overrides+1]={owner=owner,priority=priority,key=key,action=action}
end
SetBinding=function() error("must not modify saved bindings") end
SaveBindings=function() error("must not modify saved bindings") end
IsControlKeyDown=function() return control end
IsShiftKeyDown=function() return shift end
IsAltKeyDown=function() return alt end
IsMetaKeyDown=function() return meta end
C_Timer={After=function(delay,fn) check(delay==0,"only same-frame deduplication timer"); timers[#timers+1]=fn end}
local function nextFrame() local current=timers; timers={}; for _,fn in ipairs(current) do fn() end end
assert(loadfile(base.."Keybindings.lua"))("MyForeverChat",NS)
combat=true; NS.InstallQuickReplyShortcut()
check(#overrides==0 and frames[1].events.PLAYER_REGEN_ENABLED,"combat login defers registration")
frames[1].scripts.OnEvent(frames[1],"PLAYER_REGEN_ENABLED")
check(#overrides==0,"premature combat event cannot modify binding")
combat=false; frames[1].scripts.OnEvent(frames[1],"PLAYER_REGEN_ENABLED")
check(#overrides==1 and overrides[1].key=="CTRL-X" and overrides[1].action=="MYFOREVERCHAT_QUICKREPLY",
    "registers only requested CTRL-X action")
check(not overrides[1].priority and not frames[1].events.PLAYER_REGEN_ENABLED,"low-priority session override leaves no pending combat listener")
NS.InstallQuickReplyShortcut()
check(#overrides==1 and #frames==1,"installation is idempotent")
local editor={focus=true,text="草稿保持不变",ClearFocus=function(self) self.focus=false end}
NS.HandleShortcutKey(editor,"X")
check(activated==0 and editor.focus,"ordinary X is untouched")
control=true; shift=true; NS.HandleShortcutKey(editor,"X"); shift=false
alt=true; NS.HandleShortcutKey(editor,"X"); alt=false
meta=true; NS.HandleShortcutKey(editor,"X"); meta=false
NS.HandleShortcutKey(editor,"C")
check(activated==0 and editor.focus,"other modifiers and copy shortcut are untouched")
NS.HandleShortcutKey(editor,"X")
check(activated==1 and not editor.focus and editor.text=="草稿保持不变","Ctrl-X clears own field focus without editing text")
NS.RunQuickReplyShortcut()
check(activated==1,"same physical key cannot minimize and immediately reopen")
nextFrame(); combat=true; NS.RunQuickReplyShortcut()
check(activated==2 and #overrides==1,"existing shortcut operates in combat without rebinding")
nextFrame(); NS.RunQuickReplyShortcut()
check(activated==3,"next keypress remains responsive")
print("chat_keybindings_test: "..checks.." checks passed")
