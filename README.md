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
| Your dragon's signature ability (from level 3) | 1 |
| Skill tree abilities | 2, 3, 4 |
| Interact (shops, quests, plants, fishing, carcasses) | E |
| Water a plant / pack meat from a carcass | R |
| Eat the best food in your bag | G |
| Reel in a fish | T (or click REEL) |
| Skills / Bag / Pets / Quests / Map / Fly home | K / B / P / J / M / H |

On mobile, on-screen buttons handle breath, abilities, flying, up and down.

## What's in the game

- **5 dragon types**, each with its own body shape, fire color and fire style, stats and skill tree:
  - **Shadowstalker** (stealthy): a feline hunter with blade horns and a bladed tail fan. Purple shadowflame, crits, Vanish
  - **Stormwing** (agile): a two-legged wyvern with a fin crest and a kite tail. Lightning breath, fastest flyer, dodges
  - **Behemoth** (strong but slow): an armored hulk with a spiked rock shell, lava seams, tusks and a club tail. Magma breath, huge health and defense
  - **Frostwyrm** (control): a long serpentine wyrm with crystal spines and glass wings. Frost breath that slows, freezes and shields
  - **Venomspine** (poison): a frilled lizard whose neck frill flares when it breathes, with a curling scorpion stinger. Toxic fire whose damage keeps ticking

  Every dragon also shares the Dragon Realm signature look: a glowing ember core between the belly plates, rune markings, scalloped two-part wings and a hinged jaw. They're animated in code: wings fold at rest, beat hard on a jump, glide when falling and flap in flight. The jaw opens to breathe fire, the eyes blink, the core pulses and the knees bend when walking. Body plans live in `src/shared/DragonBuilder.luau` and poses in `src/shared/DragonRig.luau`.

  At level 3 each type unlocks its own **signature ability** on key 1: Rending Claws (Shadowstalker), Spark Bolt (Stormwing), Tail Sweep (Behemoth), Frost Shards (Frostwyrm) and Venom Spit (Venomspine).

  Elder Pyrrhus can transform you into a different type for 50 gold (free before level 5). Your level and gear stay the same, and your skill points are refunded.
- **Tutorial**: new dragons get a short guided tour (walk, fly, breathe fire on a dummy, take a quest, fly home, plant, eat). A marker and a glowing line show where to go. It can be skipped, restarted from ❓ Help, and pays 150 gold and a dragon egg at the end.
- **Skill trees**: 3 branches × 5 tiers per dragon. Each tier needs 4 points spent in that branch. You get 29 points by level 30, but each tree holds 63 ranks. That's enough for one capstone ultimate plus part of a second branch. Click a skill to see it and again to learn it (a Learn button also pops up beside it). Bars under each skill show your ranks, **Max** learns all remaining ranks, and **⚡ Auto** spends your points down a branch.
- **Dragon Town**: the houses are dragon-sized and you can walk (or fly) inside: a fireplace, a straw nest, a bookshelf, a table and a little hoard. **Villagers** (small civilian dragons like Old Cinderbeard, Pip and Auntie Mossgleam) stroll the streets, pop into their houses, and say something helpful if you chat with them (E). They can't be attacked.
- **Map and waypoints**: a minimap in the top right (N hides it), and a full map on M. Pick a place, click anywhere on the map, or click a quest in the tracker to get a 📍 waypoint with a glowing guide line. By default the waypoint follows your current quest.
- **Training grounds** (south-east of the plaza): straw dummies show your live DPS, total damage and time. The golem in the fenced **Sparring Pen** throws practice axes at anyone inside; they hurt, but can never take you below 1 health.
- **Vikings**: Raiders, Axe Throwers, Shieldbearers, Berserkers, Hornblowers and elite Chieftains, spread across 4 camps from level 1 to 28. They chase, swing, and throw axes at dragons flying overhead.
  - Every camp has a **treasure chest** in the middle. Hold E to open it; the moment you start, the whole camp comes for you. Each dragon has their own chest timer: opening it gets you a prize (gold, gear, sometimes seeds or an egg) and empties it for you for 5 minutes, but friends can still loot it themselves. The lid, the treasure inside and the countdown show your own timer.
  - Vikings respawn **slower while few dragons are in their camp** (2.6× as slow alone, back to normal with 4 or more), so a lone dragon can clear a camp.
  - Each camp has a **champion** (mini-boss) with a 💀 next to its health bar, a telegraphed ground slam, guaranteed Rare+ gear and a chance at eggs. Everyone who hit it and is still near the camp when it falls gets their own drops, so team up without worrying about who lands the last hit.
  - In **Jarl's Fortress**, **Hornblowers** raise the alarm when they spot you. If they finish blowing the horn, every viking in the fortress hunts you. Stun or kill them first! The lower camps only attack when you get close.
