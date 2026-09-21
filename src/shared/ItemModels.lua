-- ── ItemModels ───────────────────────────────────────────────────────────────
-- One model per item, doing two jobs. It is what gets welded onto a character
-- when the item is worn or held, and it is also the item's picture in the UI,
-- rendered live in a ViewportFrame. No image uploads, and the picture can never
-- drift out of date with the thing itself.
--
-- Worn pieces are built from the size of the limb they attach to, so armour
-- fits whatever avatar is wearing it rather than one fixed body.
--
-- First batch: the Thermal set and the Iron Pick. Items without a builder here
-- simply have no model yet — they still work, they just aren't drawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local ItemModels = {}

-- ── Palette ──────────────────────────────────────────────────────────────────
local IRON_DARK = Color3.fromRGB(58, 60, 66)
local IRON      = Color3.fromRGB(98, 102, 110)
local IRON_LIT  = Color3.fromRGB(152, 158, 166)
local EMBER     = Color3.fromRGB(255, 124, 44)
local SMOKE     = Color3.fromRGB(42, 36, 32)
local WOOD      = Color3.fromRGB(124, 86, 54)
local WRAP      = Color3.fromRGB(58, 44, 36)

-- ── Construction ─────────────────────────────────────────────────────────────

local function newModel(name)
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name         = "Root"
	root.Size         = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide   = false
	root.CanQuery     = false
	root.CanTouch     = false
	root.Massless     = true
	root.CFrame       = CFrame.new()
	root.Parent       = model
	model.PrimaryPart = root

	return model, root
end

-- A part placed at `offset` from `root` and held there by a Weld with an
-- explicit C0, so the offset survives however the assembly is moved later.
local function piece(model, root, name, size, offset, colour, material, shape)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = root.CFrame * offset
	p.Color         = colour
	p.Material      = material or Enum.Material.Metal
	p.CanCollide    = false
	p.CanQuery      = false
	p.CanTouch      = false
	p.Massless      = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent        = model

	local weld = Instance.new("Weld")
	weld.Part0  = root
	weld.Part1  = p
	weld.C0     = offset
	weld.Parent = root
	return p
end

-- ── Thermal set ──────────────────────────────────────────────────────────────
-- Dark iron with orange heat vents: the look should say "built to stand in
-- lava" before anyone reads a stat. In limb space +Y is up and -Z is the front.

