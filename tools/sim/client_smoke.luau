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
	-- the default Roblox camera follows your character
	game:GetService("RunService").RenderStepped:Connect(function()
		local r = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		if r then
			workspace.CurrentCamera.CFrame = CFrame.lookAt(r.Position + Vector3.new(0, 12, 25), r.Position)
		end
	end)
	me.Parent = Players
	task.spawn(function()
		require(__proxy("Client"))
	end)
	Players.PlayerAdded:Fire(me)
	task.wait(2)
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
	for _, name in ipairs({ "SkillTree", "Inventory", "QuestLog", "Help", "Potions", "Pets", "Robots", "Codes" }) do
		Windows.open(name)
		task.wait(0.1)
		check(Windows.isOpen(name), "window opens: " .. name)
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
	local shop = Windows.registry.Shop.frame
	click(shop, "Sell")
	click(shop, "Upgrade")
	mod("UI/Pets").open("Eggs")
	task.wait(0.2)
	local pets = Windows.registry.Pets.frame
	click(pets, "Hatch") -- the tutorial egg
	task.wait(3)
	click(pets, "My Pets")
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
	local _, hum = S.PlayerService.getCharacter(me)
	hum.Health = 0
	task.wait(Game.RESPAWN_TIME + 2)
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
		if d.ClassName == "TextButton" and d.Size and d.Size[1] == 50 and d.Size[2] == 50 then
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

	-- boss banner can be minimized to a pill and opened again
	Remotes.func("AdminAction"):InvokeServer("bossNow", { seconds = 60 })
	task.wait(1.5)
	local banner = Windows.guis.HUD:FindFirstChild("BossBanner")
	check(banner and banner.Visible, "boss banner shows")
	click(banner, "➖")
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

	-- eat with G, go home with H, pets with P
	local UIS = game:GetService("UserInputService")
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
