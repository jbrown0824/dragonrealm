-- Plays sounds from Config/Sounds (ids left blank are skipped).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local Sfx = {}
local cache = {}

function Sfx.play(name: string, volume: number?)
	local id = Sounds[name]
	if not id or id == "" then
		return
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Parent = SoundService
		cache[name] = sound
	end
	sound.Volume = volume or 0.6
	SoundService:PlayLocalSound(sound)
end

function Sfx.init()
	if Sounds.Music and Sounds.Music ~= "" then
		local music = Instance.new("Sound")
		music.SoundId = Sounds.Music
		music.Looped = true
		music.Volume = 0.25
		music.Parent = SoundService
		music:Play()
	end
end

return Sfx
