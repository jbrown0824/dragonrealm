-- All client <-> server communication goes through these named remotes.
-- The server creates them at startup; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- server -> client
	"ProfileUpdated", -- full profile snapshot for UI
	"VFX", -- visual effect to play
	"DamageNumber",
	"Notify", -- small toast for one player
	"Announce", -- big banner (often to everyone)
	"BossState",
	"OpenShop",
	"OpenQuestDialog",
	"OpenSeedPicker",
	"ZoneChanged",
	"Died",
	-- client -> server
	"CastAbility",
	"SetFlying",
}

local FUNCTIONS = {
	"GetProfile",
	"ChooseClass",
	"SpendTalent",
	"ResetTalents",
	"EquipItem",
	"UnequipItem",
	"BuyItem",
	"SellItem",
	"UpgradeItem",
	"GetShopStock",
	"PlantSeed",
	"AcceptQuest",
	"TurnInQuest",
	"AbandonQuest",
	"BossQueue",
	"LeaveBossFight",
	"Transform",
	"TeleportHome",
}

local Remotes = {}
local folder: Folder

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in ipairs(EVENTS) do
			if not folder:FindFirstChild(name) then
				local r = Instance.new("RemoteEvent")
				r.Name = name
				r.Parent = folder
			end
		end
		for _, name in ipairs(FUNCTIONS) do
			if not folder:FindFirstChild(name) then
				local r = Instance.new("RemoteFunction")
				r.Name = name
				r.Parent = folder
			end
		end
		folder.Parent = ReplicatedStorage
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return folder
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Remotes.init()
	getFolder()
end

return Remotes
