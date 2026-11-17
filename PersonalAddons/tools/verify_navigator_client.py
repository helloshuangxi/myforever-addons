"""Replay two explicit player questions through the native manager in a disposable game tree."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from lupa.lua51 import LuaRuntime, lua_type


ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "_forever_/Interface/AddOns/MyForeverNavigator"
FILES = ("Core", "Data", "Classification", "Navigation", "RoutePhrases", "FuzzySearch",
         "RouteData", "Routes", "RoutePlanner", "QuestData", "QuestNavigation", "GameBridge")
QUEST = "林中的群狼这个任务怎么做"
PLACE = "我要去铁炉堡"


def literal(value):
    if lua_type(value) == "table":
        return "{" + "".join(f"[{literal(k)}]={literal(v)}," for k, v in value.items()) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (bool, int, float)):
        return json.dumps(value)
    raise TypeError(type(value))


def create_character(slot):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().testGUID = f"fixture-{slot}"
    lua.execute("""
        GetTime=function()return 10 end
        UnitFactionGroup=function()return 'Alliance' end
        UnitGUID=function()return testGUID end
        GetLocale=function()return 'zhCN' end
        C_Map={GetBestMapForUnit=function()return 1429 end,
            GetPlayerMapPosition=function()return {x=.43,y=.64}end,
            GetMapInfo=function(id)return {name=tostring(id),mapType=3,mapID=id}end,
            GetMapWorldSize=function()return 3000,2000 end}
        C_QuestLog={GetNumQuestLogEntries=function()return 1 end,
            GetInfo=function()return {title='林中的群狼',questID=33}end,
            GetSelectedQuest=function()return 33 end,
            GetTitleForQuestID=function()return '林中的群狼'end,
            IsOnQuest=function(q)return q==33 end,
            GetQuestObjectives=function()return {{text='硬狼肉：0/8',type='item',finished=false}}end,
            ReadyForTurnIn=function()return false end}
    """)
    ns = lua.table()
    lua.globals().NS = ns
    for name in FILES:
        lua.execute((ADDON / f"{name}.lua").read_text(), "MyForeverNavigator", ns)
    lua.execute("NS.Initialize(nil)")
    return lua


def run(args):
    with tempfile.TemporaryDirectory(prefix="myforever-route-check-") as directory:
        game = Path(directory) / "_forever_"
        dest = game / "Interface/AddOns/MyForeverNavigator"
        dest.mkdir(parents=True)
        (game / "Wow.exe").touch()
        (dest / "MyForeverNavigator.toc").write_bytes((ADDON / "MyForeverNavigator.toc").read_bytes())
        inbox = dest / "ClientInbox.lua"
        inbox.write_text("MyForeverNavigatorInbox = {version=1,replies={}}\n")
        cases = []
        for i, question in enumerate((QUEST, PLACE)):
            lua = create_character(i)
            lua.globals().question = question
            lua.execute("assert(NS.SubmitClientQuestion(question))")
            folder = game / f"WTF/Account/Sample/Realm/Fixture{i}/SavedVariables"
            folder.mkdir(parents=True)
            snap = "MyForeverNavigatorDB = " + literal(lua.globals().NS.DB)
            snap += "\nMyForeverNavigatorOutbox = " + literal(lua.globals().MyForeverNavigatorOutbox) + "\n"
            (folder / "MyForeverNavigator.lua").write_text(snap)
            cases.append((question, i, snap))
        subprocess.run([args.dotnet, "run", "--project", str(args.manager / "NavigatorBridgeTests"), "-c", "Release",
                        "--", "--live-local", args.endpoint, args.model, str(game)], cwd=args.manager, check=True)
        results = []
        for question, i, snap in cases:
            # New Lua VM simulates the second load of the same character's SavedVariables.
            lua = create_character(i)
            lua.execute(snap)
            lua.execute(inbox.read_text())
            lua.execute("""
                NS.Initialize(MyForeverNavigatorDB)
                assert(NS.ClientQuestionStatus()=='ready')
                route=assert(NS.BuildClientRouteState())
                while not route.plan do
                    local choices=NS.GetRouteCandidates(route)
                    assert(#choices>0,route.terms[route.index])
                    assert(NS.ChooseRouteCandidate(route,choices[1].id))
                end
                assert(NS.ConfirmRouteQuery(route))
                assert(NS.GetActiveRoute())
                assert(NS.LookupClientRouteState(route.question))
            """)
            state = lua.globals().route
            steps = [s["label"] for _, s in sorted(state.plan.steps.items())]
            refs = [s["ref"] or s["term"] for _, s in sorted(state.clientSteps.items())]
            if question == QUEST:
                assert "item:750" in refs and refs[-1] == "turnin", refs
                assert len(steps) == 2 and "硬狼肉" in steps[0] and "交付" in steps[-1], steps
                assert "杀死" not in steps[-1], steps
                assert all(s.mapID == 1429 for _, item in state.ids.items()
                           for s in [lua.globals().NS.GetPoint(item)]), steps
            results.append({"question": question, "model_steps": refs, "navigation": steps,
                            "active": True, "confirmed_query_reused": True})
        return {"model": args.model, "native_manager_bridge": True, "in_game": False, "cases": results}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--manager", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.dumps(run(args), ensure_ascii=False, indent=2)
    args.output.write_text(data + "\n")
    print(data)
