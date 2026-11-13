# MyForever development handoff

Snapshot date: **13 November 2026, Asia/Shanghai**. This private repository contains seven owned WoW Forever addons, the .NET/Avalonia desktop manager, website/community service, tools, tests, and our research/experiments. It is a development snapshot, not a release branch.

Read the root `AGENTS.md` before making changes. The detailed issue register is `CURRENT_ISSUES.md` (Chinese); current validation is in `docs/HANDOFF_VALIDATION.md`. Existing subdirectory READMEs include dated version numbers and original-machine paths.

## Version boundaries

| Component | Working source | Published version recorded in local metadata |
| --- | --- | --- |
| MyForeverChat | 0.9.3 | 0.9.3 |
| MyForeverProfessions | **0.4.7-dev.22**, local only | 0.4.6 |
| MyForeverNavigator | **0.4.1**, NPC/profession catalogues pending native acceptance | 0.4.1 |
| MyForeverTargets | **0.1.45**, optional diagnostic probe | 0.1.46, frozen from the 0.1.44 feature baseline |
| MyForeverCoach | 0.2.0, local behavior collector | Not in the public addon catalogue |
| MyForeverMacros / FieldKit | 0.2.2 / 0.1.0 | Local addons |
| Desktop manager | **0.3.1**, includes behavior statistics | 0.2.1, addon management only |

The five live latest-version endpoints matched the local metadata during the initial handoff. Navigator subsequently reached 0.4.1; its live metadata and actual package size/SHA-256 were rechecked for this follow-up. Other components retain the initial verification scope. This Git sync did not run a deployment or repeat the full public-archive audit. The higher public Targets number does not contain the local diagnostic probe. Its source/tests are preserved separately in `PersonalAddons/work/targets-0.1.46-release-root`.

## Open problems

**UX-001, high priority — overall UI/UX is unsatisfactory.** On 13 November the user explicitly said they are very unhappy with the overall UI/UX. This covers the addon suite, desktop manager and website; working features and earlier acceptance of individual controls do not mean the overall design is approved. Review current-version screenshots and real workflows, then propose a coherent visual/interaction system and representative prototypes. Priorities include keeping the game viewport clear, emphasizing content, reducing secondary chrome, consistent entry points, readability, layout/scaling and task flow. The existing `design/modern-flat-20261111` prototype is reference material, not an approved implementation. Final acceptance requires the user's explicit visual and interaction approval. Preserve already accepted capabilities, saved positions/settings and all runtime safety/release boundaries.

1. **MFP-001, high priority:** minimap resource-name scanning remains blocked/unproven in the current game build. Local dev.22 actually loaded on `1.60.1 / 70938 / Interface 16001`; the sampled tooltip text was restricted and no names were accepted. A fixed alpha-quantization guard allowed sampling, but did not fix protected text. Never recycle stale names or infer all APIs are inaccessible from this observation. New nearby-resource alerts, audible sound, right-click camera behavior, flicker and yellow-dot continuity still need dev.22 acceptance.
2. **MFT-001, high priority:** automatic exact-GUID focus selection for arbitrary same-name NPCs **during combat is unresolved**. Out-of-combat multi-click cycling has limited positive live results. Ordinary Lua GUID reads do not provide a proven secure combat identity/action path. The user requires automatic confirmation; asking players to confirm identity manually is not an accepted substitute. The optional `NativeScaleProbe` is default-off and has not passed native hit-test validation.
3. **MFT-002:** friendly out-of-combat ordinary-key casting uses temporary target selection/restoration; it is not a general native `@mouseover` fix. Enemy/enemy-target casting, combat casting, empty original target and longer restoration cases remain incompletely validated.
4. **MFN-001:** Navigator 0.4.1 adds a separate profession-trainer category with 12 profession filters/search aliases to the read-only, incremental Questie NPC catalogue. Current installed-database integration uses **modeled map APIs**: 9,902 reference records / 9,006 distinct NPCs / 50 model map IDs, including 305 profession-trainer points (299 primary-category entries and six curated secondary members preserving their old IDs/categories). These are not live tracking or guaranteed native coverage. Profession entry display, native maps, character phasing, physical clicks, saved favorites, real journeys, trainer locations and teachable skills/profession requirements need game acceptance. Sidebar spacing adjustments do not close UX-001. Questie absence must preserve the curated fallback; do not redistribute the entire Questie database. Updated research/evidence is under `PersonalAddons/work/navigator-0.4.1`.
5. **MFM-001:** Windows x64 and Intel Mac native execution, real directory permissions, full 30-minute update cycle, and post-exit retry timing are still pending. Windows Authenticode and Mac Developer ID/notarization are not done. Behavior data is local-only, usually available after game save/reload; daily boundaries are fixed **UTC+08:00**, including on an Australian machine. Incomplete historical samples are not player-performance evidence.
6. **MFC-001:** Chat 0.9.3's final compact toast layout and several physical paging/community interactions lack independent current-version live acceptance. Generic offline character whispers are not implemented.
7. **DEV-001:** the legacy `run_tests.py` includes a third-party Details patch test whose target addon is absent. Use the new owned-addon runner below; the original test and repair diff remain available. Downloaded third-party reference implementations, raw private evidence, runtime SDKs and release binaries are intentionally outside Git.

