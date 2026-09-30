-- Client smoke test: runs the real client (src/client/init.client.luau) for one local player
-- against the simulated server, then opens every window, clicks through tabs, plays the
-- tutorial and triggers the new UI events. Remotes loop back between the two sides.
local Windows = nil
local function mod(path)
	return require(__proxy("Client/" .. path))
end
local function findButton(root: Instance, text: string)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Text and tostring(d.Text):find(text, 1, true) then
			return d
		end
	end
	return nil
end
local function click(root: Instance, text: string)
	local b = findButton(root, text)
	check(b ~= nil, "button '" .. text .. "' exists")
	if b then
		b.Activated:Fire()
	end
	return b
end

-- Dungeons on the client: the 🏰 button at level 15 (and its badge), the unlock toast, the window,
-- the pill (queue, run, ready check), the cave's light, the dungeon minimap and map, Haldor on his
-- throne, the hoard opening, the low hover, the death screen's Leave, invites as a toast.
-- (Its own function: the main scenario is out of local variables.)
local function dungeonClientScenario(me)
	local Lighting = game:GetService("Lighting")
	local keys = game:GetService("UserInputService")
	local menu = Windows.guis.HUD:FindFirstChild("Menu", true)
	local function castleButton()
		for _, b in ipairs(menu:GetChildren()) do
			if b:IsA("TextButton") and b.Text == "🏰" then
				return b
			end
		end
		return nil
	end
	local function hasText(root: Instance, text: string): boolean
		for _, d in ipairs(root:GetDescendants()) do
			if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and tostring(d.Text):find(text, 1, true) then
				return true
			end
		end
		return false
	end
	-- the quest markers of a giver (every copy of it: a dungeon keeper stands outside and inside)
	local function markersOf(giverId: string, within: Instance?)
		local list = {}
		for _, child in ipairs(me.PlayerGui:GetChildren()) do
			local model = child.Name == "QuestMarker" and child.Adornee and child.Adornee.Parent
			if model and model:GetAttribute("GiverId") == giverId and (not within or model:IsDescendantOf(within)) then
				table.insert(list, child:FindFirstChildOfClass("TextLabel"))
			end
		end
		return list
	end
	Remotes.func("AdminAction"):InvokeServer("setLevel", { level = 14 })
	task.wait(1.5)
	check(castleButton() ~= nil and not castleButton().Visible, "no 🏰 button before level 15")
	-- Ylva's quest wants level 15: a grey ! over her until then
	local ylvaMark = markersOf("Ylva")[1]
	local grey = ylvaMark and ylvaMark.TextColor3
	check(ylvaMark and ylvaMark.Text == "!" and math.abs(grey.R - grey.B) < 0.1 and grey.R < 0.7, "a grey ! over a quest you're not high enough level for (" .. tostring(ylvaMark and ylvaMark.Text) .. ")")
	Remotes.func("AdminAction"):InvokeServer("setLevel", { level = 15 })
	task.wait(6) -- (the unlock news comes after the level-up banner)
	check(castleButton() and castleButton().Visible, "the 🏰 button appears at level 15")
	local badge = castleButton() and castleButton():FindFirstChild("Badge")
	check(badge and badge.Visible, "...with a badge")
	local toasts = Windows.guis.HUD:FindFirstChild("Toasts")
	check(findButton(toasts, "Open") ~= nil, "the unlock toast has an Open button")
	click(toasts, "Open")
	task.wait(1.5)
	check(Windows.isOpen("Dungeons"), "...which opens the Dungeons window")
	check(badge and not badge.Visible, "opening the window clears the badge")
	local win = Windows.registry.Dungeons.frame
	local barrow, forge = win:FindFirstChild("Barrow", true), win:FindFirstChild("Forge", true)
	check(barrow ~= nil and forge ~= nil, "both dungeons are listed")
	check(forge and hasText(forge, "Unlocks at level 30"), "the Forge shows it's locked until 30")
	check(barrow and hasText(barrow, "Barrow Egg"), "the Barrow card says what it drops")
	check(hasText(win, "Your group"), "the group panel")

	-- queue, then leave the queue from the pill
	click(barrow, "Find group")
	task.wait(1.5)
	local pill = Windows.guis.HUD:FindFirstChild("DungeonPill")
	check(pill and pill.Visible and tostring(pill.Title.Text):find("Draugr Barrow") ~= nil, "the pill shows the queue")
	Windows.close("Dungeons")
	click(pill, "X")
	task.wait(1.5)
	check(not pill.Visible, "leaving the queue hides the pill")

	-- alone into the Barrow: the pill tracks the run, the cave is dark, the minimap says where you are
	Windows.open("Dungeons")
	task.wait(0.5)
	click(win:FindFirstChild("Barrow", true), "Enter alone")
	task.wait(2)
	check(me:GetAttribute("InDungeon") == "Barrow", "into the Barrow from the window")
	check(pill.Visible and tostring(pill.Title.Text):find("Packs") ~= nil, "the pill tracks the run")
	local DungeonInfo = require(__proxy("Shared/Config/Dungeons"))
	local DungeonBuilder = require(__proxy("Server/World/DungeonBuilder"))
	check(Lighting.ClockTime == 0 and Lighting.Ambient == DungeonInfo.List.Barrow.theme.ambient, "the cave's own light inside (no sun)")
	check(hasText(Windows.guis.HUD, "The Draugr Barrow"), "the minimap shows the dungeon's name")
	-- Ylva stands inside too, with her own marker
	local runIn = S.DungeonService.runOf(me)
	task.wait(0.5)
	local inner = markersOf("Ylva", runIn.built.model)[1]
	check(inner and inner.Text ~= "", "the keeper inside the dungeon has her quest marker too (" .. tostring(inner and inner.Text) .. ")")
	-- no waypoint to anything outside the dungeon while you're in it
	local Waypoint = mod("Controllers/Waypoint")
	local clientProfile = mod("Controllers/State").profile
	clientProfile.quests.active.C1 = 0
	check(Waypoint.questTarget("C1") == nil, "in a dungeon the quest guide never points outside it")
	clientProfile.quests.active.C1 = nil
	-- the minimap draws the dungeon itself, and a click on it opens the dungeon's map
	task.wait(0.5)
	local minimap = Windows.guis.HUD:FindFirstChild("Minimap", true)
	local caveMap = minimap and minimap:FindFirstChild("DungeonCanvas")
	check(caveMap and caveMap.Visible and not minimap.Canvas.Visible, "in a dungeon the minimap shows the dungeon's own map")
	for _, b in ipairs(minimap:GetChildren()) do
		if b.ClassName == "TextButton" and b.Text == "" then
			b.Activated:Fire()
		end
	end
	task.wait(0.5)
	local mapWin = Windows.registry.Map.frame
	local bigCave = mapWin:FindFirstChild("DungeonMap", true)
	check(Windows.isOpen("Map") and bigCave and bigCave.Visible and bigCave:FindFirstChild("DungeonCanvas") ~= nil, "clicking it opens the dungeon's map, not the world's")
	check(hasText(mapWin, "The way out") and hasText(mapWin, "Haldor"), "...with what the marks mean")
	Windows.close()
	-- Haldor sits on his throne (the Animator bends his legs; it only poses what's near the camera)
	local seated = nil
	for _, m in ipairs(CollectionService:GetTagged("Viking")) do
		if m:GetAttribute("Pose") == "sit" then
			seated = m
		end
	end
	local cam = workspace.CurrentCamera
	local camBefore = cam.CFrame
	if seated then
		local at = seated:GetPivot().Position
		cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 20, -120), at)
	end
	task.wait(0.3)
	local leg = seated and seated:FindFirstChild("LegL", true)
	cam.CFrame = camBefore
	local knee = seated and seated:FindFirstChild("KneeL", true)
	check(leg and math.abs(leg.Transform.LookVector.Y) > 0.5, "Haldor sits on his throne, legs bent")
	check(knee and math.abs(knee.Transform.LookVector.Y) > 0.5, "...at the knee, shins down")
	-- on one knee (a second life's collapse): the right shin flat behind, the left foot forward
	if seated then
		local at = seated:GetPivot().Position
		cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 20, -120), at)
		seated:SetAttribute("Pose", "kneel")
		task.wait(0.3)
		local kneeR, legL = seated:FindFirstChild("KneeR", true), seated:FindFirstChild("LegL", true)
		check(kneeR and legL and math.abs(kneeR.Transform.LookVector.Y) > 0.9 and legL.Transform.LookVector.Y > 0.9, "kneeling: one knee down, the other foot forward")
		seated:SetAttribute("Pose", "sit")
		task.wait(0.2)
		cam.CFrame = camBefore
	end
	-- the hidden hoard: a chest that shows open (and no prompt) once you've had your share
	local run = S.DungeonService.runOf(me)
	local hoardPrompt = run.built.chest:FindFirstChildWhichIsA("ProximityPrompt", true)
	check(hasText(me.PlayerGui, "Hidden hoard") and hoardPrompt.Enabled, "the hidden hoard, shut")
	hoardPrompt.Triggered:Fire(me)
	task.wait(1)
	check(hasText(me.PlayerGui, "Looted") and not hoardPrompt.Enabled, "...and open once you've looted it")
	-- wings only lift you a little in here: above that, flight eases you back down
	local Movement = mod("Controllers/Movement")
	local r = me.Character.HumanoidRootPart
	local hover = me.Character:FindFirstChildOfClass("Humanoid")
	Movement.toggleFlight()
	Movement.setVertical(1)
	local floorY = DungeonBuilder.floorAt(r.Position, 0.5).Y
	r.CFrame = CFrame.new(r.Position.X, floorY + hover.HipHeight + r.Size.Y / 2 + DungeonInfo.HOVER_HEIGHT + 8, r.Position.Z)
	task.wait(0.3)
	local lv = r:FindFirstChildOfClass("LinearVelocity")
	check(lv and lv.VectorVelocity.Y < -1, "flying too high in a dungeon pulls you back down")
	-- once its boss is down, the cave is yours to fly
	me:SetAttribute("DungeonCleared", true)
	task.wait(0.3)
	check(lv and lv.VectorVelocity.Y > 1, "...but full flight comes back once the dungeon is cleared")
	me:SetAttribute("DungeonCleared", nil)
	Movement.setVertical(0)
	Movement.toggleFlight()
	-- hooked by a harpoon: dragged along to the boss
	Movement.reel(r.Position + Vector3.new(30, 0, 0), 0.5)
	task.wait(0.1)
	local lv2 = r:FindFirstChildOfClass("LinearVelocity")
	check(lv2 and lv2.Enabled and lv2.VectorVelocity.X > 20, "reeled in by a harpoon: dragged toward the boss")
	task.wait(0.6)
	check(not lv2.Enabled, "...and let go at the end")
	-- knocked out alone: the death screen offers a way out
	local _, hum = S.PlayerService.getCharacter(me)
	hum.Health = 0
	task.wait(0.6)
	local death = Windows.guis.Overlay:FindFirstChild("Death")
	check(death and death.Visible and death.Leave.Visible, "knocked out in a dungeon: the death screen has Leave dungeon")
	click(death, "Leave dungeon")
	task.wait(1.5)
	check(me:GetAttribute("InDungeon") == nil and me.Character ~= nil, "Leave dungeon takes you back out")
	check(not death.Visible, "...and clears the death screen")

	-- the quest guide: pick the quest it's following to turn it off (remembered), and back on
	local sp = S.PlayerService.getProfile(me)
	sp.quests.active.C1 = 0
	clientProfile = mod("Controllers/State").profile
	clientProfile.quests.active.C1 = 0
	Waypoint.trackQuest("C1")
	task.wait(0.3)
	check(Waypoint.get() ~= nil and Waypoint.get().questId == "C1", "the guide follows a quest you pick")
	Waypoint.trackQuest("C1")
	task.wait(0.5)
	check(not Waypoint.guiding() and Waypoint.get() == nil and sp.settings.questGuide == false, "picking it again turns the quest guide off (and it's remembered)")
	Windows.open("Map")
	task.wait(0.3)
	check(hasText(Windows.registry.Map.frame, "Guide me to my quests"), "the map offers to turn it back on")
	click(Windows.registry.Map.frame, "Guide me to my quests")
	task.wait(0.5)
	check(Waypoint.guiding() and sp.settings.questGuide == true, "...and it's back on")
	Windows.close()
	sp.quests.active.C1 = nil
	mod("Controllers/State").profile.quests.active.C1 = nil

	-- a friend invites you: a toast with Join; their ready check shows Enter on the pill
	local buddy = addPlayer(301, "Pal")
	task.wait(1)
	invoke("ChooseClass", buddy, "Behemoth")
	S.PlayerService.setLevel(buddy, 20)
	task.wait(1)
	check(invoke("DungeonAction", buddy, "invite", { userId = me.UserId }), "a friend invites you")
	task.wait(0.5)
	check(findButton(toasts, "Join") ~= nil, "the invite shows as a toast with Join")
	click(toasts, "Join")
	task.wait(1)
	check(S.DungeonService.groupOf(me) ~= nil and S.DungeonService.groupOf(me) == S.DungeonService.groupOf(buddy), "Join puts you in their group")
	check(invoke("DungeonAction", buddy, "enter", { dungeonId = "Barrow" }), "the leader takes the group in")
	task.wait(1.2)
	local enter = findButton(pill, "Enter")
	check(pill.Visible and enter ~= nil and enter.Visible, "a ready check: Enter on the pill")
	click(pill, "Enter")
	task.wait(1.5)
	check(me:GetAttribute("InDungeon") == "Barrow" and buddy:GetAttribute("InDungeon") == "Barrow", "Enter takes you both in")
	click(pill, "Leave")
	task.wait(1)
	check(me:GetAttribute("InDungeon") == nil, "Leave on the pill")
	invoke("DungeonAction", buddy, "leaveRun")
	invoke("DungeonAction", me, "leaveGroup")
	buddy.Parent = nil
	Players.PlayerRemoving:Fire(buddy)
	-- I opens the window
	Windows.close()
	keys.InputBegan:Fire({ KeyCode = Enum.KeyCode.I, UserInputType = Enum.UserInputType.Keyboard }, false)
	task.wait(0.3)
	check(Windows.isOpen("Dungeons"), "I opens the Dungeons window")
	Windows.close()
	task.wait(0.5)
