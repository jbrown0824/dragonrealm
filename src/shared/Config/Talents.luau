-- Skill trees, WotLK style. Each dragon type has three branches. Each branch has five tiers;
-- tier N needs (N-1) * Game.TALENT_POINTS_PER_TIER points already spent in that branch.
-- You earn one point per level after level 1 (29 points at the cap) but each tree holds
-- 63 ranks, so you can finish one capstone and dabble in one more branch, never all three.
--
-- effects: stat bonus PER RANK (see TalentUtil.STAT_LABELS for every stat key)
-- ability: an ability id from Config/Abilities unlocked by this talent
-- mods:    per-rank tweaks to one ability: dmgPct, cdFlat, radiusPct, durFlat, stunFlat, healPct
-- requires: key of another talent in the same branch that must be at max rank first
-- col: 1 or 2 (left/right). Capstones sit in the middle (col 1.5).

local function T(key, name, tier, col, maxRank, effects, extra)
	local t = {
		key = key,
		name = name,
		tier = tier,
		col = col,
		maxRank = maxRank,
		effects = effects or {},
	}
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return t
end

local Talents = {}

Talents.Shadowstalker = {
	{
		id = "Assassination", name = "Assassination", icon = "🗡️",
		desc = "Critical hits and burst damage.",
		talents = {
			T("KeenEyes", "Keen Eyes", 1, 1, 3, { critChance = 3 }),
			T("RazorTalons", "Razor Talons", 1, 2, 3, { attackPct = 5 }),
			T("DeadlyPrecision", "Deadly Precision", 2, 1, 3, { critDamage = 20 }),
			T("SwiftStrikes", "Swift Strikes", 2, 2, 2, { cooldownPct = 6 }),
			T("ShadowPounce", "Shadow Pounce", 3, 1, 1, {}, { ability = "ShadowPounce" }),
			T("Opportunist", "Opportunist", 3, 2, 3, { executePct = 12 }),
			T("PounceMastery", "Pounce Mastery", 4, 1, 2, {}, { requires = "ShadowPounce", mods = { ShadowPounce = { dmgPct = 25, cdFlat = -1 } } }),
			T("Lethality", "Lethality", 4, 2, 3, { abilityPct = 10 }),
			T("DeathMark", "Death Mark", 5, 1.5, 1, {}, { ability = "DeathMark" }),
		},
	},
	{
		id = "Umbra", name = "Umbra", icon = "🌘",
		desc = "Stealth, dodging and slipping away.",
		talents = {
			T("SoftWings", "Soft Wings", 1, 1, 3, { speedPct = 5 }),
			T("DuskScales", "Dusk Scales", 1, 2, 3, { dodge = 4 }),
			T("NightGlider", "Night Glider", 2, 1, 3, { staminaPct = 15 }),
			T("HiddenHoard", "Hidden Hoard", 2, 2, 2, { goldPct = 12 }),
			T("Vanish", "Vanish", 3, 1, 1, {}, { ability = "Vanish" }),
			T("Ambusher", "Ambusher", 3, 2, 3, { critChance = 4 }),
			T("LingeringShadows", "Lingering Shadows", 4, 1, 2, {}, { requires = "Vanish", mods = { Vanish = { durFlat = 2, cdFlat = -3 } } }),
			T("PhantomHide", "Phantom Hide", 4, 2, 3, { defensePct = 10, dodge = 2 }),
			T("Eclipse", "Eclipse", 5, 1.5, 1, {}, { ability = "Eclipse" }),
		},
	},
	{
		id = "Nightmare", name = "Nightmare", icon = "😈",
		desc = "Life-draining shadowflame and fear.",
		talents = {
			T("DarkHunger", "Dark Hunger", 1, 1, 3, { lifesteal = 3 }),
			T("DreadScales", "Dread Scales", 1, 2, 3, { healthPct = 6 }),
			T("Shadowflame", "Shadowflame", 2, 1, 3, { breathPct = 12 }),
			T("Terror", "Terror", 2, 2, 2, { slowPct = 18 }),
			T("NightmareBurst", "Nightmare Burst", 3, 1, 1, {}, { ability = "NightmareBurst" }),
			T("SoulSiphon", "Soul Siphon", 3, 2, 3, { lifesteal = 3 }),
			T("BurstMastery", "Burst Mastery", 4, 1, 2, {}, { requires = "NightmareBurst", mods = { NightmareBurst = { dmgPct = 20, radiusPct = 20 } } }),
			T("EndlessNight", "Endless Night", 4, 2, 3, { burnPct = 15 }),
			T("UmbralDevour", "Umbral Devour", 5, 1.5, 1, {}, { ability = "UmbralDevour" }),
		},
	},
}

