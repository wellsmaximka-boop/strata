-- ── OreModelBuilder ──────────────────────────────────────────────────────────
-- An ore node is a chunk of rock with the ore glowing out of it, not a bare
-- floating crystal. You break the rock to get the ore, so the rock has to be
-- the thing you see and hit.
--
-- Still no meshes: the boulder is a handful of jittered, rotated blocks and the
-- veins are neon shards pushed through its surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local OreModelBuilder = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local ROCK_DARK  = Color3.fromRGB(62, 62, 68)
local ROCK_LIGHT = Color3.fromRGB(88, 88, 96)

-- Deterministic pseudo-random from the node's own variant number, so a given
-- node looks the same every time it is built.
local function rand(seed, index)
	local h = (seed * 7919 + index * 104729) % 2147483647
	h = (h * 48271) % 2147483647
	return h / 2147483647
end

local function rigid(parent, name, size, cf, colour, material)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = cf
	p.Color         = colour
	p.Material      = material or Enum.Material.Slate
	p.Anchored      = true
	p.CanCollide    = false
	p.CanQuery      = true    -- the node has to be clickable
	p.CanTouch      = false
	p.CastShadow    = false
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent        = parent
	return p
end

-- ── Health bar ───────────────────────────────────────────────────────────────
-- Driven by the model's HP attribute, which the server owns. Attributes
-- replicate on their own, so no per-hit remote is needed to keep it in sync.

local function healthBar(model, root, ore)
	local gui = Instance.new("BillboardGui")
	gui.Name         = "OreBar"
	gui.Size         = UDim2.new(0, 190, 0, 34)
	gui.StudsOffset  = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop  = true
	gui.MaxDistance  = 90
	gui.Adornee      = root
	gui.Enabled      = false   -- only shown once the node has been hit
	gui.Parent       = root

	local frame = Instance.new("Frame")
	frame.Size             = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	frame.BorderSizePixel  = 0
	frame.Parent           = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local edge = Instance.new("UIStroke", frame)
	edge.Color     = Color3.fromRGB(8, 9, 12)
	edge.Thickness = 2.5

	local track = Instance.new("Frame")
	track.Name             = "Track"
	track.Size             = UDim2.new(1, -10, 1, -10)
	track.Position         = UDim2.new(0, 5, 0, 5)
	track.BackgroundColor3 = Color3.fromRGB(34, 38, 46)
	track.BorderSizePixel  = 0
	track.Parent           = frame
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 5)

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = ore.color
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local label = Instance.new("TextLabel")
	label.Name                   = "Label"
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = string.upper(ore.name)
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextSize               = 15
	label.Font                   = StrataConfig.UI.Head
	label.ZIndex                 = 3
	label.Parent                 = track

	local shade = Instance.new("UIStroke", label)
	shade.Color     = Color3.fromRGB(0, 0, 0)
	shade.Thickness = 2

	return gui
end

-- ── Build ────────────────────────────────────────────────────────────────────

function OreModelBuilder.Build(ore, variant)
	variant = variant or 1

	local model = Instance.new("Model")
	model.Name = ore.id

	-- Invisible root at the centre so the pivot and the billboard are stable
	local root = rigid(model, "Root", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), ROCK_DARK)
	root.Transparency = 1
	root.CanQuery     = false
	model.PrimaryPart = root

	-- Boulder: overlapping blocks at scattered angles read as broken rock
	local chunks = 5 + math.floor(rand(variant, 1) * 3)
	for i = 1, chunks do
		local a  = (i / chunks) * math.pi * 2 + rand(variant, i) * 1.2
		local r  = 0.5 + rand(variant, i + 20) * 0.7
		local sx = 1.5 + rand(variant, i + 40) * 1.4
		local sy = 1.2 + rand(variant, i + 60) * 1.1
		local sz = 1.5 + rand(variant, i + 80) * 1.4

		rigid(model, "Rock" .. i, Vector3.new(sx, sy, sz),
			CFrame.new(math.cos(a) * r, (rand(variant, i + 100) - 0.5) * 0.9, math.sin(a) * r)
				* CFrame.Angles(
					rand(variant, i + 120) * 1.1,
					rand(variant, i + 140) * 3.1,
					rand(variant, i + 160) * 1.1),
			i % 2 == 0 and ROCK_DARK or ROCK_LIGHT)
	end

	-- Veins: neon shards pushed out through the boulder's surface
	local veins = 4 + math.floor(rand(variant, 2) * 3)
	for i = 1, veins do
		local a    = (i / veins) * math.pi * 2 + rand(variant, i + 200) * 0.9
		local lift = 0.2 + rand(variant, i + 220) * 0.9
		local len  = 0.9 + rand(variant, i + 240) * 0.8

		local shard = rigid(model, "Vein" .. i,
			Vector3.new(0.34, len, 0.34),
			CFrame.new(math.cos(a) * 1.05, lift, math.sin(a) * 1.05)
				* CFrame.Angles(
					math.rad(20 + rand(variant, i + 260) * 40),
					a,
					math.rad(rand(variant, i + 280) * 50 - 25)),
			ore.color, Enum.Material.Neon)
		shard.CanQuery = true
	end

	-- A brighter core peeking out of the top
	rigid(model, "Core", Vector3.new(0.7, 0.9, 0.7),
		CFrame.new(0, 0.95, 0) * CFrame.Angles(0.2, 0.6, 0.15),
		ore.color:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Neon)

	if ore.glow then
		local light = Instance.new("PointLight")
		light.Color      = ore.color
		light.Brightness  = 1.2 + (ore.tier or 1) * 0.5
		light.Range      = 12 + (ore.tier or 1) * 4
		light.Shadows    = false
		light.Parent     = root

		if (ore.tier or 1) >= 2 then
			local pe = Instance.new("ParticleEmitter")
			pe.Texture       = SPARKLE
			pe.Color         = ColorSequence.new(ore.color)
			pe.Size          = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 0),
			})
			pe.Transparency  = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Lifetime      = NumberRange.new(0.5, 1.1)
			pe.Rate          = 10
			pe.Speed         = NumberRange.new(0.7)
			pe.SpreadAngle   = Vector2.new(180, 180)
			pe.LightEmission = 1
			pe.Acceleration  = Vector3.new(0, 1.1, 0)
			pe.Parent        = root
		end
	end

	-- Weld everything to the root so the whole node can be shaken on a hit
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0  = root
			w.Part1  = p
			w.Parent = root
		end
	end

	local hp = ore.hp or 25
	model:SetAttribute("OreId", ore.id)
	model:SetAttribute("OreValue", ore.value)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("HP", hp)

	healthBar(model, root, ore)

	return model
end

return OreModelBuilder