end

local UIS
task.spawn(function()
	task.wait(2)
	local me = Instance.new("Player")
	me.Name = "ClientTester"
	me.DisplayName = "ClientTester"
	me.UserId = 201
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = me
	SIM_LOCAL_PLAYER = me
	Players.LocalPlayer = me
	-- the default Roblox camera follows your character, keeping whatever direction it points in
	game:GetService("RunService").RenderStepped:Connect(function()
		local r = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local camera = workspace.CurrentCamera
			camera.CFrame = CFrame.lookAt(r.Position - camera.CFrame.LookVector * 27, r.Position)
		end
	end)
	me.Parent = Players
	task.spawn(function()
		require(__proxy("Client"))
	end)
	Players.PlayerAdded:Fire(me)
	task.wait(2)
	require(__proxy("Shared/Config/Raids")).CHANCE = 0 -- raids only when this test starts them
	Windows = mod("UI/Windows")
	local State = mod("Controllers/State")
	check(State.profile ~= nil, "client got its profile")
	check(mod("UI/ClassSelect").isVisible(), "class select shows for a new dragon")

	-- choose a dragon the way the class screen does
	check(Remotes.func("ChooseClass"):InvokeServer("Frostwyrm") == true, "choose class from client")
	mod("UI/ClassSelect").hide()
	task.wait(2)
	check(me.Character ~= nil, "character spawned")
	check(State.profile and State.profile.class == "Frostwyrm", "profile has class")

	-- tutorial should be running; walk it
	local Tutorial = mod("UI/Tutorial")
	local panel = Windows.guis.HUD:FindFirstChild("Tutorial")
	check(panel and panel.Visible, "tutorial shows")
	click(panel, "Let's go!")
	task.wait(0.5)
	local root = me.Character:FindFirstChild("HumanoidRootPart")
	root.CFrame = root.CFrame + Vector3.new(30, 0, 0) -- walk
	task.wait(0.5)
	local Movement = mod("Controllers/Movement")
	Movement.toggleFlight()
	task.wait(2)
	Movement.toggleFlight()
	task.wait(0.5)
	-- breathe on a dummy (server side hit -> DummyStats -> meter + tutorial)
	local dummy = findEnemy(function(e)
		return e.dummy
	end)
	S.CombatService.damageEnemy(me, dummy, 50, false)
	task.wait(0.5)
	mod("Controllers/Combat").cast("Fireball")
	task.wait(0.5)
	-- quest from the Elder
	tp(me, Zones.QuestGivers.Elder.position + Vector3.new(0, 5, -10))
	task.wait(0.3)
	local okAccept, errAccept = Remotes.func("AcceptQuest"):InvokeServer("E1")
	check(okAccept, "accept quest: " .. tostring(errAccept))
	task.wait(0.5)
	tp(me, S.FarmService.getHomeCFrame(me).Position)
	task.wait(0.5)
	check(Remotes.func("PlantSeed"):InvokeServer(1, "Emberbloom") == true, "plant from client")
	task.wait(1)
	for _ = 1, 3 do
		local nextButton = findButton(panel, "Got it") or findButton(panel, "Cool!") or findButton(panel, "Finish tour")
		if nextButton then
			nextButton.Activated:Fire()
			task.wait(0.4)
		end
	end
	task.wait(1)
	check(State.profile.tutorial == -1, "tutorial finished (" .. tostring(State.profile.tutorial) .. ")")
	check(not panel.Visible, "tutorial panel hidden")

	-- every window
	for _, name in ipairs({ "SkillTree", "Inventory", "QuestLog", "Help", "Potions", "Pets", "Robots", "Codes", "Store", "Collection" }) do
		Windows.open(name)
		task.wait(0.1)
		check(Windows.isOpen(name), "window opens: " .. name)
	end
	-- collection tabs, a Studio test purchase, the skill tree's key picker
	Windows.open("Collection")
	local collection = Windows.registry.Collection.frame
	click(collection, "Achievements")
	click(collection, "Skins")
	click(collection, "Pet Book")
	local treatsBefore = State.profile.treats or 0
	Windows.open("Store")
	mod("UI/Store").buy("product", "TreatBag")
	task.wait(1)
	check((State.profile.treats or 0) >= treatsBefore + 40, "store purchase from the client (Studio test)")
	Windows.open("SkillTree")
	local keySlot = Windows.registry.SkillTree.frame:FindFirstChild("KeySlot1", true)
	check(keySlot ~= nil, "skill tree has the keys 2-5 strip")
	if keySlot then
		keySlot.Activated:Fire()
		task.wait(0.1)
	end
	Windows.open("Inventory")
	local inv = Windows.registry.Inventory.frame
	click(inv, "Seeds")
	click(inv, "Food")
	click(inv, "Gear")
	Windows.open("QuestDialog", "Elder")
	Windows.open("SeedPicker", 2)
	mod("UI/Shop").open("Buy")
	task.wait(0.5)
	-- each shop does one job now; opening another page just switches the window
	mod("UI/Shop").open("Sell")
	task.wait(0.2)
	mod("UI/Shop").open("Upgrade")
	task.wait(0.2)
	mod("UI/Pets").open("Eggs")
	task.wait(0.2)
	local pets = Windows.registry.Pets.frame
	-- eggs waiting: a red count on the Pets menu button and on the Eggs tab
	local waiting = mod("UI/HUD").eggsWaiting(State.profile)
	check(waiting > 0, "the tutorial egg is waiting")
	local function badgeOn(root: Instance, buttonText: string): string?
		local button = findButton(root, buttonText)
		local badge = button and button:FindFirstChild("Badge")
		return badge and badge.Visible and badge.Text or nil
	end
	check(badgeOn(Windows.guis.HUD, "🐲") == tostring(waiting), "a red egg count on the Pets menu button")
	check(badgeOn(pets, "Eggs") == tostring(waiting), "... and on the Eggs tab")
	-- the odds fit on one line; the full list of pets opens on request
	check(findButton(pets, "Hide pets") == nil, "egg cards start folded")
	click(pets, "See every pet")
	task.wait(0.1)
	check(findButton(pets, "Hide pets") ~= nil, "See every pet unfolds an egg")
	click(pets, "Hide pets")
	click(pets, "Hatch yours") -- the tutorial egg
	local overlay = Windows.guis.Top:FindFirstChild("HatchOverlay")
	task.wait(0.3)
	overlay.Activated:Fire()
	check(overlay.Visible, "a click before the reveal doesn't skip it")
	task.wait(2.5)
	overlay.Activated:Fire() -- a click outside the card closes the reveal
	check(not overlay.Visible, "clicking the underlay closes the reveal")
	task.wait(3)
	check(mod("UI/HUD").eggsWaiting(State.profile) == waiting - 1, "the egg hatched")
	-- can't afford an egg: the message offers gold packs (never a pop-up of its own)
	local goldBefore = S.PlayerService.getProfile(me).gold
	S.PlayerService.getProfile(me).gold = 0
	S.PlayerService.markDirty(me)
	task.wait(0.5)
	mod("UI/Pets").open("Eggs")
	task.wait(0.1)
	click(pets, "Buy & Hatch")
	local banner = pets:FindFirstChild("StatusBanner")
	check(banner.Visible and banner.Action.Visible, "a click on an egg you can't afford offers gold")
	check(banner.Position.Y.Scale == 1 or banner.Position.Y.Offset <= 8, "the message sits below the window or on its title bar, not over the eggs")
	click(banner, "Get gold")
	check(Windows.isOpen("Store"), "Get gold opens the Store")
	S.PlayerService.getProfile(me).gold = goldBefore
	S.PlayerService.markDirty(me)
	-- on a big screen there's room for the message just below the window
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	camera.ViewportSize = Vector2.new(1920, 1080)
	task.wait(0.1)
	Windows.notify("Testing the banner", nil, "🧪")
	local storeBanner = Windows.registry.Store.frame:FindFirstChild("StatusBanner")
	check(storeBanner.Visible and storeBanner.Position.Y.Scale == 1, "window messages show just below the window when there's room")
	camera.ViewportSize = viewport
	task.wait(0.1)
	mod("UI/Pets").open("Pets")
	task.wait(0.2)

	-- pets follow their owner, even across a long teleport (boss arena) and back
	for _, pet in ipairs(State.profile.pets or {}) do
		Remotes.func("EquipPet"):InvokeServer(pet.uid)
	end
	task.wait(0.5)
	local function petDistances()
		local folder = workspace:FindFirstChild("ClientPets")
		local r = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		local list = {}
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			if m.PrimaryPart and r then
				table.insert(list, (m.PrimaryPart.Position - r.Position).Magnitude)
			end
		end
		return list
	end
	local d0 = petDistances()
	check(#d0 >= 1, "pet models exist (" .. #d0 .. ")")
	for _, d in ipairs(d0) do
		check(d < 15, "pet near owner (" .. math.floor(d) .. ")")
	end
	tp(me, Vector3.new(3000, 10, 60))
	task.wait(2)
	for _, d in ipairs(petDistances()) do
		check(d < 15, "pet followed a long teleport (" .. math.floor(d) .. ")")
	end
	tp(me, Zones.SPAWN)
	task.wait(2)
	for _, d in ipairs(petDistances()) do
		check(d < 15, "pet came back (" .. math.floor(d) .. ")")
	end
	-- pets wear nametags; treats level them up; three of a kind merge into a golden one
	local petFolder = workspace:FindFirstChild("ClientPets")
	local tagged, models = 0, 0
	for _, m in ipairs(petFolder and petFolder:GetChildren() or {}) do
		models += 1
		if m.PrimaryPart and m.PrimaryPart:FindFirstChild("PetTag") then
			tagged += 1
		end
	end
	check(models >= 1 and tagged == models, string.format("every pet has a nametag (%d/%d)", tagged, models))
	local myProfile = S.PlayerService.getProfile(me)
	local firstPet = myProfile.pets[1]
	if firstPet then
		myProfile.treats = 20
		Windows.open("Pets")
		mod("UI/Pets").refresh()
		local fed = Remotes.func("FeedPet"):InvokeServer(firstPet.uid)
		check(fed == true and firstPet.level == 2 and myProfile.treats == 17, "feeding treats levels a pet up")
		for i = 1, 2 do
			table.insert(myProfile.pets, { uid = "extra" .. i, species = firstPet.species, level = 3 })
		end
		local before = #myProfile.pets
		S.PlayerService.addGold(me, 20000)
		local merged = Remotes.func("MergePets"):InvokeServer(firstPet.uid)
		check(merged == true and firstPet.golden == true and #myProfile.pets == before - 2, "three pets merge into a golden one")
		check(firstPet.level == 3, "the golden pet keeps the best level")
		check(not Remotes.func("MergePets"):InvokeServer(firstPet.uid), "a golden pet can't merge again")
		Remotes.func("EquipPet"):InvokeServer(firstPet.uid)
		task.wait(1.5)
		local sparkly = false
		for _, m in ipairs(petFolder and petFolder:GetChildren() or {}) do
			if m.PrimaryPart and m.PrimaryPart:FindFirstChild("GoldenSparkle") then
				sparkly = true
			end
		end
		check(sparkly, "the golden pet sparkles")
		mod("UI/Pets").refresh()
		Windows.close("Pets")
		-- in a boss fight the pets' nametags hide
		me:SetAttribute("InBossFight", true)
		task.wait(0.3)
		local shown = 0
		for _, m in ipairs(petFolder:GetChildren()) do
			local tag = m.PrimaryPart and m.PrimaryPart:FindFirstChild("PetTag")
			if tag and tag.Enabled then
				shown += 1
			end
		end
		check(shown == 0, "in a boss fight the pets' nametags hide")
		me:SetAttribute("InBossFight", false)
		-- knocked out: your pets settle on the ground beside you instead of flapping over you
		local character = me.Character
		local root = character.HumanoidRootPart
		character:SetAttribute("KnockedOut", true)
		task.wait(1)
		local mine, low = 0, 0
		for _, m in ipairs(petFolder:GetChildren()) do
			local p = m.PrimaryPart and m.PrimaryPart.Position
			if p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < 25 then
				mine += 1
				if p.Y < root.Position.Y then
					low += 1
				end
			end
		end
		check(mine >= 1 and low == mine, string.format("a knocked-out dragon's pets settle beside it (%d/%d)", low, mine))
		character:SetAttribute("KnockedOut", nil)
		task.wait(0.5)
	end

	-- camp chests are per dragon: the lid, treasure and prompt follow MY timer
	local chest = nil
	for _, m in ipairs(game:GetService("CollectionService"):GetTagged("CampChest")) do
		if m:GetAttribute("CampId") == "RaiderCamp" then
			chest = m
		end
	end
	if chest then
		local prompt = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
		check(prompt.Enabled and chest:FindFirstChild("Treasure") ~= nil, "a full chest shows its treasure")
		me:SetAttribute("ChestReady_RaiderCamp", workspace:GetServerTimeNow() + 60)
		task.wait(1.5)
		check(not prompt.Enabled and chest:FindFirstChild("Treasure") == nil, "an empty chest hides the treasure and prompt")
		me:SetAttribute("ChestReady_RaiderCamp", nil)
		task.wait(1.5)
		check(prompt.Enabled and chest:FindFirstChild("Treasure") ~= nil, "the chest refills")
	end

	-- every ability's effects play without errors (ultimates, heals, lasting spells, eclipse)
	do
		local Abilities = require(__proxy("Shared/Config/Abilities"))
		local VFX = mod("Controllers/VFX")
		local character = me.Character
		local root = character:FindFirstChild("HumanoidRootPart")
		local pos = root.Position
		local ids = {}
		for id, ability in pairs(Abilities) do
			if type(ability) == "table" and ability.kind then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		for i, id in ipairs(ids) do
			local a = Abilities[id]
			local data = { kind = a.kind, abilityId = id, classId = "Frostwyrm", character = character, pos = pos, radius = a.radius or 10 }
			if a.kind == "projectile" then
				data.origin = pos
				data.list = { { id = "fx" .. i, dir = Vector3.new(0, 0, -1) } }
				data.speed, data.range, data.size = a.speed, a.range, a.size
			elseif a.kind == "strike" then
				data.delay, data.style = a.delay, a.style
			elseif a.kind == "buff" then
				data.duration = a.duration
			elseif a.kind == "breath" then
				data.dir, data.duration = Vector3.new(0, 0, -1), 0.5
			elseif a.kind == "dash" then
				data.from, data.to = pos, pos + Vector3.new(0, 0, -20)
			end
			Remotes.event("VFX"):FireAllClients(data)
			if a.kind == "projectile" then
				task.wait(0.3)
				Remotes.event("VFX"):FireAllClients({ kind = "projectileHit", id = "fx" .. i, pos = pos + Vector3.new(0, 0, -20), radius = a.radius or 5, classId = "Venomspine", abilityId = id })
			end
			task.wait(0.4)
			if id == "Eclipse" then
				check(game:GetService("Lighting"):FindFirstChild("EclipseTint") ~= nil, "eclipse darkens the sky")
			end
		end
		local lighting = game:GetService("Lighting")
		task.wait(12)
		check(lighting:FindFirstChild("EclipseTint") == nil, "the sun comes back after the eclipse")
		check(VFX.errorCount == 0, "every spell effect played cleanly (" .. VFX.errorCount .. " errors)")
	end

	local function questMarkers(): number
		local count = 0
		for _, child in ipairs(me.PlayerGui:GetChildren()) do
			if child.Name == "QuestMarker" then
				count += 1
			end
		end
		return count
	end
	local markersBefore = questMarkers()
	check(markersBefore > 0, "quest markers over the givers")
	local _, hum = S.PlayerService.getCharacter(me)
	hum.Health = 0
	task.wait(Game.RESPAWN_TIME + 2)
	check(questMarkers() == markersBefore, "quest markers survive a respawn (" .. questMarkers() .. "/" .. markersBefore .. ")")
	check(me.PlayerGui:FindFirstChild("WaypointMarker") ~= nil, "the waypoint pin survives a respawn")
	local d1 = petDistances()
	check(#d1 >= 1, "pets after respawn (" .. #d1 .. ")")
	for _, d in ipairs(d1) do
		check(d < 15, "pet near owner after respawn (" .. math.floor(d) .. ")")
	end

	-- codes -> admin panel
	Windows.open("Codes")
	local codes = Windows.registry.Codes.frame
	for _, d in ipairs(codes:GetDescendants()) do
		if d.ClassName == "TextBox" then
			d.Text = "DRAGONLORD"
		end
	end
	click(codes, "Redeem")
	task.wait(0.5)
	check(Windows.isOpen("Admin"), "admin panel opens after the code")
	local admin = Windows.registry.Admin.frame
	click(admin, "Lv 30")
	task.wait(0.5)
	check(State.profile.level == 30, "admin level 30 from the panel")
	-- signature ability unlocked (level 30 now) and castable from key 1
	check(State.profile.stats.abilities[3] == "FrostShards", "signature ability on key 1")
	-- skill tree: click a skill twice to learn it, Max the rest, then auto-fill a branch
	Windows.open("SkillTree")
	task.wait(0.2)
	local tree = Windows.registry.SkillTree.frame
	local tile = nil
	for _, d in ipairs(tree:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Size and d.Size.X.Offset == 50 and d.Size.Y.Offset == 50 then
			tile = d
			break
		end
	end
	check(tile ~= nil, "found a skill tile")
	local function spent()
		local n = 0
		for _, r in pairs(State.profile.talents) do
			n += r
		end
		return n
	end
	local before = spent()
	tile.Activated:Fire()
	task.wait(0.3)
	check(spent() == before, "first click only selects")
	-- the Learn / Max bubble never covers another skill (you can click between the two in a row)
	local bubble, neighbour = nil, nil
	for _, child in ipairs(tile.Parent:GetChildren()) do
		if child.ClassName == "Frame" and child.ZIndex == 20 and child.Visible then
			bubble = child
		elseif child ~= tile and child.ClassName == "TextButton" and child.Size.X.Offset == 50 and child.Position.Y.Offset == tile.Position.Y.Offset then
			neighbour = child
		end
	end
	check(bubble ~= nil, "the Learn / Max bubble shows")
	if bubble then
		local bx, by, bw, bh = bubble.Position.X.Offset, bubble.Position.Y.Offset, bubble.Size.X.Offset, bubble.Size.Y.Offset
		for _, child in ipairs(tile.Parent:GetChildren()) do
			if child.ClassName == "TextButton" and child.Size.X.Offset == 50 then
				local x, y = child.Position.X.Offset, child.Position.Y.Offset
				check(bx + bw <= x or bx >= x + 50 or by + bh <= y or by >= y + 50, "the bubble doesn't cover a skill")
			end
		end
	end
	check(neighbour ~= nil, "the tile has a neighbour in its row")
	if neighbour then
		neighbour.Activated:Fire()
		task.wait(0.2)
		tile.Activated:Fire()
		task.wait(0.2)
		check(spent() == before, "clicking between two skills only selects them")
	end
	tile.Activated:Fire()
	task.wait(0.5)
	check(spent() == before + 1, "second click learns a rank")
	click(tree, "Max (+2)")
	task.wait(0.5)
	check(spent() == before + 3, "Max learns the remaining ranks")
	local auto = findButton(tree, "Auto")
	check(auto ~= nil, "auto button")
	auto.Activated:Fire()
	task.wait(0.2)
	auto.Activated:Fire()
	task.wait(0.5)
	check(spent() > before + 3, "auto-fill spent points (" .. spent() .. ")")

	-- equip best (gear + pets)
	Remotes.func("AdminAction"):InvokeServer("item", { rarity = "Legendary" })
	task.wait(0.5)
	Windows.open("Inventory")
	click(Windows.registry.Inventory.frame, "Gear")
	click(Windows.registry.Inventory.frame, "Equip Best")
	task.wait(0.5)
	local worn = 0
	for _ in pairs(State.profile.equipped) do
		worn += 1
	end
	check(worn >= 1, "equip best wore gear (" .. worn .. ")")
	Remotes.func("AdminAction"):InvokeServer("egg", { eggId = "MythicEgg" })
	task.wait(0.3)
	Remotes.func("HatchEgg"):InvokeServer("MythicEgg")
	mod("UI/Pets").open("Pets")
	task.wait(0.2)
	click(Windows.registry.Pets.frame, "Equip Best")
	task.wait(0.5)
	check(#State.profile.petsEquipped == math.min(#State.profile.pets, State.profile.petSlots), "equip best pets fills the slots")

	-- map + waypoints
	local Waypoint = mod("Controllers/Waypoint")
	Windows.open("Map")
	task.wait(0.3)
	click(Windows.registry.Map.frame, "Training grounds")
	task.wait(0.3)
	check(Waypoint.get() and Waypoint.get().source == "place", "waypoint set from the map")
	tp(me, Zones.Training.dummies[2] + Vector3.new(0, 5, -8))
	task.wait(0.5)
	check(Waypoint.get() == nil or Waypoint.get().source == "quest", "waypoint clears on arrival")
	local okQ = Remotes.func("AcceptQuest"):InvokeServer("C1")
	Waypoint.trackQuest("C1")
	task.wait(0.3)
	check(not okQ or (Waypoint.get() and Waypoint.get().questId == "C1"), "tracking a quest sets its waypoint")
	local mini = Windows.guis.HUD:FindFirstChild("Minimap")
	check(mini ~= nil, "minimap exists")
	-- the Wayfinder pass: a 🌀 beside every place on the map teleports you there
	local mapFrame = Windows.registry.Map.frame
	check(mapFrame:FindFirstChild("Teleport", true) == nil, "no teleport buttons without the Wayfinder pass")
	Remotes.func("AdminAction"):InvokeServer("pass", { pass = "Wayfinder", on = true })
	task.wait(4.5) -- (no teleporting straight out of a fight)
	Windows.open("Map")
	task.wait(0.3)
	local hatchery = Zones.getPlace("shop:Hatchery")
	local tpButton = nil
	for _, d in ipairs(mapFrame:GetDescendants()) do
		if d.Name == "Teleport" then
			for _, sibling in ipairs(d.Parent:GetChildren()) do
				if sibling ~= d and sibling.ClassName == "TextButton" and tostring(sibling.Text):find("Hatchery", 1, true) then
					tpButton = d
				end
			end
		end
	end
	check(tpButton ~= nil, "teleport buttons with the Wayfinder pass")
	if tpButton then
		tpButton.Activated:Fire()
		task.wait(0.5)
		local at = rootOf(me).Position
		check(Vector3.new(at.X - hatchery.drop.X, 0, at.Z - hatchery.drop.Z).Magnitude < 4, "the 🌀 button teleports you to the Hatchery")
		check(not Windows.isOpen("Map"), "... and closes the map")
	end
	Remotes.func("AdminAction"):InvokeServer("pass", { pass = "Wayfinder", on = false })

	-- boss banner can be minimized to a pill and opened again
	Remotes.func("AdminAction"):InvokeServer("bossNow", { seconds = 60 })
	task.wait(1.5)
	local banner = Windows.guis.HUD:FindFirstChild("BossBanner")
	check(banner and banner.Visible, "boss banner shows")
	local minimize = banner:FindFirstChild("Minimize", true)
	check(minimize ~= nil, "boss banner has a minimize button")
	if minimize then
		minimize.Activated:Fire()
	end
	task.wait(0.3)
	local pillButton = Windows.guis.HUD:FindFirstChild("BossPill")
	check(pillButton and pillButton.Visible and not banner.Visible, "banner minimized to a pill")
	pillButton.Activated:Fire()
	task.wait(0.3)
	check(banner.Visible, "pill reopens the banner")

	click(admin, "Balance")
	task.wait(0.3)
	click(admin, "Print changes")
	click(admin, "World")
	click(admin, "Dragon")
	click(admin, "Max potions")
	click(admin, "Starving (5)")
	task.wait(1.5)

	-- server-driven panels and events
	Remotes.event("OpenPanel"):FireClient(me, "Potions")
	task.wait(0.1)
	check(Windows.isOpen("Potions"), "OpenPanel Potions")
	Remotes.event("OpenPanel"):FireClient(me, "Hatchery")
	task.wait(0.1)
	check(Windows.isOpen("Pets"), "OpenPanel Hatchery")
	Remotes.event("OpenPanel"):FireClient(me, "Robots")
	task.wait(0.1)
	check(Windows.isOpen("Robots"), "OpenPanel Robots")
	click(Windows.registry.Robots.frame, "Buy")

	-- fishing through the client UI
	local spot = CollectionService:GetTagged("FishingSpot")[2]
	tp(me, spot:GetPivot().Position + Vector3.new(0, 8, -14))
	local logStart = #REMOTE_LOG
	spot:FindFirstChildWhichIsA("ProximityPrompt", true).Triggered:Fire(me)
	local bit = false
	for _ = 1, 100 do
		task.wait(0.1)
		for i = logStart + 1, #REMOTE_LOG do
			local entry = REMOTE_LOG[i]
			if entry.remote == "Fishing" and entry.player == me and entry.args[1].phase == "bite" then
				bit = true
			end
		end
		if bit then
			break
		end
	end
	check(bit, "a fish bites")
	local fishing = Windows.guis.HUD:FindFirstChild("Fishing")
	check(fishing and fishing.Visible, "fishing panel shows")
	click(fishing, "REEL!")
	task.wait(1)

	-- the sky follows the server's day/night clock
	local Lighting = game:GetService("Lighting")
	local dayBrightness = Lighting.Brightness
	Remotes.func("AdminAction"):InvokeServer("setHour", { hour = 23 })
	task.wait(0.5)
	check(math.abs(Lighting.ClockTime - 23) < 0.3, "the sky clock follows the server (" .. Lighting.ClockTime .. ")")
	check(Lighting.Brightness < dayBrightness, "nights are darker")
	local lamp = CollectionService:GetTagged("Lamp")[1]
	check(lamp and lamp:FindFirstChildOfClass("PointLight").Enabled, "street lamps light up at night")
	local clockText = nil
	for _, d in ipairs(Windows.guis.HUD.Minimap:GetDescendants()) do
		if d.ClassName == "TextLabel" and tostring(d.Text):find("PM", 1, true) then
			clockText = d.Text
		end
	end
	check(clockText ~= nil and clockText:find("11:") ~= nil, "the minimap clock shows the night (" .. tostring(clockText) .. ")")

	-- a night raid: the bar, the longships, then a lost raid closes the shops
	local Raids = require(__proxy("Shared/Config/Raids"))
	tp(me, S.FarmService.getHomeCFrame(me).Position) -- (away from the water: during a raid it'd scoop some up)
	Remotes.func("AdminAction"):InvokeServer("raidNow")
	task.wait(1)
	local raidBar = Windows.guis.HUD:FindFirstChild("RaidBar")
	check(raidBar and raidBar.Visible, "the raid bar shows")
	local minimize = raidBar:FindFirstChild("Minimize", true)
	check(minimize ~= nil, "the raid bar has a minimize button")
	if minimize then
		minimize.Activated:Fire()
	end
	task.wait(0.4)
	local raidPill = Windows.guis.HUD:FindFirstChild("RaidPill")
	check(raidPill and raidPill.Visible and not raidBar.Visible, "the raid bar minimizes to a pill")
	if raidPill then
		raidPill.Activated:Fire()
	end
	task.wait(0.4)
	check(raidBar.Visible and not raidPill.Visible, "the pill opens the raid bar again")
	-- the vikings on deck cheer with their axes up (the Animator)
	local deckViking = S.RaidService.aboard()[1]
	local armR = deckViking and deckViking.model:FindFirstChild("ArmR", true)
	if deckViking then
		tp(me, deckViking.root.Position + Vector3.new(0, 30, -60)) -- (the Animator only poses what's near the camera)
	end
	task.wait(0.3)
	if armR and armR:IsA("Motor6D") then
		local up = armR.Transform.UpVector
		local x = math.atan2(up.Z, up.Y) -- the arm's swing about its shoulder
		check(x > 1.5, "the vikings on deck cheer (arm " .. string.format("%.2f", x) .. ")")
	else
		check(false, "a viking on deck with an arm to wave")
	end
	tp(me, S.FarmService.getHomeCFrame(me).Position)
	-- a house on fire: the water chip says where to get water, then how much you carry
	Remotes.func("AdminAction"):InvokeServer("burnHouse")
	task.wait(0.6)
	local chip = Windows.guis.HUD:FindFirstChild("WaterChip")
	check(chip and chip.Visible and chip.Text:find("on fire") ~= nil, "a burning house shows the water hint (" .. tostring(chip and chip.Text) .. ")")
	local well = workspace.Map.Town:FindFirstChild("Well1")
	check(well and well:FindFirstChild("WellTag", true).Enabled, "the wells light up \"Water\" while a house burns")
	tp(me, Zones.Wells[1] + Vector3.new(4, 4, 0))
	task.wait(0.6)
	check(chip.Visible and chip.Text:find("Hover over") ~= nil and chip.Gauge.Visible and chip.Gauge.Fill.Size.X.Scale == 1, "scooped water shows on the chip, gauge full (" .. chip.Text .. ")")
	tp(me, Zones.Houses[1].pos + Vector3.new(0, 30, 0))
	task.wait(0.6)
	check(chip.Text:find("Pouring") ~= nil and workspace.Map.Town.House1:GetAttribute("Fire") == "burning", "hovering over the fire pours (" .. chip.Text .. ")")
	task.wait(Raids.DOUSE_TIME)
	local gaugeLeft = chip.Gauge.Fill.Size.X.Scale
	check(workspace.Map.Town.House1:GetAttribute("Fire") == nil and gaugeLeft < 1 and gaugeLeft > 0, "the fire's out and the gauge went down (" .. string.format("%.2f", gaugeLeft) .. ")")
	task.wait(Raids.WARNING + 3)
	check(workspace:GetAttribute("RaidPhase") == "fighting", "the raiders landed")
	-- a knocked-out villager sprawls on the ground (the Animator poses it)
	local villager = S.CivilianService.villagers()[1]
	for _ = 1, Raids.VILLAGER_HITS do
		S.CivilianService.hurt(villager)
	end
	task.wait(0.5)
	check(villager.model:GetAttribute("KnockedOut") == true, "a villager is knocked out")
	-- the quest givers show crossed swords while they fight, and their quests again afterwards
	local QuestsInfo = require(__proxy("Shared/Config/Quests"))
	local function markerTexts(): { [string]: number }
		-- (the village's givers: the dungeon keepers don't fight raids, so they keep their ❗)
		local texts = {}
		for _, child in ipairs(me.PlayerGui:GetChildren()) do
			local model = child.Name == "QuestMarker" and child.Adornee and child.Adornee.Parent
			local giver = model and QuestsInfo.Givers[model:GetAttribute("GiverId") or ""]
			if child.Name == "QuestMarker" and not (giver and giver.dungeon) then
				local label = child:FindFirstChildOfClass("TextLabel")
				texts[label.Text] = (texts[label.Text] or 0) + 1
			end
		end
		return texts
	end
	local during = markerTexts()
	check(during["⚔️"] ~= nil and (during["!"] or 0) + (during["?"] or 0) == 0, "quest givers show swords during a raid")
	Remotes.func("AdminAction"):InvokeServer("raidEnd", { won = false })
	task.wait(0.5)
	check(markerTexts()["⚔️"] == nil, "the swords go away after the raid")
	check(not chip.Visible, "the water chip goes away with the raid")
	check(raidBar.Visible and workspace:GetAttribute("ShopsClosedUntil") ~= nil, "the shops-closed countdown shows")
	Remotes.func("AdminAction"):InvokeServer("shops", { open = true })
	Remotes.func("AdminAction"):InvokeServer("rebuildHouses")
	Remotes.func("AdminAction"):InvokeServer("setHour", { hour = 10 })
	task.wait(0.5)
	check(not raidBar.Visible, "the bar hides once the shops reopen")

	-- target practice: the window, AFK auto-fire, and left click firing Fireball on the range
	local casts = {}
	Remotes.event("CastAbility").OnServerEvent:Connect(function(_, abilityId)
		casts[abilityId] = (casts[abilityId] or 0) + 1
	end)
	tp(me, Vector3.new(Zones.Range.matX, 6, Zones.Range.lanes[2]))
	task.wait(0.3)
	Remotes.event("OpenPanel"):FireClient(me, "Range")
	task.wait(0.2)
	check(Windows.isOpen("Range"), "OpenPanel Range")
	me.CameraMaxZoomDistance = 160
	click(Windows.registry.Range.frame, "Start AFK")
	task.wait(0.1)
	local RangeInfo = require(__proxy("Shared/Config/Range"))
	check(me.CameraMaxZoomDistance == RangeInfo.CAMERA_ZOOM, "starting practice pulls the camera in")
	check(workspace.CurrentCamera.CFrame.LookVector.X < -0.5, "and points it down the lane")
	task.wait(0.5)
	check(me.CameraMaxZoomDistance == Game.CAMERA_MAX_ZOOM, "then lets the player zoom again")
	check(me:GetAttribute("RangeMode") == "afk" and not Windows.isOpen("Range"), "AFK practice starts from the window")
	local logAfk = #REMOTE_LOG
	local rangePanel = Windows.guis.HUD:FindFirstChild("RangePanel")
	check(rangePanel and rangePanel.Visible, "the practice panel shows")
	task.wait(6)
	check((casts.Fireball or 0) >= 1, "AFK practice fires by itself (" .. tostring(casts.Fireball) .. ")")
	local xpNumbers = 0
	for i = logAfk + 1, #REMOTE_LOG do
		local entry = REMOTE_LOG[i]
		if entry.remote == "DamageNumber" and entry.player == me then
			for _, n in ipairs(entry.args[1]) do
				if n.kind == "xp" then
					xpNumbers += 1
				end
			end
		end
	end
	check(xpNumbers >= 1, "AFK hits show rising +XP (" .. xpNumbers .. ")")
	local target = CollectionService:GetTagged("PracticeTarget")[1]
	if target then
		local RangeUtil = require(__proxy("Shared/RangeUtil"))
		local want = RangeUtil.position(RangeUtil.fromModel(target), workspace:GetServerTimeNow())
		check((target:GetPivot().Position - want).Magnitude < 1, "the client moves the targets")
	end
	click(rangePanel, "Stop")
	task.wait(0.5)
	check(me:GetAttribute("RangeMode") == nil and not rangePanel.Visible, "practice stops")
	check(Remotes.func("RangeAction"):InvokeServer("start", 1), "start level 1 from the client")
	task.wait(0.3)
	casts = {}
	UIS = game:GetService("UserInputService")
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
	task.wait(1.6)
	UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown })
	check((casts.Fireball or 0) >= 2 and not casts.Breath, "holding left click fires Fireball on the range")
	mod("Controllers/Combat").cast("Breath")
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.Two, UserInputType = Enum.UserInputType.Keyboard }, false)
	task.wait(0.3)
	Remotes.func("RangeAction"):InvokeServer("stop")
	task.wait(0.3)

	dungeonClientScenario(me)

	-- eat with G, go home with H, pets with P
	UIS = game:GetService("UserInputService")
	for _, key in ipairs({ Enum.KeyCode.G, Enum.KeyCode.P, Enum.KeyCode.K, Enum.KeyCode.B, Enum.KeyCode.J, Enum.KeyCode.H, Enum.KeyCode.Q, Enum.KeyCode.T, Enum.KeyCode.F }) do
		UIS.InputBegan:Fire({ KeyCode = key, UserInputType = Enum.UserInputType.Keyboard }, false)
		task.wait(0.2)
	end
	task.wait(3)
	SIM.done = true
end)

local limit = 400
while not SIM.done and SIM.now < limit do
	SIM.step(1 / 30)
end
print(string.format("\nsimulated %.0f seconds", SIM.now))
for _, e in ipairs(SIM.errors) do
	print(string.format("\nERROR (x%d): %s\n%s", e.count, e.msg, e.trace))
end
print(string.format("%d script errors, %d failed checks", #SIM.errors, #failures))