Talents.Stormwing = {
	{
		id = "Tempest", name = "Tempest", icon = "⚡",
		desc = "Raw lightning damage.",
		talents = {
			T("ChargedScales", "Charged Scales", 1, 1, 3, { attackPct = 5 }),
			T("StaticSpark", "Static Spark", 1, 2, 3, { critChance = 3 }),
			T("Overcharge", "Overcharge", 2, 1, 3, { breathPct = 12 }),
			T("Conductive", "Conductive", 2, 2, 2, { critDamage = 20 }),
			T("Thunderclap", "Thunderclap", 3, 1, 1, {}, { ability = "Thunderclap" }),
			T("Voltage", "Voltage", 3, 2, 3, { abilityPct = 8 }),
			T("RollingThunder", "Rolling Thunder", 4, 1, 2, {}, { requires = "Thunderclap", mods = { Thunderclap = { dmgPct = 25, radiusPct = 15 } } }),
			T("StormSurge", "Storm Surge", 4, 2, 3, { cooldownPct = 6 }),
			T("LightningStorm", "Lightning Storm", 5, 1.5, 1, {}, { ability = "LightningStorm" }),
		},
	},
	{
		id = "Windrider", name = "Windrider", icon = "🍃",
		desc = "Speed, flight and evasion.",
		talents = {
			T("SwiftWings", "Swift Wings", 1, 1, 3, { speedPct = 6 }),
			T("LightBones", "Light Bones", 1, 2, 3, { dodge = 4 }),
			T("EndlessSky", "Endless Sky", 2, 1, 3, { staminaPct = 20 }),
			T("Tailwind", "Tailwind", 2, 2, 2, { speedPct = 5, xpPct = 8 }),
			T("GaleDash", "Gale Dash", 3, 1, 1, {}, { ability = "GaleDash" }),
			T("Evasion", "Evasion", 3, 2, 3, { dodge = 5 }),
			T("GaleMastery", "Gale Mastery", 4, 1, 2, {}, { requires = "GaleDash", mods = { GaleDash = { dmgPct = 30, cdFlat = -1 } } }),
			T("AerialAce", "Aerial Ace", 4, 2, 3, { attackPct = 6 }),
			T("Cyclone", "Cyclone", 5, 1.5, 1, {}, { ability = "Cyclone" }),
		},
	},
	{
		id = "Skyhunter", name = "Skyhunter", icon = "🎯",
		desc = "Long-range bolts and boss hunting.",
		talents = {
			T("EagleEye", "Eagle Eye", 1, 1, 3, { critChance = 3 }),
			T("SkyScales", "Sky Scales", 1, 2, 3, { healthPct = 6 }),
			T("BallLightning", "Ball Lightning", 2, 1, 3, { fireballPct = 15 }),
			T("QuickDraw", "Quick Draw", 2, 2, 2, {}, { mods = { Fireball = { cdFlat = -0.5 } } }),
			T("ArcVolley", "Arc Volley", 3, 1, 1, {}, { ability = "ArcVolley" }),
			T("Marksdragon", "Marksdragon", 3, 2, 3, { critDamage = 20 }),
			T("PlasmaCore", "Plasma Core", 4, 1, 2, {}, { requires = "ArcVolley", mods = { ArcVolley = { dmgPct = 20, radiusPct = 20 }, Fireball = { dmgPct = 10 } } }),
			T("HuntersMark", "Hunter's Mark", 4, 2, 3, { bossPct = 10 }),
			T("StormBarrage", "Storm Barrage", 5, 1.5, 1, {}, { ability = "StormBarrage" }),
		},
	},
}

