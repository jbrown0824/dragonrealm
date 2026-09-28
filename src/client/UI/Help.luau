-- A simple "How to play" window.

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Help = {}

local TEXT = [[
<font color="#FFBE46"><b>CONTROLS</b></font>
• <b>Move</b>: WASD  •  <b>Jump</b>: Space  •  <b>Camera</b>: right-click drag / scroll
• <b>Fly</b>: F (or jump, then press Space again in the air). While flying: Space = up, Ctrl or C = down. Flying uses stamina (blue bar).
• <b>Dragon Breath</b>: hold Left Mouse. Aim with your mouse.
• <b>Fireball</b>: Q  •  <b>Your dragon's own ability</b> (from level 3): 1  •  <b>Skill tree abilities</b>: 2, 3, 4, 5 (pick which ones in the skill tree)
• <b>Interact</b> (shops, quests, plants, fishing, carcasses): E  •  <b>Water</b> plants / <b>pack meat</b>: R
• <b>Eat</b>: G  •  <b>Reel</b> a fish: T or click REEL
• <b>Skills</b>: K  •  <b>Bag</b>: B  •  <b>Pets</b>: P  •  <b>Quests</b>: J  •  <b>Map</b>: M  •  <b>Hide minimap</b>: N  •  <b>Collection</b>: L  •  <b>Fly home</b>: H

<font color="#FFBE46"><b>HOW TO PLAY</b></font>
• Talk to dragons with a <b>❗</b> in Dragon Town for quests. <b>❓</b> means a quest is ready to turn in.
• <b>Villagers</b> stroll around town. Chat with them (E), and pop into their houses: every house has a fireplace and a nest.
• Practice on the <b>Training Dummies</b> (they show your DPS). The golem in the <b>Sparring Pen</b> throws back but can't knock you out.
• Cross the bridge south to the <b>Viking Lands</b>. Defeat vikings for XP, gold, gear and (rarely) seeds and eggs.
• Every camp has a <b>treasure chest</b> in the middle. Opening it brings the whole camp after you! Everyone has their own chest timer, so your friends can loot it too. Vikings come back slower while you're alone in a camp.
• Each camp has a champion with a <b>💀</b> on its health bar: big loot, telegraphed ground slams. Everyone who helps beat it gets their own loot.
• In <b>Jarl's Fortress</b>, <b>Hornblowers</b> sound the alarm when they spot you. Stop them before they finish!
• <b>Hunger</b> (orange bar) drops over time. Hungry dragons fly slower and shorter and hit softer. Hunt animals in <b>Elk Meadows</b> (west) and <b>Whisperwood</b> (east), fish at the 🎣 spots, and eat with G.
• Each level gives a <b>skill point</b>. In the skill tree, click a skill to see it and click it again to learn it. The bars under each skill show how many ranks you have. <b>⚡ Auto</b> spends your points down a branch for you. You can't learn every skill: choose a path!
• The <b>map</b> (M, or click the minimap) shows everything. Click a quest in the tracker, a place on the map, or anywhere on the map to get a 📍 waypoint with a glowing guide line.
• <b>⚡ Equip Best</b> in your Bag and Pets windows puts on your best gear and pets. Gear marked ⬆️ is better than what you're wearing.
• Buy, sell and upgrade gear at the shops around the town square. The <b>Bubbling Cauldron</b> sells permanent potions; <b>Nestmother's Hatchery</b> sells eggs that hatch right away into <b>nano dragon pets</b> (P). The Armory, Cauldron and Hatchery have <b>limited stock</b> that refills every 5 minutes. Feed pets <b>🍬 Pet Treats</b> (from full-grown flowers) to level them up, and merge three of a kind into a <b>✨ Golden</b> pet.
• Your lair has <b>planting spots</b>. Water plants when they get thirsty 💧; a missed drink lowers their quality (and value), but they keep growing. The <b>Bot Dock</b> sells robots that water and harvest for you.
• When the <b>war horn</b> sounds, join the boss queue. Bosses scale to your group and drop amazing loot. You get <b>3 lives</b> per boss fight, and you can leave any time from the boss banner.
• The <b>Battle Zone</b> (north end of town) is PvP: other dragons can fight you there for Glory.
• After level 30, XP earns <b>💫 Paragon levels</b>: a little stronger each time, and an extra skill point every 5.
• The <b>📖 Collection</b> (L) tracks your pet book and achievements. Rewards (gold, treats, eggs, skins and titles) arrive by themselves; pick your skin and title there.
• Got a code? Use the <b>🎁</b> button at the top right. <b>💎</b> is the Robux store.
]]

function Help.init(app)
	local window, content, close = Theme.window(app.Windows.guis.Windows, "❓ How to Play", Vector2.new(700, 520))
	close.Activated:Connect(function()
		app.Windows.close("Help")
	end)
	local scroll = Theme.scroll(content, { Size = UDim2.new(1, 0, 1, -44) })
	Theme.button("🎓 Restart the tour", Color3.fromRGB(70, 120, 180), function()
		app.Windows.close("Help")
		app.Tutorial.restart()
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(200, 36), Parent = content })
	Theme.label({
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		Font = Theme.Fonts.body,
		TextColor3 = C.text,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = TEXT,
		Parent = scroll,
	})
	app.Windows.register("Help", window)
end

return Help
