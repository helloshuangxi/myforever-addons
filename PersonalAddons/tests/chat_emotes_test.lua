local NS,checks={},0
local function check(condition,label)
    assert(condition,label)
    checks=checks+1
end

local packPath="Interface\\AddOns\\MyForeverChatEmotes_raid\\Media\\"
local token="[表情:raid:m1]"
local secret={}
issecretvalue=function(value) return value==secret end
MyForeverChatEmotePacks={
    raid={title="开荒组",items={
        {id="m1",label="开怪😀",texture="Interface\\Injected"},
        {id="m1",label="重复"},
        {id="../escaped",label="越界"},
        {id="pipe",label="|Tbad|t"},
        {id="bracket",label="[坏标签]"},
        {id="invalid",label="\237\160\128"},
        {id="overlong",label=("好"):rep(17)},
        {id="secret",label=secret},
        [48]={id="last",label="最后一个"},
        [49]={id="outside",label="超过上限"},
    }},
    builtin={title="自制内置",items={{id="ok",label="准备好"}}},
    ["bad/path"]={title="不合法",items={{id="ok",label="坏 ID"}}},
    empty={title="空素材包",items={{id="!",label="坏 ID"}}},
    broken={title="坏\n标题",items={{id="ok",label="坏标题"}}},
    hidden=secret,
}

assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Emotes.lua"))("MyForeverChat",NS)
local groups=NS.GetEmoteGroups()
check(#groups==3,"valid preloaded packs are discovered in addition to builtins")
check(groups[1].id=="builtin" and groups[1].items==NS.emotes and #NS.emotes==12,"preserves the built-in picker")
check(groups[2].id=="pack:builtin" and groups[3].id=="pack:raid","group IDs are distinct and deterministic")
check(#groups[3].items==2 and groups[3].items[2].key=="last","skips invalid entries and enforces the 48-slot manifest limit")
check(groups[3].items[1].label=="开怪😀" and groups[3].items[1].token==token,"retains the valid UTF-8 label independently of the wire token")
check(NS.FormatEmotes(token)=="|T"..packPath.."m1:20:20|t","renders only the approved local texture path")
check(NS.FormatEmotes("[微笑]")=="|TInterface\\AddOns\\MyForeverChat\\Media\\Emotes\\smile:20:20|t","built-in token renders as before")
check(NS.FormatEmotes("[表情:raid:outside] [表情:other:m1] [表情:raid:../escaped]")=="[表情:raid:outside] [表情:other:m1] [表情:raid:../escaped]","uninstalled, skipped, and invalid references remain readable")

MyForeverChatEmotePacks.raid.items[1].label="新名字"
MyForeverChatEmotePacks.later={title="后加载",items={{id="m2",label="看到了"}}}
NS.RefreshEmotePacks()
groups=NS.GetEmoteGroups()
check(#groups==4 and groups[3].id=="pack:later","pack loaded after the main addon appears on refresh")
check(groups[4].items[1].label=="新名字" and groups[4].items[1].token==token,"renaming a label leaves existing chat tokens stable")

MyForeverChatEmotePacks=nil
NS.RefreshEmotePacks()
check(#NS.GetEmoteGroups()==1 and NS.FormatEmotes(token)==token,"refresh removes stale pack entries and restores text fallback")
print("chat_emotes_test: "..checks.." checks passed")
