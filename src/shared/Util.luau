local Util = {}

function Util.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = Util.deepCopy(v)
	end
	return copy
end

-- Pick a key from { key = weight }. `rng` is an optional Random object.
function Util.weightedPick(weights, rng)
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	-- Iterate in a stable order so the same roll always gives the same result.
	local keys = {}
	for k in pairs(weights) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, k in ipairs(keys) do
		roll -= weights[k]
		if roll <= 0 then
			return k
		end
	end
	return keys[#keys]
end

function Util.formatNumber(n: number): string
	n = math.floor(n + 0.5)
	local s = tostring(math.abs(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (n < 0 and "-" or "") .. formatted
end

function Util.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.round(n: number, decimals: number?): number
	local m = 10 ^ (decimals or 0)
	return math.floor(n * m + 0.5) / m
end

-- Trim trailing zeros: 3.50 -> "3.5", 4.00 -> "4"
function Util.fmt(n: number): string
	local r = Util.round(n, 1)
	if r == math.floor(r) then
		return tostring(math.floor(r))
	end
	return tostring(r)
end

function Util.countKeys(t): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

return Util
