-- Robux purchases (Config/Store): game passes (2x XP, 2x Gold, and the handy ones: 2x Flight
-- Time, Never Hungry, Wayfinder) and developer products (Starter Pack, Gold Rush, gold packs, the
-- Mythic and Secret Eggs, treats, shop restock). Other services ask about passes here
-- (xpMultiplier, goldMultiplier, flightMultiplier, hasPass).
--
-- Gold Rush is a boost measured in minutes of play: profile.goldRushLeft counts down only while
-- the player is in the game, so it can't run out while they're away.
--
-- Developer products are granted in ProcessReceipt. Every receipt id is remembered on the
-- profile and the profile is saved before we tell Roblox the purchase went through, so a
-- purchase is never granted twice and never lost (Roblox retries until we return
-- PurchaseGranted, even on a later visit).
--
-- Studio testing: items whose id is still 0 can be "bought" for free in Studio only
-- (StudioPurchase). Pass ownership is checked with UserOwnsGamePassAsync when you join and
-- updated when you buy one.
--
-- Paid random items: when a player joins we ask PolicyService whether they may buy them
-- (ArePaidRandomItemsRestricted) and set the player attribute `PaidRandomItems` to true only
-- when they may. Until the answer comes, or if the call keeps failing, the answer is no. The
-- Store hides every `paidRandom` item (Config/Store) from those players and StudioPurchase
-- refuses them.

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Store = require(Shared.Config.Store)
local Items = require(Shared.Config.Items)
local Pets = require(Shared.Config.Pets)
local Skins = require(Shared.Config.Skins)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local StoreService = {}
local S

local owned = {} -- [Player] = { [passId] = true } (from Roblox; profile.passes adds Studio grants)
local MAX_RECEIPTS = 60

---------------------------------------------------------------- passes

function StoreService.ownedPasses(player: Player)
	local profile = S.PlayerService.getProfile(player)
	local out = {}
	for id in pairs(owned[player] or {}) do
		out[id] = true
	end
	for id in pairs(profile and profile.passes or {}) do
		out[id] = true
	end
	return out
end

function StoreService.hasPass(player: Player, passId: string): boolean
	return StoreService.ownedPasses(player)[passId] == true
end

function StoreService.xpMultiplier(player: Player): number
	return StoreService.hasPass(player, "DoubleXP") and 2 or 1
end

-- 2x Flight Time: flight stamina multiplier (PlayerService.recompute applies it).
function StoreService.flightMultiplier(player: Player): number
	return StoreService.hasPass(player, "DoubleFlight") and Store.FLIGHT_MULT or 1
end

function StoreService.goldMultiplier(player: Player): number
	local profile = S.PlayerService.getProfile(player)
	local rush = profile and (profile.goldRushLeft or 0) > 0 and Store.GOLD_RUSH_BONUS or 0
	return (StoreService.hasPass(player, "DoubleGold") and 2 or 1) + rush
end

-- When the player's Gold Rush ends (server time), for the HUD's countdown. nil if none.
function StoreService.goldRushEnds(player: Player): number?
	local profile = S.PlayerService.getProfile(player)
	local left = profile and profile.goldRushLeft or 0
	return left > 0 and workspace:GetServerTimeNow() + left or nil
end

-- Count down every online player's Gold Rush.
local function tickGoldRush(dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = S.PlayerService.getProfile(player)
		if profile and (profile.goldRushLeft or 0) > 0 then
			profile.goldRushLeft = math.max(0, profile.goldRushLeft - dt)
			if profile.goldRushLeft == 0 then
				S.PlayerService.notify(player, "Your Gold Rush is over. Thanks for playing!", Color3.fromRGB(255, 210, 90), "💸")
				S.PlayerService.markDirty(player)
			end
		end
	end
end

local function checkPasses(player: Player)
	owned[player] = owned[player] or {}
	for passId, pass in pairs(Store.Passes) do
		if pass.assetId ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.assetId)
			end)
			if ok and has then
				owned[player][passId] = true
			end
		end
	end
	S.PlayerService.recompute(player)
	S.PlayerService.markDirty(player)
end

local function passGranted(player: Player, passId: string)
	local pass = Store.Passes[passId]
	owned[player] = owned[player] or {}
	owned[player][passId] = true
	S.PlayerService.notify(player, string.format("Thank you! %s %s is now active.", pass.icon, pass.name), Color3.fromRGB(120, 230, 140), "💎")
	S.PlayerService.recompute(player)
	S.PlayerService.markDirty(player)
end

---------------------------------------------------------------- paid random items

-- May this player buy the `paidRandom` items? (No until PolicyService says yes.)
function StoreService.paidRandomAllowed(player: Player): boolean
	return player:GetAttribute("PaidRandomItems") == true
end

function StoreService.checkPolicy(player: Player)
	for attempt = 1, 3 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			player:SetAttribute("PaidRandomItems", info.ArePaidRandomItemsRestricted == false)
			return
		end
		task.wait(2 * attempt)
	end
	warn("[StoreService] Couldn't read the policy for", player.Name, "- paid random items stay off")
	player:SetAttribute("PaidRandomItems", false)
end

---------------------------------------------------------------- products

