-- The 📖 Collection (Config/Collections, Config/Skins): the pet book, achievements, skins and
-- titles. Rewards are granted the moment you reach them: a quick check runs every few seconds
-- for everyone, and right away when a new pet species is discovered.
--
-- Profile: petBook[species] = 1 hatched / 2 made golden, achievements[id] = tiers reached,
-- milestones["m<i>"] = true, skins[id] / titles[text] = true, skin / title = the chosen ones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collections = require(Shared.Config.Collections)
local Skins = require(Shared.Config.Skins)
local Pets = require(Shared.Config.Pets)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local AchievementService = {}
local S

local lastSkinChange = {} -- [Player] = os.clock()

local function statValue(profile, stat: string): number
	if stat == "level" then
		return profile.level
	end
	return tonumber(profile[stat]) or 0
end

-- Counts for the pet book: different species hatched, different species made golden.
function AchievementService.bookCounts(petBook)
	local species, golden = 0, 0
	for _, state in pairs(petBook or {}) do
		species += 1
		if state >= 2 then
			golden += 1
		end
	end
	return species, golden
end

-- Hand out a reward and describe it ("+500 gold, +15 🍬, Storm Egg").
function AchievementService.grant(player: Player, reward): string
	local profile = S.PlayerService.getProfile(player)
	local parts = {}
	if reward.gold then
		S.PlayerService.addGold(player, reward.gold)
		table.insert(parts, "+" .. Util.formatNumber(reward.gold) .. " gold")
	end
	if reward.treats then
		profile.treats = (profile.treats or 0) + reward.treats
		table.insert(parts, "+" .. reward.treats .. " 🍬 treats")
	end
	for eggId, n in pairs(reward.eggs or {}) do
		profile.eggs[eggId] = (profile.eggs[eggId] or 0) + n
		table.insert(parts, string.format("%s %s%s", Pets.Eggs[eggId].icon, Pets.Eggs[eggId].name, n > 1 and (" x" .. n) or ""))
	end
	if reward.skin and not profile.skins[reward.skin] then
		profile.skins[reward.skin] = true
		table.insert(parts, "🎨 " .. Skins.get(reward.skin).name .. " skin")
	end
	if reward.title and not profile.titles[reward.title] then
		profile.titles[reward.title] = true
		table.insert(parts, "🏷️ title \"" .. reward.title .. "\"")
	end
	S.PlayerService.markDirty(player)
	return table.concat(parts, ", ")
end

local function celebrate(player: Player, title: string, text: string)
	Remotes.event("Announce"):FireClient(player, { title = title, text = text, color = Color3.fromRGB(255, 205, 90), duration = 4 })
	S.PlayerService.notify(player, title .. " " .. text, Color3.fromRGB(255, 205, 90), "🏆")
end

-- Grant anything newly reached.
function AchievementService.check(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile or not profile.class then
		return
	end
	-- Saves from before the pet book: everything you already own counts.
	if not profile.bookSynced then
		profile.bookSynced = true
		for _, pet in ipairs(profile.pets) do
			profile.petBook[pet.species] = math.max(profile.petBook[pet.species] or 0, pet.golden and 2 or 1)
		end
	end
	for _, a in ipairs(Collections.Achievements) do
		local reached = profile.achievements[a.id] or 0
		local value = statValue(profile, a.stat)
		while reached < #a.tiers and value >= a.tiers[reached + 1].count do
			reached += 1
			profile.achievements[a.id] = reached
			local got = AchievementService.grant(player, a.tiers[reached].reward)
			celebrate(player, string.format("%s %s %s!", a.icon, a.name, string.rep("I", reached)), got)
		end
	end
	local species, golden = AchievementService.bookCounts(profile.petBook)
	for i, m in ipairs(Collections.PetMilestones) do
		local key = "m" .. i
		local have = m.kind == "golden" and golden or species
		if not profile.milestones[key] and have >= m.count then
			profile.milestones[key] = true
			local got = AchievementService.grant(player, m.reward)
			celebrate(player, m.kind == "golden" and string.format("✨ %d Golden pets!", m.count) or string.format("📖 %d pet species!", m.count), got)
		end
	end
end

function AchievementService.discoverPet(player: Player, species: string, golden: boolean?)
	local profile = S.PlayerService.getProfile(player)
	if not profile or not Pets.get(species) then
		return
	end
	local before = profile.petBook[species] or 0
	local now = math.max(before, golden and 2 or 1)
	if now ~= before then
		profile.petBook[species] = now
		if before == 0 then
			S.PlayerService.notify(player, "New pet in your 📖 Collection: " .. Pets.get(species).name .. "!", Color3.fromRGB(190, 220, 255), "📖")
		end
		AchievementService.check(player)
	end
end

function AchievementService.giveSkin(player: Player, skinId: string)
	local profile = S.PlayerService.getProfile(player)
	if profile and Skins.get(skinId) then
		profile.skins[skinId] = true
		S.PlayerService.markDirty(player)
	end
end

local function onSetSkin(player: Player, skinId)
	local profile = S.PlayerService.getProfile(player)
	local skin = type(skinId) == "string" and Skins.get(skinId)
	if not profile or not skin then
		return false, "Unknown skin."
	end
	if skinId ~= "Classic" and not profile.skins[skinId] then
		return false, "You haven't unlocked that skin yet. " .. skin.unlock
	end
	if os.clock() - (lastSkinChange[player] or -10) < 3 then
		return false, "Give it a moment..."
	end
	lastSkinChange[player] = os.clock()
	AchievementService.wearSkin(player, skinId)
	return true
end

-- Put a skin on (no unlock check: the admin panel uses this too) and rebuild the dragon where
-- it stands, keeping its health.
function AchievementService.wearSkin(player: Player, skinId: string)
	local profile = S.PlayerService.getProfile(player)
	if not profile or not Skins.get(skinId) then
		return
	end
	profile.skin = skinId
	local character, humanoid, root = S.PlayerService.getCharacter(player)
	if character then
		local ratio = humanoid.Health / math.max(1, humanoid.MaxHealth)
		S.PlayerService.spawn(player, root.CFrame)
		local _, newHumanoid = S.PlayerService.getCharacter(player)
		if newHumanoid then
			newHumanoid.Health = math.max(1, newHumanoid.MaxHealth * ratio)
		end
	end
	S.PlayerService.markDirty(player)
end

local function onSetTitle(player: Player, title)
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(title) ~= "string" then
		return false
	end
	if title ~= "" and not profile.titles[title] then
		return false, "You haven't earned that title yet."
	end
	profile.title = title
	S.PlayerService.recompute(player) -- refreshes the nametag
	return true
end

function AchievementService.init(services)
	S = services
end

function AchievementService.start()
	Remotes.func("SetSkin").OnServerInvoke = onSetSkin
	Remotes.func("SetTitle").OnServerInvoke = onSetTitle
	Players.PlayerRemoving:Connect(function(player)
		lastSkinChange[player] = nil
	end)
	while true do
		task.wait(3)
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(AchievementService.check, player)
			if not ok then
				warn("[AchievementService]", err)
			end
		end
	end
end

return AchievementService
