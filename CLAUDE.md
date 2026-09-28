# Dragon Realm

A Roblox game where every player is a dragon. It's a Rojo project and **everything is generated in code**: the map, the dragons, the vikings, the animals and the UI. There are no meshes, models or Studio-built assets. The README covers features and controls; this file covers how to work on the code.

## Workflow

- The user playtests in Roblox Studio. **You can't run Roblox here**, so do all your checking offline (see below), then ask the user to playtest and paste errors from the **Output** window.
- Build the place file: `rojo build default.project.json -o DragonRealm.rbxlx`. It's git-ignored, so rebuild after every change. The user opens it in Studio, or live-syncs with `rojo serve`.
- Git remote: `git@github.com:jbrown0824/dragonrealm.git`, branch `main`. Pushing works through the user's SSH key. The `gh` CLI isn't installed, so you can't create repos. **Commit and push only when the user asks.**
- Tools (Homebrew): `rojo`, `luau`, `luau-analyze`, `luau-compile`. Python 3 has numpy and Pillow.

## Checks (run before telling the user something works)

```
tools/checks/run_all.sh     # lint, xref, logic tests, place build
tools/sim/run.sh            # boots the real server + client in a simulator and plays the game
```

`run_all.sh` runs six things:
1. Compiles every file and runs `luau-analyze`, filtering out noise about Roblox globals and types it doesn't know.
2. `xref.py`: every `S.Service.fn` (server) and `App.Module.fn` (client) call, `Remotes.event/func("Name")` name and require path must actually exist. The analyzer can't see these because services are wired together at runtime. Module tables must be named like their file (a UI module `Pets.luau` returns `Pets`; alias a same-named config, e.g. `PetInfo`).
3. `logic_test.luau`: data-consistency tests for the shared modules (talent trees, abilities, items, quests, zones, potions, pets and pet levels, treats, villagers and their walking graph, animals, food, hunger, live tuning, balance table).
4. `walk_check.py`: builds the world offline and checks every straight walk a villager can take (`Zones.TownWalk`, each house door, up the ramp and between the indoor spots) against the solid parts. Move a stall, lamp or piece of furniture and this tells you if you blocked a route.
5. `water_check.luau`: every lake and the river is deep enough, never hangs over the void, and the longships have water under their whole hull.
6. Builds the place file.

**Simulation** (`tools/sim/`): `boot.luau` runs every server service (in `init.server.luau` ORDER) on a virtual clock against the mock Roblox API in `tools/preview/mock.luau`. `smoke.luau` plays two fake players through classes, admin tools, farming and robots, potions, eggs and pets, hunger, fishing, dummies, hunting, per-player chests, champion helpers, villagers, the alarm, bosses, death and an old-format save. `client_smoke.luau` runs the real `init.client.luau` for a local player with remotes looping back to the server: tutorial, every window, pet nametags / feeding / golden merge, per-player chest view, every ability's effects (`VFX.errorCount` must stay 0), codes → admin panel, fishing UI, hotkeys. Both print every script error with a traceback and must end with `0 script errors, 0 failed checks`. When you add a feature, add it to a scenario. When the mock is missing an API, add it to `mock.luau` the way Roblox behaves (defaults matter: buttons are `Active`, GUI objects are `Visible`).

**Offline visuals** (`tools/preview/`, see its README): renders parts to PNGs, draws a top-down **terrain map** (lakes, river, hills), checks **sign clearance** above the terrain, and finds **clipping** (signs, or whole buildings against each other). Use them for any change to map layout, props, signs, terrain, or dragon models and poses, and look at the images before handing off.

## Layout

