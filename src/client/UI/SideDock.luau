-- Info boxes that pop up big at the top of the screen when something starts, then glide over to
-- the side once you get going, the way the tour does: the world boss banner and the night raid
-- bar (with its water chip under it). Docked, they stack down the left column under the player
-- card and the offer button on computers (below the docked tour or the dungeon pill when those
-- are up, and the toasts move down below them), or up the bottom-left stack on phones (right of
-- the menu grid, clear of the thumb buttons). A minimized box's pill sits in its spot.
--
-- Owners say what they want shown (`show(entry, "box" | "pill" | nil)`) and SideDock shows and
-- places it. `pop(entry)` marks something new: the box shows up top for at least MIN_CENTER
-- seconds, then docks once the dragon has moved DOCK_MOVE studs, or after DOCK_AFTER seconds
-- anyway. On a phone the stack only grows up to the offer button under the player card: a box
-- that doesn't fit shows as its pill, and the one opened (or popped) last gets the room.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SideDock = {}
local App

SideDock.WIDTH = 340 -- (the tour panel's width)
SideDock.MIN_CENTER = 2.5 -- seconds a box stays up top, even if you're already moving
SideDock.DOCK_AFTER = 8 -- seconds before it moves aside anyway
SideDock.DOCK_MOVE = 6 -- studs of moving (or flying up) that count as getting going

local CENTER_ZOOM = 1.15 -- computers: up top a box is shown bigger (clear of the big announcements under it)
local PHONE_CENTER = 0.34 -- phones: how far down the screen a box pops up (under the bars)
local DESK_X, DESK_TOP = 12, 180 -- under the player card and the offer button
local PHONE_X, PHONE_BOTTOM = 130, 8
local GAP = 6
local GLIDE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local SHUFFLE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local entries = {} -- top to bottom on computers (bottom up on phones)
local placed = {} -- [GuiObject] = { key, centered } where it was last put
local phoneStack = 0 -- height of the bottom-left stack on phones (DungeonHUD sits above it)

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- Register a box. opts.pill: its minimized pill. opts.follow: an entry it always sits under (and
-- pops and docks with).
function SideDock.add(frame: GuiObject, opts)
	opts = opts or {}
	local zoom = Instance.new("UIScale")
	zoom.Name = "Zoom"
	zoom.Parent = frame
	local entry = { frame = frame, pill = opts.pill, follow = opts.follow, zoom = zoom, centered = false, want = nil, openedAt = 0 }
	frame.Visible = false
	if entry.pill then
		entry.pill.Visible = false
	end
	table.insert(entries, entry)
	return entry
end

-- What the owner wants on screen: "box", "pill" (minimized) or nil.
function SideDock.show(entry, want: string?)
	if want == "box" and entry.want ~= "box" then
		entry.openedAt = os.clock()
	end
	entry.want = want
end

function SideDock.wants(entry): string?
	return entry.want
end

-- Someone opened this box on purpose (its pill): it gets the room on a phone.
function SideDock.raise(entry)
	entry.openedAt = os.clock()
end

-- Something new happened: show the box big up top for a moment.
function SideDock.pop(entry)
	entry.centered = true
	entry.shownAt = os.clock()
	entry.shownFrom = rootPosition()
	entry.moved = false
	entry.openedAt = os.clock()
end

-- Is it at the side (or would it be, once shown)?
function SideDock.isDocked(entry): boolean
	if entry.follow then
		return SideDock.isDocked(entry.follow) or not entry.follow.frame.Visible
	end
	return not entry.centered
end

-- Phones: how tall the bottom-left stack is right now (0 when empty).
function SideDock.phoneStackHeight(): number
	return phoneStack
end

-- (moving counts from the moment it popped up, even if you've come back since)
local function shouldDock(entry): boolean
	local pos = rootPosition()
	if pos and not entry.shownFrom then
		entry.shownFrom = pos
	end
	if pos and (pos - entry.shownFrom).Magnitude > SideDock.DOCK_MOVE then
		entry.moved = true
	end
	local age = os.clock() - entry.shownAt
	return age > SideDock.DOCK_AFTER or (age >= SideDock.MIN_CENTER and entry.moved)
end

-- Put a gui in its spot: straight there when it just appeared, a long glide between the top and
-- the side, a short slide when the stack shuffles.
local function put(gui: GuiObject, zoom: UIScale?, anchor: Vector2, position: UDim2, scale: number, centered: boolean)
	local key = string.format("%.2f %.2f %s %.2f", anchor.X, anchor.Y, tostring(position), scale)
	local last = placed[gui]
	if last and last.key == key then
		last.shown = true
		return
	end
	local goal = { AnchorPoint = anchor, Position = position }
	if not last or not last.shown then
		gui.AnchorPoint = anchor
		gui.Position = position
		if zoom then
			zoom.Scale = scale
		end
	else
		local info = last.centered ~= centered and GLIDE or SHUFFLE
		TweenService:Create(gui, info, goal):Play()
		if zoom then
			TweenService:Create(zoom, info, { Scale = scale }):Play()
		end
	end
	placed[gui] = { key = key, centered = centered, shown = true }
end

-- Phones: how high the bottom-left stack may grow (up to the offer button under the player card).
local function phoneRoom(): number
	local hud = App.Windows.guis.HUD
	local ceiling = 120
	for _, name in ipairs({ "StarterAd", "GoldRushAd" }) do
		local ad = hud:FindFirstChild(name)
		if ad and ad.Visible then
			ceiling = math.max(ceiling, ad.Position.Y.Offset + ad.Size.Y.Offset)
		end
	end
	return App.Windows.hudHeight() - ceiling - GAP - PHONE_BOTTOM
end

-- Which boxes show as boxes: all of them, except on a phone where the docked ones that don't
-- fit (newest open first) fall back to their pills.
local function decide(mobile: boolean)
	for _, entry in ipairs(entries) do
		entry.mode = entry.want
	end
	if not mobile then
		return
	end
	local docked = {}
	local used = 0
	for _, entry in ipairs(entries) do
		if entry.want == "pill" and entry.pill then
			used += entry.pill.Size.Y.Offset + GAP
		elseif entry.want == "box" and not (entry.follow and entry.follow.want == "box" and entry.follow.centered) and not entry.centered then
			table.insert(docked, entry)
		end
	end
	table.sort(docked, function(a, b)
		return (a.follow and a.follow.openedAt or a.openedAt) > (b.follow and b.follow.openedAt or b.openedAt)
	end)
	local room = phoneRoom()
	for _, entry in ipairs(docked) do
		local height = entry.frame.Size.Y.Offset + GAP
		if used + height <= room or not entry.pill then
			used += height
		else
			entry.mode = "pill"
			used += entry.pill.Size.Y.Offset + GAP
		end
	end
end

local function layout()
	local mobile = App.Windows.mobile
	decide(mobile)
	for _, entry in ipairs(entries) do
		entry.frame.Visible = entry.mode == "box"
		if entry.pill then
			entry.pill.Visible = entry.mode == "pill"
		end
	end
	local otherBottom = App.Notifications.claimedBottom("side")
	local top = math.max(DESK_TOP, otherBottom and otherBottom + GAP or 0)
	local deskY = top
	local centerY = 8
	local lift = PHONE_BOTTOM
	local order = entries
	if mobile then
		order = {}
		for i = #entries, 1, -1 do
			table.insert(order, entries[i])
		end
	end
	for _, entry in ipairs(order) do
		if entry.centered and entry.frame.Visible and shouldDock(entry) then
			entry.centered = false
		end
		for _, gui in ipairs({ entry.frame, entry.pill }) do
			if gui and not gui.Visible and placed[gui] then
				placed[gui].shown = false -- (next time it shows, it goes straight to its spot)
			end
		end
		local gui = (entry.frame.Visible and entry.frame) or (entry.pill and entry.pill.Visible and entry.pill) or nil
		if gui then
			local centered = gui == entry.frame and not SideDock.isDocked(entry)
			local zoom = gui == entry.frame and entry.zoom or nil
			local scale = centered and not mobile and CENTER_ZOOM or 1
			local height = gui.Size.Y.Offset * scale
			if centered and mobile then
				put(gui, zoom, Vector2.new(0.5, 0), UDim2.new(0.5, 0, PHONE_CENTER, centerY - 8), scale, true)
				centerY += height + GAP
			elseif centered then
				put(gui, zoom, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, centerY), scale, true)
				centerY += height + GAP
			elseif mobile then
				put(gui, zoom, Vector2.new(0, 1), UDim2.new(0, PHONE_X, 1, -lift), scale, false)
				lift += height + GAP
			else
				put(gui, zoom, Vector2.new(0, 0), UDim2.fromOffset(DESK_X, deskY), scale, false)
				deskY += height + GAP
			end
		end
	end
	phoneStack = lift > PHONE_BOTTOM and lift - PHONE_BOTTOM or 0
	App.Notifications.setTopInset(deskY > top and deskY - GAP or nil, "side")
end

function SideDock.init(app)
	App = app
	RunService.RenderStepped:Connect(layout)
end

return SideDock
