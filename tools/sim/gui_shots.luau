-- GUI screenshots: runs the real client for one player at a chosen screen size (desktop or a
-- phone), gives them some things to look at, opens the main screens one by one and dumps each
-- as JSON (GUI_DUMP) for tools/preview/gui_render.py. Settings come from a header:
--   GUI_W, GUI_H (viewport in points), GUI_TOUCH (true = phone: touch, no keyboard)
-- Run: tools/sim/gui_shots.sh <width> <height> <touch> <outdir>
local W, H, TOUCH = GUI_W or 1280, GUI_H or 720, GUI_TOUCH == true
local function mod(path)
	return require(__proxy("Client/" .. path))
end

task.spawn(function()
	task.wait(2)
	workspace.CurrentCamera.ViewportSize = Vector2.new(W, H)
	local UIS = game:GetService("UserInputService")
	UIS.TouchEnabled = TOUCH
	UIS.KeyboardEnabled = not TOUCH
	UIS.MouseEnabled = not TOUCH
	local me = Instance.new("Player")
	me.Name = "Shooter"
	me.DisplayName = "Shooter"
	me.UserId = 301
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = me
	SIM_LOCAL_PLAYER = me
	Players.LocalPlayer = me
	me.Parent = Players
	task.spawn(function()
		require(__proxy("Client"))
	end)
	Players.PlayerAdded:Fire(me)
	task.wait(2)
	local function shot(tag: string)
		task.wait(0.5)
		for _, line in ipairs(GUI_DUMP(gui, tag)) do
			print(line)
		end
	end
	-- click the first visible button under `root` whose text contains `text`
	local function click(root: Instance, text: string)
		for _, d in ipairs(root:GetDescendants()) do
			if d.ClassName == "TextButton" and d.Visible ~= false and tostring(d.Text):find(text, 1, true) then
				d.Activated:Fire()
				return d
			end
		end
		io.stderr:write("ERROR: no button '" .. text .. "'\n")
		return nil
	end
	shot("classselect")
	Remotes.func("ChooseClass"):InvokeServer("Stormwing")
	mod("UI/ClassSelect").hide()
	task.wait(1)
	Remotes.event("TutorialStep"):FireServer(-1) -- (finished: pays the tutorial egg)
	task.wait(1)
	click(gui, "Skip tour") -- and close the tour panel, so the HUD shots show what's under it
	task.wait(0.2)
	click(gui, "Really skip?")
	task.wait(0.5)
	-- a brand-new dragon: the Starter Pack button (with its Robux price) and a Gold Rush running
	S.PlayerService.getProfile(me).goldRushLeft = 1500
	S.PlayerService.markDirty(me)
	task.wait(1)
	shot("hud_new")
	-- give the dragon a little of everything so the screens have content
	local profile = S.PlayerService.getProfile(me)
	S.PlayerService.setLevel(me, 12)
	S.PlayerService.addGold(me, 25000)
	profile.treats = 12
	profile.eggs.MythicEgg = 1
	for _, species in ipairs({ "EmberKit", "EmberKit", "SparkSprite", "DuskwingImp", "SolarSeraph" }) do
		S.PetService.givePet(me, species)
	end
	profile.vikingKills = 80
	profile.fishCaught = 12
	S.PlayerService.markDirty(me)
	task.wait(4)
	shot("hud")
	local Windows = mod("UI/Windows")
	mod("UI/Pets").open("Pets")
	shot("pets")
	mod("UI/Pets").open("Eggs")
	shot("eggs")
	local petsFrame = Windows.registry.Pets.frame
	click(petsFrame, "See every pet")
	shot("eggs_open")
	click(petsFrame, "Hatch yours")
	task.wait(2.5)
	shot("hatch")
	click(gui, "Awesome!")
	-- can't afford an egg: the message under the window offers gold, and opens the Store at it
	local goldBefore = profile.gold
	profile.gold = 100
	S.PlayerService.markDirty(me)
	task.wait(0.5)
	mod("UI/Pets").open("Eggs")
	click(petsFrame, "Buy & Hatch")
	shot("need_gold")
	click(petsFrame, "Get gold")
	shot("store_gold")
	profile.gold = goldBefore
	S.PlayerService.markDirty(me)
	task.wait(0.5)
	mod("UI/Store").open()
	shot("store")
	for _, tab in ipairs({ "Pets", "Achievements", "Skins" }) do
		mod("UI/Collection").open(tab)
		shot("collection_" .. tab)
	end
	Windows.open("SkillTree")
	shot("skilltree")
	-- a skill picked: its Learn / Max bubble sits between the row's two skills
	for _, d in ipairs(Windows.registry.SkillTree.frame:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Size.X.Offset == 50 and d.Size.Y.Offset == 50 then
			d.Activated:Fire()
			break
		end
	end
	shot("skilltree_popup")
	Windows.open("Potions")
	shot("potions")
	mod("UI/Shop").open("Buy")
	shot("armory")
	Windows.open("Map")
	shot("map")
	-- the admin panel, scrolled through its Dragon page
	Remotes.func("RedeemCode"):InvokeServer("DRAGONLORD")
	task.wait(0.5)
	Windows.open("Admin")
	shot("admin1")
	local adminScroll = nil
	for _, d in ipairs(Windows.registry.Admin.frame:GetDescendants()) do
		if d.ClassName == "ScrollingFrame" and d.Visible ~= false and not adminScroll then
			adminScroll = d
		end
	end
	for i, y in ipairs({ 420, 840, 1260 }) do
		if adminScroll then
			adminScroll.CanvasPosition = Vector2.new(0, y)
		end
		shot("admin" .. (i + 1))
	end
	Windows.close()
	shot("hud2")
	-- a night raid on the way (the raid bar), then target practice (window and session panel)
	S.DayNightService.setHour(22)
	Remotes.func("AdminAction"):InvokeServer("raidNow")
	task.wait(1)
	shot("raid")
	Remotes.func("AdminAction"):InvokeServer("burnHouse")
	task.wait(0.5)
	shot("raid_fire")
	me:SetAttribute("Water", 3)
	task.wait(0.5)
	mod("UI/RaidUI").setMinimized(true)
	shot("raid_pill")
	mod("UI/RaidUI").setMinimized(false)
	me:SetAttribute("Water", nil)
	Remotes.func("AdminAction"):InvokeServer("raidEnd", { won = false })
	task.wait(0.5)
	shot("shops_closed")
	Remotes.func("AdminAction"):InvokeServer("shops", { open = true })
	S.DayNightService.setHour(10)
	tp(me, Vector3.new(Zones.Range.matX, 6, Zones.Range.lanes[1]))
	task.wait(0.5)
	Windows.open("Range")
	shot("range")
	Windows.close()
	Remotes.func("RangeAction"):InvokeServer("start", 1)
	task.wait(1)
	shot("range_session")
	Remotes.func("RangeAction"):InvokeServer("stop")
	-- dungeons: the window, the pill while queued, a ready check from a friend's group, the run
	S.PlayerService.setLevel(me, 16)
	task.wait(11) -- (the unlock news has gone)
	Windows.open("Dungeons")
	shot("dungeons")
	Windows.close()
	invoke("DungeonAction", me, "queue", { dungeonId = "Barrow" })
	task.wait(1.2)
	shot("dungeon_queue")
	invoke("DungeonAction", me, "unqueue")
	invoke("DungeonAction", me, "leaveGroup")
	local buddy = addPlayer(302, "Wingmate")
	task.wait(1)
	invoke("ChooseClass", buddy, "Behemoth")
	S.PlayerService.setLevel(buddy, 18)
	task.wait(0.5)
	invoke("DungeonAction", buddy, "invite", { userId = me.UserId })
	invoke("DungeonAction", me, "accept", { groupId = S.DungeonService.groupOf(buddy).id })
	invoke("DungeonAction", buddy, "enter", { dungeonId = "Barrow" })
	task.wait(1.2)
	shot("dungeon_ready")
	click(Windows.guis.HUD:FindFirstChild("DungeonPill"), "Enter")
	task.wait(2)
	shot("dungeon_run")
	SIM.done = true
end)

local limit = 160
while not SIM.done and SIM.now < limit do
	SIM.step(1 / 30)
end
for _, e in ipairs(SIM.errors) do
	io.stderr:write(string.format("\nERROR (x%d): %s\n%s\n", e.count, e.msg, e.trace))
end