```
src/shared/   -> ReplicatedStorage.Shared
  Config/       all tuning data: Game (pacing, boss timers, hunger, robots, pet slots, camp respawns),
                Classes, Talents, Abilities, Items, Seeds, Enemies (vikings, champions, bosses), Animals,
                Food (meat, fish), Potions, Pets (species, eggs, levels, golden merges), Civilians
                (village dragons), Quests, Zones (map layout, houses, villager walking graph), Sounds
  DragonBuilder builds a dragon from parts (body plan per class in PLANS; `colors`/`fire`/`lite`
                options make the nano dragon pets)
  DragonRig     pure pose math for dragon Motor6Ds (used by the client Animator, pets and the previews)
  StatCalc      final stats; BonusUtil adds potions, pets and hunger as buff entries
  Tuning        live admin balance multipliers (server owns, replicated to clients)
  ItemUtil (incl. isUpgrade / bestPerSlot), TalentUtil (incl. autoFill), QuestUtil, Remotes, Signal,
  Util (incl. spline, shared by the river builder and the map)
src/server/   -> ServerScriptService.Server (init.server.luau boots World, then Services in ORDER)
  Config/       AdminConfig: admin code, allowed user ids, promo codes (server-only)
  World/        WorldBuilder (terrain, town, bases, Battle Zone, arena), Wilds (river, lakes, hunting
                grounds, fishing spots), Camps (viking camps + chests), Props, WorldUtil, VikingBuilder,
                AnimalBuilder
  Services/     Data, Player, Combat, Enemy, Loot, Shop, Farm, Quest, PvP, Boss, Zone, Survival (hunger,
                food), Wildlife (animals, carcasses), Fishing, Potion, Pet, Training (dummies, DPS,
                sparring golem), Camp (per-player chests, champions), Civilian (village dragons who
                walk Zones.TownWalk and visit houses), Admin (codes, admin actions, tuning), Tutorial
src/client/   -> StarterPlayerScripts.Client (init.client.luau builds App)
  Controllers/  State, Combat (input/aim, hotkeys), Movement (flight/dash), VFX (basic effects),
                SpellFX (ultimate flourishes, heal "+" signs, lasting spells that follow a dragon,
                Eclipse sky), Animator, WorldView (prompt filtering, plot focus, per-player chest
                view), PetFollow (draws everyone's pets + nametags), Waypoint (the one
                destination: quest or picked place, pin + guide line), Sfx
  UI/           Theme helpers, Windows manager, HUD and each screen (Shop, Inventory, SkillTree, QuestUI,
                Potions, Pets, Robots, Codes, Admin, Fishing, Training, Tutorial, Map (minimap + M map)...)
tools/checks/   lint / xref / logic tests   tools/sim/   server + client simulation   tools/preview/   renders + checks
```

## Conventions

- **Server services** are modules that return a table with `init(services)` (store `S`, set up state) and `start()` (connect remotes, run loops; always called with `task.spawn`). They call each other as `S.PlayerService.x(...)`. A new service must be added to `ORDER` in `src/server/init.server.luau`.
- **Client modules** get the shared `App` table in `init(App)`. A new module must be added to `src/client/init.client.luau`.
- **Remotes**: every name is listed in `src/shared/Remotes.luau`. The server is authoritative: clients send intents (cast, buy, plant...) and the server validates cooldowns, range, gold and ownership. Vendors check range with `S.ShopService.isNear(player, { shopId })`.
- **Stats**: anything that changes stats outside gear and talents (potions, pets, hunger) goes through `BonusUtil.entries(profile)` so `PlayerService.recompute` and the tests agree. Balance numbers that the admin panel tunes go through `Tuning` inside `StatCalc`.
- **Stalls** that open a window (not a gear shop) use a `PanelPrompt` tag with a `Panel` attribute; the server fires `OpenPanel` and `init.client.luau` opens the window.
- **Profile fields**: add new fields to `defaultProfile` in DataService; `reconcile` fills them into old saves. Migrate changed shapes on load (see `FarmService.migratePlant`) and add the old shape to the sim's save test.
- **UI** is built in code with `Theme.make/label/button/window`, designed for a 1100×700 screen and scaled with UIScale. The HUD's top-right column is: minimap (y 10-190), zone name, then the quest tracker (y 236+); the menu buttons sit to its right.
- **Text glyphs**: use emoji or plain ASCII in UI text. Symbol characters like ✕ ▲ ● − ↺ ✔ can render as empty boxes in Roblox fonts (the old close button did). Draw shapes (pips, arrows) with Frames instead.
- **Map data**: roads, trails, lakes, the river, camps and shops all come from `Config/Zones`, which both the world builder and the map UI read. Add new places there so they show up on the map.
- **Balance numbers** belong in `src/shared/Config/`, not in service code.
- Match the existing style: tabs, typed function parameters, and short header comments explaining *why*.

## Gotchas (learned the hard way)

