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
| Fireball | Q (and Left Mouse on the target practice range) |
| Your dragon's signature ability (from level 3) | 1 |
| Skill tree abilities | 2, 3, 4, 5 (choose which ones in the skill tree's "Keys 2-5" strip) |
| Interact (shops, quests, plants, fishing, carcasses) | E |
| Water a plant / pack meat from a carcass | R |
| Eat the best food in your bag | G |
| Reel in a fish | T (or click REEL) |
| Skills / Bag / Pets / Quests / Collection / Map / Fly home | K / B / P / J / L / M / H |
| Dungeons (from level 15) | I |
| Hide or show the minimap | N |

New dragons start with no menu buttons: each one appears when it's first useful (Quests with your first quest, Home when the tour sends you home or you first leave town, the Bag at your garden or with your first gear or food, Pets with your first egg, Skills at level 2, Collection with your first pet). A new button glows with a speech bubble saying what it's for until you click it (or open it with its key).

The 💎 Store, 🎁 Codes and ❓ Help are the round buttons at the top right. The big map has no menu button: press M or click the minimap. Hover the 💰 ⚔️ ⚡ numbers on your player card (tap them on a phone) for what they mean.

Messages about what you just did in a window ("Bought it!", "You need 300 more gold") show just below the window, or on its title bar when the screen is too short, so they never cover what you're reading.

**Phones and tablets:** the ability buttons sit in a thumb cluster around Roblox's jump button (with Fly, Up and Down above it), the health bars move to the top, the menu is a grid on the left, and abilities aim themselves at the enemy nearest to where the camera is looking. Windows shrink to fit small screens. Test it in Studio with the device emulator (Test → Device).

## What's in the game

- **5 dragon types**, each with its own body shape, fire color and fire style, stats and skill tree:
  - **Shadowstalker** (stealthy): a feline hunter with blade horns and a bladed tail fan. Purple shadowflame, crits, Vanish
  - **Stormwing** (agile): a two-legged wyvern with a fin crest and a kite tail. Lightning breath, fastest flyer, dodges
  - **Behemoth** (strong but slow): an armored hulk with a spiked rock shell, lava seams, tusks and a club tail. Magma breath, huge health and defense
  - **Frostwyrm** (control): a long serpentine wyrm with crystal spines and glass wings. Frost breath that slows, freezes and shields
  - **Venomspine** (poison): a frilled lizard whose neck frill flares when it breathes, with a curling scorpion stinger. Toxic fire whose damage keeps ticking

  Every dragon also shares the Dragon Realm signature look: a glowing ember core between the belly plates, rune markings, scalloped two-part wings and a hinged jaw. They're animated in code: wings fold at rest, beat hard on a jump, glide when falling and flap in flight. The jaw opens to breathe fire, the eyes blink, the core pulses and the knees bend when walking. Body plans live in `src/shared/DragonBuilder.luau` and poses in `src/shared/DragonRig.luau`.

  At level 3 each type unlocks its own **signature ability** on key 1: Rending Claws (Shadowstalker), Spark Bolt (Stormwing), Tail Sweep (Behemoth), Frost Shards (Frostwyrm) and Venom Spit (Venomspine).

  Elder Pyrrhus can transform you into a different type for the same price as a skill reset (free up to level 5). Your level and gear stay the same, and your skill points are refunded.
- **2 legendary dragons** (Robux game passes, yours forever), a little stronger than the free five and each with its own kind of primary attack instead of a breath cone, plus an extra skill at level 10 on top of the signature:
  - **Tidecaller** (399 R$): a sea dragon with manta fin-wings of see-through water on glowing ribs, a ribbed sail down its back, gill frills, whiskers, a pearl on its brow, webbed feet and a whale's fluke. Left click spits a rapid stream of **Tide Shots** (water orbs that reach 95 studs, splash and slow). Signature **Riptide** (a whirlpool that drags enemies in), level 10 **Tidal Surge** (a wave rolling along the ground through everything in its path). Its tree: Torrent (Geyser, Maelstrom), Tidewarden (Healing Tide, Abyssal Shell), Abyss (Undertow, Kraken's Grasp).
  - **Solaris** (999 R$): a crowned sun dragon, ivory under gilded armor, with feathered gold wings, a blazing sunburst halo, gold greaves and a phoenix-plume tail. Left click pours out a **Solar Beam** that pierces everything in a 55-stud line. Signature **Solar Flare**, level 10 **Sunfall** (a pillar of sunfire that burns for 4 seconds). Its tree: Radiance (Sunspear, Zenith), Phoenix (Phoenix Feathers, Phoenix Form), Corona (Dawnbreak, Supernova).

  They stand on their own showcase platforms at the south side of the town square (press E for their window: what they do, and a buy or "Become one" button), and in the 💎 Store's Legendary Dragons. The class picker shows them as gold cards with their price. Once you own one, becoming it (from its showcase, the Store or Elder Pyrrhus) is free.
