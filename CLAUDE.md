# Dragon Realm

A Roblox game where every player is a dragon. It's a Rojo project and **everything is generated in code**: the map, the dragons, the vikings and the UI. There are no meshes, models or Studio-built assets. The README covers features and controls; this file covers how to work on the code.

## Workflow

- The user playtests in Roblox Studio. **You can't run Roblox here**, so do all your checking offline (see below), then ask the user to playtest and paste errors from the **Output** window.
- Build the place file: `rojo build default.project.json -o DragonRealm.rbxlx`. It's git-ignored, so rebuild after every change. The user opens it in Studio, or live-syncs with `rojo serve`.
- Git remote: `git@github.com:jbrown0824/dragonrealm.git`, branch `main`. Pushing works through the user's SSH key. The `gh` CLI isn't installed, so you can't create repos. **Commit and push only when the user asks.**
- Tools (Homebrew): `rojo`, `luau`, `luau-analyze`, `luau-compile`. Python 3 has numpy and Pillow.

## Checks (run before telling the user something works)

```
tools/checks/run_all.sh
```

This runs four things:
1. Compiles every file and runs `luau-analyze`, filtering out noise about Roblox globals and types it doesn't know.
2. `xref.py`: every `S.Service.fn` (server) and `App.Module.fn` (client) call, `Remotes.event/func("Name")` name and require path must actually exist. The analyzer can't see these because services are wired together at runtime.
3. `logic_test.luau`: data-consistency tests for the shared modules (talent trees, abilities, items, quest chains, zone layout, balance table).
4. Builds the place file.

**Offline visuals:** `tools/preview/` runs the real `WorldBuilder` and `DragonBuilder` against a mock Roblox API, renders the parts to PNGs and finds parts clipping into each other. See `tools/preview/README.md`. Use it for any change to map layout, props, signs or dragon models or poses, and look at the images before handing off.

## Layout

```
src/shared/   -> ReplicatedStorage.Shared
  Config/       all tuning data: Game (pacing, boss timers), Classes, Talents, Abilities, Items,
                Seeds, Enemies (vikings + bosses), Quests, Zones (map layout), Sounds
  DragonBuilder builds a dragon from parts (body plan per class in PLANS)
  DragonRig     pure pose math for dragon Motor6Ds (used by the client Animator and the previews)
  StatCalc, ItemUtil, TalentUtil, QuestUtil, Remotes, Signal, Util
src/server/   -> ServerScriptService.Server (init.server.luau boots World, then Services in ORDER)
  World/        WorldBuilder (whole map + terrain), Props, VikingBuilder
  Services/     Data, Player, Combat, Enemy, Loot, Shop, Farm, Quest, PvP, Boss, Zone
src/client/   -> StarterPlayerScripts.Client (init.client.luau builds App)
  Controllers/  State, Combat (input/aim), Movement (flight/dash), VFX, Animator, WorldView, Sfx
  UI/           Theme helpers, Windows manager, HUD and each screen
tools/checks/   lint / xref / logic tests      tools/preview/   offline render + clipping checks
```

## Conventions

- **Server services** are modules that return a table with `init(services)` (store `S`, set up state) and `start()` (connect remotes, run loops; always called with `task.spawn`). They call each other as `S.PlayerService.x(...)`. A new service must be added to `ORDER` in `src/server/init.server.luau`.
- **Client modules** get the shared `App` table in `init(App)`. A new module must be added to `src/client/init.client.luau`.
- **Remotes**: every name is listed in `src/shared/Remotes.luau`. The server is authoritative: clients send intents (cast, buy, plant...) and the server validates cooldowns, range, gold and ownership.
- **UI** is built in code with `Theme.make/label/button/window`, designed for a 1100×700 screen and scaled with UIScale.
- **Balance numbers** belong in `src/shared/Config/`, not in service code.
- Match the existing style: tabs, typed function parameters, and short header comments explaining *why*.

## Gotchas (learned the hard way)

- **`CanQuery = false` only works when `CanCollide = false`.** Solid invisible walls still block raycasts. That's why barriers (world bounds, arena walls and ceiling) live in `workspace.Barriers`, outside `workspace.Map`: services raycast against Map + Terrain only. The boss once spawned on top of the arena ceiling because of this.
- Spawn points use `terrainGround` plus a clear-spot check (`EnemyService`), so vikings don't land on roofs or tents. `groundAt(pos, fromAbove)` casts from just above a point.
- **Services find world objects by tag, name and attribute**, so keep these if you rework the map: tags `PlayerBase`, `ShopPrompt`, `QuestPrompt`, `QuestGiver`, `Dragon`, `Viking`; names `Plots/Plot1..12`, `HomeSpawn`, `Sign` (with a SurfaceGui `Title`), `WarHornPrompt`; attributes `BaseIndex`, `OwnerUserId`, `ShopTab`, `GiverId`.
- **Dragon rig**: the Motor6D names (`BodyJoint`, `Neck1..n`, `Head`, `Jaw`, `LidL/R`, `WingL/R`, `WingL2/R2`, `LegXX`/`KneeXX`, `Tail1..n`, `Frill`) and the model attributes `RigNeck/RigTail/RigLegs/RigCurl/RigFrill/DragonScale` are the contract between DragonBuilder, DragonRig and the Animator. Models are built facing -Z, spread for gliding; all joint frames are world-aligned.
- Player dragons are custom Humanoid rigs (R15 rig type, manual `HipHeight`, `CharacterAutoLoads = false`, spawned by `PlayerService.spawn`). The client owns its dragon's physics, so flight and dash run client-side in `Movement`.
- `Workspace.StreamingEnabled` is off (the project file sets it), so clients can assume the whole map exists.
- DataStores are skipped in Studio unless API access is enabled; `DataService` falls back to a fresh profile each session. Saved plot arrays use `false` for empty slots, never `nil` holes.
- The user wants **distinctive dragons**, not a generic "AI dragon" look. Keep each class's silhouette unique, and keep the shared signature: the ember core, rune marks, scalloped two-part wings and the hinged jaw.
