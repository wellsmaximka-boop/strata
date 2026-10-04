-- ── Cave lighting ────────────────────────────────────────────────────────────
-- Darkness, and a lamp on your head to push it back.
--
-- Roblox has one Lighting object for the whole world, so a single Ambient
-- cannot be right for a timber lodge in daylight and for a basalt hall seven
-- hundred studs down. It was set once at boot from StrataConfig.Look and then
-- left, which meant the caves were lit to roughly the same level as the camp
-- and every lamp in them was competing with a free wash of skylight.
--
-- This runs on the client, which is the whole trick: a LocalScript's changes to
-- Lighting are local to that player's view. So the camp keeps the look it was
-- tuned with, the caves get their own, and two players standing in different
-- places each see the air they are actually in.
--
-- The camp values are read off Lighting at startup rather than copied out of
-- the config, so tuning the surface still means editing one table and nothing
-- here has to know about it.

local Lighting   = game:GetService("Lighting")
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local LOOK = StrataConfig.Look
local CAVE = LOOK.Cave
local LAMP = StrataConfig.Headlamp

local player = Players.LocalPlayer

-- ── The two looks ────────────────────────────────────────────────────────────

-- Whatever the server left here is the camp. Captured before anything is
-- touched, and the only record of it from this point on.
local function atmosphere()
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if not a then
		a = Instance.new("Atmosphere")
		a.Parent = Lighting
	end
	return a
end

local air = atmosphere()

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")

local SURFACE = {
	bloomI     = bloom and bloom.Intensity or 0,
	bloomS     = bloom and bloom.Size or 0,
	bloomT     = bloom and bloom.Threshold or 1,
	ambient    = Lighting.Ambient,
	outdoor    = Lighting.OutdoorAmbient,
	brightness = Lighting.Brightness,
	exposure   = Lighting.ExposureCompensation,
	diffuse    = Lighting.EnvironmentDiffuseScale,
	specular   = Lighting.EnvironmentSpecularScale,
	density    = air.Density,
	haze       = air.Haze,
	glare      = air.Glare,
	colour     = air.Color,
	decay      = air.Decay,
}

-- Hard shadow edges, everywhere. Not depth-dependent: the lodge lamps throw a
-- better shadow for it too.
Lighting.ShadowSoftness = CAVE.ShadowSoftness

-- The air underground takes its colour from the rock of the layer you are in,
-- so adding a layer to the ladder gives it its own atmosphere for free rather
-- than needing a second table kept in step with the first.
local function layerAir(y)
	local tint = Color3.fromRGB(16, 16, 20)
	for _, s in ipairs(StrataConfig.Strata) do
		if y <= (s.top or 0) and s.color then
			tint = s.color
		end
	end

	local k = CAVE.TintShare
	local own = Color3.new(tint.R * k, tint.G * k, tint.B * k)

	-- Pulled most of the way to one cool base. Each layer still reads as its
	-- own place, but as a variation rather than a separate palette — three
	-- unrelated hues plus the prop lights is four colour families competing,
	-- and that is what made the caves hard to unpack.
	local b = CAVE.CoolBase
	local m = CAVE.CoolBlend
	return Color3.new(
		own.R + (b.R - own.R) * m,
		own.G + (b.G - own.G) * m,
		own.B + (b.B - own.B) * m)
end

-- ── The crossfade ────────────────────────────────────────────────────────────

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpColour(a, b, t)
	return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end

-- 0 at the camp, 1 once you are properly underground, eased so the descent
-- darkens as it drops instead of switching at a line.
local function depthBlend(y)
	local span = CAVE.FadeFrom - CAVE.FadeTo
	if span <= 0 then return y <= CAVE.FadeTo and 1 or 0 end
	local raw = math.clamp((CAVE.FadeFrom - y) / span, 0, 1)
	return raw * raw * (3 - 2 * raw)
end

local applied = -1