- **`CanQuery = false` only works when `CanCollide = false`.** Solid invisible walls still block raycasts. That's why barriers (world bounds, arena walls and ceiling) live in `workspace.Barriers`, outside `workspace.Map`: services raycast against Map + Terrain only. The boss once spawned on top of the arena ceiling because of this.
- Spawn points use `terrainGround` plus `EnemyService.isGoodSpawn` (not water, not inside a prop), so vikings and animals don't land on roofs, tents or lakes. `groundAt(pos, fromAbove)` casts from just above a point.
- **Signs** use `Props.sign`, which raycasts the terrain and lifts the board so its bottom clears the ground by 3.5 studs. Low signs used to sink into hills and banks. Anything placed on uneven ground should use `Props.groundY`.
- **Water**: lakes and the river are carved as round air "basins" and then `ReplaceMaterial(Air → Water)` below `Zones.WATER_LEVEL` (-4). Keep water regions inside the ground block (x ±660) or the fill spills into the void. The ground block is only 16 studs thick, so `Wilds.lakeBed` fills mud down to -44 under every lake and the river first; without it, deep bowls punched through and left water hanging over the void. `water_check.luau` guards all of this.
- **Per-player state on shared objects** (camp chests): the server keeps a player attribute (`ChestReady_<campId>`, server time) and each client draws the lid, treasure and prompt from its own attribute in WorldView. Local changes to replicated instances only affect that client.
- **Villagers** live in `workspace.Civilians` (outside Map, so attacks and service raycasts ignore them), use the `Dragons` collision group (they never block players), and hop to the next node if a walk takes too long. Their routes are data in `Zones.TownWalk`; keep them clear (`walk_check.py`).
- **Services find world objects by tag, name and attribute**, so keep these if you rework the map: tags `PlayerBase`, `ShopPrompt`, `PanelPrompt`, `QuestPrompt`, `QuestGiver`, `Dragon`, `Civilian`, `Viking`, `Animal`, `CampChest`, `TrainingDummy`, `FishingSpot`; names `Plots/Plot1..12`, `HomeSpawn`, `BotDock`, `Sign` (with a SurfaceGui `Title`), `WarHornPrompt`, chest parts `Base`, `Lid` (a model), `Treasure` (a model), `Glow`; attributes `BaseIndex`, `OwnerUserId`, `ShopTab`, `Panel`, `GiverId`, `CampId`, `SpotId`, `Kind` (Dummy/Golem), `PlotIndex`.
- **Prompt filtering is client-side** (WorldView): a prompt with an `OwnerUserId` only shows for that player; farm prompts also carry an `On` attribute (the server's wish) and only show on the plot you're facing. Set both when you add owner-only prompts.
- **Dragon rig**: the Motor6D names (`BodyJoint`, `Neck1..n`, `Head`, `Jaw`, `LidL/R`, `WingL/R`, `WingL2/R2`, `LegXX`/`KneeXX`, `Tail1..n`, `Frill`) and the model attributes `RigNeck/RigTail/RigLegs/RigCurl/RigFrill/DragonScale` are the contract between DragonBuilder, DragonRig, the Animator and PetFollow. Models are built facing -Z, spread for gliding; all joint frames are world-aligned. Animal rigs use `LegFL/FR/BL/BR`, `Head`, `Tail`.
- Player dragons are custom Humanoid rigs (R15 rig type, manual `HipHeight`, `CharacterAutoLoads = false`, spawned by `PlayerService.spawn`). The client owns its dragon's physics, so flight and dash run client-side in `Movement` (flight speed × the `FlightSpeedMult` character attribute).
- Tween completion: connect `tween.Completed` **before** `tween:Play()`.
- **Pets** are drawn by each client from the character's `Pets` attribute: `species:level:golden` entries, comma-separated (PetService.applyToCharacter). Pet records are `{ uid, species, level?, golden? }`; a missing level means 1.
- **Part shapes**: `Shape = Ball` forces a part to a sphere. For an ellipsoid use a block with a `SpecialMesh` of type Sphere (`Props.ellipsoid`).
- `Workspace.StreamingEnabled` is off (the project file sets it), so clients can assume the whole map exists.
- DataStores are skipped in Studio unless API access is enabled; `DataService` falls back to a fresh profile each session. Saved plot arrays use `false` for empty slots, never `nil` holes. Players whose save predates the tutorial skip it.
- **Admin code** lives in `src/server/Config/AdminConfig.luau` (default `DRAGONLORD`). Remind the user to change it or set `ALLOWED_USER_IDS` before publishing.
- The user wants **distinctive dragons**, not a generic "AI dragon" look. Keep each class's silhouette unique, and keep the shared signature: the ember core, rune marks, scalloped two-part wings and the hinged jaw.