-- Gold for each pack at this player's strength (shown in the Store).
function StoreService.goldPackAmounts(player: Player)
	local profile = S.PlayerService.getProfile(player)
	local out = {}
	for key, product in pairs(Store.Products) do
		if product.goldMinutes and profile then
			out[key] = Store.goldFor(product.goldMinutes, profile.level, profile.paragon)
		end
	end
	return out
end

-- An Epic piece for the slot where your gear is weakest.
local function epicGear(player: Player, profile)
	local worst, worstScore = Items.Slots[1], math.huge
	for _, slot in ipairs(Items.Slots) do
		local id = profile.equipped[slot]
		local item = id and S.PlayerService.findItem(profile, id)
		local score = item and ItemUtil.score(item) or 0
		if score < worstScore then
			worst, worstScore = slot, score
		end
	end
	local item = ItemUtil.new(worst, profile.level, "Epic")
	S.PlayerService.addItem(player, item, true)
	return item
end

-- Give a product's contents. Returns a short description.
function StoreService.grantProduct(player: Player, key: string): string
	local product = Store.Products[key]
	local profile = S.PlayerService.getProfile(player)
	local parts = {}
	if product.goldMinutes then
		local gold = Store.goldFor(product.goldMinutes, profile.level, profile.paragon)
		S.PlayerService.addGold(player, gold)
		table.insert(parts, "+" .. Util.formatNumber(gold) .. " gold")
	end
	for eggId, n in pairs(product.eggs or {}) do
		profile.eggs[eggId] = (profile.eggs[eggId] or 0) + n
		table.insert(parts, string.format("%s %s%s", Pets.Eggs[eggId].icon, Pets.Eggs[eggId].name, n > 1 and (" x" .. n) or ""))
	end
	if product.treats then
		profile.treats = (profile.treats or 0) + product.treats
		table.insert(parts, "+" .. product.treats .. " 🍬 treats")
	end
	if product.epicGear then
		local item = epicGear(player, profile)
		table.insert(parts, "an Epic " .. ItemUtil.displayName(item))
	end
	if product.skin then
		S.AchievementService.giveSkin(player, product.skin)
		table.insert(parts, "the " .. Skins.get(product.skin).name .. " skin")
	end
	if product.goldRushMinutes then
		local cap = Store.GOLD_RUSH_MAX_MINUTES * 60
		profile.goldRushLeft = math.min(cap, (profile.goldRushLeft or 0) + product.goldRushMinutes * 60)
		table.insert(parts, string.format("+100%% gold for %d minutes of play", math.floor(profile.goldRushLeft / 60 + 0.5)))
	end
	if product.restock then
		S.StockService.restockNow(player)
		table.insert(parts, "fresh shop stock")
	end
	if key == "StarterPack" then
		profile.starterPack = true
	end
	S.PlayerService.markDirty(player)
	local text = table.concat(parts, ", ")
	S.PlayerService.notify(player, string.format("Thank you! %s %s: %s", product.icon, product.name, text), Color3.fromRGB(120, 230, 140), "💎")
	Remotes.event("Announce"):FireClient(player, { title = product.icon .. " " .. product.name:upper() .. "!", text = text, color = Color3.fromRGB(120, 230, 140), duration = 4 })
	return text
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and S.PlayerService.getProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they're back
	end
	local key = Store.productByAssetId(receipt.ProductId)
	if not key then
		warn("[StoreService] Unknown developer product", receipt.ProductId, "- add its id to Config/Store")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(profile.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, err = pcall(StoreService.grantProduct, player, key)
	if not ok then
		warn("[StoreService] Granting", key, "failed:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(profile.receipts, receipt.PurchaseId)
	while #profile.receipts > MAX_RECEIPTS do
		table.remove(profile.receipts, 1)
	end
	S.DataService.save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio only: buy an item that has no id yet, for free, to test it.
local function onStudioPurchase(player: Player, kind, key)
	if not RunService:IsStudio() then
		return false, "This item is coming soon!"
	end
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(key) ~= "string" then
		return false, "Unknown item."
	end
	if Store.isPaidRandom(kind, key) and not StoreService.paidRandomAllowed(player) then
		return false, "That item isn't available where you live."
	end
	if kind == "pass" and Store.Passes[key] then
		profile.passes[key] = true
		passGranted(player, key)
		return true, "(Studio test) " .. Store.Passes[key].name .. " unlocked."
	elseif kind == "product" and Store.Products[key] then
		if Store.Products[key].once and profile.starterPack then
			return false, "You already have the Starter Pack."
		end
		return true, "(Studio test) " .. StoreService.grantProduct(player, key)
	end
	return false, "Unknown item."
end

function StoreService.init(services)
	S = services
end

function StoreService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, assetId, purchased)
		if not purchased then
			return
		end
		for passId, pass in pairs(Store.Passes) do
			if pass.assetId == assetId then
				passGranted(player, passId)
			end
		end
	end)
	Remotes.func("StudioPurchase").OnServerInvoke = onStudioPurchase
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPasses, player)
		task.spawn(StoreService.checkPolicy, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(checkPasses, player)
		task.spawn(StoreService.checkPolicy, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	local last = workspace:GetServerTimeNow()
	while true do
		task.wait(5)
		local now = workspace:GetServerTimeNow()
		tickGoldRush(now - last)
		last = now
	end
end

return StoreService