local function apply(y)
	local t = depthBlend(y)

	-- Nothing has moved far enough to be worth writing eleven properties for.
	-- This runs every frame and most frames are not a descent.
	if math.abs(t - applied) < 0.004 then return end
	applied = t

	local caveAir = layerAir(y)

	Lighting.Ambient        = lerpColour(SURFACE.ambient, CAVE.Ambient, t)
	Lighting.OutdoorAmbient = lerpColour(SURFACE.outdoor, CAVE.Ambient, t)
	Lighting.Brightness     = lerp(SURFACE.brightness, CAVE.Brightness, t)
	Lighting.ExposureCompensation =
		lerp(SURFACE.exposure, CAVE.ExposureBias, t)
	Lighting.EnvironmentDiffuseScale  = lerp(SURFACE.diffuse, CAVE.Diffuse, t)
	Lighting.EnvironmentSpecularScale = lerp(SURFACE.specular, CAVE.Specular, t)

	air.Density = lerp(SURFACE.density, CAVE.Density, t)
	air.Haze    = lerp(SURFACE.haze, CAVE.Haze, t)
	air.Glare   = lerp(SURFACE.glare, CAVE.Glare, t)
	air.Color   = lerpColour(SURFACE.colour, caveAir, t)
	air.Decay   = lerpColour(SURFACE.decay, caveAir, t)

	-- The lodge is lit by warm lamps and wants its bloom; a cave full of neon
	-- props with the same bloom is a cave full of halos, and a halo is the
	-- enemy of reading what you are looking at.
	if bloom and CAVE.Bloom then
		bloom.Intensity = lerp(SURFACE.bloomI, CAVE.Bloom.Intensity, t)
		bloom.Size      = lerp(SURFACE.bloomS, CAVE.Bloom.Size, t)
		bloom.Threshold = lerp(SURFACE.bloomT, CAVE.Bloom.Threshold, t)
	end
end

-- ── The beam ─────────────────────────────────────────────────────────────────
-- Not a second light source: the shape of the pack lamp you are already
-- carrying. PackLight has six steps and the whole point of buying one is seeing
-- further, so the beam takes its range, its brightness and its colour from
-- whichever step you own and gets better exactly when the pack does.
--
-- A bulb lights the air around you; a beam lights what you are looking at. A
-- cave wants both, which is why there is also a weak fill at the chest — a beam
-- on its own leaves you standing in a hole of your own making.

local packLevel = 1

local function fitLamp(character)
	local head = character:WaitForChild("Head", 10)
	if not head then return end

	local spec = StrataConfig.PackLightLevel(packLevel)
	if not spec then return end

	local beam = head:FindFirstChild("Headlamp")
	if not beam then
		beam = Instance.new("SpotLight")
		beam.Name   = "Headlamp"
		beam.Face   = Enum.NormalId.Front
		beam.Parent = head
	end
	beam.Angle      = LAMP.Angle
	beam.Range      = spec.range * LAMP.RangeScale
	beam.Brightness = spec.brightness * LAMP.BrightScale
	beam.Color      = spec.colour
	beam.Shadows    = LAMP.Shadows

	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
	if torso then
		local fill = torso:FindFirstChild("HeadlampFill")
		if not fill then
			fill = Instance.new("PointLight")
			fill.Name    = "HeadlampFill"
			fill.Shadows = false
			fill.Parent  = torso
		end
		fill.Range      = spec.range * LAMP.FillScale
		fill.Brightness = LAMP.FillBrightness
		fill.Color      = spec.colour
	end
end

local function refit()
	if player.Character then task.spawn(fitLamp, player.Character) end
end

-- The same push SurfaceUI reads. Subscribed to here rather than routed through
-- that file, which is already sitting on Luau's limit of 200 locals per chunk.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("MineRemotes", 20)
	local changed = remotes and remotes:WaitForChild("StateChanged", 20)
	if not changed then return end

	changed.OnClientEvent:Connect(function(state)
		local level = state and state.lightLevel
		if level and level ~= packLevel then
			packLevel = level
			refit()
		end
	end)
end)

refit()
player.CharacterAdded:Connect(function(character)
	task.spawn(fitLamp, character)
end)

-- ── Driving it ───────────────────────────────────────────────────────────────

-- Before the character exists there is nothing to measure, and the camp look is
-- already in place, so the first frames are left alone.
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then apply(root.Position.Y) end
end)

print("[CaveLighting] ready")