Talents.Behemoth = {
	{
		id = "Juggernaut", name = "Juggernaut", icon = "🛡️",
		desc = "Unstoppable, unkillable tank.",
		talents = {
			T("ThickHide", "Thick Hide", 1, 1, 3, { defensePct = 8 }),
			T("MountainHeart", "Mountain Heart", 1, 2, 3, { healthPct = 7 }),
			T("SpikedScales", "Spiked Scales", 2, 1, 3, { thorns = 10 }),
			T("Regrowth", "Regrowth", 2, 2, 2, { regen = 0.6 }),
			T("IronScales", "Iron Scales", 3, 1, 1, {}, { ability = "IronScales" }),
			T("Unbreakable", "Unbreakable", 3, 2, 3, { healthPct = 7 }),
			T("IronMastery", "Iron Mastery", 4, 1, 2, {}, { requires = "IronScales", mods = { IronScales = { durFlat = 2, cdFlat = -3 } } }),
			T("Bulwark", "Bulwark", 4, 2, 3, { defensePct = 10 }),
			T("UndyingTitan", "Undying Titan", 5, 1.5, 1, { cheatDeath = 1, healthPct = 5 }, {
				desc = "Once every 90 seconds, a killing blow leaves you at 30% health instead. +5% Max Health.",
			}),
		},
	},
	{
		id = "Magma", name = "Magma", icon = "🌋",
		desc = "Molten fire and burning ground.",
		talents = {
			T("MoltenCore", "Molten Core", 1, 1, 3, { attackPct = 5 }),
			T("SearingBreath", "Searing Breath", 1, 2, 3, { breathPct = 10 }),
			T("LavaVeins", "Lava Veins", 2, 1, 3, { burnPct = 18 }),
			T("MagmaFist", "Magma Fist", 2, 2, 2, { fireballPct = 16 }),
			T("Eruption", "Eruption", 3, 1, 1, {}, { ability = "Eruption" }),
			T("HeatWave", "Heat Wave", 3, 2, 3, { abilityPct = 8 }),
			T("EruptionMastery", "Eruption Mastery", 4, 1, 2, {}, { requires = "Eruption", mods = { Eruption = { dmgPct = 25, radiusPct = 15 } } }),
			T("ScorchedEarth", "Scorched Earth", 4, 2, 3, { critChance = 4 }),
			T("Meteor", "Meteor", 5, 1.5, 1, {}, { ability = "Meteor" }),
		},
	},
	{
		id = "Warlord", name = "Warlord", icon = "⚒️",
		desc = "Brutal slams and rampages.",
		talents = {
			T("BruteForce", "Brute Force", 1, 1, 3, { attackPct = 5 }),
			T("HeavyTread", "Heavy Tread", 1, 2, 3, { healthPct = 6 }),
			T("CrushingBlows", "Crushing Blows", 2, 1, 3, { critDamage = 25 }),
			T("Momentum", "Momentum", 2, 2, 2, { speedPct = 7 }),
			T("GroundSlam", "Ground Slam", 3, 1, 1, {}, { ability = "GroundSlam" }),
			T("Bloodlust", "Bloodlust", 3, 2, 3, { lifesteal = 3 }),
			T("Earthshaker", "Earthshaker", 4, 1, 2, {}, { requires = "GroundSlam", mods = { GroundSlam = { dmgPct = 25, stunFlat = 0.5 } } }),
			T("TitansMight", "Titan's Might", 4, 2, 3, { abilityPct = 10 }),
			T("Rampage", "Rampage", 5, 1.5, 1, {}, { ability = "Rampage" }),
		},
	},
}

