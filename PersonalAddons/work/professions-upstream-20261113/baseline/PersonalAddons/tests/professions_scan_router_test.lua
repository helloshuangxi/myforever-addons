-- Source handoff and consume-once contracts; no native game is controlled.
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": " .. tostring(actual))
end
local base = "_forever_/Interface/AddOns/MyForeverProfessions/"
local ns = {db = {gatherMethod = "cursor"}}
local oldCalls, resets, calls, active, failRestore, supported, queued = 0, 0, 0, false, false, true
GetTime = function() return 10 end
GetCursorPosition = function() return 500, 300 end
InCombatLockdown = function() return true end
Minimap = {
    IsVisible = function() oldCalls = oldCalls + 1; return true end,
    SetUsingSoftCursor = function() oldCalls = oldCalls + 1 end,
    UpdateMouseoverAtPoint = function() oldCalls = oldCalls + 1 end,
}
C_TooltipInfo = {GetMinimapMouseover = function() error("legacy reader cannot run in experiment") end}
ns.GatherResource = function() end
assert(loadfile(base .. "GatherScan.lua"))("MyForeverProfessions", ns)
local scanner = ns.GatherScan
eq(scanner.GetMethod(), "cursor", "selected experiment remains selected when its module is absent")
eq(scanner.IsSupported(), false, "missing experiment module does not silently fall back")
eq(scanner.ScanNames(), nil, "missing module has no result")
eq(oldCalls, 0, "missing experiment never touches native legacy map")
local data = scanner.ScanDiagnostics()
eq(data.method, "cursor", "missing-source diagnostics identify experiment")
eq(data.reason, "cursor-module-unavailable", "missing-source diagnosis is explicit")

local cursor = {
    IsSupported = function() return supported end,
    IsActive = function() return active end,
    Reset = function()
        resets = resets + 1
        queued = nil
        if not failRestore then active = false end
    end,
    ScanNames = function()
        calls = calls + 1
        local result = queued
        queued = nil
        return result
    end,
    ScanDiagnostics = function() return {state = "idle", reason = "fresh-only"} end,
}
ns.GatherCursorScan = cursor
eq(ns.GatherScan, scanner, "loading a new source preserves the controller's captured object")
eq(scanner.IsSupported(), true, "selected experiment reports its capabilities")
scanner.ScanNames()
queued = {{name = "铜矿"}}
local result = scanner.ScanNames()
eq(result[1].name, "铜矿", "fresh experiment name passes through unchanged")
eq(result[1].dx, nil, "experiment supplies no resource direction")
eq(scanner.ScanNames(), nil, "the router does not replay a consumed name")
queued = {}
eq(#scanner.ScanNames(), 0, "completed empty scan remains distinct from no result")
supported = false
eq(scanner.IsSupported(), false, "unavailable experiment does not use old capabilities")
supported = true
local beforeCalls, beforeResets = calls, resets
data = scanner.ScanDiagnostics()
eq(data.method, "cursor", "diagnostics identify active source")
eq(calls, beforeCalls, "diagnostics cannot advance scanning")
eq(resets, beforeResets, "diagnostics cannot clear a scan")

queued, active = {{name = "铜矿"}}, true
scanner.Reset("world-leaving")
eq(active, false, "reset releases experiment state")
eq(scanner.ScanNames(), nil, "reset discards a not-yet-delivered name")
queued, active, failRestore = {{name = "铜矿"}}, true, true
ns.db.gatherMethod = "original"
beforeCalls = oldCalls
eq(scanner.ScanNames(), nil, "failed experiment restore blocks original reader")
eq(oldCalls, beforeCalls, "legacy map remains untouched while restoration is pending")
eq(scanner.Scan(), nil, "deprecated positional entry also waits for restoration")
failRestore = false
eq(scanner.ScanNames(), nil, "original reader resumes only after cleanup and respects combat")
eq(active, false, "source handoff retries and completes restoration")
eq(scanner.GetMethod(), "original", "fallback is explicit")
eq(scanner.ScanDiagnostics().method, "original", "fallback diagnostics use legacy state")
eq(scanner.IsSupported(), true, "explicit fallback retains original native API support")
ns.db.gatherMethod = "cursor"
queued = {{name = "铜矿"}}
eq(scanner.ScanNames(), nil, "switching back clears a queued result from the prior source epoch")
queued = {{name = "铜矿"}}
eq(scanner.Scan()[1].name, "铜矿", "old entry point routes experiment into names only")
eq(ns.GatherScan, scanner, "all mode switches preserve the captured facade")
print("Gather scan source router: " .. checks .. " checks passed")