- **Tutorial**: new dragons get a short guided tour (walk, fly, breathe fire on a dummy, take a quest, fly home, plant, eat). Each step pops up big in the middle of the screen, then glides to the left edge once you start moving (and if you're moving through the steps quickly, the next one stays at the side). A marker and a glowing line show where to go. It can be skipped, restarted from ❓ Help, and pays 150 gold and a dragon egg at the end.
- **Skill trees**: 3 branches × 5 tiers per dragon. Each tier needs 4 points spent in that branch. You get 29 points by level 30, but each tree holds 63 ranks. That's enough for one capstone ultimate plus part of a second branch. Click a skill to see it and again to learn it (a Learn button also pops up beside it). Bars under each skill show your ranks, **Max** learns all remaining ranks, and **⚡ Auto** spends your points down a branch.
- **Dragon Town**: the houses are dragon-sized, with wide gaps between them so you can see (and fly) through the town, and you can walk (or fly) inside: a fireplace, a straw nest, a bookshelf, a table and a little hoard. **Villagers** (small civilian dragons like Old Cinderbeard, Pip and Auntie Mossgleam) stroll the streets, pop into their houses, and say something helpful if you chat with them (E). They can't be attacked.
- **Map and waypoints**: a minimap in the top right (N hides it; the 🗺️ button brings it back), and a full map on M or by clicking the minimap. Pick a place, click anywhere on the map, or click a quest in the tracker to get a 📍 waypoint with a glowing guide line. By default the waypoint follows your current quest. It hides during a boss fight (the world boss arena or a dungeon boss's room) and comes back afterwards.
- **Training grounds** (behind the houses east of the main road): straw dummies show your live DPS, total damage and time. The golem in the fenced **Sparring Pen** throws practice axes at anyone inside; they hurt, but can never take you below 1 health.
- **🏹 Target practice** (behind the houses west of the main road): three lanes, each with a firing mat. Stand on a mat, press E and pick a level: your own targets pop up and slide, bob, zigzag, sprint (dash across the lane, catch their breath at the side, dash back), float or pop up and vanish, and you knock them down with Fireball. Starting a session swings the camera round behind you, looking down the lane. While you practice, left click fires Fireball too, its cooldown drops to 0.6 seconds and your other abilities rest. The targets get smaller and faster level by level, and practice fireballs have to really hit them. Hit enough targets before time runs out to clear the level; the first clear of each of the 10 levels pays a share of your next level's XP (replays pay less). Gold targets count double. **AFK practice** fires by itself at slow targets and pays a little XP (shown as a rising "+XP") for every one it knocks down: about a quarter of a level every 10 minutes. Roblox still logs out anyone idle for 20 minutes.
- **Day and night**: a 9-minute day and a 6-minute night. The sun and moon move, the light cools at night and the street lamps come on. The minimap shows the time.
- **🌙 Night raids**: each night there's a 1 in 3 chance vikings raid Dragon Town, and after 5 quiet nights in a row the next one always brings a raid. Longships row down the river with the vikings cheering on deck and run aground below town, where the vikings leap ashore one after another. You don't have to wait for them: fly out and fight them on the ships (their axe throwers throw back). Packed on deck they huddle behind their shields (🛡️ on their nametags) and take a bit under half damage, so one big blast doesn't clear a whole ship. A viking beaten on deck tumbles overboard with a splash, and one you hurt lands still hurt. Then the ships row back upriver and return with the next wave: three waves, with a Raid Captain in the last one (the raid bar counts down to the next landing). The raid's size follows the strongest dragon online, so a server of new dragons gets a smaller, gentler raid (and more time to save burning houses).
  - **Torchbearers** head for the houses and set them alight. Dragons breathe fire, so to put one out you need **water**: dive low over the river below town (or any lake), or dip into one of the two **town wells**, to scoop up 2 loads, then **hover over the burning house** to pour it. A load lasts about 4 seconds of pouring, and that's what a fire takes from one dragon; several dragons pouring on the same house put it out much faster. Leave a half-soaked fire alone and it creeps back. While you pour, water streams down from you, the flames shrink, the smoke turns to steam and a blue bar fills under the house's countdown; once it's out the flames die away and the steam billows for a while. Water drips off you while you carry it, the wells light up "💧 Water" while a house burns, and a chip under the raid bar shows your water gauge (or where to get some). A house that isn't saved flares up, blackens, caves in and smolders for a while, and nobody goes inside until it's rebuilt.
  - The other raiders pick their own victims: villagers, and dragons all over town, even ones at home in their lairs. At most 3 go after the same dragon, and they give up on dragons that fly high or far away.
  - The villagers come out and puff fire at the raiders, spread out over them, each at their own pace (the youngsters run, the grown-ups jog, the old-timers walk); between waves they wait by their own street. The four quest givers breathe fire at any raider that comes near their posts (they won't talk quests until the raid is over: their markers turn to ⚔️). Their fire can't finish a raider fresh off the boat, but the longer one has been ashore the lower they can take it, until they can finish it off; with only one or two dragons online they hit harder and finish raiders sooner. A few axe hits knock a villager out cold for a while.
  - The raid keeps its own clock: 3 minutes after the last wave lands (dawn doesn't cut it short). Beat every raider in time and everyone who hit a raider or saved a house gets XP, gold, Pet Treats and a good chance at Rare gear or an egg. Lose (time runs out with raiders in town, or 5 houses burn down) and the raiders run back to their ships with sacks of loot and row away, and every shop closes for 3 minutes. Burned houses are rebuilt a few minutes later. The raid bar can be minimized. World bosses never arrive during a raid (they wait), and a raid waits for a boss fight to finish.
- **Vikings**: Raiders, Axe Throwers, Shieldbearers, Berserkers, Hornblowers and elite Chieftains, spread across 4 camps from level 1 to 28. They chase, swing, and throw axes at dragons flying overhead. Beaten vikings topple over before they vanish, and a dragon that falls in battle lies sprawled where it fell until it respawns.
  - Every camp has a **treasure chest** in the middle. Hold E to open it; the moment you start, the whole camp comes for you. Each dragon has their own chest timer: opening it gets you a prize (gold, gear, sometimes seeds or an egg) and empties it for you for 5 minutes, but friends can still loot it themselves. The lid, the treasure inside and the countdown show your own timer.
  - Vikings respawn **slower while few dragons are in their camp** (2.6× as slow alone, back to normal with 4 or more), so a lone dragon can clear a camp.
  - Each camp has a **champion** (mini-boss) with a 💀 next to its health bar, a telegraphed ground slam, guaranteed Rare+ gear and a chance at eggs. Everyone who hit it and is still near the camp when it falls gets their own drops, so team up without worrying about who lands the last hit.
  - In **Jarl's Fortress**, **Hornblowers** raise the alarm when they spot you. If they finish blowing the horn, every viking in the fortress hunts you. Stun or kill them first! The lower camps only attack when you get close.
- **Hunting and hunger**: your hunger bar drains over time (faster while flying, half as fast in town). Hungry dragons fly slower and shorter and hit softer; starving is worse. Hunt deer, goats, boars, wolves and bears in **Elk Meadows** (west of town), **Whisperwood** (east), **Bearclaw Hollow** and **Frostfang Ridge** (north). Deer and goats run, boars fight back when hurt, wolves and bears attack. A kill leaves a carcass: hold E to eat it or R to pack the meat.
- **Fishing**: 🎣 spots on the river, the lakes and the frozen tarn. Fjord Lake (the Fishing Village's harbor) has a channel out to the river for its longships. Cast, wait for a bite, then stop the needle in the green zone. Fish fill your food bag; rare ones (Golden Carp, Ancient Eel) sell for a lot.
- **Gear**: new gear for an empty slot is put on right away (a red dot on the Bag button); other new gear waits in the Bag, counted on the Bag button and tagged NEW until you look. **⚡ Equip Best** wears your best item in every slot. Items better than what you're wearing are marked ⬆️ in your Bag and in the Armory, and worn items are marked EQUIPPED at the Anvil.
- **Loot**: gold on every kill; gear drops in Common, Uncommon, Rare, Epic and Legendary; seeds and eggs are rare drops. Loot only shows up for the player who earned it.
- **Shops** on the town square: the Emberforge Armory (buy), the Hoard Exchange (sell gear and food) and the Anvil of Ages (upgrade items up to +10).
- **Limited stock**: the Armory, the Hatchery and the Cauldron restock every 5 minutes with random items in random amounts (the Armory always has at least one Epic). Each player has their own stock, so friends never empty the shelves for each other, and it's saved, so rejoining doesn't reroll it. A countdown shows the next restock.
- **Potions** at the **Bubbling Cauldron**: permanent upgrades with 5 ranks each: Wing Tonic (flight time), Gale Draught (flight speed), Swiftclaw Brew (walk speed), Heartblood Elixir (health), Iron Belly Stew (slower hunger), Emberheart Tonic (attack) and Stoneskin Draught (defense).
- **Nano dragon pets**: buying an egg at **Nestmother's Hatchery** hatches it on the spot; eggs found on champions, bosses and chests wait in the Eggs tab until you hatch them (a red count on the Pets button and the Eggs tab says how many). Every egg shows its rarity odds on one color-coded line, and **See every pet** lists each pet it can hatch with its chance and boosts. Click outside the hatched pet's card (or Awesome!) to close the reveal. 15 species across 5 rarities, each a tiny version of one of the five body plans in its own colors, with its own boosts. One pet follows you at first, two at level 10, three at level 20. **⚡ Equip Best** picks your best ones. Pets show their name, rarity and level above them (other dragons' pets only when you're close). In a boss fight other dragons' pets step aside (hidden), and when a dragon is knocked out its pets settle on the ground beside it.
  - **Pet Treats** 🍬 drop when you harvest full-grown flowers (rarer and better-watered flowers drop more). Feed them to a pet to level it up (to level 5; each level adds +25% to its boosts, so level 5 doubles them).
  - **Golden pets**: merge three of the same species into one ✨ Golden pet with ×1.5 boosts, gold trim and a sparkle. It keeps the highest level of the three.
  - **Secret pets**: four extra species (Prismatic Wyrmlet, Celestial Drake, Phantom Nibbler, and the **Heartbloom Wyrm**, which gives a little lifesteal and health regen) that only hatch from the Secret Egg in the 💎 Store, and the **Aurora Serpent**, a 1% chance in every Mythic Egg and nowhere else. They always trail a sparkle.
  - **Dungeon pets**: the Barrow Egg and the Forge Egg only drop from their dungeon's boss (🏰 below), and each hatches three species found nowhere else. The Forge Egg rolls better (Rare 20%, Epic 55%, Legendary 24%) and has a 1% chance of the **Forgeheart Wyrmling**, a Secret whose +50% breath range doesn't change with its level.
  - **Mythic Eggs** always hatch Epic or Legendary (72% / 27%), with that 1% Aurora Serpent. They drop free from champions, bosses and camp chests, and are also sold in the 💎 Store for 49 R$ (the Eggs tab has a buy button, and says where to find them free).
- **Levels and the level gap**: every level makes your own dragon noticeably stronger (about 4% more attack), and gear of your level makes up the rest. Hitting something below your level hurts it more, and above your level less (and the same for monsters hitting you): barely noticeable for a couple of levels, x1.2 at 5, x1.6 at 10, capped at x2.5. It doesn't apply in PvP or at the world boss.
- **Paragon levels**: after level 30, XP keeps counting into Paragon levels (💫 on your nametag). Each one adds about 1% health and attack and 0.5% defense (the level-up toast shows the gains) up to Paragon 100, and a smaller bonus for every level past that, so XP always counts. Every 5 gives an extra skill point, so you can slowly fill more of your tree. With more abilities than keys, pick which four go on keys 2-5.
- **📖 Collection** (L): the pet book (every species you've hatched and made golden, with milestone rewards), achievements with bronze, silver and gold tiers (vikings, champions, bosses, flowers, fish, hunting, chests, Glory, levels, Paragon), and the **skins** and **titles** they unlock. Skins recolor your dragon (the shape and signature stay the same); titles show over your name. Rewards arrive automatically.
- **Lairs and farming**: every player gets a base with 6 planting spots, and up to 12 can be unlocked. The spot you're facing (or standing on) glows, and only its prompts show. You can also just click or tap a spot to plant, water, or harvest a grown flower, and empty spots glow green while you have seeds. Plants grow Seed → Seedling → Sprout → Flower. A few times per stage a plant gets thirsty (💧 and a countdown over it). If you miss the window it keeps growing, but its quality drops, and quality sets the harvest value. You can harvest at any stage; full Flowers give seeds back and often Pet Treats. The **Bot Dock** in your lair sells robots: the Drizzle-Bot waters for you, and the Reap-Bot harvests flowers (and replants them once upgraded).
- **Quests** from 4 village dragons: a main story, combat bounties (including a champion hunt), gardening and fishing, and adventure chains (hunting, treasure chests). Two more dragons keep watch at the dungeon entrances (below). ❗ means a new quest, ❓ means one is ready to turn in, and a grey ! is a quest you're not high enough level for yet. A red line guides you to your quest (never to somewhere outside the dungeon you're in, and trips into a dungeon only once you pick that quest): click the quest you're following in the tracker to turn the guide off, and the map (M) turns it back on.
- **World bosses** (Jarl Ragnar, Grimhilda, Hrothgar): the whole server gets a 90-second warning (the banner can be minimized), and anyone can join the queue from the banner or the War Horn. The boss's health scales with the group's damage and its hits scale with the group's health. Fights include telegraphed slams, rune strikes, axe volleys, summoned vikings and an enrage phase. Each dragon gets 3 lives per fight, and you can leave at any time. Rewards are Epic or Legendary gear, boss-only uniques, rare seeds, eggs, big XP and gold.
- **🏰 Dungeons** (from level 15; the 🏰 menu button or I, or fly to a cave mouth dug into a rocky knoll in the viking lands): small group adventures for 1 to 4 dragons. **The Draugr Barrow** (level 15+) is a flooded burial mound of undead vikings that winds down through tunnels, a pillared gallery, a flooded crypt and a hidden hoard to the Hollow King's burial chamber. **The Rune Forge** (level 30+) is big and vertical: great halls with throwing ledges, a lava river with two bridges, a ramp spiraling down around the forge shaft, and a round chamber where the vikings keep an elder dragon in chains.
  - **Groups**: invite dragons in your server (friends first; a friend in another server can join yours from the Roblox friends list), then either **Enter now** with whoever you have (even alone) or **Find group** to let the queue fill you up to 4. When the queue finds a group (4 dragons, or 2-3 after a minute and a half) everyone gets a ready check: Enter or Not now. A small pill under your player card (bottom left on phones) shows the queue, the ready check and then your run: packs cleared, in or out of combat, the boss's health.
  - The dungeon doesn't scale to your level, only a little to your group's size (fewer dragons, less monster health, slightly softer hits). A dragon at the dungeon's level beats a pack alone but comes out hurt, and needs better gear, lifesteal or friends for the final boss.
  - **The rules**: hit one monster and its whole pack comes, and monsters standing close by join the fight. Nothing fights through a shut boss door, either way. Some monsters guard their spot, some wander around it, and one pack in each dungeon patrols a route. They walk round lava (over the bridges, down the spiral) and lava burns them too. Knocked out mid-fight, you stay down until your group is out of combat, then get back up beside a friend. If everyone falls, the group wakes at the entrance and the monsters (and the boss) heal back to full. Outrunning monsters doesn't reset them: only ones that can't reach you (or haven't got any closer) for a while give up and walk home, healing slowly. Nobody gets the out-of-combat heal while their group is fighting.
  - **No flying over it**: in the caves your wings only lift you a few studs off the floor, until the dungeon's boss is down.
  - **Boss doors**: the mini-boss and boss rooms are shut behind great doors. Opening them (hold) breaks stealth and wakes the monsters nearby, and the mini-boss's door opens by itself once you've beaten the packs on the way to it. A few seconds after the boss wakes, a rune seal locks the room: nobody gets out until it dies, but anyone from the group left outside can still **Join the fight** through the seal. A boss only gives up when nobody's left in its room. During a boss fight 🧪 healing draughts appear on the floor now and then: walk over one to drink it (they fade after 12 seconds).
  - **Finding the way**: a glowing **Way out** sign on the wall beside the tunnel back toward the entrance points the way in every room with more than one way out.
  - **The keeper and provisions**: Ylva and Kael also wait just inside their dungeon, next to a provisions table (eat once a run). Your hunger doesn't drop in a dungeon.
  - **Maps**: the minimap and the map (M, or click the minimap) show the dungeon itself: its rooms and tunnels, lava and water, the way out, the keeper, the hoard, the bosses and your group.
  - **Bosses fight differently**: Grimvald the Bone-Warden charges and calls his hounds; Haldor the Hollow King waits on his throne, hurls axes and raises bone spikes under every dragon in his mound, drops to one knee at zero and rises again as Haldor Unbound (red-eyed, in a ghostly aura), who leaps onto whoever's farthest, even a lone dragon; Brakki Anvil-Jarl leaps and enrages; Runemaster Sigrun harpoons dragons hovering over the floor or keeping their distance and reels them in on her chain, the chained elder dragon breathes lanes of fire across her chamber, at 60% she holds the middle of the room behind a rune shield throwing rune bolts until her three guards fall (the shield gives out on its own if a fight drags on), and then she spins into a fiery whirlwind that throws off four smaller cyclones. Beat her and the dragon's enormous chains burst apart and it rears up and flies off, free.
  - **Loot**: everyone in the run gets their own. Monsters drop like tougher vikings. The mini-boss gives Rare+ gear. The boss gives Epic or Legendary gear at the dungeon's item level, a chance at a **relic** (named gear with a little lifesteal or health regen, found nowhere else) and a chance at the dungeon's **egg**. That chance grows with every clear until one drops. Your first clear of each dungeon gives a big XP bonus (1.5 levels' worth) and a title (Barrow Breaker, Chainbreaker); later clears give a smaller one. The hidden hoard opens once a run for each dragon.
  - **Lifesteal and regen are capped**: gear relics and pets together add at most 8% lifesteal and 0.8% regen, on top of talents, and totals stop at 30% and 3% a second. Lifesteal talents give 2% a rank (2.5% at tier 3), and only the Shadowstalker's Nightmare path stacks two of them.
  - **Ylva the Grave-Singer** and **Old Kael** wait at the cave mouths with quests for relics you can't get anywhere else, and repeatable monster bounties.
- **Battle Zone**: the walled arena at the north end of town is PvP. Wins earn Glory (⚔️ on your player card: +1 a win, +3 for ending someone's streak of 3 or more; only PvP wins count) and gold, and kill streaks get announced to the server.
- **Codes**: the 🎁 button redeems promo codes (set in `src/server/Config/AdminConfig.luau`).
- **💎 Store** (Robux): the two **legendary dragons** (above), a 9 R$ **Gold Rush** (+100% gold for 30 minutes of play; its clock only runs while you're in the game, and it stacks with 2x Gold), 2x XP and 2x Gold game passes, handy passes (**2x Flight Time**, **Never Hungry**, and **Wayfinder**: a 🌀 beside every place on the world map teleports you there, outside combat and boss fights, with a 20-second cooldown), gold packs sized to your level, the Mythic and Secret Eggs, a bag of Pet Treats and an instant shop restock. One small button under your player card shows its R$ price: the Starter Pack until level 10 (or until you buy it), then the Gold Rush. The game never pops the Store open: when you click to buy something you can't afford, the message under the window says how much gold you're missing and has a 💎 Get gold button that opens the Store at the gold packs. See "Robux store setup" below.

## Admin mode

Type the admin code into the 🎁 **Codes** window (the default is `DRAGONLORD`: **change it in `src/server/Config/AdminConfig.luau` before you publish**, or lock it to your user id with `ALLOWED_USER_IDS`). A 🛠️ button appears and opens the admin panel:

- **Dragon**: pick any player in the server (🎯, top right), then set their level (1-30) and Paragon, dragon type, gold, gear, eggs, seeds, food, potions, robots and hunger; give any pet (including Secret ones, golden and at any level) and Pet Treats; fill or clear the pet book; max or reset achievements; unlock, lock or put on skins and titles; switch the 2x XP / 2x Gold passes on or off and hand out any store product for testing (no Robux involved); reset the Starter Pack; restock their shops; heal, god mode, no cooldowns, teleports.
- **World**: bring the boss in 10-60 seconds, respawn camps, refill chests, respawn champions, restock, close or reopen everyone's shops, set the time of day (dawn, noon, just before dusk, midnight), start a night raid or end it (repelled or lost), set a house on fire and rebuild every house, send the picked dragon into a dungeon alone (any level) and reset its dungeon clears.
- **Balance**: live multipliers for every ability's damage and cooldown, every skill's values, global damage, health, XP and gold rates, the lifesteal and regen caps, the level gap (per level, growth past 10, cap), and for each dungeon its monsters' health and damage, its bosses' health and damage, and the relic and egg luck (plus how much easier small groups have it). Changes apply to everyone on the server right away (dungeons from the next run) and reset when it restarts. **Print changes** lists the new numbers so you can paste them into `src/shared/Config`.

## Robux store setup

The Store needs real ids from Roblox before it can sell anything:

1. Publish the game, then open it in the Creator Dashboard (create.roblox.com) → **Monetization**.
2. Create the **Game Passes** (2x XP, 2x Gold, 2x Flight Time, Never Hungry, Wayfinder, and the legendary dragons Tidecaller and Solaris) and a **Developer Product** for each item in `src/shared/Config/Store.luau` (Starter Pack, the one-pet Starter Pack below, Gold Rush, three gold packs, Mythic Egg, Secret Egg, Bag of Treats, Restock Shops).
3. Paste each id into `Store.luau` (`assetId` for passes, `productId` for products) and set the dashboard prices to the `robux` numbers there (that's what the Store shows).

Until an item has an id, clicking Buy in **Studio** grants it for free so you can test it; in a live game it says "coming soon". Purchases are saved with a receipt id first, so Roblox's retries never grant anything twice.

**Paid random items**: eggs hatch a random pet, and they can be bought with Robux or with gold that Robux can buy, so the game respects Roblox's `ArePaidRandomItemsRestricted` policy (answer **Yes** to that question in the Content Rating questionnaire). When a player joins, the server asks `PolicyService` about them. Where paid random items are restricted, the Store and every Robux button hide the eggs (Mythic, Secret, the Starter Pack) and every way to buy gold or egg stock with Robux (gold packs, Gold Rush, 2x Gold, Restock Shops), and the server refuses them too. Those players still hatch eggs with gold they earn by playing, and can buy 2x XP, the handy passes and Pet Treats. Instead of the usual Starter Pack they're offered their own (`StarterPet`): one particular pet (Thunderhatch, an Epic) and nothing random. A pet bought that way releases for no gold, so it can't be turned into gold for eggs. Until the answer comes back, or if Roblox can't be reached, those items stay hidden. Which items count is the `paidRandom` flag in `Store.luau`.

## Tuning

All balance numbers live in `src/shared/Config/`:

| File | What it controls |
|---|---|
| `Game.luau` | Level cap, XP curve, Paragon levels, day and night length, player dragon size and starting camera distance, boss timers, regen and the lifesteal / regen caps, flight, plot and robot prices, hunger, pet slots, camp respawn scaling, chest timer |
| `Dungeons.luau` | Dungeons: unlock levels, group-size scaling, the combat rules (giving up, reviving, wipes), the queue and ready check, loot chances and pity, every layout (rooms, tunnels, ramps, lava, bridges, decorations, monster packs), and the bosses' moves and traits |
| `Raids.luau` | Night raids: the chance, the pity rule, raid tiers by level (waves, Raid Captain, burn time), the raid's clock, how raiders chase and spread out, villager help and knockouts, the ships (speed, deck room, leaps, the retreat), water for fires (splashes per scoop, reach), how houses burn down, rewards, how long the shops close, bosses vs raids |
| `Range.luau` | Target practice: the 10 levels (targets, patterns, time, XP), hit radius, the practice Fireball cooldown, camera distance, AFK practice |
| `Classes.luau` | Dragon stats, colors, fire styles |
| `Talents.luau`, `Abilities.luau` | Skill trees and abilities |
| `Enemies.luau` | Viking, champion (mini-boss), boss and dungeon monster stats and attacks |
| `Animals.luau`, `Food.luau` | Wild animals, meat and fish, fishing difficulty |
| `Potions.luau`, `Pets.luau` | Potion ranks and prices; pet species (including Secret ones), boosts, eggs, levels, treat costs and golden merges |
| `Shops.luau` | Limited stock: restock timer, how many items, rarities and amounts |
| `Store.luau` | Robux passes and products: ids, prices, contents, how gold packs scale |
| `Collections.luau`, `Skins.luau` | Pet book milestones, achievements and their rewards; dragon skins |
| `Civilians.luau` | The village dragons: names, looks, homes, ages (how fast they hurry during a raid), what they say, walking pace |
| `Items.luau`, `Seeds.luau`, `Quests.luau` | Gear, plants, quests |
| `Zones.luau` | Map layout: camps, shops, bases, houses, town wells, the villagers' walking routes, Battle Zone, hunting grounds, lakes, river and the fjord channel, fishing spots, training grounds, target practice range |
| `Sounds.luau` | Sound effect IDs. Paste Creator Store audio IDs here; blank entries are silent |

**Testing quickly:** use admin mode (the World page sets the time of day, starts or ends a raid, sets a house on fire, closes or reopens the shops and drops you into a dungeon), or in `Game.luau` set `BOSS_FIRST_SPAWN = 40` and `BOSS_WARNING = 20`. To try dungeon groups, invites and ready checks in Studio: **Test → Clients and Servers** with 2-4 players, set them to level 15 in the admin panel, and invite each other from the 🏰 window.

## Project layout

```
src/
  shared/    Config data + shared logic (stats, items, talents, quests, dragon model builder)
  server/    init.server.luau boots World/ (map generation) and Services/ (gameplay)
  client/    init.client.luau boots UI/ (screens) and Controllers/ (input, flight, VFX, animation)
```

## Ideas for next steps

- **Cross-server dungeon queue** (next up): match dragons from every server, not just yours. A shared queue (MemoryStore) forms the groups and teleports them into a private copy of the game for their run (reserved servers of this same place), then sends them back to the server they came from. Friends in other servers could be invited directly. Teleports only work in the published game, not in Studio, and saves need a hand-off first (see session locking below). In-server groups keep working as they do now.
- **More endgame**: more dungeons (and harder versions of these two), more bosses and more camps.
- **PvP tournament as a world event**: when the world boss timer comes up, randomly pick between the boss and a PvP battle arena.
  - Players join from the same banner and War Horn queue. The event fails (nobody wins anything) if fewer than 2 dragons join.
  - Inside the arena, **health and damage are normalized to a level 30 dragon** so low levels have a chance. Everything else still counts: gear, pets and potions keep their bonuses.
  - The winner gets glorious prizes: plenty of Glory, and gear, gold and eggs **sized to the winner's own level** (a level 5 winner shouldn't get gear as good as a level 30's).
  - Everyone else gets much smaller prizes, scaled by where they placed.
- **Villagers rebuild burned houses**: after a raid the village dragons gather at a ruin with timber and hammers and patch it up bit by bit (scaffolding, fresh planks going up), instead of it simply popping back after a few minutes. Dragons could chip in (carry logs from the woods) to speed it up.
- Add sound effects and music IDs in `Config/Sounds.luau` (and music that gets more intense in fights, raids and boss battles).
- Add DataStore session locking (for example with ProfileStore) before a big public launch, and before the cross-server queue: a dragon teleporting to another server mustn't load its save before the old server has written it.
