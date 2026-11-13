# Bundled range libraries

Retrieved 2026-11-09. Runtime source files are byte-identical to the pinned upstream commits; no local patches.

## LibRangeCheck-3.0

- Upstream: https://github.com/WeakAuras/LibRangeCheck-3.0
- Commit: `3f9e454971a011d08fc1b5c73c0a0ad4168c2f44` (2026-11-07); library minor version 39.
- License: MIT; full upstream license is retained in `LibRangeCheck-3.0/LICENSE`.
- Explicit Forever detection: Interface >= 16000 and < 20000; includes Forever spell/item lists.
- Dependency: LibStub. CallbackHandler-1.0 is initialized lazily only if `RegisterCallback` is called; this addon does not register library callbacks.

## LibStub

- Upstream maintained copy: https://github.com/WoWUIDev/Ace3
- Commit: `ac3d1225037e0dc74e025a72342c0f7824aae147` (2026-10-28); LibStub minor version 2.
- License: Public Domain, stated with author credits in the unmodified Lua header. It is not relicensed as MIT.

## TOC loading order

```text
Libs/LibStub/LibStub.lua
Libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua
```

Load these before the addon distance provider. Do not load the libraries as separate addons.

## Range semantics

`LibStub("LibRangeCheck-3.0"):GetRange(unit, true, false, 0.1)` returns an estimated `minRange, maxRange` pair in yards, not an exact distance. `minRange == nil` is unavailable; `maxRange == nil` means there is no finite upper bound. Use finite, public, nonnegative bounds only. Do not invent precision within a shared interval. Failed/secret checks must degrade to unknown. The upstream library can encounter invalid/secret unit information, so guard calls and returned values.

The library manages its own spell/item checker refresh. Friendly item/interact checks are omitted in combat. Secure clickable tile bindings and ordering must remain fixed during combat; update the visible distance text only and reorder after combat.

## Exact file sources and SHA-256

| File | Bytes | SHA-256 | Source |
| --- | ---: | --- | --- |
| `LibRangeCheck-3.0/LibRangeCheck-3.0.lua` | 178043 | `61d412559b082bdcd8fc5d29c67b27b7dfdb782e8c55fcb483fdce5c0edddf8b` | [Pinned upstream](https://raw.githubusercontent.com/WeakAuras/LibRangeCheck-3.0/3f9e454971a011d08fc1b5c73c0a0ad4168c2f44/LibRangeCheck-3.0/LibRangeCheck-3.0.lua) |
| `LibRangeCheck-3.0/LICENSE` | 1079 | `e3fdaf76f03ccf2bf5ec951f5e14eaf1178a6f6af8f7c9d321e3256fa31e25f9` | [Pinned upstream](https://raw.githubusercontent.com/WeakAuras/LibRangeCheck-3.0/3f9e454971a011d08fc1b5c73c0a0ad4168c2f44/LICENSE) |
| `LibStub/LibStub.lua` | 1366 | `26401bc42c26d1d1b6f7ad9410aa464edcbe4d32d74ebadeeecd8c0110236f7d` | [Pinned upstream](https://raw.githubusercontent.com/WoWUIDev/Ace3/ac3d1225037e0dc74e025a72342c0f7824aae147/LibStub/LibStub.lua) |

## Dependency smoke validation

A Lua 5.1 simulation loaded the two pinned libraries with mocked native APIs, ran deferred initialization, confirmed the Forever `CVAR_UPDATE` path, and obtained finite friendly/enemy interaction intervals without CallbackHandler installed. This verifies dependency wiring; it is not a game-client distance measurement.
