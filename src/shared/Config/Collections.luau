-- The 📖 Collection: the pet book (every nano dragon species you've hatched, and which ones
-- you've made Golden) with milestone rewards, and achievements with three tiers each.
-- Rewards are granted automatically the moment you reach them (AchievementService).
--
-- reward = { gold, treats, eggs = { [eggId] = n }, skin = skinId, title = text }
-- `stat` is a profile field (or "paragon" / "level").
-- Each dungeon also gives a title the first time you clear it (Config/Dungeons `title`).

local Dungeons = require(script.Parent.Dungeons)

local Collections = {}

-- Pet book milestones. `kind`: "species" = different species hatched (Secret ones count too),
-- "golden" = different species you've made Golden.
Collections.PetMilestones = {
	{ kind = "species", count = 3, reward = { treats = 10, gold = 1000 } },
	{ kind = "species", count = 6, reward = { treats = 15, eggs = { EmberEgg = 2 } } },
	{ kind = "species", count = 10, reward = { treats = 25, eggs = { StormEgg = 1 } } },
	{ kind = "species", count = 15, reward = { eggs = { MythicEgg = 1 }, skin = "Starlight", title = "Pet Collector" } },
	{ kind = "golden", count = 1, reward = { treats = 15 } },
	{ kind = "golden", count = 3, reward = { treats = 25, skin = "Gilded" } },
	{ kind = "golden", count = 8, reward = { eggs = { MythicEgg = 2 }, title = "Golden Keeper" } },
	{ kind = "golden", count = 15, reward = { skin = "Sunforged", title = "Midas Wing" } },
}

local function tiers(t1, t2, t3, skin, title)
	return {
		{ count = t1[1], reward = { gold = t1[2], treats = 5 } },
		{ count = t2[1], reward = { gold = t2[2], treats = 15, eggs = { StormEgg = 1 } } },
		{ count = t3[1], reward = { gold = t3[2], eggs = { MythicEgg = 1 }, skin = skin, title = title } },
	}
end

Collections.Achievements = {
	{ id = "Vikings", name = "Viking Slayer", icon = "⚔️", stat = "vikingKills", desc = "Defeat vikings",
		tiers = tiers({ 50, 500 }, { 500, 2500 }, { 2500, 10000 }, "Obsidian", "Viking Bane") },
	{ id = "Champions", name = "Champion Hunter", icon = "💀", stat = "championKills", desc = "Defeat camp champions",
		tiers = tiers({ 1, 500 }, { 10, 2500 }, { 50, 10000 }, "Bloodmoon", "Champion Slayer") },
	{ id = "Bosses", name = "Boss Slayer", icon = "👑", stat = "bossKills", desc = "Defeat world bosses",
		tiers = tiers({ 1, 1000 }, { 10, 5000 }, { 50, 20000 }, "Royal", "Boss Breaker") },
	{ id = "Flowers", name = "Green Claws", icon = "🌸", stat = "flowersHarvested", desc = "Harvest full-grown flowers",
		tiers = tiers({ 25, 500 }, { 250, 2500 }, { 1000, 10000 }, "Verdant", "Master Gardener") },
	{ id = "Fish", name = "Angler", icon = "🎣", stat = "fishCaught", desc = "Catch fish",
		tiers = tiers({ 10, 300 }, { 100, 2000 }, { 500, 8000 }, "Frostbite", "Master Angler") },
	{ id = "Hunter", name = "Wild Hunter", icon = "🦌", stat = "animalsHunted", desc = "Hunt wild animals",
		tiers = tiers({ 25, 300 }, { 250, 2000 }, { 1000, 8000 }, "Sandstorm", "Apex Hunter") },
	{ id = "Chests", name = "Treasure Hunter", icon = "💰", stat = "chestsOpened", desc = "Loot camp chests",
		tiers = tiers({ 5, 500 }, { 50, 2500 }, { 200, 10000 }, nil, "Hoard Keeper") },
	{ id = "Defender", name = "Town Defender", icon = "🛡️", stat = "raidsRepelled", desc = "Repel night raids on Dragon Town",
		tiers = tiers({ 1, 800 }, { 10, 4000 }, { 40, 12000 }, nil, "Town Guardian") },
	{ id = "Sharpshooter", name = "Sharpshooter", icon = "🎯", stat = "rangeLevel", desc = "Clear target practice levels",
		tiers = tiers({ 3, 300 }, { 6, 1500 }, { 10, 5000 }, nil, "Dead Eye") },
	{ id = "Glory", name = "Battle Legend", icon = "🏆", stat = "glory", desc = "Earn Glory in the Battle Zone",
		tiers = tiers({ 100, 500 }, { 1000, 2500 }, { 5000, 10000 }, nil, "Legend of Glory") },
	{ id = "Dungeons", name = "Dungeon Delver", icon = "🏰", stat = "dungeonClears", desc = "Clear dungeons (beat the boss at the end)",
		tiers = tiers({ 1, 1000 }, { 10, 5000 }, { 50, 20000 }, nil, "Dungeon Delver") },
	{ id = "Level", name = "Growing Up", icon = "🐉", stat = "level", desc = "Reach dragon levels",
		tiers = tiers({ 10, 500 }, { 20, 2500 }, { 30, 5000 }, nil, "Elder Dragon") },
	{ id = "Paragon", name = "Paragon", icon = "💫", stat = "paragon", desc = "Reach Paragon levels after level 30",
		tiers = tiers({ 1, 2000 }, { 25, 10000 }, { 100, 50000 }, "Voidborn", "Paragon of Dragons") },
}

function Collections.getAchievement(id: string)
	for _, a in ipairs(Collections.Achievements) do
		if a.id == id then
			return a
		end
	end
	return nil
end

-- Every title there is (for the title picker), in the order they appear above.
function Collections.allTitles(): { string }
	local list = {}
	for _, m in ipairs(Collections.PetMilestones) do
		if m.reward.title then
			table.insert(list, m.reward.title)
		end
	end
	for _, a in ipairs(Collections.Achievements) do
		for _, t in ipairs(a.tiers) do
			if t.reward.title then
				table.insert(list, t.reward.title)
			end
		end
	end
	for _, id in ipairs(Dungeons.Order) do
		table.insert(list, Dungeons.List[id].title)
	end
	return list
end

return Collections