local function thermalVisor(size)
	local m, r = newModel("ThermalVisor")
	local w, h, d = size.X, size.Y, size.Z

	piece(m, r, "Shell",  Vector3.new(w * 1.18, h * 1.05, d * 1.18), CFrame.new(0, h * 0.08, 0), IRON_DARK)
	piece(m, r, "Crest",  Vector3.new(w * 0.22, h * 0.22, d * 1.1),  CFrame.new(0, h * 0.62, 0), IRON)
	piece(m, r, "Visor",  Vector3.new(w * 1.02, h * 0.3, 0.12),      CFrame.new(0, h * 0.1, -d * 0.6), SMOKE, Enum.Material.Glass)
	piece(m, r, "VisorGlow", Vector3.new(w * 0.9, 0.06, 0.1),        CFrame.new(0, -h * 0.08, -d * 0.61), EMBER, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		piece(m, r, "Vent", Vector3.new(0.1, h * 0.36, d * 0.36), CFrame.new(sx * w * 0.6, 0, d * 0.05), EMBER, Enum.Material.Neon)
	end
	piece(m, r, "Collar", Vector3.new(w * 1.1, h * 0.16, d * 1.1), CFrame.new(0, -h * 0.5, 0), IRON)
	return m
end

local function thermalPlate(size)
	local m, r = newModel("ThermalPlate")
	local w, h, d = size.X, size.Y, size.Z

	piece(m, r, "Plate", Vector3.new(w * 1.12, h * 1.04, d * 1.3), CFrame.new(0, h * 0.02, 0), IRON_DARK)
	piece(m, r, "Ridge", Vector3.new(w * 0.14, h * 0.9, 0.16),     CFrame.new(0, 0, -d * 0.68), IRON)
	local core = piece(m, r, "Core", Vector3.new(w * 0.26, w * 0.26, 0.14),
		CFrame.new(0, h * 0.12, -d * 0.7), EMBER, Enum.Material.Neon)

	-- Vent slits either side of the ridge
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 2 do
			piece(m, r, "Slit", Vector3.new(w * 0.22, 0.07, 0.1),
				CFrame.new(sx * w * 0.3, h * 0.2 - i * h * 0.16, -d * 0.66), EMBER, Enum.Material.Neon)
		end
	end
	piece(m, r, "Trim", Vector3.new(w * 1.16, h * 0.12, d * 1.34), CFrame.new(0, -h * 0.5, 0), IRON_LIT)

	local glow = Instance.new("PointLight")
	glow.Color      = EMBER
	glow.Brightness = 0.6
	glow.Range      = 6
	glow.Shadows    = false
	glow.Parent     = core
	return m
end

-- Shoulder guard for one arm. `side` is -1 for the left arm, 1 for the right,
-- and the plate tilts so its outer edge sits lower.
local function thermalPauldron(side)
	return function(size)
		local m, r = newModel("ThermalPauldron")
		local w, h, d = size.X, size.Y, size.Z
		local tilt = CFrame.Angles(0, 0, math.rad(-side * 12))

		piece(m, r, "Pauldron", Vector3.new(w * 1.4, h * 0.42, d * 1.35),
			CFrame.new(side * w * 0.12, h * 0.36, 0) * tilt, IRON_DARK)
		piece(m, r, "Edge", Vector3.new(w * 1.42, 0.08, d * 1.38),
			CFrame.new(side * w * 0.12, h * 0.14, 0) * tilt, EMBER, Enum.Material.Neon)
		return m
	end
end

local function thermalCuisse(size)
	local m, r = newModel("ThermalCuisse")
	local w, h, d = size.X, size.Y, size.Z

	piece(m, r, "Cuisse", Vector3.new(w * 1.2, h * 0.9, d * 1.25), CFrame.new(0, h * 0.02, 0), IRON_DARK)
	piece(m, r, "Band",   Vector3.new(w * 1.24, 0.08, d * 1.29),   CFrame.new(0, -h * 0.28, 0), EMBER, Enum.Material.Neon)
	return m
end

local function thermalGreave(size)
	local m, r = newModel("ThermalGreave")
	local w, h, d = size.X, size.Y, size.Z

	piece(m, r, "Greave", Vector3.new(w * 1.2, h * 0.95, d * 1.3), CFrame.new(0, -h * 0.02, 0), IRON_DARK)
	piece(m, r, "Knee",   Vector3.new(w * 0.7, w * 0.7, w * 0.7),  CFrame.new(0, h * 0.42, -d * 0.5),
		IRON, Enum.Material.Metal, Enum.PartType.Ball)
	piece(m, r, "Strip",  Vector3.new(w * 0.16, h * 0.6, 0.08),    CFrame.new(0, -h * 0.05, -d * 0.67), EMBER, Enum.Material.Neon)
	return m
end

-- ── Worn items: which pieces go on which limbs ───────────────────────────────

local WORN = {
	ThermalVisor = {
		{ limb = "Head", build = thermalVisor },
	},
	ThermalPlate = {
		{ limb = "UpperTorso",    build = thermalPlate },
		{ limb = "LeftUpperArm",  build = thermalPauldron(-1) },
		{ limb = "RightUpperArm", build = thermalPauldron(1) },
	},
	ThermalGreaves = {
		{ limb = "LeftUpperLeg",  build = thermalCuisse },
		{ limb = "RightUpperLeg", build = thermalCuisse },
		{ limb = "LeftLowerLeg",  build = thermalGreave },
		{ limb = "RightLowerLeg", build = thermalGreave },
	},
}

-- R6 rigs name their limbs differently and have no lower legs; a piece meant
-- for a lower leg is skipped there, and the upper-leg piece covers the leg.
local R6_LIMB = {
	UpperTorso    = "Torso",
	LeftUpperArm  = "Left Arm",
	RightUpperArm = "Right Arm",
	LeftUpperLeg  = "Left Leg",
	RightUpperLeg = "Right Leg",
}

function ItemModels.FindLimb(character, limbName)
	return character:FindFirstChild(limbName)
		or (R6_LIMB[limbName] and character:FindFirstChild(R6_LIMB[limbName]))
end

function ItemModels.WornPieces(gearId)
	return WORN[gearId] or {}
end

-- ── Held items ───────────────────────────────────────────────────────────────
-- Same convention as the starter pick in MineClient: the handle is the root,
-- running along its own Y with the head at the top, so the grip offset and the
-- swing animation work unchanged whichever pick is in your hand.

local HELD = {}

HELD.IronPick = function()
	local model = Instance.new("Model")
	model.Name = "IronPick"

	local handle = Instance.new("Part")
	handle.Name       = "Handle"
	handle.Size       = Vector3.new(0.2, 2.7, 0.2)
	handle.Color      = WOOD
	handle.Material   = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery   = false
	handle.CanTouch   = false
	handle.Massless   = true
	handle.CFrame     = CFrame.new()
	handle.Parent     = model
	model.PrimaryPart = handle

	-- Head with a point each way: the thing that makes it read as a pick
	piece(model, handle, "Head",   Vector3.new(0.36, 0.42, 1.3), CFrame.new(0, 1.22, 0), IRON)
	piece(model, handle, "PointF", Vector3.new(0.28, 0.3, 0.8),
		CFrame.new(0, 1.16, -1.0) * CFrame.Angles(math.rad(-10), 0, 0), IRON_LIT)
	piece(model, handle, "PointB", Vector3.new(0.28, 0.3, 0.8),
		CFrame.new(0, 1.16, 1.0) * CFrame.Angles(math.rad(10), 0, 0), IRON_LIT)
	piece(model, handle, "TipF",   Vector3.new(0.16, 0.18, 0.42),
		CFrame.new(0, 1.07, -1.5) * CFrame.Angles(math.rad(-18), 0, 0), IRON_LIT)
	piece(model, handle, "TipB",   Vector3.new(0.16, 0.18, 0.42),
		CFrame.new(0, 1.07, 1.5) * CFrame.Angles(math.rad(18), 0, 0), IRON_LIT)
	piece(model, handle, "Collar", Vector3.new(0.3, 0.32, 0.3),  CFrame.new(0, 0.92, 0), IRON_DARK)
	piece(model, handle, "Grip",   Vector3.new(0.25, 0.85, 0.25), CFrame.new(0, -0.72, 0), WRAP, Enum.Material.Fabric)
	piece(model, handle, "Pommel", Vector3.new(0.3, 0.2, 0.3),   CFrame.new(0, -1.3, 0), IRON_DARK)

	return model, handle
end

-- Returns (model, handle) for a pick with a model, or nil if it has none yet
function ItemModels.BuildHeld(gearId)
	local build = gearId and HELD[gearId]
	if not build then return nil end
	return build()
end

-- ── Display ──────────────────────────────────────────────────────────────────
-- For pictures, worn pieces are laid out on a stand-in body so a chestplate
-- shows up with its shoulder guards in the right places.

local STAND_IN = {
	Head          = { size = Vector3.new(1.2, 1.2, 1.2), at = Vector3.new(0, 1.5, 0) },
	UpperTorso    = { size = Vector3.new(2, 1.6, 1),     at = Vector3.new(0, 0, 0) },
	LeftUpperArm  = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(-1.5, 0.2, 0) },
	RightUpperArm = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(1.5, 0.2, 0) },
	LeftUpperLeg  = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(-0.5, -1.9, 0) },
	RightUpperLeg = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(0.5, -1.9, 0) },
	LeftLowerLeg  = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(-0.5, -3.1, 0) },
	RightLowerLeg = { size = Vector3.new(1, 1.2, 1),     at = Vector3.new(0.5, -3.1, 0) },
}