- **Hunting and hunger**: your hunger bar drains over time (faster while flying, half as fast in town). Hungry dragons fly slower and shorter and hit softer; starving is worse. Hunt deer, goats, boars, wolves and bears in **Elk Meadows** (west of town), **Whisperwood** (east), **Bearclaw Hollow** and **Frostfang Ridge** (north). Deer and goats run, boars fight back when hurt, wolves and bears attack. A kill leaves a carcass: hold E to eat it or R to pack the meat.
- **Fishing**: 🎣 spots on the river, the lakes and the frozen tarn. Cast, wait for a bite, then stop the needle in the green zone. Fish fill your food bag; rare ones (Golden Carp, Ancient Eel) sell for a lot.
- **Gear**: **⚡ Equip Best** wears your best item in every slot. Items better than what you're wearing are marked ⬆️ in your Bag and in the Armory, and worn items are marked EQUIPPED at the Anvil.
- **Loot**: gold on every kill; gear drops in Common, Uncommon, Rare, Epic and Legendary; seeds and eggs are rare drops. Loot only shows up for the player who earned it.
- **Shops** on the town square: the Emberforge Armory (buy), the Hoard Exchange (sell gear and food) and the Anvil of Ages (upgrade items up to +10).
- **Potions** at the **Bubbling Cauldron**: permanent upgrades with 5 ranks each: Wing Tonic (flight time), Gale Draught (flight speed), Swiftclaw Brew (walk speed), Heartblood Elixir (health), Iron Belly Stew (slower hunger), Emberheart Tonic (attack) and Stoneskin Draught (defense).
- **Nano dragon pets**: buy eggs at **Nestmother's Hatchery** (or find them on champions, bosses and chests) and hatch them. 15 species across 5 rarities, each a tiny version of one of the five body plans in its own colors, with its own boosts. One pet follows you at first, two at level 10, three at level 20. **⚡ Equip Best** picks your best ones. Pets show their name, rarity and level above them for everyone to see.
  - **Pet Treats** 🍬 drop when you harvest full-grown flowers (rarer and better-watered flowers drop more). Feed them to a pet to level it up (to level 5; each level adds +25% to its boosts, so level 5 doubles them).
  - **Golden pets**: merge three of the same species into one ✨ Golden pet with ×1.5 boosts, gold trim and a sparkle. It keeps the highest level of the three.
- **Lairs and farming**: every player gets a base with 6 planting spots, and up to 12 can be unlocked. The spot you're facing glows, and only its prompts show. Plants grow Seed → Seedling → Sprout → Flower. A few times per stage a plant gets thirsty (💧 and a countdown over it). If you miss the window it keeps growing, but its quality drops, and quality sets the harvest value. You can harvest at any stage; full Flowers give seeds back and often Pet Treats. The **Bot Dock** in your lair sells robots: the Drizzle-Bot waters for you, and the Reap-Bot harvests flowers (and replants them once upgraded).
- **Quests** from 4 village dragons: a main story, combat bounties (including a champion hunt), gardening and fishing, and adventure chains (hunting, treasure chests). ❗ means a new quest, ❓ means one is ready to turn in.
- **World bosses** (Jarl Ragnar, Grimhilda, Hrothgar): the whole server gets a 90-second warning (the banner can be minimized), and anyone can join the queue from the banner or the War Horn. The boss's health scales with the group's damage and its hits scale with the group's health. Fights include telegraphed slams, rune strikes, axe volleys, summoned vikings and an enrage phase. Each dragon gets 3 lives per fight, and you can leave at any time. Rewards are Epic or Legendary gear, boss-only uniques, rare seeds, eggs, big XP and gold.
- **Battle Zone**: the walled arena at the north end of town is PvP. Wins earn Glory and gold, and kill streaks get announced to the server.
- **Codes**: the 🎁 button redeems promo codes (set in `src/server/Config/AdminConfig.luau`).

## Admin mode

Type the admin code into the 🎁 **Codes** window (the default is `DRAGONLORD`: **change it in `src/server/Config/AdminConfig.luau` before you publish**, or lock it to your user id with `ALLOWED_USER_IDS`). A 🛠️ button appears and opens the admin panel:

- **Dragon**: pick any player in the server (🎯, top right), then set their level (1-30), dragon type, gold, gear, eggs, seeds, food, potions, robots and hunger; heal, god mode, no cooldowns, teleports.
- **World**: bring the boss in 10-60 seconds, respawn camps, refill chests, respawn champions.
- **Balance**: live multipliers for every ability's damage and cooldown, every skill's values, and global damage, health, XP and gold rates. Changes apply to everyone on the server right away and reset when it restarts. **Print changes** lists the new numbers so you can paste them into `src/shared/Config`.

## Tuning

All balance numbers live in `src/shared/Config/`:

| File | What it controls |
|---|---|
| `Game.luau` | Level cap, XP curve, boss timers, regen, flight, plot and robot prices, hunger, pet slots, camp respawn scaling, chest timer |
| `Classes.luau` | Dragon stats, colors, fire styles |
| `Talents.luau`, `Abilities.luau` | Skill trees and abilities |
| `Enemies.luau` | Viking, champion (mini-boss) and boss stats and attacks |
| `Animals.luau`, `Food.luau` | Wild animals, meat and fish, fishing difficulty |
| `Potions.luau`, `Pets.luau` | Potion ranks and prices; pet species, boosts, eggs, levels, treat costs and golden merges |
| `Civilians.luau` | The village dragons: names, looks, homes, what they say, walking pace |
| `Items.luau`, `Seeds.luau`, `Quests.luau` | Gear, plants, quests |
| `Zones.luau` | Map layout: camps, shops, bases, houses, the villagers' walking routes, Battle Zone, hunting grounds, lakes, river, fishing spots, training grounds |
| `Sounds.luau` | Sound effect IDs. Paste Creator Store audio IDs here; blank entries are silent |

**Testing quickly:** use admin mode, or in `Game.luau` set `BOSS_FIRST_SPAWN = 40` and `BOSS_WARNING = 20`.

## Project layout

```
src/
  shared/    Config data + shared logic (stats, items, talents, quests, dragon model builder)
  server/    init.server.luau boots World/ (map generation) and Services/ (gameplay)
  client/    init.client.luau boots UI/ (screens) and Controllers/ (input, flight, VFX, animation)
```

## Ideas for next steps

- Add sound effects and music IDs in `Config/Sounds.luau`.
- Add DataStore session locking (for example with ProfileStore) before a big public launch.
- Add more bosses, more camps, and a day/night cycle.