## Start on macOS / Windows

Clone into a separate development directory with your own GitHub identity. Use Python 3.10+ and the .NET SDK specified by `PersonalAddons/Manager/global.json` (currently 10.0.403).

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python tools/check_addons.py
python3 PersonalAddons/website/community/test_server.py
python3 PersonalAddons/website/ops/test_upload_archive.py
```

On Windows substitute `.venv\Scripts\python.exe` and `python` as appropriate. Lupa's **Lua 5.1** runtime is required; passing checks in a different Lua version is insufficient.

```bash
cd PersonalAddons/Manager
dotnet run --project BehaviorTests/MyForeverManager.BehaviorTests.csproj
dotnet build Desktop/MyForeverManager.Desktop.csproj -c Release
```

For update/install fixtures restore the latest four published addon ZIPs first, then run `dotnet run --project Tests/MyForeverManager.Tests.csproj -- --site-root ../website/public` from the Manager directory. The tests use isolated game directories. Never test updater installation against a running real game.

```bash
# From the repository root. Validates published size/SHA-256; no installation.
python3 tools/restore_release_assets.py
# Full website validation also needs historic addon and manager runtime ZIPs.
python3 tools/restore_release_assets.py --all --include-manager
python3 PersonalAddons/website/ops/verify_site.py
```

Run release regression scripts listed in `CONTRIBUTING.md` only after restoring their fixtures. The website can be previewed with Python's HTTP server; its suggestion service has its own local tests. Production database and SSH credentials are not included.

## Collaboration and acceptance

Use `feature/<topic>` / `fix/<topic>` branches and Pull Requests. Coordinate shared `Main.lua`, `UI.lua` and release metadata ownership. Record exact addon version/client build, reproduction, expected/observed behavior and recovery results. Keep simulated API calls, real hardware interaction, audibility, user approval and publication as separate statuses.

All addon TOCs target **16001**, the China WoW Forever client. An Australian developer needs the matching client for meaningful native acceptance; another WoW flavor does not prove compatibility. Copy only selected owned addons while the game is closed and retain existing WTF data.

**Professions dev.22 remains on an explicit publication hold.** Do not generate a public ZIP, change public release metadata or deploy it until the user's separate approval. The behavior manager is also a local candidate. Uploading source to this private repo does not change those states. Other established release procedures remain in `AGENTS.md`; immutable public ZIPs must never be overwritten.

Keep personal saved variables, chat, logs, raw screenshots, databases and keys outside Git. Module-specific MIT licenses and third-party notices remain applicable; this handoff does not introduce a repository-wide open-source license. The Xiaoai speaker command in `AGENTS.md` is an optional service on the original Mac, not a dependency to install on your computer.