Talents.Frostwyrm = {
	{
		id = "Glacier", name = "Glacier", icon = "🏔️",
		desc = "Icy armor and crowd control.",
		talents = {
			T("FrozenScales", "Frozen Scales", 1, 1, 3, { defensePct = 8 }),
			T("ColdBlood", "Cold Blood", 1, 2, 3, { healthPct = 6 }),
			T("ChillingBreath", "Chilling Breath", 2, 1, 3, { slowPct = 12 }),
			T("IceArmor", "Ice Armor", 2, 2, 2, { thorns = 12 }),
			T("FrostNova", "Frost Nova", 3, 1, 1, {}, { ability = "FrostNova" }),
			T("Permafrost", "Permafrost", 3, 2, 3, { defensePct = 7 }),
			T("DeepFreeze", "Deep Freeze", 4, 1, 2, {}, { requires = "FrostNova", mods = { FrostNova = { stunFlat = 0.5, cdFlat = -2 } } }),
			T("GlacialHeart", "Glacial Heart", 4, 2, 3, { regen = 0.5 }),
			T("IceFortress", "Ice Fortress", 5, 1.5, 1, {}, { ability = "IceFortress" }),
		},
	},
	{
		id = "Blizzard", name = "Blizzard", icon = "🌨️",
		desc = "Storms of ice over large areas.",
		talents = {
			T("Frostfire", "Frostfire", 1, 1, 3, { breathPct = 10 }),
			T("WintersGrasp", "Winter's Grasp", 1, 2, 3, { attackPct = 5 }),
			T("Hailstones", "Hailstones", 2, 1, 3, { fireballPct = 15 }),
			T("Snowdrift", "Snowdrift", 2, 2, 2, { abilityPct = 8 }),
			T("IcicleRain", "Icicle Rain", 3, 1, 1, {}, { ability = "IcicleRain" }),
			T("BitingCold", "Biting Cold", 3, 2, 3, { critChance = 3 }),
			T("IcicleMastery", "Icicle Mastery", 4, 1, 2, {}, { requires = "IcicleRain", mods = { IcicleRain = { dmgPct = 20, radiusPct = 20 } } }),
			T("ArcticWinds", "Arctic Winds", 4, 2, 3, { cooldownPct = 6 }),
			T("Blizzard", "Blizzard", 5, 1.5, 1, {}, { ability = "Blizzard" }),
		},
	},
	{
		id = "Frostfang", name = "Frostfang", icon = "🐺",
		desc = "Shattering single-target strikes.",
		talents = {
			T("IceFangs", "Ice Fangs", 1, 1, 3, { critChance = 3 }),
			T("SharpFrost", "Sharp Frost", 1, 2, 3, { critDamage = 15 }),
			T("Shatter", "Shatter", 2, 1, 3, { executePct = 15 }),
			T("ColdPrecision", "Cold Precision", 2, 2, 2, { attackPct = 6 }),
			T("GlacialLance", "Glacial Lance", 3, 1, 1, {}, { ability = "GlacialLance" }),
			T("GiantHunter", "Giant Hunter", 3, 2, 3, { bossPct = 8 }),
			T("LanceMastery", "Lance Mastery", 4, 1, 2, {}, { requires = "GlacialLance", mods = { GlacialLance = { dmgPct = 25, cdFlat = -1 } } }),
			T("FrozenHeart", "Frozen Heart", 4, 2, 3, { attackPct = 5 }),
			T("AbsoluteZero", "Absolute Zero", 5, 1.5, 1, {}, { ability = "AbsoluteZero" }),
		},
	},
}

