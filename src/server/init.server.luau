-- Dragon Realm server entry point.
-- Builds the world, then initializes and starts every service in Services/.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

Remotes.init()

-- Collision groups: dragons pass through each other and through vikings (so vikings can
-- reach them and players don't shove each other around town).
PhysicsService:RegisterCollisionGroup("Dragons")
PhysicsService:RegisterCollisionGroup("Enemies")
PhysicsService:RegisterCollisionGroup("Loot")
PhysicsService:CollisionGroupSetCollidable("Dragons", "Dragons", false)
PhysicsService:CollisionGroupSetCollidable("Dragons", "Enemies", false)
PhysicsService:CollisionGroupSetCollidable("Loot", "Dragons", false)
PhysicsService:CollisionGroupSetCollidable("Loot", "Enemies", false)
PhysicsService:CollisionGroupSetCollidable("Loot", "Loot", false)

local WorldBuilder = require(script.World.WorldBuilder)
WorldBuilder.build()

local ORDER = {
	"DataService",
	"PlayerService",
	"CombatService",
	"EnemyService",
	"LootService",
	"ShopService",
	"FarmService",
	"QuestService",
	"PvPService",
	"BossService",
	"ZoneService",
	"SurvivalService",
	"WildlifeService",
	"FishingService",
	"PotionService",
	"PetService",
	"TrainingService",
	"CampService",
	"CivilianService",
	"AdminService",
	"TutorialService",
}

local services = {}
for _, name in ipairs(ORDER) do
	services[name] = require(script.Services:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.init then
		service.init(services)
	end
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.start then
		task.spawn(service.start)
	end
end

print("[Dragon Realm] Server ready")