local function anchorAll(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
end

-- A standalone, anchored copy of an item for showing rather than wearing
function ItemModels.BuildDisplay(gearId)
	local heldModel = ItemModels.BuildHeld(gearId)
	if heldModel then
		anchorAll(heldModel)
		-- Lay the pick across the view at an angle rather than end-on
		heldModel:PivotTo(CFrame.Angles(0, 0, math.rad(35)) * CFrame.Angles(0, math.rad(90), 0))
		return heldModel
	end

	local pieces = WORN[gearId]
	if not pieces then return nil end

	local container = Instance.new("Model")
	container.Name = gearId
	for _, spec in ipairs(pieces) do
		local stand = STAND_IN[spec.limb]
		if stand then
			local m = spec.build(stand.size)
			m:PivotTo(CFrame.new(stand.at))
			m.Parent = container
		end
	end
	anchorAll(container)
	return container
end

-- ── Backpack ─────────────────────────────────────────────────────────────────
-- Built here rather than in the client so the world model and the picture of it
-- in the kit screen are the same object, and so the server can weld it later
-- without any of this moving.
--
-- The mast on its side is the light: a thin dark pole with a glowing head, and
-- the level decides how tall it is, how many heads it carries and how far it
-- throws light. Levels come from prestige, so the mast is a rank badge you wear
-- on your back.

local CANVAS  = Color3.fromRGB(76, 66, 52)
local CANVAS_D = Color3.fromRGB(58, 50, 40)
local STRAP   = Color3.fromRGB(52, 46, 38)
local MAST    = Color3.fromRGB(26, 24, 26)

-- A six-sided head, made from three crossed slabs. Roblox has no hexagonal
-- part, and three boxes at sixty degrees read as one from any distance.
local function lightHead(model, root, at, size, colour)
	for i = 0, 2 do
		piece(model, root, "Head", Vector3.new(size, size * 0.42, size * 0.58),
			at * CFrame.Angles(0, math.rad(i * 60), 0), colour, Enum.Material.Neon)
	end
end

-- Returns the model, its body part, and the light instance so a caller can
-- brighten it without rebuilding.
function ItemModels.Backpack(tier, lightLevel)
	local model = Instance.new("Model")
	model.Name = "StrataPack"

	local depth = (tier or 1) >= 2 and 1.0 or 0.72

	local body = Instance.new("Part")
	body.Name          = "Body"
	body.Size          = Vector3.new(1.55, 1.7, depth)
	body.Color         = CANVAS
	body.Material      = Enum.Material.Fabric
	body.CanCollide    = false
	body.CanQuery      = false
	body.CanTouch      = false
	body.Massless      = true
	body.CFrame        = CFrame.new()
	body.TopSurface    = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent        = model
	model.PrimaryPart  = body

	piece(model, body, "Flap", Vector3.new(1.62, 0.55, depth + 0.08),
		CFrame.new(0, 0.62, 0.02), CANVAS_D, Enum.Material.Fabric)
	piece(model, body, "Frame", Vector3.new(1.3, 0.14, 0.14),
		CFrame.new(0, -0.75, -0.1), Color3.fromRGB(118, 124, 132))
	piece(model, body, "Buckle", Vector3.new(0.3, 0.22, 0.1),
		CFrame.new(0, 0.3, depth / 2 + 0.04), Color3.fromRGB(150, 132, 92))

	for i, side in ipairs({ -1, 1 }) do
		piece(model, body, "Strap" .. i, Vector3.new(0.22, 1.5, 0.16),
			CFrame.new(side * 0.5, 0.05, -depth / 2 - 0.42), STRAP, Enum.Material.Fabric)
		piece(model, body, "Pocket" .. i, Vector3.new(0.34, 0.68, depth * 0.7),
			CFrame.new(side * 0.92, -0.3, 0.02), CANVAS_D, Enum.Material.Fabric)
	end

	-- ── The mast ──
	local spec = StrataConfig.PackLightLevel(lightLevel)

	piece(model, body, "MastFoot", Vector3.new(0.28, 0.24, 0.28),
		CFrame.new(0.62, 0.72, 0.06), Color3.fromRGB(64, 66, 72))
	piece(model, body, "Mast", Vector3.new(0.12, spec.mast, 0.12),
		CFrame.new(0.62, 0.86 + spec.mast / 2, 0.06), MAST)

	local topY = 0.86 + spec.mast
	for i = 1, spec.heads do
		-- Heads stack down the mast, biggest at the top
		local drop = (i - 1) * 0.36
		local size = 0.42 - (i - 1) * 0.06
		lightHead(model, body, CFrame.new(0.62, topY - drop, 0.06), size, spec.colour)
	end

	local glow = Instance.new("PointLight")
	glow.Name       = "PackLight"
	glow.Color      = spec.colour
	glow.Brightness = spec.brightness
	glow.Range      = spec.range
	glow.Shadows    = false
	glow.Parent     = body

	return model, body, glow
end

-- A standalone, anchored copy for the kit screen to spin
function ItemModels.BackpackDisplay(tier, lightLevel)
	local model = ItemModels.Backpack(tier, lightLevel)
	anchorAll(model)
	return model
end

-- ── Ore, as an item ──────────────────────────────────────────────────────────
-- In the ground an ore node is a boulder with something glowing inside it. In
-- your pack it is the ore itself, so the inventory gets its own small cluster
-- rather than a picture of a rock.

local function oreCluster(ore)
	local m, r = newModel(ore.id)
	local colour   = ore.color
	local material = ore.glow and Enum.Material.Neon or Enum.Material.Slate

	local shards = {
		{ size = Vector3.new(0.62, 1.30, 0.62), at = CFrame.new(0, 0.10, 0),
		  tilt = CFrame.Angles(math.rad(6), math.rad(22), math.rad(4)) },
		{ size = Vector3.new(0.44, 0.92, 0.44), at = CFrame.new(-0.42, -0.16, 0.16),
		  tilt = CFrame.Angles(math.rad(-8), math.rad(-14), math.rad(-17)) },
		{ size = Vector3.new(0.38, 0.74, 0.38), at = CFrame.new(0.44, -0.24, -0.12),
		  tilt = CFrame.Angles(math.rad(10), math.rad(36), math.rad(15)) },
		{ size = Vector3.new(0.30, 0.48, 0.30), at = CFrame.new(0.06, -0.42, 0.40),
		  tilt = CFrame.Angles(math.rad(-14), math.rad(8), math.rad(9)) },
	}

	for i, s in ipairs(shards) do
		local shade = 1 - (i - 1) * 0.12
		piece(m, r, "Shard" .. i, s.size, s.at * s.tilt,
			Color3.new(colour.R * shade, colour.G * shade, colour.B * shade), material)
	end

	-- A little dark rock still clinging to it, so it reads as mined
	piece(m, r, "Matrix", Vector3.new(1.02, 0.34, 0.92), CFrame.new(0, -0.60, 0),
		Color3.fromRGB(64, 62, 68), Enum.Material.Slate)

	return m
end

-- ── Pictures ─────────────────────────────────────────────────────────────────

-- Frames a model in a ViewportFrame of `px` square. Shared by everything with
-- a picture, so gear and ore are lit and framed identically.
local function renderIcon(model, parent, px, position)
	local vp = Instance.new("ViewportFrame")
	vp.Name             = "Icon"
	vp.Size             = UDim2.new(0, px, 0, px)
	vp.Position         = position or UDim2.new()
	vp.BackgroundColor3 = Color3.fromRGB(40, 46, 56)
	vp.BorderSizePixel  = 0
	vp.Ambient          = Color3.fromRGB(140, 140, 150)
	vp.LightColor       = Color3.fromRGB(255, 240, 220)
	vp.LightDirection   = Vector3.new(-0.6, -1, -0.8)
	if parent:IsA("GuiObject") then vp.ZIndex = parent.ZIndex + 1 end
	vp.Parent = parent

	local rounding = Instance.new("UICorner")
	rounding.CornerRadius = UDim.new(0, 8)
	rounding.Parent       = vp

	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent      = vp
	vp.CurrentCamera = cam

	-- Frame the whole model, looking at its front from a little right and above
	local cf, size = model:GetBoundingBox()
	local reach    = math.max(size.X, size.Y, size.Z)
	local dist     = (reach / 2) / math.tan(math.rad(15)) * 1.15
	local centre   = cf.Position
	cam.CFrame = CFrame.lookAt(centre + Vector3.new(0.45, 0.25, -1).Unit * dist, centre)

	return vp
end

-- A live picture of an item, sized `px` square, placed in `parent`.
-- Returns the ViewportFrame, or nil if the item has no model yet.
function ItemModels.Icon(gearId, parent, px, position)
	local model = ItemModels.BuildDisplay(gearId)
	if not model then return nil end
	return renderIcon(model, parent, px, position)
end

-- The same, for an ore out of StrataConfig.Ores.
function ItemModels.OreIcon(ore, parent, px, position)
	if not ore then return nil end
	local model = oreCluster(ore)
	anchorAll(model)
	return renderIcon(model, parent, px, position)
end

return ItemModels
