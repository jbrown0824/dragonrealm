-- Client-side copy of the player's profile and the boss state, with change signals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local State = {
	profile = nil,
	boss = nil,
	changed = Signal.new(),
	bossChanged = Signal.new(),
}

function State.init()
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(snapshot)
		State.profile = snapshot
		State.changed:Fire(snapshot)
	end)
	Remotes.event("BossState").OnClientEvent:Connect(function(data)
		State.boss = data
		State.bossChanged:Fire(data)
	end)
	task.spawn(function()
		local snapshot = Remotes.func("GetProfile"):InvokeServer()
		if snapshot and not State.profile then
			State.profile = snapshot
			State.changed:Fire(snapshot)
		end
	end)
end

function State.findItem(itemId: string)
	local p = State.profile
	if not p then
		return nil
	end
	for _, item in ipairs(p.inventory) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

function State.isEquipped(item): boolean
	local p = State.profile
	return p ~= nil and p.equipped[item.slot] == item.id
end

return State
