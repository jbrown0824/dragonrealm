-- Draws the day/night cycle on this client: moves the sun and moon (Lighting.ClockTime) every
-- frame from the shared clock (shared/DayNight), cools and dims the light at night, and lights
-- the street lamps after dusk. Everything here is local, so it stays smooth and costs no traffic.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayNight = require(Shared.DayNight)

local Sky = {}

-- Day values come from the place (default.project.json / WorldBuilder); night ones are a cool,
-- dim blue that still leaves the ground readable.
local NIGHT = {
	OutdoorAmbient = Color3.fromRGB(78, 92, 138),
	Ambient = Color3.fromRGB(52, 54, 82),
	Brightness = 1.2,
	AtmosphereColor = Color3.fromRGB(70, 80, 120),
	AtmosphereDecay = Color3.fromRGB(40, 45, 80),
	Tint = Color3.fromRGB(190, 205, 255),
}

local day = nil -- the place's own daytime values, read once
local tint: ColorCorrectionEffect
local lampsLit: boolean? = nil
local lastDark = -1

local function setLamps(on: boolean)
	lampsLit = on
	for _, glass in ipairs(CollectionService:GetTagged("Lamp")) do
		local light = glass:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
		if glass:IsA("BasePart") then
			glass.Material = on and Enum.Material.Neon or Enum.Material.Glass
		end
	end
end

local function apply(dark: number)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not day then
		day = {
			OutdoorAmbient = Lighting.OutdoorAmbient,
			Ambient = Lighting.Ambient,
			Brightness = Lighting.Brightness,
			AtmosphereColor = atmosphere and atmosphere.Color,
			AtmosphereDecay = atmosphere and atmosphere.Decay,
		}
	end
	Lighting.OutdoorAmbient = day.OutdoorAmbient:Lerp(NIGHT.OutdoorAmbient, dark)
	Lighting.Ambient = day.Ambient:Lerp(NIGHT.Ambient, dark)
	Lighting.Brightness = day.Brightness + (NIGHT.Brightness - day.Brightness) * dark
	if atmosphere and day.AtmosphereColor then
		atmosphere.Color = day.AtmosphereColor:Lerp(NIGHT.AtmosphereColor, dark)
		atmosphere.Decay = day.AtmosphereDecay:Lerp(NIGHT.AtmosphereDecay, dark)
	end
	tint.TintColor = Color3.new(1, 1, 1):Lerp(NIGHT.Tint, dark)
	tint.Saturation = -0.15 * dark
end

function Sky.update()
	local _, clock = DayNight.now()
	Lighting.ClockTime = clock
	local dark = DayNight.darkness(clock)
	if math.abs(dark - lastDark) > 0.002 then
		lastDark = dark
		apply(dark)
	end
	local wantLamps = dark > 0.35
	if wantLamps ~= lampsLit then
		setLamps(wantLamps)
	end
end

function Sky.init()
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "NightTint"
	tint.Parent = Lighting
	CollectionService:GetInstanceAddedSignal("Lamp"):Connect(function(glass)
		if lampsLit ~= nil then
			local light = glass:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = lampsLit
			end
			glass.Material = lampsLit and Enum.Material.Neon or Enum.Material.Glass
		end
	end)
	RunService.RenderStepped:Connect(Sky.update)
end

return Sky
