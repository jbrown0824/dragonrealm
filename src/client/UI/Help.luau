-- A simple "How to play" window.

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Help = {}

local TEXT = [[
<font color="#FFBE46"><b>CONTROLS</b></font>
• <b>Move</b>: WASD  •  <b>Jump</b>: Space  •  <b>Camera</b>: right-click drag / scroll
• <b>Fly</b>: F (or jump, then press Space again in the air). While flying: Space = up, Ctrl or C = down. Flying uses stamina (blue bar).
• <b>Dragon Breath</b>: hold Left Mouse. Aim with your mouse.
• <b>Fireball</b>: Q  •  <b>Skill abilities</b>: 1, 2, 3, 4
• <b>Interact</b> (shops, quests, plants): E  •  Water plants: R  •  Give sun: T
• <b>Skills</b>: K  •  <b>Bag</b>: B  •  <b>Quests</b>: J  •  <b>Fly home</b>: H

<font color="#FFBE46"><b>HOW TO PLAY</b></font>
• Talk to dragons with a <b>❗</b> in Dragon Town for quests. <b>❓</b> means a quest is ready to turn in.
• Cross the bridge south to the <b>Viking Lands</b>. Defeat vikings for XP, gold, gear and (rarely) seeds.
• Each level gives a <b>skill point</b>. You can't learn every skill — choose a path!
• Buy, sell and upgrade gear at the three shops around the town square.
• Your base has <b>planting spots</b>. Plants ask for 💧 or ☀️ — give them the right one in time!
• When the <b>war horn</b> sounds, join the boss queue. Bosses scale to your group and drop amazing loot. You get <b>3 lives</b> per boss fight, and you can leave any time from the boss banner.
• The <b>Battle Zone</b> (north end of town) is PvP: other dragons can fight you there for Glory.
]]

function Help.init(app)
	local window, content, close = Theme.window(app.Windows.guis.Windows, "❓ How to Play", Vector2.new(700, 520))
	close.Activated:Connect(function()
		app.Windows.close("Help")
	end)
	local scroll = Theme.scroll(content, { Size = UDim2.fromScale(1, 1) })
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