Talents.Venomspine = {
	{
		id = "Plague", name = "Plague", icon = "🦠",
		desc = "Poison that keeps on hurting.",
		talents = {
			T("ToxicGlands", "Toxic Glands", 1, 1, 3, { poisonPct = 15 }),
			T("RottingBreath", "Rotting Breath", 1, 2, 3, { breathPct = 10 }),
			T("Virulence", "Virulence", 2, 1, 3, { poisonPct = 15 }),
			T("Contagion", "Contagion", 2, 2, 2, { abilityPct = 8 }),
			T("PlagueCloud", "Plague Cloud", 3, 1, 1, {}, { ability = "PlagueCloud" }),
			T("Festering", "Festering", 3, 2, 3, { attackPct = 4 }),
			T("CloudMastery", "Cloud Mastery", 4, 1, 2, {}, { requires = "PlagueCloud", mods = { PlagueCloud = { dmgPct = 25, radiusPct = 20 } } }),
			T("Pestilence", "Pestilence", 4, 2, 3, { cooldownPct = 6 }),
			T("Epidemic", "Epidemic", 5, 1.5, 1, {}, { ability = "Epidemic" }),
		},
	},
	{
		id = "Toxin", name = "Toxin", icon = "🐍",
		desc = "Draining life to survive anything.",
		talents = {
			T("LeechingFangs", "Leeching Fangs", 1, 1, 3, { lifesteal = 3 }),
			T("ScaledHide", "Scaled Hide", 1, 2, 3, { healthPct = 6 }),
			T("VenomBlood", "Venom Blood", 2, 1, 3, { thorns = 10 }),
			T("Resilience", "Resilience", 2, 2, 2, { defensePct = 8 }),
			T("VenomFeast", "Venom Feast", 3, 1, 1, {}, { ability = "VenomFeast" }),
			T("Antivenom", "Antivenom", 3, 2, 3, { regen = 0.5 }),
			T("FeastMastery", "Feast Mastery", 4, 1, 2, {}, { requires = "VenomFeast", mods = { VenomFeast = { healPct = 10, cdFlat = -3 } } }),
			T("HydraScales", "Hydra Scales", 4, 2, 3, { healthPct = 7 }),
			T("HydrasBlood", "Hydra's Blood", 5, 1.5, 1, { lifesteal = 6, regen = 1.0, healthPct = 10 }),
		},
	},
	{
		id = "Corrosion", name = "Corrosion", icon = "🧪",
		desc = "Acid that melts armor and bosses.",
		talents = {
			T("AcidSpit", "Acid Spit", 1, 1, 3, { fireballPct = 12 }),
			T("Corrosive", "Corrosive", 1, 2, 3, { attackPct = 5 }),
			T("MeltArmor", "Melt Armor", 2, 1, 3, { critChance = 3 }),
			T("Caustic", "Caustic", 2, 2, 2, { critDamage = 20 }),
			T("AcidWave", "Acid Wave", 3, 1, 1, {}, { ability = "AcidWave" }),
			T("Dissolve", "Dissolve", 3, 2, 3, { executePct = 12 }),
			T("WaveMastery", "Wave Mastery", 4, 1, 2, {}, { requires = "AcidWave", mods = { AcidWave = { dmgPct = 25, cdFlat = -1.5 } } }),
			T("Liquefy", "Liquefy", 4, 2, 3, { bossPct = 10 }),
			T("ToxicDeluge", "Toxic Deluge", 5, 1.5, 1, {}, { ability = "ToxicDeluge" }),
		},
	},
}

-- Build a flat lookup: Talents.byId["Shadowstalker.KeenEyes"] = { talent, branchIndex, classId }
Talents.byId = {}
for classId, branches in pairs(Talents) do
	if type(branches) == "table" and classId ~= "byId" then
		for branchIndex, branch in ipairs(branches) do
			for _, talent in ipairs(branch.talents) do
				talent.id = classId .. "." .. talent.key
				talent.branch = branchIndex
				talent.classId = classId
				Talents.byId[talent.id] = talent
			end
		end
	end
end

function Talents.forClass(classId: string)
	return Talents[classId]
end

return Talents
