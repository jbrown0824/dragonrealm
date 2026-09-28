-- Dumps every straight walk a village dragon can take (CivilianService): the TownWalk graph,
-- each house door to its street node and up the ramp inside, and between the indoor spots.
-- walk_check.py tests them against the world's solid parts.
local Zones = require(__proxy("Shared/Config/Zones"))
local W = Zones.TownWalk
local function out(a: Vector3, b: Vector3, floor: number, label: string)
	print(string.format('{"walk":[%.2f,%.2f,%.2f,%.2f],"floor":%.2f,"label":"%s"}', a.X, a.Z, b.X, b.Z, floor, label))
end
for _, e in ipairs(W.edges) do
	out(W.nodes[e[1]], W.nodes[e[2]], 0, e[1] .. "-" .. e[2])
end
for i, house in ipairs(Zones.Houses) do
	local door = Zones.houseDoor(house)
	local link = W.houseLinks[i]
	out(door, W.nodes[link], 0, "Door" .. i .. "-" .. link)
	local entry = Zones.housePoint(house, Zones.HouseEntry.X, Zones.HouseEntry.Z)
	out(door, entry, -1, "Door" .. i .. "-inside") -- -1: up the ramp, only check above it
	local spots = { entry }
	for _, s in ipairs(Zones.HouseSpots) do
		table.insert(spots, Zones.housePoint(house, s.X, s.Z))
	end
	for a = 1, #spots do
		for b = a + 1, #spots do
			out(spots[a], spots[b], Zones.HOUSE_FLOOR, string.format("House%d spot%d-spot%d", i, a - 1, b - 1))
		end
	end
end
