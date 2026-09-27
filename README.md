# Dragon Realm

A Roblox game where every player is a dragon. Choose your dragon type, fight viking raiders, level up through a WotLK-style skill tree, farm rare plants at your lair, team up against world bosses, and battle other dragons in the Battle Zone.

Everything is built in code: the map, the dragons, the vikings, and the UI. You don't need to download any models or meshes.

## Play it

1. Install **Roblox Studio** (free) from https://create.roblox.com and sign in.
2. Open `DragonRealm.rbxlx` from this folder in Studio.
3. Press **Play** (F5). The server builds the world, then you pick your dragon.

To test with friends, or PvP against yourself: **Test** tab → **Clients and Servers** → 2 players → **Start**.

### Editing with live sync (recommended)

The Lua source lives in `src/`. To have your edits show up in Studio instantly:

1. In Studio, install the **Rojo** plugin (Plugins → Manage Plugins, or https://rojo.space).
2. In this folder run:
   ```
   rojo serve
   ```
3. In Studio, click the Rojo plugin and **Connect**.

To rebuild the place file after editing: `rojo build -o DragonRealm.rbxlx`

### Saving progress

Progress saves with DataStores. To test saving in Studio, first publish the game (File → Publish to Roblox), then turn on **Game Settings → Security → Enable Studio Access to API Services**. Without that, the game still runs; progress just resets each session. The Output window prints a warning when saving is off.

## Controls

| Action | Keys |
|---|---|
| Move / jump | WASD / Space |
| Fly | F, or jump and press Space again. While flying: Space = up, Ctrl or C = down |
| Dragon Breath | Hold Left Mouse (aim with the mouse) |
| Fireball | Q |
| Skill abilities | 1, 2, 3, 4 |
| Interact / Water / Sun | E / R / T |
| Skills / Bag / Quests / Fly home | K / B / J / H |

On mobile, on-screen buttons handle breath, abilities, flying, up and down.

## What's in the game

- **5 dragon types**, each with its own body shape, fire color and fire style, stats and skill tree:
  - **Shadowstalker** (stealthy): a feline hunter with blade horns and a bladed tail fan. Purple shadowflame, crits, Vanish
  - **Stormwing** (agile): a two-legged wyvern with a fin crest and a kite tail. Lightning breath, fastest flyer, dodges
  - **Behemoth** (strong but slow): an armored hulk with a spiked rock shell, lava seams, tusks and a club tail. Magma breath, huge health and defense
  - **Frostwyrm** (control): a long serpentine wyrm with crystal spines and glass wings. Frost breath that slows, freezes and shields
  - **Venomspine** (poison): a frilled lizard whose neck frill flares when it breathes, with a curling scorpion stinger. Toxic fire whose damage keeps ticking

  Every dragon also shares the Dragon Realm signature look: a glowing ember core between the belly plates, rune markings, scalloped two-part wings and a hinged jaw. They're animated in code: wings fold at rest, beat hard on a jump, glide when falling and flap in flight. The jaw opens to breathe fire, the eyes blink, the core pulses and the knees bend when walking. Body plans live in `src/shared/DragonBuilder.luau` and poses in `src/shared/DragonRig.luau`.

  Elder Pyrrhus can transform you into a different type later. Your level and gear stay the same, and your skill points are refunded.
- **Skill trees**: 3 branches × 5 tiers per dragon. Each tier needs 4 points spent in that branch. You get 29 points by level 30, but each tree holds 63 ranks. That's enough for one capstone ultimate plus part of a second branch.
- **Vikings**: Raiders, Axe Throwers, Shieldbearers, Berserkers and elite Chieftains, spread across 4 camps from level 1 to 28. They chase, swing, and throw axes at dragons flying overhead.
- **Loot**: gold on every kill; gear drops in Common, Uncommon, Rare, Epic and Legendary; seeds are rare drops. Loot only shows up for the player who earned it.
- **Shops** on the town square: the Emberforge Armory (buy), the Hoard Exchange (sell) and the Anvil of Ages (upgrade items up to +10).
- **Lairs and farming**: every player gets a base with 6 planting spots, and up to 12 can be unlocked. Plants grow Seed → Seedling → Sprout → Flower. Above each plant is a sign showing when it needs 💧 or ☀️ and how long you have to give it. Ignore it or give the wrong thing and the plant loses health. You can harvest at any stage; bigger plants are worth more gold, and full Flowers give seeds back (with a small chance of a rarer seed).
- **Quests** from 4 village dragons: a main story, combat bounties, gardening and adventure chains. ❗ means a new quest, ❓ means one is ready to turn in.
- **World bosses** (Jarl Ragnar, Grimhilda, Hrothgar): the whole server gets a 3-minute warning, and anyone can join the queue from the banner or the War Horn. The boss's health scales with the group's damage and its hits scale with the group's health. Fights include telegraphed slams, rune strikes, axe volleys, summoned vikings and an enrage phase. Each dragon gets 3 lives per fight, and you can leave at any time. Rewards are Epic or Legendary gear, boss-only uniques, rare seeds, big XP and gold.
- **Battle Zone**: the walled arena at the north end of town is PvP. Wins earn Glory and gold, and kill streaks get announced to the server.

## Tuning

All balance numbers live in `src/shared/Config/`:

| File | What it controls |
|---|---|
| `Game.luau` | Level cap, XP curve, boss timers, regen, flight, plot prices |
| `Classes.luau` | Dragon stats, colors, fire styles |
| `Talents.luau`, `Abilities.luau` | Skill trees and abilities |
| `Enemies.luau` | Viking and boss stats and attacks |
| `Items.luau`, `Seeds.luau`, `Quests.luau` | Gear, plants, quests |
| `Zones.luau` | Map layout: camps, shops, bases, Battle Zone |
| `Sounds.luau` | Sound effect IDs. Paste Creator Store audio IDs here; blank entries are silent |

**Testing bosses quickly:** in `Game.luau`, set `BOSS_FIRST_SPAWN = 40` and `BOSS_WARNING = 20`.

## Project layout

```
src/
  shared/    Config data + shared logic (stats, items, talents, quests, dragon model builder)
  server/    init.server.luau boots World/ (map generation) and Services/ (gameplay)
  client/    init.client.luau boots UI/ (screens) and Controllers/ (input, flight, VFX, animation)
```

## Ideas for next steps

- Swap the part-built dragons and vikings for meshes made in Blender or the Toolbox. Keep the part names and Motor6D names so the animation still works.
- Add sound effects and music IDs in `Config/Sounds.luau`.
- Add DataStore session locking (for example with ProfileStore) before a big public launch.
- Add more bosses, more camps, and a day/night cycle that changes plant needs.
