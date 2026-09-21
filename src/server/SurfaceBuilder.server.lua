local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── Surface builder ──────────────────────────────────────────────────────────
-- The camp above the shaft, built as four places rather than four sheds.
--
--   Depot      a timbered mine portal with rails, a loaded minecart and scales
--   Forge      a stone furnace, anvil, bellows and quench barrel
--   Pick Works a grindstone, workbench and racked picks
--   Winch      the cable drum and gearing that drives the headframe
--
-- Timber, stone and iron rather than painted steel: warm posts, plank roofs,
-- lantern light. Everything is parts — no meshes anywhere in this project.

local S     = StrataConfig.Surface
local ZONES = StrataConfig.Zones

local camp = Instance.new("Folder")
camp.Name   = "SurfaceCamp"
camp.Parent = workspace

-- ── Palette ──────────────────────────────────────────────────────────────────
local TIMBER  = Color3.fromRGB(124, 86, 54)    -- posts and beams
local TIMBER_D= Color3.fromRGB(92, 63, 40)     -- shadowed timber
local PLANK   = Color3.fromRGB(158, 116, 74)   -- decking and walls
local STONE   = Color3.fromRGB(122, 120, 116)  -- masonry
local STONE_D = Color3.fromRGB(92, 90, 88)
local DECK    = Color3.fromRGB(150, 146, 138)  -- plaza slab
local DECK_2  = Color3.fromRGB(132, 128, 121)
local IRON    = Color3.fromRGB(84, 88, 94)
local IRON_L  = Color3.fromRGB(126, 132, 140)
local CANVAS  = Color3.fromRGB(176, 162, 132)
local HAZARD  = Color3.fromRGB(214, 174, 72)
local EMBER   = Color3.fromRGB(226, 118, 48)
local LAMP    = Color3.fromRGB(232, 196, 128)
local OUTLINE = Color3.fromRGB(38, 32, 28)

local Y = S.PlatformY

-- ── Primitives ───────────────────────────────────────────────────────────────

local function part(name, size, cf, colour, material, parent)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = cf
	p.Color         = colour
	p.Material      = material or Enum.Material.WoodPlanks
	p.Anchored      = true
	p.CanCollide    = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent        = parent or camp
	return p
end

local function decor(...)
	local p = part(...)
	p.CanCollide = false
	p.CanQuery   = false
	p.CastShadow = false
	return p
end

local function cylinder(name, diameter, length, cf, colour, material, parent)
	local p = part(name, Vector3.new(diameter, length, diameter), cf, colour, material, parent)
	Instance.new("CylinderMesh").Parent = p
	p.CanCollide = false
	return p
end

local function glow(p, colour, brightness, range)
	local l = Instance.new("PointLight")
	l.Color      = colour
	l.Brightness = brightness or 0.8
	l.Range      = range or 16
	l.Shadows    = false
	l.Parent     = p
	return l
end

local function emitter(parent, opts)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture       = opts.texture or "rbxasset://textures/particles/smoke_main.dds"
	pe.Color         = ColorSequence.new(opts.colour or LAMP)
	pe.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, opts.size or 0.6),
		NumberSequenceKeypoint.new(1, opts.endSize or 0),
	})
	pe.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, opts.transparency or 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime      = NumberRange.new(opts.life or 0.8, (opts.life or 0.8) * 1.6)
	pe.Rate          = opts.rate or 8
	pe.Speed         = NumberRange.new(opts.speed or 1.5)
	pe.SpreadAngle   = Vector2.new(opts.spread or 25, opts.spread or 25)
	pe.Acceleration  = opts.accel or Vector3.new(0, 2, 0)
	pe.LightEmission = opts.emission or 0.5
	pe.Parent        = parent
	return pe
end

-- Floating sign above a station.
-- Sized in *studs*, not pixels. On a BillboardGui the scale half of Size is
-- measured in studs, so the sign shrinks with distance like the building under
-- it. The old 330px signs stayed 330px at any range, which is why every
-- station's sign piled up on the same patch of screen from across the camp.
-- Everything inside is scale-only for the same reason: a pixel offset would
-- stay fixed while the card around it shrank.
local function billboard(adornee, title, blurb, accent, height, width)
	width = width or 12

	local gui = Instance.new("BillboardGui")
	gui.Name           = "Sign"
	gui.Size           = UDim2.new(width, 0, width * 0.28, 0)
	gui.StudsOffset    = Vector3.new(0, height or 6, 0)
	gui.MaxDistance    = 150
	gui.LightInfluence = 0
	gui.Adornee        = adornee
	gui.Parent         = adornee

	local card = Instance.new("Frame")
	card.Size                   = UDim2.fromScale(1, 1)
	card.BackgroundColor3       = Color3.fromRGB(30, 24, 20)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel        = 0
	card.Parent                 = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0.16, 0)

	local stroke = Instance.new("UIStroke", card)
	stroke.Color     = OUTLINE
	stroke.Thickness = 2

	local bar = Instance.new("Frame")
	bar.Size             = UDim2.fromScale(0.9, 0.06)
	bar.Position         = UDim2.fromScale(0.05, 0.12)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel  = 0
	bar.Parent           = card
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

	local name = Instance.new("TextLabel")
	name.Size                   = UDim2.fromScale(0.9, 0.44)
	name.Position               = UDim2.fromScale(0.05, 0.2)
	name.BackgroundTransparency = 1
	name.Text                   = title
	name.TextColor3             = Color3.fromRGB(255, 248, 236)
	name.TextScaled             = true
	name.Font                   = StrataConfig.UI.Head
	name.Parent                 = card

	local sub = Instance.new("TextLabel")
	sub.Size                   = UDim2.fromScale(0.9, 0.22)
	sub.Position               = UDim2.fromScale(0.05, 0.67)
	sub.BackgroundTransparency = 1
	sub.Text                   = blurb
	sub.TextColor3             = Color3.fromRGB(190, 174, 152)
	sub.TextScaled             = true
	sub.Font                   = StrataConfig.UI.Body
	sub.Parent                 = card

	return gui
end

-- ── Prop library ─────────────────────────────────────────────────────────────
-- Each prop is built around a CFrame so a scene can place it anywhere.

local function barrel(cf, parent, lidColour)
	local body = cylinder("Barrel", 2.0, 2.4, cf, TIMBER, Enum.Material.Wood, parent)
	body.CanCollide = true
	cylinder("BarrelBandA", 2.12, 0.28, cf * CFrame.new(0, 0.65, 0), IRON, Enum.Material.Metal, parent)
	cylinder("BarrelBandB", 2.12, 0.28, cf * CFrame.new(0, -0.65, 0), IRON, Enum.Material.Metal, parent)
	if lidColour then
		cylinder("BarrelLid", 1.8, 0.16, cf * CFrame.new(0, 1.22, 0), lidColour, Enum.Material.SmoothPlastic, parent)
	end
	return body
end

local function crate(cf, size, parent)
	size = size or 1.7
	local c = part("Crate", Vector3.new(size, size, size), cf, PLANK, Enum.Material.WoodPlanks, parent)
	-- Corner banding so it reads as a crate and not a cube
	decor("CrateBandA", Vector3.new(size + 0.08, size * 0.16, size + 0.08),
		cf * CFrame.new(0, size * 0.3, 0), TIMBER_D, Enum.Material.Wood, parent)
	decor("CrateBandB", Vector3.new(size + 0.08, size * 0.16, size + 0.08),
		cf * CFrame.new(0, -size * 0.3, 0), TIMBER_D, Enum.Material.Wood, parent)
	return c
end

local function logPile(cf, parent, rows)
	rows = rows or 3
	local n = 0
	for row = 0, rows - 1 do
		for i = 0, (rows - 1 - row) do
			n += 1
			local x = (i - (rows - 1 - row) / 2) * 1.15
			local yy = row * 1.0
			cylinder("Log" .. n, 1.05, 3.2,
				cf * CFrame.new(x, yy, 0) * CFrame.Angles(0, 0, math.rad(90)),
				row % 2 == 0 and TIMBER or TIMBER_D, Enum.Material.Wood, parent)
		end
	end
end

local function lantern(cf, parent, onPost)
	if onPost then
		part("LanternPost", Vector3.new(0.28, 5.0, 0.28), cf * CFrame.new(0, -2.5, 0),
			TIMBER_D, Enum.Material.Wood, parent)
		decor("LanternArm", Vector3.new(1.2, 0.22, 0.22), cf * CFrame.new(0.5, 0.1, 0),
			TIMBER_D, Enum.Material.Wood, parent)
	end
	local body = decor("Lantern", Vector3.new(0.7, 0.9, 0.7),
		cf * CFrame.new(onPost and 1.0 or 0, -0.4, 0), LAMP, Enum.Material.Neon, parent)
	decor("LanternCap", Vector3.new(0.9, 0.18, 0.9),
		cf * CFrame.new(onPost and 1.0 or 0, 0.14, 0), IRON, Enum.Material.Metal, parent)
	glow(body, LAMP, 0.85, 20)
	return body
end

-- ── Building shell ───────────────────────────────────────────────────────────
-- Timber frame, plank walls, sloped plank roof on exposed rafters. Local +Z is
-- the open front, so the caller only has to rotate the whole thing.

local function shell(cf, spec)
	local g = Instance.new("Folder")
	g.Name   = spec.key
	g.Parent = camp

	local w, d, h = spec.width, spec.depth, spec.height
	local accent  = spec.zone.accent

	local function piece(name, size, offset, colour, material)
		return part(name, size, cf * offset, colour, material, g)
	end
	local function trim(name, size, offset, colour, material)
		local p = piece(name, size, offset, colour, material)
		p.CanCollide = false
		p.CanQuery   = false
		return p
	end

	-- Stone footing, one step up
	-- Sunk into the deck rather than resting exactly on it. Two faces at the same
	-- height fight over which one is drawn, which is what made the station floors
	-- flicker against the plaza from a distance.
	piece("Footing", Vector3.new(w + 6, 1.8, d + 6), CFrame.new(0, 0.3, 0), STONE, Enum.Material.Slate)
	trim("FootingLip", Vector3.new(w + 6.6, 0.34, d + 6.6), CFrame.new(0, 1.11, 0), STONE_D, Enum.Material.Slate)
	piece("Step", Vector3.new(w * 0.55, 0.9, 2.2), CFrame.new(0, 0.15, d / 2 + 4), STONE_D, Enum.Material.Slate)

	local base = 1.2

	-- Plank walls, left open at the front
	piece("Back",  Vector3.new(w, h, 0.7), CFrame.new(0, base + h / 2, -d / 2), PLANK, Enum.Material.WoodPlanks)
	piece("Left",  Vector3.new(0.7, h, d), CFrame.new(-w / 2, base + h / 2, 0), PLANK, Enum.Material.WoodPlanks)
	piece("Right", Vector3.new(0.7, h, d), CFrame.new( w / 2, base + h / 2, 0), PLANK, Enum.Material.WoodPlanks)

	-- Corner posts, oversized and proud of the walls
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			piece("Post", Vector3.new(1.3, h + 1.6, 1.3),
				CFrame.new(sx * w / 2, base + (h + 1.6) / 2, sz * d / 2), TIMBER, Enum.Material.Wood)
		end
	end

	-- Head beam across the open front, with braces
	trim("HeadBeam", Vector3.new(w + 2.6, 1.0, 1.0), CFrame.new(0, base + h + 0.3, d / 2), TIMBER, Enum.Material.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		trim("Brace", Vector3.new(2.4, 0.7, 0.7),
			CFrame.new(sx * (w / 2 - 1.1), base + h - 0.9, d / 2) * CFrame.Angles(0, 0, math.rad(sx * 42)),
			TIMBER_D, Enum.Material.Wood)
	end

	-- Rafters, then a two-slope plank roof
	for i = -2, 2 do
		trim("Rafter", Vector3.new(0.5, 0.5, d + 5),
			CFrame.new(i * (w / 5), base + h + 1.0, 0), TIMBER_D, Enum.Material.Wood)
	end
	for _, sz in ipairs({ -1, 1 }) do
		trim("Roof", Vector3.new(w + 5, 0.7, d * 0.75),
			CFrame.new(0, base + h + 2.0, sz * d * 0.3) * CFrame.Angles(math.rad(sz * 16), 0, 0),
			TIMBER_D, Enum.Material.WoodPlanks)
	end
	trim("Ridge", Vector3.new(w + 5.4, 0.6, 1.1), CFrame.new(0, base + h + 2.9, 0), TIMBER, Enum.Material.Wood)

	-- Painted board in the station's colour, under the ridge
	trim("Board", Vector3.new(w - 2, 1.3, 0.4), CFrame.new(0, base + h + 1.3, d / 2 + 0.5),
		accent, Enum.Material.SmoothPlastic)

	-- Lanterns either side of the opening
	for _, sx in ipairs({ -1, 1 }) do
		lantern(cf * CFrame.new(sx * (w / 2 + 0.9), base + h - 2.2, d / 2 + 0.6), g, false)
	end

	-- Sign post above the ridge
	local post = trim("SignPost", Vector3.new(0.5, 2.4, 0.5), CFrame.new(0, base + h + 4.2, 0),
		TIMBER_D, Enum.Material.Wood)
	billboard(post, spec.zone.title, spec.zone.blurb, accent, 3.4)

	return g, cf, base
end

-- ── Scenes ───────────────────────────────────────────────────────────────────
-- Each fills the inside of a shell with the work that happens there.

-- DEPOT: a mine portal, rails, a loaded cart and a set of scales.
local function depotScene(cf, g, base)
	local function at(offset) return cf * offset end

	-- Timbered portal on the back wall, with a black opening behind it
	part("PortalDark", Vector3.new(7.5, 6.2, 0.6), at(CFrame.new(0, base + 3.1, -6.4)),
		Color3.fromRGB(18, 16, 15), Enum.Material.Slate, g)
	for _, sx in ipairs({ -1, 1 }) do
		part("PortalPost", Vector3.new(1.0, 6.4, 1.0), at(CFrame.new(sx * 3.9, base + 3.2, -5.9)),
			TIMBER, Enum.Material.Wood, g)
	end
	part("PortalLintel", Vector3.new(9.6, 1.1, 1.2), at(CFrame.new(0, base + 6.8, -5.9)),
		TIMBER, Enum.Material.Wood, g)
	decor("PortalBraceL", Vector3.new(2.2, 0.6, 0.6),
		at(CFrame.new(-3.1, base + 5.9, -5.9) * CFrame.Angles(0, 0, math.rad(-40))), TIMBER_D, Enum.Material.Wood, g)
	decor("PortalBraceR", Vector3.new(2.2, 0.6, 0.6),
		at(CFrame.new(3.1, base + 5.9, -5.9) * CFrame.Angles(0, 0, math.rad(40))), TIMBER_D, Enum.Material.Wood, g)
	lantern(at(CFrame.new(0, base + 6.2, -5.2)), g, false)

	-- Rails running out of the portal toward the front
	for _, sx in ipairs({ -1, 1 }) do
		decor("Rail", Vector3.new(0.25, 0.18, 13), at(CFrame.new(sx * 1.1, base + 0.15, 0)),
			IRON_L, Enum.Material.Metal, g)
	end
	for i = -5, 5 do
		decor("Sleeper", Vector3.new(3.4, 0.16, 0.5), at(CFrame.new(0, base + 0.05, i * 1.25)),
			TIMBER_D, Enum.Material.Wood, g)
	end

	-- Minecart, tipped full of ore
	local cartCf = CFrame.new(0, base + 1.35, 1.4)
	part("CartBody", Vector3.new(3.2, 1.9, 4.0), at(cartCf), IRON, Enum.Material.Metal, g)
	decor("CartLip", Vector3.new(3.5, 0.28, 4.3), at(cartCf * CFrame.new(0, 1.05, 0)), IRON_L, Enum.Material.Metal, g)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1.2, 1.2 }) do
			cylinder("CartWheel", 1.0, 0.28,
				at(cartCf * CFrame.new(sx * 1.6, -1.0, sz) * CFrame.Angles(0, 0, math.rad(90))),
				IRON_L, Enum.Material.Metal, g)
		end
	end
	-- Ore heaped above the rim
	for i = 1, 7 do
		local a = i * 1.6
		decor("CartOre" .. i, Vector3.new(0.8, 0.7, 0.8),
			at(cartCf * CFrame.new(math.cos(a) * 0.9, 1.15 + (i % 3) * 0.18, math.sin(a) * 1.2)
				* CFrame.Angles(a, a * 0.7, 0)),
			EMBER, Enum.Material.Neon, g)
	end
	glow(part("CartGlow", Vector3.new(0.4, 0.4, 0.4), at(cartCf * CFrame.new(0, 1.4, 0)), EMBER, Enum.Material.Neon, g),
		EMBER, 1.1, 14)

	-- Weighing scales beside the cart
	local scaleCf = CFrame.new(-5.6, base, 2.0)
	part("ScalePost", Vector3.new(0.5, 4.4, 0.5), at(scaleCf * CFrame.new(0, 2.2, 0)), IRON, Enum.Material.Metal, g)
	decor("ScaleBeam", Vector3.new(4.6, 0.28, 0.28), at(scaleCf * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(-7))),
		IRON_L, Enum.Material.Metal, g)
	for _, sx in ipairs({ -1, 1 }) do
		decor("ScaleChain", Vector3.new(0.1, 1.1, 0.1), at(scaleCf * CFrame.new(sx * 2.1, 3.7, 0)), IRON, Enum.Material.Metal, g)
		cylinder("ScalePan", 1.6, 0.16, at(scaleCf * CFrame.new(sx * 2.1, 3.1, 0)), IRON_L, Enum.Material.Metal, g)
	end

	-- Sacks and crates on the other side
	crate(at(CFrame.new(5.3, base + 0.85, -1.0)), 1.7, g)
	crate(at(CFrame.new(5.3, base + 2.5, -1.0) * CFrame.Angles(0, 0.4, 0)), 1.5, g)
	crate(at(CFrame.new(5.4, base + 0.8, 1.6)), 1.6, g)
	for i = 1, 3 do
		local sack = decor("Sack", Vector3.new(1.3, 1.5, 1.3),
			at(CFrame.new(-5.4, base + 0.75, -2.2 + i * 0.2) * CFrame.Angles(0, i * 0.8, 0)),
			CANVAS, Enum.Material.Fabric, g)
		sack.Position = sack.Position + Vector3.new(i * 0.4, 0, -i * 1.4)
	end
end

-- FORGE: furnace, anvil, bellows, quench barrel, racked stock.
local function forgeScene(cf, g, base)
	local function at(offset) return cf * offset end

	-- Stone furnace against the back wall
	local furnaceCf = CFrame.new(-3.4, base, -5.2)
	part("Furnace", Vector3.new(5.6, 5.0, 3.4), at(furnaceCf * CFrame.new(0, 2.5, 0)), STONE, Enum.Material.Slate, g)
	part("FurnaceBase", Vector3.new(6.2, 0.7, 4.0), at(furnaceCf * CFrame.new(0, 0.35, 0)), STONE_D, Enum.Material.Slate, g)

	-- Glowing mouth
	local mouth = decor("FurnaceMouth", Vector3.new(2.6, 1.9, 0.5),
		at(furnaceCf * CFrame.new(0, 2.0, 1.75)), EMBER, Enum.Material.Neon, g)
	glow(mouth, EMBER, 2.2, 26)
	emitter(mouth, { texture = "rbxasset://textures/particles/fire_main.dds",
		colour = EMBER, rate = 14, size = 1.1, speed = 1.4, life = 0.7, emission = 0.9 })
	decor("FurnaceArch", Vector3.new(3.2, 0.6, 0.7), at(furnaceCf * CFrame.new(0, 3.1, 1.75)), STONE_D, Enum.Material.Slate, g)

	-- Chimney rising through the roof, smoking
	local chim = part("Chimney", Vector3.new(2.2, 9.0, 2.2), at(furnaceCf * CFrame.new(0, 9.0, 0)), STONE, Enum.Material.Slate, g)
	decor("ChimneyCap", Vector3.new(2.8, 0.6, 2.8), at(furnaceCf * CFrame.new(0, 13.7, 0)), STONE_D, Enum.Material.Slate, g)
	emitter(chim, { colour = Color3.fromRGB(80, 76, 72), rate = 5, size = 1.6, endSize = 5,
		speed = 3.5, life = 2.4, transparency = 0.6, accel = Vector3.new(1.2, 3, 0), emission = 0.1 })

	-- Bellows beside the furnace
	part("BellowsBoard", Vector3.new(1.4, 0.4, 3.0), at(CFrame.new(-6.6, base + 2.3, -3.4)), TIMBER, Enum.Material.Wood, g)
	decor("BellowsBag", Vector3.new(1.6, 1.0, 2.4), at(CFrame.new(-6.6, base + 1.7, -3.4)), Color3.fromRGB(96, 62, 44), Enum.Material.Fabric, g)
	decor("BellowsNose", Vector3.new(0.4, 0.4, 1.6), at(CFrame.new(-6.6, base + 2.0, -1.6)), IRON, Enum.Material.Metal, g)
	decor("BellowsHandle", Vector3.new(0.3, 0.3, 2.0), at(CFrame.new(-6.6, base + 2.8, -4.8)), TIMBER_D, Enum.Material.Wood, g)

	-- Anvil on a stump, dead centre where the smith would stand
	local stump = CFrame.new(1.8, base, 0.4)
	cylinder("Stump", 2.4, 2.0, at(stump * CFrame.new(0, 1.0, 0)), TIMBER_D, Enum.Material.Wood, g)
	part("AnvilBody", Vector3.new(2.6, 0.9, 1.3), at(stump * CFrame.new(0, 2.45, 0)), IRON, Enum.Material.Metal, g)
	decor("AnvilWaist", Vector3.new(1.2, 0.5, 1.0), at(stump * CFrame.new(0, 1.85, 0)), IRON, Enum.Material.Metal, g)
	decor("AnvilFoot", Vector3.new(2.0, 0.35, 1.2), at(stump * CFrame.new(0, 1.5, 0)), IRON, Enum.Material.Metal, g)
	decor("AnvilHorn", Vector3.new(1.2, 0.55, 0.7), at(stump * CFrame.new(1.7, 2.5, 0) * CFrame.Angles(0, 0, math.rad(-6))),
		IRON_L, Enum.Material.Metal, g)

	-- Hot bar on the anvil, with sparks
	local hot = decor("HotBar", Vector3.new(1.6, 0.18, 0.4), at(stump * CFrame.new(-0.3, 2.98, 0)), EMBER, Enum.Material.Neon, g)
	glow(hot, EMBER, 1.1, 12)
	emitter(hot, { texture = "rbxasset://textures/particles/sparkles_main.dds",
		colour = Color3.fromRGB(255, 196, 108), rate = 16, size = 0.35, speed = 4,
		life = 0.4, spread = 60, emission = 1, accel = Vector3.new(0, -6, 0) })

	-- The hammer works on its own. It lifts slowly, falls fast, and the bar
	-- flares white when it lands — two parts moving on a timer, which costs
	-- nothing and does more for the room than any amount of geometry.
	local pivotCf = at(stump * CFrame.new(-1.5, 3.7, 1.1))
	local haft = decor("HammerHaft", Vector3.new(0.24, 2.4, 0.24), pivotCf, TIMBER, Enum.Material.Wood, g)
	local head = decor("HammerHead", Vector3.new(0.64, 0.6, 1.3), pivotCf, IRON, Enum.Material.Metal, g)

	task.spawn(function()
		local RAISED, STRUCK = math.rad(-76), math.rad(12)

		local function pose(a)
			local arm = pivotCf * CFrame.Angles(a, 0, 0)
			haft.CFrame = arm * CFrame.new(0, -1.2, 0)
			head.CFrame = arm * CFrame.new(0, -2.5, 0)
		end

		while haft.Parent do
			-- Down, accelerating
			for t = 0, 1, 0.2 do
				pose(RAISED + (STRUCK - RAISED) * t * t)
				task.wait(0.03)
			end

			hot.Color = Color3.fromRGB(255, 240, 200)
			task.wait(0.09)
			hot.Color = EMBER

			-- Up, taking its time
			for t = 1, 0, -0.1 do
				pose(RAISED + (STRUCK - RAISED) * t * t)
				task.wait(0.035)
			end
			task.wait(0.55)
		end
	end)

	-- Quench barrel, water dark on top
	barrel(at(CFrame.new(4.8, base + 1.2, -2.2)), g, Color3.fromRGB(52, 74, 88))

	-- Stock rack on the right wall: bars and finished plate
	part("RackPost", Vector3.new(0.4, 4.0, 0.4), at(CFrame.new(6.2, base + 2.0, 1.2)), TIMBER_D, Enum.Material.Wood, g)
	decor("RackBar", Vector3.new(0.35, 0.35, 4.4), at(CFrame.new(6.2, base + 3.6, 1.2)), TIMBER_D, Enum.Material.Wood, g)
	for i = 1, 4 do
		decor("Stock" .. i, Vector3.new(0.28, 2.4, 0.28),
			at(CFrame.new(6.2, base + 2.3, -0.6 + i * 0.75) * CFrame.Angles(math.rad(6), 0, 0)),
			i % 2 == 0 and IRON_L or IRON, Enum.Material.Metal, g)
	end

	-- Cooling ingots on a low bench
	part("BenchTop", Vector3.new(3.4, 0.3, 1.6), at(CFrame.new(4.6, base + 1.7, 2.6)), PLANK, Enum.Material.WoodPlanks, g)
	for _, sx in ipairs({ -1, 1 }) do
		decor("BenchLeg", Vector3.new(0.3, 1.6, 0.3), at(CFrame.new(4.6 + sx * 1.4, base + 0.85, 2.6)), TIMBER_D, Enum.Material.Wood, g)
	end
	for i = 1, 3 do
		decor("Ingot" .. i, Vector3.new(0.9, 0.28, 0.5),
			at(CFrame.new(3.6 + i * 0.7, base + 2.0, 2.6) * CFrame.Angles(0, i * 0.4, 0)),
			IRON_L, Enum.Material.Metal, g)
	end
end

-- PICK WORKS: grindstone, workbench, racked picks, haft barrel.
local function pickScene(cf, g, base)
	local function at(offset) return cf * offset end

	-- Grindstone on a timber frame, turning
	local gcf = CFrame.new(-3.2, base, 1.0)
	for _, sx in ipairs({ -1, 1 }) do
		part("GrindLeg", Vector3.new(0.5, 3.0, 0.5), at(gcf * CFrame.new(sx * 1.6, 1.5, 0)), TIMBER, Enum.Material.Wood, g)
	end
	decor("GrindBeam", Vector3.new(3.6, 0.4, 0.4), at(gcf * CFrame.new(0, 3.0, 0)), TIMBER_D, Enum.Material.Wood, g)

	local wheel = cylinder("Grindstone", 3.2, 0.6,
		at(gcf * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90))), STONE, Enum.Material.Concrete, g)
	local hub = decor("GrindHub", Vector3.new(0.5, 1.1, 0.5),
		at(gcf * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90))), IRON, Enum.Material.Metal, g)

	-- Sparks off the stone where a blade would meet it
	local spark = decor("GrindSpark", Vector3.new(0.3, 0.3, 0.3), at(gcf * CFrame.new(0, 3.9, 0.4)),
		Color3.fromRGB(255, 214, 140), Enum.Material.Neon, g)
	spark.Transparency = 1
	emitter(spark, { texture = "rbxasset://textures/particles/sparkles_main.dds",
		colour = Color3.fromRGB(255, 206, 130), rate = 20, size = 0.3, speed = 7,
		life = 0.35, spread = 30, emission = 1, accel = Vector3.new(0, -10, 0) })
	glow(spark, Color3.fromRGB(255, 206, 130), 0.7, 10)

	-- Treadle below it
	decor("Treadle", Vector3.new(2.0, 0.24, 0.9), at(gcf * CFrame.new(0, 0.5, 1.3) * CFrame.Angles(math.rad(7), 0, 0)),
		TIMBER_D, Enum.Material.Wood, g)

	-- Workbench along the back
	part("BenchTop", Vector3.new(8.0, 0.4, 2.2), at(CFrame.new(1.6, base + 2.2, -5.0)), PLANK, Enum.Material.WoodPlanks, g)
	for _, sx in ipairs({ -1, 1 }) do
		part("BenchLeg", Vector3.new(0.5, 2.2, 0.5), at(CFrame.new(1.6 + sx * 3.5, base + 1.1, -5.0)), TIMBER, Enum.Material.Wood, g)
	end
	-- Pick heads and hafts laid out on it
	for i = 1, 3 do
		decor("HeadStock" .. i, Vector3.new(1.9, 0.34, 0.42),
			at(CFrame.new(-0.6 + i * 1.5, base + 2.55, -5.2) * CFrame.Angles(0, i * 0.3, 0)), IRON_L, Enum.Material.Metal, g)
	end
	decor("Vice", Vector3.new(0.8, 0.9, 0.8), at(CFrame.new(4.4, base + 2.7, -5.0)), IRON, Enum.Material.Metal, g)

	-- Rack of finished picks on the right wall
	part("PickRack", Vector3.new(0.4, 4.2, 0.4), at(CFrame.new(6.0, base + 2.1, 0.6)), TIMBER_D, Enum.Material.Wood, g)
	decor("PickRail", Vector3.new(0.32, 0.32, 5.0), at(CFrame.new(6.0, base + 3.8, 0.6)), TIMBER_D, Enum.Material.Wood, g)
	for i = 1, 3 do
		local z = -1.2 + i * 1.2
		decor("PickHaft" .. i, Vector3.new(0.22, 2.6, 0.22),
			at(CFrame.new(5.8, base + 2.4, z) * CFrame.Angles(math.rad(8), 0, 0)), TIMBER, Enum.Material.Wood, g)
		decor("PickHead" .. i, Vector3.new(0.3, 0.34, 1.7),
			at(CFrame.new(5.8, base + 3.6, z)), IRON_L, Enum.Material.Metal, g)
	end

	-- Barrel of spare hafts, ends poking out
	barrel(at(CFrame.new(4.6, base + 1.2, 3.2)), g)
	for i = 1, 5 do
		decor("Haft" .. i, Vector3.new(0.2, 2.6, 0.2),
			at(CFrame.new(4.6 + (i - 3) * 0.28, base + 2.9, 3.2 + (i % 2) * 0.3)
				* CFrame.Angles(math.rad((i - 3) * 7), 0, math.rad((i % 3 - 1) * 8))),
			TIMBER, Enum.Material.Wood, g)
	end

	-- Offcuts and a whetstone crate
	crate(at(CFrame.new(-6.0, base + 0.85, -2.4)), 1.7, g)
	logPile(at(CFrame.new(-5.6, base + 0.5, 3.4)), g, 2)

	-- Slow turn on the stone; one part, so the replication cost is trivial
	local spin = 0
	task.spawn(function()
		while wheel.Parent do
			spin += 0.16
			local turn = at(gcf * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, spin, 0))
			wheel.CFrame = turn
			hub.CFrame   = turn
			task.wait(0.06)
		end
	end)
end

-- WINCH: the drum and gearing that runs the headframe cable.
local function winchScene(cf, g, base)
	local function at(offset) return cf * offset end

	-- Drum bed
	part("DrumBed", Vector3.new(9.0, 0.8, 4.0), at(CFrame.new(0, base + 0.4, -1.0)), TIMBER_D, Enum.Material.Wood, g)
	for _, sx in ipairs({ -1, 1 }) do
		part("DrumStand", Vector3.new(0.9, 3.2, 2.4), at(CFrame.new(sx * 3.6, base + 2.4, -1.0)), IRON, Enum.Material.Metal, g)
	end

	-- The drum itself, with wound cable bands
	local drumCf = CFrame.new(0, base + 3.2, -1.0) * CFrame.Angles(0, 0, math.rad(90))
	local drum = cylinder("Drum", 3.4, 6.4, at(drumCf), IRON, Enum.Material.Metal, g)
	local winds = {}
	for i = -6, 6 do
		local w = cylinder("Wind" .. (i + 7), 3.62, 0.34, at(drumCf * CFrame.new(0, i * 0.44, 0)),
			i % 2 == 0 and IRON_L or Color3.fromRGB(66, 70, 76), Enum.Material.Metal, g)
		winds[#winds + 1] = { part = w, along = i * 0.44 }
	end

	-- The drum turns, slowly, like something is being hauled up. The wound
	-- cable turns with it, which is what sells the rotation.
	task.spawn(function()
		local spin = 0
		while drum.Parent do
			spin += 0.05
			local turn = at(drumCf * CFrame.Angles(0, spin, 0))
			drum.CFrame = turn
			for _, w in ipairs(winds) do
				w.part.CFrame = turn * CFrame.new(0, w.along, 0)
			end
			task.wait(0.06)
		end
	end)
	for _, sx in ipairs({ -1, 1 }) do
		cylinder("DrumFlange", 4.4, 0.5, at(drumCf * CFrame.new(0, sx * 3.3, 0)), IRON_L, Enum.Material.Metal, g)
	end

	-- Gear wheel on one end, with teeth
	local gearCf = CFrame.new(4.6, base + 3.2, -1.0) * CFrame.Angles(0, 0, math.rad(90))
	cylinder("Gear", 3.0, 0.5, at(gearCf), IRON_L, Enum.Material.Metal, g)
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		decor("Tooth" .. i, Vector3.new(0.5, 0.5, 0.6),
			at(gearCf * CFrame.new(math.cos(a) * 1.65, 0, math.sin(a) * 1.65) * CFrame.Angles(0, -a, 0)),
			IRON_L, Enum.Material.Metal, g)
	end

	-- Control lever and panel
	part("Panel", Vector3.new(2.2, 2.6, 0.6), at(CFrame.new(-5.4, base + 2.5, 2.2)), TIMBER, Enum.Material.Wood, g)
	decor("Lever", Vector3.new(0.26, 2.4, 0.26),
		at(CFrame.new(-5.4, base + 4.4, 2.2) * CFrame.Angles(math.rad(-24), 0, 0)), IRON_L, Enum.Material.Metal, g)
	decor("LeverKnob", Vector3.new(0.55, 0.55, 0.55), at(CFrame.new(-5.4, base + 5.4, 1.7)),
		Color3.fromRGB(178, 74, 58), Enum.Material.SmoothPlastic, g)
	for i, colour in ipairs({ Color3.fromRGB(120, 200, 120), Color3.fromRGB(220, 180, 80) }) do
		local bulb = decor("Bulb" .. i, Vector3.new(0.4, 0.4, 0.3),
			at(CFrame.new(-6.0 + i * 0.8, base + 3.2, 2.55)), colour, Enum.Material.Neon, g)
		glow(bulb, colour, 0.5, 7)
	end

	-- Cable leaving toward the shaft
	decor("Cable", Vector3.new(0.22, 0.22, 9.0), at(CFrame.new(0, base + 4.4, 4.0) * CFrame.Angles(math.rad(-8), 0, 0)),
		Color3.fromRGB(58, 60, 66), Enum.Material.Metal, g)

	-- Chain coil and oil cans
	for i = 1, 3 do
		cylinder("Coil" .. i, 2.2 - i * 0.35, 0.32, at(CFrame.new(5.4, base + 0.9 + i * 0.3, 3.0)),
			Color3.fromRGB(72, 76, 82), Enum.Material.Metal, g)
	end
	for i = 1, 2 do
		decor("OilCan" .. i, Vector3.new(0.8, 1.1, 0.8), at(CFrame.new(-4.4 + i * 1.1, base + 0.75, -3.6)),
			Color3.fromRGB(96, 108, 96), Enum.Material.Metal, g)
	end
	crate(at(CFrame.new(6.0, base + 0.85, -3.4)), 1.6, g)
end

-- ── Plaza ────────────────────────────────────────────────────────────────────

local function plaza()
	local size, shaft = S.PlatformSize, S.ShaftSize
	local arm = (size - shaft) / 2
	local off = shaft / 2 + arm / 2

	for i, s in ipairs({
		{ Vector3.new(arm, 2, size),  Vector3.new(-off, Y - 1, 0) },
		{ Vector3.new(arm, 2, size),  Vector3.new( off, Y - 1, 0) },
		{ Vector3.new(shaft, 2, arm), Vector3.new(0, Y - 1, -off) },
		{ Vector3.new(shaft, 2, arm), Vector3.new(0, Y - 1,  off) },
	}) do
		part("Deck" .. i, s[1], CFrame.new(s[2]), DECK, Enum.Material.Slate)
	end

	-- The plank decking and the shaft lip that used to sit here are now part
	-- of the lodge floor, which is built over this whole area.
end

local function perimeter()
	local half = S.PlatformSize / 2
	for _, axis in ipairs({ "x", "z" }) do
		for i = -half + 7, half - 7, 14 do
			for _, sign in ipairs({ -1, 1 }) do
				local pos = axis == "x"
					and Vector3.new(i, Y + 2.0, sign * half)
					or  Vector3.new(sign * half, Y + 2.0, i)
				part("Post", Vector3.new(0.7, 4.0, 0.7), CFrame.new(pos), TIMBER, Enum.Material.Wood)
			end
		end
	end
	for _, s in ipairs({
		{ Vector3.new(S.PlatformSize, 0.4, 0.4), Vector3.new(0, Y + 3.6, -half) },
		{ Vector3.new(S.PlatformSize, 0.4, 0.4), Vector3.new(0, Y + 3.6,  half) },
		{ Vector3.new(0.4, 0.4, S.PlatformSize), Vector3.new(-half, Y + 3.6, 0) },
		{ Vector3.new(0.4, 0.4, S.PlatformSize), Vector3.new( half, Y + 3.6, 0) },
	}) do
		decor("Rail", s[1], CFrame.new(s[2]), TIMBER_D, Enum.Material.Wood)
	end

	-- Lantern posts on the corners
	for _, c in ipairs({ {-1,-1}, {1,-1}, {-1,1}, {1,1} }) do
		lantern(CFrame.new(c[1] * (half - 6), Y + 7.5, c[2] * (half - 6)), camp, true)
	end
end

-- ── Headframe ────────────────────────────────────────────────────────────────

local function headframe()
	local leg = S.ShaftSize / 2 + 2
	local top = 30

	for _, c in ipairs({ {-leg,-leg}, {leg,-leg}, {-leg,leg}, {leg,leg} }) do
		part("Leg", Vector3.new(1.5, top, 1.5), CFrame.new(c[1], Y + top / 2, c[2]), TIMBER, Enum.Material.Wood)
		decor("LegShoe", Vector3.new(2.1, 0.8, 2.1), CFrame.new(c[1], Y + 0.4, c[2]), IRON, Enum.Material.Metal)
	end

	local span = leg * 2
	for _, h in ipairs({ 11, 20, 28 }) do
		for _, s in ipairs({
			{ Vector3.new(span, 0.6, 0.6), Vector3.new(0, Y + h, -leg) },
			{ Vector3.new(span, 0.6, 0.6), Vector3.new(0, Y + h,  leg) },
			{ Vector3.new(0.6, 0.6, span), Vector3.new(-leg, Y + h, 0) },
			{ Vector3.new(0.6, 0.6, span), Vector3.new( leg, Y + h, 0) },
		}) do
			decor("Brace", s[1], CFrame.new(s[2]), TIMBER_D, Enum.Material.Wood)
		end
	end

	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -leg, leg }) do
			decor("Diagonal", Vector3.new(0.45, 21, 0.45),
				CFrame.new(0, Y + 16, z) * CFrame.Angles(0, 0, math.rad(s * 38)), TIMBER_D, Enum.Material.Wood)
		end
	end

	local hub = decor("Sheave", Vector3.new(1.6, 8, 8), CFrame.new(0, Y + 32, 0),
		Color3.fromRGB(170, 84, 62), Enum.Material.Metal)
	Instance.new("CylinderMesh").Parent = hub
	decor("SheaveHub", Vector3.new(1.8, 2.4, 2.4), CFrame.new(0, Y + 32, 0), IRON, Enum.Material.Metal)
	decor("Gantry", Vector3.new(3.6, 1.0, span + 6), CFrame.new(0, Y + 29.5, 0), TIMBER, Enum.Material.Wood)
	-- Stops above the cage. It used to run to the deck, which now means running
	-- down the middle of a lift that is standing at the mouth.
	decor("Cable", Vector3.new(0.24, 13, 0.24), CFrame.new(0, Y + 25.5, 0), IRON, Enum.Material.Metal)

	local beacon = decor("Beacon", Vector3.new(1.6, 1.2, 1.6), CFrame.new(0, Y + 33.6, 0),
		Color3.fromRGB(226, 96, 76), Enum.Material.Neon)
	glow(beacon, Color3.fromRGB(226, 96, 76), 1.2, 32)

	local sign = decor("HeadSign", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, Y + 8, 0), TIMBER)
	sign.Transparency = 1
	billboard(sign, "THE SHAFT", "the cage runs from here — sign for a contract", HAZARD, 10)
end

-- ── Boundary wall ────────────────────────────────────────────────────────────
-- A ring of worked stone enclosing the whole claim, so the edge of the world
-- reads as somewhere that ends on purpose rather than somewhere that ran out.
-- Four arched gateways line up with the four paths out of the shaft.

-- Centred 3 studs inside the rock's edge: the wall is 6 thick, so its outer
-- face lands exactly where the terrain stops and there is no gap between them.
local WALL_R      = StrataConfig.Mine.Radius - 3
local WALL_FOOT   = -16          -- sunk into the rock so the wall never hovers
local WALL_H      = 46
-- Segments are sized from the circumference rather than counted, so a bigger
-- claim gets more of them instead of coarser ones.
local WALL_STEPS  = math.floor((math.pi * 2 * WALL_R) / 13)
-- Half-width of a gateway, in radians. Derived from a fixed 21 studs, because
-- the gateway itself is a fixed size: a constant angle would open a hole in the
-- wall wider than the arch built to fill it.
local GATE_ARC    = 21 / WALL_R

local WALL_STONE   = Color3.fromRGB(146, 140, 130)
local WALL_STONE_D = Color3.fromRGB(112, 107, 100)
local WALL_MOSS    = Color3.fromRGB(108, 128, 88)
local CRYSTAL      = Color3.fromRGB(150, 206, 226)

local function nearGate(angle)
	for _, gate in ipairs({ 0, math.pi / 2, math.pi, math.pi * 1.5 }) do
		local d = math.abs(((angle - gate + math.pi) % (math.pi * 2)) - math.pi)
		if d < GATE_ARC then return true end
	end
	return false
end

local function gateway(angle, accent)
	local out  = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local face = CFrame.new(out * WALL_R) * CFrame.Angles(0, -angle, 0)
	local base = Y - 2

	-- Piers either side of the opening
	for _, sx in ipairs({ -1, 1 }) do
		-- Runs down into the rock like the wall does, so the gate never hovers
		local pierTop = base + WALL_H + 8
		part("GatePier", Vector3.new(7, pierTop - WALL_FOOT, 12),
			face * CFrame.new(0, (pierTop + WALL_FOOT) / 2, sx * 20), WALL_STONE, Enum.Material.Slate)
		decor("GateCap", Vector3.new(9, 2.4, 14),
			face * CFrame.new(0, base + WALL_H + 9, sx * 20), WALL_STONE_D, Enum.Material.Slate)
		-- Stepped shoulders into the wall proper
		decor("GateShoulder", Vector3.new(6, 8, 8),
			face * CFrame.new(0, base + WALL_H + 2, sx * 29), WALL_STONE_D, Enum.Material.Slate)
	end

	-- Arch over the opening, approximated with rotated voussoirs
	for i = -4, 4 do
		local t  = i / 4
		local a  = t * math.rad(62)
		local yy = base + WALL_H - 6 + math.cos(a) * 9
		local zz = math.sin(a) * 15
		decor("Voussoir", Vector3.new(6.5, 4.2, 5.0),
			face * CFrame.new(0, yy, zz) * CFrame.Angles(a, 0, 0), WALL_STONE, Enum.Material.Slate)
	end

	-- Keystone, painted so each gate reads as its own doorway
	decor("Keystone", Vector3.new(7.5, 5.2, 5.2),
		face * CFrame.new(0, base + WALL_H + 4.4, 0), accent, Enum.Material.Slate)

	-- Barred timber doors. The claim is an island now, so an open arch would
	-- walk you straight off the edge — the gate is a landmark, not an exit.
	local doorTop = base + WALL_H - 5
	local doorBot = WALL_FOOT + 10
	local doorH   = doorTop - doorBot
	for _, sx in ipairs({ -1, 1 }) do
		part("GateDoor", Vector3.new(2.4, doorH, 13.6),
			face * CFrame.new(0.8, (doorTop + doorBot) / 2, sx * 6.9), TIMBER_D, Enum.Material.WoodPlanks)
		for b = 1, 3 do
			decor("DoorBand", Vector3.new(2.7, 0.8, 13.9),
				face * CFrame.new(0.8, doorBot + doorH * (b / 4), sx * 6.9), IRON, Enum.Material.Metal)
		end
	end

	-- Lanterns just proud of the piers' inner faces, where they can be seen
	for _, sx in ipairs({ -1, 1 }) do
		lantern(face * CFrame.new(-4.4, base + WALL_H - 6, sx * 15.5), camp, false)
	end

	-- Banners hanging in front of the doors rather than inside them
	for _, sx in ipairs({ -1, 1 }) do
		decor("Banner", Vector3.new(0.4, 12, 4.5),
			face * CFrame.new(-1.8, base + WALL_H - 14, sx * 9), accent, Enum.Material.Fabric)
	end
end

local function boundaryWall()
	local base = Y - 2

	for i = 0, WALL_STEPS - 1 do
		local angle = (i / WALL_STEPS) * math.pi * 2
		if not nearGate(angle) then
			local out  = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local face = CFrame.new(out * WALL_R) * CFrame.Angles(0, -angle, 0)

			-- Height wobbles so the ring reads as built up over time
			local wob = math.sin(i * 0.7) * 4 + math.sin(i * 1.9) * 2.5
			local h   = WALL_H + wob
			local seg = (math.pi * 2 * WALL_R) / WALL_STEPS

			-- Runs from well under the rock up to the crenellations, so the wall
			-- meets the ground instead of standing on stilts above it
			local top = base + h
			part("Wall", Vector3.new(6, top - WALL_FOOT, seg * 1.25),
				face * CFrame.new(0, (top + WALL_FOOT) / 2, 0),
				i % 3 == 0 and WALL_STONE_D or WALL_STONE, Enum.Material.Slate)

			-- Crenellations along the top
			if i % 2 == 0 then
				decor("Merlon", Vector3.new(6.6, 3.4, seg * 0.6),
					face * CFrame.new(0, base + h + 1.7, 0), WALL_STONE_D, Enum.Material.Slate)
			end

			-- Buttresses every so often, stepping out from the base
			if i % 8 == 0 then
				local bTop = base + h * 0.62
				part("Buttress", Vector3.new(5, bTop - WALL_FOOT, 5),
					face * CFrame.new(-4.5, (bTop + WALL_FOOT) / 2, 0), WALL_STONE_D, Enum.Material.Slate)
				part("ButtressFoot", Vector3.new(7, 5, 7),
					face * CFrame.new(-5.5, StrataConfig.Mine.SurfaceY + 0.5, 0), WALL_STONE_D, Enum.Material.Slate)
			end

			-- Moss shelves and a crystal seam, so the stone is not uniform
			if i % 5 == 2 then
				decor("Moss", Vector3.new(6.4, 1.2, seg),
					face * CFrame.new(-0.2, base + h * 0.7, 0), WALL_MOSS, Enum.Material.Grass)
			end
			if i % 11 == 4 then
				local seam = decor("Seam", Vector3.new(1.4, 5, 1.4),
					face * CFrame.new(-3.2, base + h * 0.45, 0) * CFrame.Angles(0, 0, math.rad(18)),
					CRYSTAL, Enum.Material.Neon)
				glow(seam, CRYSTAL, 0.7, 18)
			end

			-- Lantern posts at intervals, facing inward
			if i % 12 == 6 then
				lantern(face * CFrame.new(-3.6, base + 12, 0), camp, false)
			end
		end
	end

	-- Gateways aligned with the four paths
	gateway(0,             ZONES.sell.accent)
	gateway(math.pi,       ZONES.craft.accent)
	gateway(math.pi / 2,   ZONES.lift.accent)
	gateway(math.pi * 1.5, ZONES.pickaxe.accent)

end

-- ── Paths and spawn ──────────────────────────────────────────────────────────

local function pathTo(target, accent)
	local dir  = Vector3.new(target.X, 0, target.Z)
	local dist = dir.Magnitude
	if dist < 1 then return end
	local unit = dir.Unit

	local startAt = S.ShaftSize / 2 + 8
	local length  = dist - S.RingSize / 2 - startAt - 1   -- stop short of the ring
	if length <= 0 then return end

	local steps = math.floor(length / 3.4)
	for i = 1, steps do
		local at  = unit * (startAt + (i - 0.5) * (length / steps))
		local cfr = CFrame.new(Vector3.new(at.X, Y + 0.07, at.Z),
			Vector3.new(at.X + unit.X, Y + 0.07, at.Z + unit.Z))
		decor("Step" .. i, Vector3.new(4.4, 0.16, 2.2), cfr,
			i % 2 == 0 and PLANK or TIMBER, Enum.Material.WoodPlanks)
	end

	-- Marker post at the far end, painted in the zone colour
	local postAt = unit * (dist - S.RingSize / 2 - 1.5)
	local post = decor("Marker", Vector3.new(0.5, 3.4, 0.5),
		CFrame.new(postAt.X, Y + 1.7, postAt.Z), TIMBER_D, Enum.Material.Wood)
	decor("MarkerFlag", Vector3.new(1.6, 0.9, 0.2),
		CFrame.new(postAt.X, Y + 3.2, postAt.Z), accent, Enum.Material.SmoothPlastic)
	post.CanCollide = false
end

local function spawnPlatform()
	local pos = StrataConfig.Player.SpawnPosition

	-- The raised deck is gone: this is inside the lodge now, and the lodge has a
	-- floor. All that is left is the spawn itself, sitting flush in the boards.


	local spawn = Instance.new("SpawnLocation")
	spawn.Name       = "MineHead"
	spawn.Size       = Vector3.new(12, 0.4, 12)
	spawn.Position   = Vector3.new(pos.X, Y - 0.02, pos.Z)
	spawn.Anchored   = true
	spawn.Neutral    = true
	spawn.Material   = Enum.Material.WoodPlanks
	spawn.Color      = PLANK
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration   = 0
	spawn.Parent     = workspace

	for _, sx in ipairs({ -1, 1 }) do
		lantern(CFrame.new(pos.X + sx * 7, Y + 5.6, pos.Z), camp, true)
	end

	-- A little clutter so the spawn reads as somewhere people work
	barrel(CFrame.new(pos.X + 6.4, Y + 1.3, pos.Z - 5.8), camp)
	crate(CFrame.new(pos.X - 6.2, Y + 0.95, pos.Z - 5.4), 1.7, camp)
	logPile(CFrame.new(pos.X - 6.0, Y + 0.6, pos.Z + 5.6), camp, 3)
end

-- ── Build ────────────────────────────────────────────────────────────────────

-- ── The lodge ────────────────────────────────────────────────────────────────
-- A great timber hall built around the mine head. Two floors: the work happens
-- on the ground, and a gallery runs right round above it, open in the middle so
-- you can stand at the rail and watch the shaft.
--
-- The four stations are buildings *inside* the hall — each one a hut with its
-- own posts, roof, counter and sign, with the working scene under it. That is
-- what makes it read as a place people trade in rather than a room with
-- furniture pushed against the walls.
--
-- Light does the composition. Lantern boxes in a rank down each wall, two
-- chandeliers over the floor, the forge fire at one end, and daylight dropping
-- through the roof opening straight down the shaft. Everything between those is
-- meant to be dark.

local L        = S.Lodge
local LODGE_Y  = Y
local SHAFT_H  = S.ShaftSize / 2
local FLOOR_T  = 0.12                  -- how proud the boards sit over the deck

local lodge = Instance.new("Folder")
lodge.Name   = "Lodge"
lodge.Parent = camp

local BANNER  = Color3.fromRGB(146, 52, 44)
local BANNER_D = Color3.fromRGB(104, 36, 32)

local function lpart(name, size, cf, colour, material)
	return part(name, size, cf, colour, material, lodge)
end

local function ldecor(name, size, cf, colour, material)
	local p = lpart(name, size, cf, colour, material)
	p.CanCollide = false
	p.CanQuery   = false
	p.CastShadow = false
	return p
end

-- ── Boards ───────────────────────────────────────────────────────────────────
-- Laid as strips so the grain runs one way and the seams read, rather than one
-- flat slab the size of a car park.

local function boards(name, x0, x1, z0, z1, top, strip)
	strip = strip or 6
	local i = 0
	for x = x0, x1 - 0.01, strip do
		local w = math.min(strip, x1 - x)
		i += 1
		ldecor(name, Vector3.new(w - 0.14, 0.7, z1 - z0),
			CFrame.new(x + w / 2, top - 0.35, (z0 + z1) / 2),
			i % 2 == 0 and PLANK or TIMBER, Enum.Material.WoodPlanks)
	end
end

local function groundFloor()
	local top = LODGE_Y + FLOOR_T

	-- Four bands around the shaft opening
	boards("Board", -L.HalfX, L.HalfX, -L.HalfZ, -SHAFT_H, top)
	boards("Board", -L.HalfX, L.HalfX, SHAFT_H, L.HalfZ, top)
	boards("Board", -L.HalfX, -SHAFT_H, -SHAFT_H, SHAFT_H, top)
	boards("Board", SHAFT_H, L.HalfX, -SHAFT_H, SHAFT_H, top)

	-- Something solid underneath, sunk well below the deck so no two faces sit
	-- at the same height. In four bands like the boards above it, because the
	-- shaft is a real hole now: one slab across the middle would cap the bore
	-- a stud and a half under the grate.
	local arm = (L.HalfZ - SHAFT_H) / 2
	for _, band in ipairs({
		{ Vector3.new(L.HalfX * 2, 1.4, arm * 2), Vector3.new(0, LODGE_Y - 1.3, -SHAFT_H - arm) },
		{ Vector3.new(L.HalfX * 2, 1.4, arm * 2), Vector3.new(0, LODGE_Y - 1.3,  SHAFT_H + arm) },
		{ Vector3.new(L.HalfX - SHAFT_H, 1.4, SHAFT_H * 2),
		  Vector3.new(-(L.HalfX + SHAFT_H) / 2, LODGE_Y - 1.3, 0) },
		{ Vector3.new(L.HalfX - SHAFT_H, 1.4, SHAFT_H * 2),
		  Vector3.new( (L.HalfX + SHAFT_H) / 2, LODGE_Y - 1.3, 0) },
	}) do
		lpart("Substrate", band[1], CFrame.new(band[2]), STONE_D, Enum.Material.Slate)
	end
end

-- ── Shell ────────────────────────────────────────────────────────────────────

local function shell()
	local h   = L.Height
	local mid = LODGE_Y + h / 2

	for _, sx in ipairs({ -1, 1 }) do
		lpart("EndWall", Vector3.new(L.Wall, h, L.HalfZ * 2 + L.Wall * 2),
			CFrame.new(sx * L.HalfX, mid, 0), PLANK, Enum.Material.WoodPlanks)
	end

	lpart("BackWall", Vector3.new(L.HalfX * 2, h, L.Wall),
		CFrame.new(0, mid, -L.HalfZ), PLANK, Enum.Material.WoodPlanks)

	-- Front wall, opened for the doors
	local doorL, doorR = L.DoorX - L.DoorW / 2, L.DoorX + L.DoorW / 2
	for i, r in ipairs({
		{ from = -L.HalfX, to = doorL },
		{ from = doorR,    to = L.HalfX },
	}) do
		local w = r.to - r.from
		if w > 0 then
			lpart("FrontWall" .. i, Vector3.new(w, h, L.Wall),
				CFrame.new(r.from + w / 2, mid, L.HalfZ), PLANK, Enum.Material.WoodPlanks)
		end
	end
	lpart("DoorHead", Vector3.new(L.DoorW + 3, h - 17, L.Wall),
		CFrame.new(L.DoorX, LODGE_Y + 17 + (h - 17) / 2, L.HalfZ), PLANK, Enum.Material.WoodPlanks)

	-- Door frame, and the doors themselves standing open
	for _, sx in ipairs({ -1, 1 }) do
		lpart("DoorPost", Vector3.new(2.2, 18, 3),
			CFrame.new(L.DoorX + sx * (L.DoorW / 2 + 1), LODGE_Y + 9, L.HalfZ), TIMBER, Enum.Material.Wood)
		ldecor("DoorLeaf", Vector3.new(L.DoorW / 2 - 0.4, 15, 0.6),
			CFrame.new(L.DoorX + sx * (L.DoorW / 2 + 2.6), LODGE_Y + 7.5, L.HalfZ - 2.6)
				* CFrame.Angles(0, math.rad(sx * -62), 0), TIMBER_D, Enum.Material.Wood)
	end
	ldecor("DoorLintel", Vector3.new(L.DoorW + 8, 2.2, 3.4),
		CFrame.new(L.DoorX, LODGE_Y + 18.6, L.HalfZ), TIMBER, Enum.Material.Wood)

	-- Corner posts
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			lpart("Corner", Vector3.new(3, h + 2, 3),
				CFrame.new(sx * (L.HalfX - 1), LODGE_Y + (h + 2) / 2, sz * (L.HalfZ - 1)),
				TIMBER, Enum.Material.Wood)
		end
	end
end

-- ── Posts ────────────────────────────────────────────────────────────────────
-- The heavy braced timbers that hold the gallery up. These are the strongest
-- shape in the room, so they are what gives it its rhythm.

local function bracedPost(x, z, height)
	lpart("Post", Vector3.new(2.6, height, 2.6),
		CFrame.new(x, LODGE_Y + height / 2, z), TIMBER, Enum.Material.Wood)

	-- Knee braces at the head, on all four faces
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local len = 5.4
		ldecor("Brace", Vector3.new(1.2, len, 1.2),
			CFrame.new(x + d[1] * 1.9, LODGE_Y + height - 1.9, z + d[2] * 1.9)
				* CFrame.Angles(math.rad(d[2] * -45), 0, math.rad(d[1] * 45)),
			TIMBER_D, Enum.Material.Wood)
	end

	-- Iron collar, because a bare box does not read as a post
	ldecor("Collar", Vector3.new(3.1, 0.7, 3.1),
		CFrame.new(x, LODGE_Y + 3.4, z), IRON, Enum.Material.Metal)
end

-- ── Gallery ──────────────────────────────────────────────────────────────────
-- A floor round the edge at the height of the post heads, open to the hall.

local function railing(x0, x1, z0, z1, top)
	local along = (x1 - x0) > (z1 - z0)
	local len   = along and (x1 - x0) or (z1 - z0)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2

	for _, hgt in ipairs({ 1.2, 3.2 }) do
		ldecor("Rail", along and Vector3.new(len, 0.5, 0.6) or Vector3.new(0.6, 0.5, len),
			CFrame.new(cx, top + hgt, cz), TIMBER, Enum.Material.Wood)
	end
	-- Balusters
	local n = math.max(math.floor(len / 3), 1)
	for i = 0, n do
		local t = i / n
		ldecor("Baluster", Vector3.new(0.5, 3.2, 0.5),
			CFrame.new(x0 + (x1 - x0) * t, top + 1.6, z0 + (z1 - z0) * t),
			TIMBER_D, Enum.Material.Wood)
	end
	-- Solid rail cap, which is what you actually see from below
	ldecor("RailCap", along and Vector3.new(len, 0.5, 1.4) or Vector3.new(1.4, 0.5, len),
		CFrame.new(cx, top + 3.5, cz), TIMBER, Enum.Material.Wood)
end

local function gallery()
	local top   = LODGE_Y + L.Gallery
	local innerX = L.HalfX - L.Depth
	local innerZ = L.HalfZ - L.Depth

	-- Four decks around an open well
	boards("Gallery", -L.HalfX, L.HalfX, -L.HalfZ, -innerZ, top, 8)
	boards("Gallery", -L.HalfX, L.HalfX, innerZ, L.HalfZ, top, 8)
	boards("Gallery", -L.HalfX, -innerX, -innerZ, innerZ, top, 8)
	boards("Gallery", innerX, L.HalfX, -innerZ, innerZ, top, 8)

	-- Joists showing on the underside
	for x = -L.HalfX + 6, L.HalfX - 6, 6 do
		for _, sz in ipairs({ -1, 1 }) do
			ldecor("Joist", Vector3.new(1.0, 1.2, L.Depth),
				CFrame.new(x, top - 1.2, sz * (innerZ + L.Depth / 2)), TIMBER_D, Enum.Material.Wood)
		end
	end

	-- The rail all the way round the well, with a gap where the stairs land
	railing(-innerX, innerX, -innerZ, -innerZ, top)
	railing(-innerX, innerX, innerZ, innerZ, top)
	railing(-innerX, -innerX, -innerZ, innerZ, top)
	railing(innerX, innerX, -innerZ, innerZ, top)

	-- Posts under the gallery edge
	for x = -innerX, innerX, 16 do
		for _, sz in ipairs({ -1, 1 }) do
			bracedPost(x, sz * innerZ, L.Gallery)
		end
	end
	for z = -innerZ + 16, innerZ - 16, 16 do
		for _, sx in ipairs({ -1, 1 }) do
			bracedPost(sx * innerX, z, L.Gallery)
		end
	end
end

-- A run of steps up to the gallery, plus the stringer and a rail
local function stair(baseCf, rise, run, steps)
	for i = 1, steps do
		local h = rise * i / steps
		lpart("Step", Vector3.new(9, 0.6, run / steps + 0.4),
			baseCf * CFrame.new(0, h, -(i - 0.5) * run / steps), PLANK, Enum.Material.WoodPlanks)
		ldecor("Riser", Vector3.new(9, rise / steps, 0.4),
			baseCf * CFrame.new(0, h - rise / steps / 2, -(i - 1) * run / steps),
			TIMBER_D, Enum.Material.Wood)
	end

	for _, sx in ipairs({ -1, 1 }) do
		ldecor("Stringer", Vector3.new(0.8, 1.6, math.sqrt(rise * rise + run * run)),
			baseCf * CFrame.new(sx * 4.9, rise / 2 - 0.4, -run / 2)
				* CFrame.Angles(math.rad(math.deg(math.atan2(rise, run))), 0, 0),
			TIMBER, Enum.Material.Wood)
		ldecor("StairRail", Vector3.new(0.5, 0.5, math.sqrt(rise * rise + run * run)),
			baseCf * CFrame.new(sx * 4.9, rise / 2 + 3.2, -run / 2)
				* CFrame.Angles(math.rad(math.deg(math.atan2(rise, run))), 0, 0),
			TIMBER, Enum.Material.Wood)
		for i = 0, steps, 2 do
			ldecor("StairPost", Vector3.new(0.45, 3.6, 0.45),
				baseCf * CFrame.new(sx * 4.9, rise * i / steps + 1.6, -(i) * run / steps),
				TIMBER_D, Enum.Material.Wood)
		end
	end
end

-- ── Roof ─────────────────────────────────────────────────────────────────────

local function roof()
	local top  = LODGE_Y + L.Height
	local half = L.Opening / 2

	-- Rafters, and the tie beams they sit on
	for x = -L.HalfX + 8, L.HalfX - 8, 8 do
		if math.abs(x) > half + 3 then
			ldecor("Tie", Vector3.new(1.6, 1.4, L.HalfZ * 2),
				CFrame.new(x, top - 1, 0), TIMBER, Enum.Material.Wood)
		else
			for _, sz in ipairs({ -1, 1 }) do
				local d = L.HalfZ - half
				ldecor("Tie", Vector3.new(1.6, 1.4, d),
					CFrame.new(x, top - 1, sz * (half + d / 2)), TIMBER, Enum.Material.Wood)
			end
		end
	end

	local panels = {
		{ Vector3.new(L.HalfX * 2, 1.2, L.HalfZ - half), Vector3.new(0, top, -(half + (L.HalfZ - half) / 2)) },
		{ Vector3.new(L.HalfX * 2, 1.2, L.HalfZ - half), Vector3.new(0, top,  (half + (L.HalfZ - half) / 2)) },
		{ Vector3.new(L.HalfX - half, 1.2, L.Opening),   Vector3.new(-(half + (L.HalfX - half) / 2), top, 0) },
		{ Vector3.new(L.HalfX - half, 1.2, L.Opening),   Vector3.new( (half + (L.HalfX - half) / 2), top, 0) },
	}
	for i, p in ipairs(panels) do
		lpart("Roof" .. i, p[1], CFrame.new(p[2]), TIMBER_D, Enum.Material.WoodPlanks)
	end

	for _, sx in ipairs({ -1, 1 }) do
		ldecor("OpenLip", Vector3.new(1.2, 2.6, L.Opening + 2.4),
			CFrame.new(sx * half, top + 1.9, 0), TIMBER, Enum.Material.Wood)
		ldecor("OpenLip", Vector3.new(L.Opening + 2.4, 2.6, 1.2),
			CFrame.new(0, top + 1.9, sx * half), TIMBER, Enum.Material.Wood)
	end
end

-- ── The shaft ────────────────────────────────────────────────────────────────

local function shaftEdge()
	local r = SHAFT_H + 2
	for _, sx in ipairs({ -1, 1 }) do
		railing(-r, r, sx * r, sx * r, LODGE_Y)
		railing(sx * r, sx * r, -r, r, LODGE_Y)
		for _, sz in ipairs({ -1, 1 }) do
			lpart("ShaftPost", Vector3.new(1.6, 5, 1.6),
				CFrame.new(sx * r, LODGE_Y + 2.5, sz * r), TIMBER, Enum.Material.Wood)
			ldecor("Hazard", Vector3.new(4, 0.5, 4),
				CFrame.new(sx * (SHAFT_H - 1.4), LODGE_Y + 0.3, sz * (SHAFT_H - 1.4)),
				HAZARD, Enum.Material.WoodPlanks)
		end
	end
end

-- ── Light ────────────────────────────────────────────────────────────────────

-- `lit` decides whether it carries an actual light. Every lantern is a prop;
-- only some of them are light sources. Roblox only renders so many at once and
-- the rest pop in and out as you turn — which is the flicker. Half as many
-- lights, each a little stronger, and the room looks the same and stays still.
local function lanternBox(at, drop, range, lit)
	ldecor("Chain", Vector3.new(0.18, drop, 0.18),
		CFrame.new(at.X, at.Y - drop / 2, at.Z), IRON, Enum.Material.Metal)

	ldecor("Cap", Vector3.new(3.4, 0.5, 3.4), CFrame.new(at.X, at.Y - drop, at.Z),
		IRON, Enum.Material.Metal)

	local glass = ldecor("Glass", Vector3.new(2.6, 2.8, 2.6),
		CFrame.new(at.X, at.Y - drop - 1.6, at.Z), LAMP, Enum.Material.Neon)
	glass.Transparency = 0.15

	-- Frame bars, so it reads as a lantern rather than a glowing cube
	for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		ldecor("Bar", Vector3.new(0.34, 3.1, 0.34),
			CFrame.new(at.X + d[1] * 1.3, at.Y - drop - 1.6, at.Z + d[2] * 1.3),
			IRON, Enum.Material.Metal)
	end
	ldecor("Base", Vector3.new(3.0, 0.5, 3.0), CFrame.new(at.X, at.Y - drop - 3.2, at.Z),
		IRON, Enum.Material.Metal)

	-- Prop only: no light in this one. The glass still glows, because it is
	-- Neon and the bloom does the rest.
	if lit == false then return end

	local light = Instance.new("PointLight")
	light.Color      = Color3.fromRGB(255, 182, 106)
	light.Brightness = 2.9
	-- Short range on purpose. A lamp that reaches thirty studs meets the next
	-- lamp and the two of them turn the hall into one flat sheet of light; at
	-- this range each one is its own pool with dark in between, which is the
	-- whole look.
	light.Range      = range or 24
	light.Shadows    = false
	light.Parent     = glass
end

-- A cartwheel of candles over the main floor
local function chandelier(x, z, y)
	ldecor("Chain", Vector3.new(0.22, 10, 0.22), CFrame.new(x, y + 5, z), IRON, Enum.Material.Metal)

	local ring = 5.2
	for i = 0, 11 do
		local a = math.rad(i * 30)
		ldecor("Rim", Vector3.new(2.9, 0.55, 0.8),
			CFrame.new(x + math.cos(a) * ring, y, z + math.sin(a) * ring)
				* CFrame.Angles(0, -a, 0), IRON, Enum.Material.Metal)
	end
	for i = 0, 5 do
		local a = math.rad(i * 60)
		ldecor("Spoke", Vector3.new(ring * 2, 0.4, 0.4),
			CFrame.new(x, y + 0.4, z) * CFrame.Angles(0, a, 0), IRON, Enum.Material.Metal)

		local candle = ldecor("Candle", Vector3.new(0.5, 1.6, 0.5),
			CFrame.new(x + math.cos(a) * ring, y + 1.2, z + math.sin(a) * ring),
			Color3.fromRGB(238, 228, 200), Enum.Material.SmoothPlastic)
		ldecor("Flame", Vector3.new(0.42, 0.7, 0.42),
			CFrame.new(candle.Position + Vector3.new(0, 1.1, 0)), LAMP, Enum.Material.Neon)
	end

	local light = Instance.new("PointLight")
	light.Color      = Color3.fromRGB(255, 192, 124)
	light.Brightness = 3.1
	light.Range      = 36
	-- No shadow casting. Shadow-casting lights are the scarcest thing the
	-- renderer has, and asking for them is what makes the rest blink out as you
	-- turn. Flip this back to true if you want the drama and can spare it.

	light.Shadows    = false
	light.Parent     = ldecor("Hub", Vector3.new(1.6, 1.2, 1.6),
		CFrame.new(x, y + 0.4, z), IRON, Enum.Material.Metal)
end

-- Cloth hung from the gallery rail, which is what stops the upper half of the
-- room being a blank wall
local function banner(x, z, facing, colour)
	local at = CFrame.new(x, LODGE_Y + L.Gallery + 3.4, z) * CFrame.Angles(0, facing, 0)

	ldecor("BannerRod", Vector3.new(7, 0.4, 0.4), at, IRON, Enum.Material.Metal)
	ldecor("BannerCloth", Vector3.new(6.2, 11, 0.25), at * CFrame.new(0, -5.7, 0.1),
		colour or BANNER, Enum.Material.Fabric)
	ldecor("BannerTrim", Vector3.new(6.2, 1.2, 0.32), at * CFrame.new(0, -1.1, 0.14),
		BANNER_D, Enum.Material.Fabric)
	-- Pointed hem, two triangles read well enough as a tail at this size
	for _, sx in ipairs({ -1, 1 }) do
		ldecor("BannerTail", Vector3.new(3, 3, 0.24),
			at * CFrame.new(sx * 1.55, -11.4, 0.1) * CFrame.Angles(0, 0, math.rad(45)),
			colour or BANNER, Enum.Material.Fabric)
	end
end

-- ── Station huts ─────────────────────────────────────────────────────────────
-- A building inside the building. Posts, a pitched roof, a counter across the
-- front, shelves behind, a hanging sign. The working scene goes underneath it.

local function hut(cf, spec)
	local w, d, h = spec.width, spec.depth, spec.height
	local accent  = spec.zone.accent

	local function at(o) return cf * o end
	local function hpart(name, size, o, colour, mat)
		return part(name, size, at(o), colour, mat, lodge)
	end
	local function hdecor(name, size, o, colour, mat)
		local p = hpart(name, size, o, colour, mat)
		p.CanCollide = false
		p.CanQuery   = false
		p.CastShadow = false
		return p
	end

	-- Back and sides, open to the front
	hpart("HutBack", Vector3.new(w, h, 0.8), CFrame.new(0, h / 2, -d / 2), PLANK, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		hpart("HutSide", Vector3.new(0.8, h, d), CFrame.new(sx * w / 2, h / 2, 0), PLANK, Enum.Material.WoodPlanks)
		hpart("HutPost", Vector3.new(1.8, h + 1.4, 1.8),
			CFrame.new(sx * w / 2, (h + 1.4) / 2, d / 2), TIMBER, Enum.Material.Wood)
		hpart("HutPost", Vector3.new(1.8, h + 1.4, 1.8),
			CFrame.new(sx * w / 2, (h + 1.4) / 2, -d / 2), TIMBER, Enum.Material.Wood)
	end

	-- Pitched roof, two slopes
	for _, sz in ipairs({ -1, 1 }) do
		hdecor("HutRoof", Vector3.new(w + 4, 0.8, d * 0.62),
			CFrame.new(0, h + 2.4, sz * d * 0.28) * CFrame.Angles(math.rad(sz * -19), 0, 0),
			TIMBER_D, Enum.Material.WoodPlanks)
	end
	hdecor("HutRidge", Vector3.new(w + 5, 0.9, 1.2), CFrame.new(0, h + 3.5, 0), TIMBER, Enum.Material.Wood)

	-- Counter across the front, with a worn top
	hpart("Counter", Vector3.new(w - 3, 3.4, 2.6), CFrame.new(0, 1.7, d / 2 - 1.6), TIMBER, Enum.Material.Wood)
	hdecor("CounterTop", Vector3.new(w - 2.2, 0.5, 3.4), CFrame.new(0, 3.6, d / 2 - 1.6), PLANK, Enum.Material.WoodPlanks)

	-- Shelves up the back wall with things on them
	for i = 0, 2 do
		hdecor("Shelf", Vector3.new(w - 4, 0.4, 1.6), CFrame.new(0, 4.4 + i * 3.2, -d / 2 + 1.1),
			TIMBER, Enum.Material.Wood)
		for j = -3, 3 do
			if (i + j) % 2 == 0 then
				hdecor("Stock", Vector3.new(1.1, 1.5, 1.1),
					CFrame.new(j * 2.4, 5.4 + i * 3.2, -d / 2 + 1.1),
					(i + j) % 4 == 0 and accent or Color3.fromRGB(172, 152, 118),
					Enum.Material.Concrete)
			end
		end
	end

	-- Hanging sign out front
	hdecor("SignArm", Vector3.new(0.4, 0.4, 4.6), CFrame.new(0, h + 1.2, d / 2 + 2.2), IRON, Enum.Material.Metal)
	hdecor("SignChain", Vector3.new(0.2, 1.6, 0.2), CFrame.new(0, h + 0.4, d / 2 + 4.2), IRON, Enum.Material.Metal)

	local board = hdecor("Sign", Vector3.new(11, 3.2, 0.5), CFrame.new(0, h - 1.4, d / 2 + 4.2),
		TIMBER_D, Enum.Material.Wood)

	-- A floating panel rather than paint on a board. Text on dark timber, under
	-- warm light and bloom, is unreadable from ten studs away — this is lit by
	-- nothing, faces you wherever you stand, and matches the rest of the UI.
	local anchor = ldecor("SignAnchor", Vector3.new(0.4, 0.4, 0.4),
		at(CFrame.new(0, h + 7.5, d / 2 + 3)), accent, Enum.Material.Neon)
	anchor.Transparency = 1

	local sign = Instance.new("BillboardGui")
	sign.Name            = "StationSign"
	-- A BillboardGui measures the SCALE half of Size in studs and the OFFSET
	-- half in pixels. Written as offsets this was a seventeen-pixel sign, which
	-- is why it looked like a speck. Scale, so it is seventeen studs wide.
	sign.Size            = UDim2.new(17, 0, 6, 0)
	sign.SizeOffset      = Vector2.new(0, 0.5)
	sign.AlwaysOnTop     = false
	sign.MaxDistance     = 260
	sign.LightInfluence  = 0
	sign.Parent          = anchor

	local plate = Instance.new("Frame")
	plate.Size                   = UDim2.fromScale(1, 1)
	plate.BackgroundColor3       = Color3.fromRGB(20, 24, 31)
	plate.BackgroundTransparency = 0.06
	plate.BorderSizePixel        = 0
	plate.Parent                 = sign
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 10)

	local edge = Instance.new("UIStroke", plate)
	edge.Color     = accent
	edge.Thickness = 2.5

	local bar = Instance.new("Frame")
	bar.Size             = UDim2.new(1, -16, 0, 4)
	bar.Position         = UDim2.new(0, 8, 0, 7)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel  = 0
	bar.Parent           = plate
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, -16, 0.52, 0)
	title.Position               = UDim2.new(0, 8, 0, 14)
	title.BackgroundTransparency = 1
	title.Text                   = spec.zone.title
	title.TextColor3             = Color3.fromRGB(240, 244, 248)
	title.TextScaled             = true
	title.Font                   = StrataConfig.UI.Head
	title.Parent                 = plate

	local hint = Instance.new("TextLabel")
	hint.Size                   = UDim2.new(1, -16, 0.24, 0)
	hint.Position               = UDim2.new(0, 8, 0.68, 0)
	hint.BackgroundTransparency = 1
	hint.Text                   = spec.zone.blurb
	hint.TextColor3             = accent
	hint.TextScaled             = true
	hint.Font                   = StrataConfig.UI.Body
	hint.Parent                 = plate

	-- Its own lamp, so each hut is a pool of light
	lanternBox(Vector3.new((at(CFrame.new(0, 0, d / 2 - 3))).X, LODGE_Y + h + 1,
		(at(CFrame.new(0, 0, d / 2 - 3))).Z), 2, 19)

	return cf
end

-- ── Dressing ─────────────────────────────────────────────────────────────────
-- The clutter is what makes it somewhere people live rather than a lobby, and
-- it is the cheapest detail in the building.

local function bench(cf)
	ldecor("BenchTop", Vector3.new(13, 0.5, 2), cf * CFrame.new(0, 1.6, 0), PLANK, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		ldecor("BenchLeg", Vector3.new(0.7, 1.6, 1.8), cf * CFrame.new(sx * 5.4, 0.8, 0),
			TIMBER_D, Enum.Material.Wood)
	end
end

local function longTable(cf)
	lpart("TableTop", Vector3.new(15, 0.6, 4.4), cf * CFrame.new(0, 3, 0), PLANK, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		ldecor("TableLeg", Vector3.new(1.1, 2.8, 3.6), cf * CFrame.new(sx * 6.2, 1.4, 0),
			TIMBER_D, Enum.Material.Wood)
	end
	bench(cf * CFrame.new(0, 0, 4.2))
	bench(cf * CFrame.new(0, 0, -4.2))

	-- Left on the table
	for _, o in ipairs({ -4.6, -1.2, 3.1 }) do
		ldecor("Mug", Vector3.new(0.8, 1.0, 0.8), cf * CFrame.new(o, 3.8, (o % 2) - 0.8),
			Color3.fromRGB(182, 168, 142), Enum.Material.Concrete)
	end
	-- Neon only, no light of its own: there is a lantern overhead already, and
	-- every extra light is one the renderer has to find room for.
	ldecor("TableLamp", Vector3.new(1.1, 1.5, 1.1), cf * CFrame.new(0, 4.1, 0),
		LAMP, Enum.Material.Neon)
end

local function crateStack(x, z, n)
	for i = 0, n - 1 do
		local s = 3.6 - i * 0.4
		ldecor("Crate", Vector3.new(s, s * 0.85, s),
			CFrame.new(x + (i % 2) * 0.6, LODGE_Y + s * 0.44 + i * 3, z - (i % 2) * 0.5)
				* CFrame.Angles(0, math.rad(i * 19), 0),
			i % 2 == 0 and TIMBER or PLANK, Enum.Material.WoodPlanks)
	end
end

local function keg(x, z)
	local b = ldecor("Keg", Vector3.new(3.4, 4, 3.4),
		CFrame.new(x, LODGE_Y + 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		TIMBER_D, Enum.Material.Wood)
	b.Shape = Enum.PartType.Cylinder
	for _, oy in ipairs({ -1.2, 1.2 }) do
		ldecor("Hoop", Vector3.new(3.6, 0.35, 3.6), CFrame.new(x, LODGE_Y + 2 + oy, z),
			IRON_L, Enum.Material.Metal)
	end
end

local function bunk(cf)
	for _, level in ipairs({ 0, 3.8 }) do
		ldecor("BunkFrame", Vector3.new(8, 0.5, 4), cf * CFrame.new(0, 1.8 + level, 0),
			TIMBER, Enum.Material.Wood)
		ldecor("Mattress", Vector3.new(7.5, 0.8, 3.6), cf * CFrame.new(0, 2.4 + level, 0),
			Color3.fromRGB(146, 132, 108), Enum.Material.Fabric)
		ldecor("Blanket", Vector3.new(3.6, 0.9, 3.7), cf * CFrame.new(1.8, 2.6 + level, 0),
			Color3.fromRGB(96, 72, 60), Enum.Material.Fabric)
	end
	for _, sx in ipairs({ -1, 1 }) do
		ldecor("BunkPost", Vector3.new(0.7, 7.2, 0.7), cf * CFrame.new(sx * 3.7, 3.6, 0),
			TIMBER_D, Enum.Material.Wood)
	end
end

local function dressing()
	local gy     = LODGE_Y + L.Gallery + FLOOR_T
	local innerX = L.HalfX - L.Depth
	local innerZ = L.HalfZ - L.Depth

	-- Tables on the ground floor, out of the way of the huts and the shaft
	longTable(CFrame.new(-24, LODGE_Y, 40))
	longTable(CFrame.new(24, LODGE_Y, 40))
	longTable(CFrame.new(-24, LODGE_Y, -40) * CFrame.Angles(0, math.rad(180), 0))

	-- Stores stacked against the walls
	crateStack(-L.HalfX + 8, 40, 3)
	crateStack(-L.HalfX + 8, 30, 2)
	crateStack(L.HalfX - 8, -40, 3)
	crateStack(L.HalfX - 8, 42, 2)
	keg(-L.HalfX + 7, 22)
	keg(-L.HalfX + 12, 20)
	keg(L.HalfX - 7, 30)
	keg(L.HalfX - 12, 28)

	-- Bunks and a table on the gallery, so the upper floor is somewhere people
	-- sleep rather than a walkway
	for i, z in ipairs({ -46, -34, -22 }) do
		bunk(CFrame.new(-L.HalfX + 11, gy, z) * CFrame.Angles(0, math.rad(90), 0))
		if i < 3 then bunk(CFrame.new(L.HalfX - 11, gy, z) * CFrame.Angles(0, math.rad(90), 0)) end
	end
	longTable(CFrame.new(0, gy, L.HalfZ - 11) * CFrame.Angles(0, math.rad(90), 0))
	crateStack(-30, L.HalfZ - 8, 2)
	keg(30, L.HalfZ - 9)

	-- Rug in the middle of the floor, between the shaft and the doors
	ldecor("Rug", Vector3.new(26, 0.2, 16), CFrame.new(0, LODGE_Y + FLOOR_T + 0.1, 44),
		Color3.fromRGB(118, 62, 52), Enum.Material.Fabric)
	ldecor("RugTrim", Vector3.new(28, 0.16, 18), CFrame.new(0, LODGE_Y + FLOOR_T + 0.06, 44),
		Color3.fromRGB(84, 44, 38), Enum.Material.Fabric)
end

-- ── The contract board ───────────────────────────────────────────────────────
-- Paper pinned to cork, by the doors, where you would actually look on the way
-- out. The least mechanical way to say "here is the work".

local function contractBoard()
	local at = CFrame.new(S.RunsPos.X, LODGE_Y, L.HalfZ - 1.6) * CFrame.Angles(0, math.rad(180), 0)

	lpart("BoardFrame", Vector3.new(16, 11, 0.8), at * CFrame.new(0, 10, 0), TIMBER, Enum.Material.Wood)
	ldecor("BoardCork", Vector3.new(14.6, 9.6, 0.3), at * CFrame.new(0, 10, -0.4),
		Color3.fromRGB(122, 88, 54), Enum.Material.Fabric)

	local papers = {
		{ x = -4.8, y =  2.2, w = 3.8, h = 3.0, a =  4 },
		{ x = -0.2, y =  2.6, w = 3.4, h = 2.6, a = -6 },
		{ x =  4.6, y =  2.0, w = 4.0, h = 3.2, a =  3 },
		{ x = -4.2, y = -2.2, w = 3.6, h = 2.8, a = -3 },
		{ x =  0.6, y = -2.4, w = 4.2, h = 2.6, a =  7 },
		{ x =  5.0, y = -2.0, w = 3.2, h = 3.0, a = -5 },
	}
	for i, p in ipairs(papers) do
		ldecor("Notice" .. i, Vector3.new(p.w, p.h, 0.12),
			at * CFrame.new(p.x, 10 + p.y, -0.6) * CFrame.Angles(0, 0, math.rad(p.a)),
			i % 3 == 0 and Color3.fromRGB(214, 198, 162) or Color3.fromRGB(232, 222, 196),
			Enum.Material.SmoothPlastic)
		ldecor("Pin" .. i, Vector3.new(0.3, 0.3, 0.22),
			at * CFrame.new(p.x, 10 + p.y + p.h / 2 - 0.4, -0.74),
			Color3.fromRGB(206, 92, 64), Enum.Material.Metal)
	end

	ldecor("BoardHead", Vector3.new(16.6, 2, 1.1), at * CFrame.new(0, 16.2, -0.2),
		TIMBER_D, Enum.Material.Wood)
	local sign = ldecor("BoardSign", Vector3.new(13, 1.4, 0.2), at * CFrame.new(0, 16.2, -0.8),
		HAZARD, Enum.Material.SmoothPlastic)

	local gui = Instance.new("SurfaceGui")
	gui.Face           = Enum.NormalId.Front
	gui.PixelsPerStud  = 40
	gui.LightInfluence = 0
	gui.Parent         = sign

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = "CONTRACTS"
	label.TextColor3             = Color3.fromRGB(38, 28, 12)
	label.TextScaled             = true
	label.Font                   = StrataConfig.UI.Head
	label.Parent                 = gui

	lanternBox(Vector3.new(S.RunsPos.X, LODGE_Y + 24, L.HalfZ - 4), 3, 19)
end
-- ── Outside the lodge ────────────────────────────────────────────────────────
-- From within it was a hall. From without it was a plain orange box, because
-- every wall was one flat slab of plank and the roof was a lid.
--
-- Three things fix that, and they are the three things every building in the
-- reference has: a roof with a pitch and an overhang, walls broken into framed
-- panels, and a chimney with something coming out of it.

local PLASTER   = Color3.fromRGB(216, 206, 186)
local PLASTER_D = Color3.fromRGB(188, 176, 154)
local FRAME     = Color3.fromRGB(74, 50, 34)
local SHINGLE   = Color3.fromRGB(96, 62, 44)
local SHINGLE_D = Color3.fromRGB(74, 48, 34)

-- A slab lying on a slope, given the two ends of the run it covers
local function slope(name, width, xCentre, z0, y0, z1, y1, thick, colour, material)
	local dz, dy = z1 - z0, y1 - y0
	local len    = math.sqrt(dz * dz + dy * dy)
	ldecor(name, Vector3.new(width, thick or 1.1, len),
		CFrame.new(xCentre, (y0 + y1) / 2, (z0 + z1) / 2)
			* CFrame.Angles(-math.atan2(dy, dz), 0, 0),
		colour or SHINGLE, material or Enum.Material.WoodPlanks)
end

-- ── Cladding ─────────────────────────────────────────────────────────────────
-- Plaster panels with dark timber framing over them, on the outside only. The
-- inside stays bare board, which is why the two read as different rooms.

local function framedWall(cx, cz, along, length, height, base)
	local outward = (along == "x") and Vector3.new(0, 0, cz > 0 and 1 or -1)
		or Vector3.new(cx > 0 and 1 or -1, 0, 0)
	local face = 0.9

	local function panel(name, size, offset, colour, material)
		local pos = Vector3.new(cx, base, cz) + outward * face + offset
		return ldecor(name, size, CFrame.new(pos), colour, material)
	end

	local wide = (along == "x")
	local function sized(w, h, d)
		return wide and Vector3.new(w, h, d) or Vector3.new(d, h, w)
	end
	local function offs(u, y)
		return wide and Vector3.new(u, y, 0) or Vector3.new(0, y, u)
	end

	-- The plaster itself
	panel("Plaster", sized(length, height, 0.5), offs(0, height / 2), PLASTER, Enum.Material.Concrete)

	-- Sill, mid rail and head, the three horizontals every framed wall has
	for _, h in ipairs({ 1.2, height * 0.46, height - 1.4 }) do
		panel("Rail", sized(length, 2.2, 1.1), offs(0, h), FRAME, Enum.Material.Wood)
	end

	-- Studs, and a brace in every third panel
	local step = 11
	local n    = math.floor(length / step)
	for i = 0, n do
		local u = -length / 2 + i * (length / n)
		panel("Stud", sized(1.8, height, 1.1), offs(u, height / 2), FRAME, Enum.Material.Wood)

		if i < n and i % 3 == 1 then
			local seg = length / n
			local h0, h1 = height * 0.46 + 1.1, height - 2.5
			local run = h1 - h0
			local diag = math.sqrt(run * run + seg * seg)
			local pos = Vector3.new(cx, base, cz) + outward * face
				+ offs(u + seg / 2, (h0 + h1) / 2)
			ldecor("Brace", sized(diag, 1.6, 1.05),
				CFrame.new(pos) * CFrame.Angles(
					wide and 0 or math.atan2(run, seg),
					0,
					wide and math.atan2(run, seg) or 0),
				FRAME, Enum.Material.Wood)
		end
	end
end

local function cladding()
	local h = L.Height
	local doorL, doorR = L.DoorX - L.DoorW / 2, L.DoorX + L.DoorW / 2
	local head = 17   -- top of the opening, matching the lintel in shell()

	-- The front is clad in three pieces, not one. Clad as a single panel it
	-- plasters straight over the doorway, and the building has no way in.
	framedWall((-L.HalfX + doorL) / 2, L.HalfZ, "x", doorL + L.HalfX, h, LODGE_Y)
	framedWall((doorR + L.HalfX) / 2, L.HalfZ, "x", L.HalfX - doorR, h, LODGE_Y)
	framedWall(L.DoorX, L.HalfZ, "x", L.DoorW, h - head, LODGE_Y + head)

	framedWall(0, -L.HalfZ, "x", L.HalfX * 2, h, LODGE_Y)
	framedWall(L.HalfX, 0, "z", L.HalfZ * 2, h, LODGE_Y)
	framedWall(-L.HalfX, 0, "z", L.HalfZ * 2, h, LODGE_Y)

	-- Stone plinth round the base, in the same three pieces up the front. A kerb
	-- three studs high across the doorway is a wall as far as walking in goes.
	ldecor("Plinth", Vector3.new(L.HalfX * 2 + 6, 3.4, 3),
		CFrame.new(0, LODGE_Y + 1.2, -(L.HalfZ + 1.4)), STONE, Enum.Material.Slate)
	for _, seg in ipairs({
		{ from = -L.HalfX - 3, to = doorL },
		{ from = doorR,        to = L.HalfX + 3 },
	}) do
		local w = seg.to - seg.from
		ldecor("Plinth", Vector3.new(w, 3.4, 3),
			CFrame.new(seg.from + w / 2, LODGE_Y + 1.2, L.HalfZ + 1.4), STONE, Enum.Material.Slate)
	end
	for _, sx in ipairs({ -1, 1 }) do
		ldecor("Plinth", Vector3.new(3, 3.4, L.HalfZ * 2 + 6),
			CFrame.new(sx * (L.HalfX + 1.4), LODGE_Y + 1.2, 0), STONE, Enum.Material.Slate)
	end
end

-- ── Roof ─────────────────────────────────────────────────────────────────────
-- A pitch with a deep overhang, split around a lantern tower in the middle that
-- the headframe stands through. Shingle courses laid over the slope, because
-- one smooth ramp reads as a wedge rather than a roof.

local function pitchedRoof()
	local eave   = LODGE_Y + L.Height + 1
	local ridge  = eave + 16
	local over   = 7
	local gapX   = L.Opening / 2 + 4
	local zEave  = L.HalfZ + over

	-- Takes its ends the same way `slope` does — a point, then a point. Written
	-- the other way round (both z, then both y) it reads fine and silently puts
	-- the roof inside the building.
	local function courses(width, xc, z0, y0, z1, y1)
		local rows = 9
		for i = 0, rows - 1 do
			local t0, t1 = i / rows, (i + 1) / rows
			slope("Shingle", width, xc,
				z0 + (z1 - z0) * t0, y0 + (y1 - y0) * t0,
				z0 + (z1 - z0) * t1, y0 + (y1 - y0) * t1,
				1.5, i % 2 == 0 and SHINGLE or SHINGLE_D)
		end
	end

	for _, sz in ipairs({ -1, 1 }) do
		-- Wide part of the slope, from the eave up to the tower
		courses(L.HalfX * 2 + over * 2, 0, sz * zEave, eave, sz * gapX,
			eave + (ridge - eave) * (1 - gapX / zEave))

		-- Either side of the tower, carrying on to the ridge
		for _, sx in ipairs({ -1, 1 }) do
			local w = L.HalfX + over - gapX
			courses(w, sx * (gapX + w / 2),
				sz * gapX, eave + (ridge - eave) * (1 - gapX / zEave), 0, ridge)
		end
	end

	-- Ridge beam, in two lengths so it does not cross the tower
	for _, sx in ipairs({ -1, 1 }) do
		local w = L.HalfX + over - gapX
		ldecor("Ridge", Vector3.new(w, 2, 2.6),
			CFrame.new(sx * (gapX + w / 2), ridge + 0.6, 0), FRAME, Enum.Material.Wood)
	end

	-- Gable ends, stepped: six blocks reads as a triangle at this size
	for _, sx in ipairs({ -1, 1 }) do
		local steps = 7
		for i = 0, steps - 1 do
			local t0, t1 = i / steps, (i + 1) / steps
			local y = eave + (ridge - eave) * t0
			local halfZ = L.HalfZ * (1 - t0)
			ldecor("Gable", Vector3.new(2.4, (ridge - eave) / steps + 0.4, halfZ * 2),
				CFrame.new(sx * L.HalfX, y + (ridge - eave) / steps / 2, 0),
				PLASTER_D, Enum.Material.Concrete)
			ldecor("GableTrim", Vector3.new(3.2, 1.4, halfZ * 2 * (1 - t1) + 2),
				CFrame.new(sx * L.HalfX, y, 0), FRAME, Enum.Material.Wood)
		end
	end

	-- Purlins under the eaves, showing the ends of the rafters
	for x = -L.HalfX, L.HalfX, 8 do
		for _, sz in ipairs({ -1, 1 }) do
			ldecor("Rafter", Vector3.new(1.2, 1.2, over * 2.4),
				CFrame.new(x, eave - 0.6, sz * (L.HalfZ + over * 0.5))
					* CFrame.Angles(math.rad(sz * 22), 0, 0), FRAME, Enum.Material.Wood)
		end
	end
end

-- The tower over the shaft: open louvred sides, so the headframe stands through
-- it and daylight still falls straight down the hole
local function lanternTower()
	local base = LODGE_Y + L.Height + 1
	local half = L.Opening / 2 + 3
	local h    = 20

	for _, sx in ipairs({ -1, 1 }) do
		for _, axis in ipairs({ "x", "z" }) do
			local size = axis == "x" and Vector3.new(2.2, h, half * 2)
				or Vector3.new(half * 2, h, 2.2)
			local pos = axis == "x" and CFrame.new(sx * half, base + h / 2, 0)
				or CFrame.new(0, base + h / 2, sx * half)
			ldecor("TowerPost", size, pos, FRAME, Enum.Material.Wood)
		end
	end

	-- Louvres: slats with gaps, the classic mine headhouse look
	for i = 0, 6 do
		local y = base + 3 + i * 2.4
		for _, sz in ipairs({ -1, 1 }) do
			ldecor("Louvre", Vector3.new(half * 2, 1.4, 0.8),
				CFrame.new(0, y, sz * half) * CFrame.Angles(math.rad(sz * -24), 0, 0),
				SHINGLE, Enum.Material.WoodPlanks)
			ldecor("Louvre", Vector3.new(0.8, 1.4, half * 2),
				CFrame.new(sz * half, y, 0) * CFrame.Angles(0, 0, math.rad(sz * 24)),
				SHINGLE, Enum.Material.WoodPlanks)
		end
	end

	-- Cap, sitting proud on posts so the middle stays open to the sky
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			ldecor("CapPost", Vector3.new(1.6, 6, 1.6),
				CFrame.new(sx * half, base + h + 3, sz * half), FRAME, Enum.Material.Wood)
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		slope("CapRoof", half * 2 + 6, 0, sz * (half + 3), base + h + 6, 0, base + h + 12,
			1.4, SHINGLE_D)
	end
end

-- ── Chimney ──────────────────────────────────────────────────────────────────
-- Over the forge, where the furnace already is. Smoke coming out of a building
-- is the single cheapest way to say somebody is inside working.

local function chimney()
	local x = S.CraftPos.X - 8
	local top = LODGE_Y + L.Height + 30

	ldecor("Chimney", Vector3.new(8, top - LODGE_Y - 6, 8),
		CFrame.new(x, LODGE_Y + 6 + (top - LODGE_Y - 6) / 2, -14), STONE, Enum.Material.Slate)
	ldecor("ChimneyCap", Vector3.new(10, 2, 10), CFrame.new(x, top, -14), STONE_D, Enum.Material.Slate)
	ldecor("ChimneyLip", Vector3.new(9.4, 1.2, 9.4), CFrame.new(x, top - 3, -14), STONE_D, Enum.Material.Slate)

	local vent = ldecor("Flue", Vector3.new(5, 1, 5), CFrame.new(x, top + 1.2, -14),
		Color3.fromRGB(30, 24, 22), Enum.Material.Slate)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture      = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color        = ColorSequence.new(Color3.fromRGB(96, 92, 88), Color3.fromRGB(52, 50, 50))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size         = NumberSequence.new(6, 20)
	smoke.Rate         = 7
	smoke.Lifetime     = NumberRange.new(3.5, 5.5)
	smoke.Speed        = NumberRange.new(6, 9)
	smoke.SpreadAngle  = Vector2.new(14, 14)
	smoke.Acceleration = Vector3.new(2, 3, 0)
	smoke.Parent       = vent
end

local function exterior()
	cladding()
	pitchedRoof()
	lanternTower()
	chimney()

	-- Porch over the doors, so the way in is obvious from across the claim
	local px = L.DoorX
	for _, sx in ipairs({ -1, 1 }) do
		lpart("PorchPost", Vector3.new(2.2, 17, 2.2),
			CFrame.new(px + sx * (L.DoorW / 2 + 4), LODGE_Y + 8.5, L.HalfZ + 9), TIMBER, Enum.Material.Wood)
		ldecor("PorchBrace", Vector3.new(1.4, 6, 1.4),
			CFrame.new(px + sx * (L.DoorW / 2 + 3), LODGE_Y + 15, L.HalfZ + 6)
				* CFrame.Angles(math.rad(42), 0, 0), TIMBER_D, Enum.Material.Wood)
	end
	ldecor("PorchBeam", Vector3.new(L.DoorW + 14, 2, 3),
		CFrame.new(px, LODGE_Y + 17.6, L.HalfZ + 9), TIMBER, Enum.Material.Wood)
	for _, sz in ipairs({ -1, 1 }) do
		slope("PorchRoof", L.DoorW + 16, px, L.HalfZ + 11, LODGE_Y + 18.4, L.HalfZ - 1,
			LODGE_Y + 23, 1.2, SHINGLE)
	end

	-- A stone stoop at the doors. Steps would be buried: the lodge floor sits
	-- barely a tenth of a stud above the deck it stands on.
	ldecor("Stoop", Vector3.new(L.DoorW + 12, 0.5, 9),
		CFrame.new(px, LODGE_Y + 0.26, L.HalfZ + 8), STONE, Enum.Material.Slate)
	ldecor("StoopEdge", Vector3.new(L.DoorW + 14, 0.34, 10.4),
		CFrame.new(px, LODGE_Y + 0.16, L.HalfZ + 8), STONE_D, Enum.Material.Slate)

	-- The name over the door
	local board = ldecor("LodgeSign", Vector3.new(26, 5, 0.8),
		CFrame.new(px, LODGE_Y + 21.5, L.HalfZ + 10.6), TIMBER_D, Enum.Material.Wood)

	local gui = Instance.new("SurfaceGui")
	gui.Face           = Enum.NormalId.Front
	gui.PixelsPerStud  = 40
	gui.LightInfluence = 0
	gui.Parent         = board

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(0.92, 0.7)
	label.AnchorPoint            = Vector2.new(0.5, 0.5)
	label.Position               = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text                   = "THE DEEP CUT"
	label.TextColor3             = Color3.fromRGB(226, 186, 118)
	label.TextScaled             = true
	label.Font                   = StrataConfig.UI.Head
	label.Parent                 = gui

	-- Lamps either side of the door
	for _, sx in ipairs({ -1, 1 }) do
		lanternBox(Vector3.new(px + sx * (L.DoorW / 2 + 4), LODGE_Y + 17, L.HalfZ + 9), 1, 20)
	end
end

-- ── Outdoors ─────────────────────────────────────────────────────────────────
-- The claim was a brown field with a box in the middle. What makes a place look
-- inhabited is not more buildings, it is the small stuff between them: paths
-- worn into the ground, lamps on posts, bunting strung overhead, a cart nobody
-- has unloaded yet.
--
-- All of it deterministic from the seed, so a server looks the same to everyone
-- and the same every time it starts.

local LEAF       = Color3.fromRGB(78, 116, 58)
local LEAF_D     = Color3.fromRGB(58, 92, 46)
local LEAF_L     = Color3.fromRGB(102, 140, 70)
local BARK       = Color3.fromRGB(84, 62, 44)
local CLOTH      = { Color3.fromRGB(178, 66, 58), Color3.fromRGB(212, 168, 76),
                     Color3.fromRGB(232, 224, 202), Color3.fromRGB(96, 118, 74) }

local outside = Instance.new("Folder")
outside.Name   = "Outdoors"
outside.Parent = camp

local function opart(name, size, cf, colour, material)
	return part(name, size, cf, colour, material, outside)
end

local function odecor(name, size, cf, colour, material)
	local p = opart(name, size, cf, colour, material)
	p.CanCollide = false
	p.CanQuery   = false
	p.CastShadow = false
	return p
end

-- ── Trees ────────────────────────────────────────────────────────────────────
-- Trunk and three stacked canopies, turned off-axis so a row of them does not
-- read as a row of the same tree.

local function tree(x, z, ground, scale, spin)
	local h = 13 * scale
	opart("Trunk", Vector3.new(2.4 * scale, h, 2.4 * scale),
		CFrame.new(x, ground + h / 2, z) * CFrame.Angles(0, spin, 0), BARK, Enum.Material.Wood)

	local tiers = {
		{ w = 15, y = 0.92, t = 5.0, c = LEAF_D },
		{ w = 12, y = 1.18, t = 4.4, c = LEAF },
		{ w =  8, y = 1.40, t = 3.6, c = LEAF_L },
	}
	for i, t in ipairs(tiers) do
		odecor("Canopy" .. i, Vector3.new(t.w * scale, t.t * scale, t.w * scale),
			CFrame.new(x, ground + h * t.y, z) * CFrame.Angles(0, spin + i * 0.5, 0),
			t.c, Enum.Material.Grass)
	end

	-- A couple of low branches, which is what stops it being a lollipop
	for _, sx in ipairs({ -1, 1 }) do
		odecor("Branch", Vector3.new(1.1 * scale, 4.4 * scale, 1.1 * scale),
			CFrame.new(x + sx * 1.8 * scale, ground + h * 0.72, z)
				* CFrame.Angles(0, spin, math.rad(sx * 38)), BARK, Enum.Material.Wood)
	end
end

-- ── Lamp posts ───────────────────────────────────────────────────────────────

local function lampPost(x, z, ground)
	opart("PostBase", Vector3.new(2.4, 1.6, 2.4), CFrame.new(x, ground + 0.8, z),
		STONE_D, Enum.Material.Slate)
	opart("Post", Vector3.new(1, 15, 1), CFrame.new(x, ground + 8, z), IRON, Enum.Material.Metal)
	odecor("PostArm", Vector3.new(1.8, 0.6, 0.6), CFrame.new(x, ground + 15.4, z),
		IRON, Enum.Material.Metal)

	local glass = odecor("PostGlass", Vector3.new(2.2, 2.6, 2.2),
		CFrame.new(x, ground + 14, z), LAMP, Enum.Material.Neon)
	glass.Transparency = 0.18
	odecor("PostCap", Vector3.new(3, 0.7, 3), CFrame.new(x, ground + 15.6, z),
		IRON, Enum.Material.Metal)

	local light = Instance.new("PointLight")
	light.Color      = Color3.fromRGB(255, 190, 118)
	light.Brightness = 2.2
	light.Range      = 26
	light.Shadows    = false
	light.Parent     = glass

	return Vector3.new(x, ground + 14.6, z)
end

-- ── Bunting ──────────────────────────────────────────────────────────────────
-- Triangles on a string between two points, sagging in the middle. This is the
-- single thing that most says "somewhere people gather" in the reference.

local function bunting(from, to, flags)
	local span = to - from
	local sag  = 5

	for i = 0, flags do
		local t = i / flags
		-- A parabola through both ends, dipping in the middle
		local drop = sag * 4 * t * (1 - t)
		local at   = from + span * t - Vector3.new(0, drop, 0)

		if i < flags then
			local nt   = (i + 1) / flags
			local next = from + span * nt - Vector3.new(0, sag * 4 * nt * (1 - nt), 0)
			local seg  = next - at
			odecor("Line", Vector3.new(0.22, 0.22, seg.Magnitude),
				CFrame.lookAt(at + seg / 2, next), Color3.fromRGB(58, 48, 40), Enum.Material.Fabric)
		end

		if i > 0 and i < flags then
			odecor("Flag", Vector3.new(2.6, 3.4, 0.16),
				CFrame.new(at - Vector3.new(0, 1.9, 0))
					* CFrame.Angles(0, math.atan2(span.X, span.Z), 0),
				CLOTH[(i % #CLOTH) + 1], Enum.Material.Fabric)
		end
	end
end

-- ── Stalls and clutter ───────────────────────────────────────────────────────

local function stall(x, z, ground, spin, colour)
	local cf = CFrame.new(x, ground, z) * CFrame.Angles(0, spin, 0)

	opart("StallTop", Vector3.new(13, 0.6, 7), cf * CFrame.new(0, 4.2, 0), PLANK, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			opart("StallLeg", Vector3.new(0.9, 4.2, 0.9),
				cf * CFrame.new(sx * 5.8, 2.1, sz * 2.8), TIMBER_D, Enum.Material.Wood)
			opart("StallMast", Vector3.new(0.8, 9, 0.8),
				cf * CFrame.new(sx * 6.4, 4.5, sz * 3.4), TIMBER, Enum.Material.Wood)
		end
	end

	-- Striped awning, two slopes
	for _, sz in ipairs({ -1, 1 }) do
		for i = -2, 2 do
			odecor("Awning", Vector3.new(2.7, 0.4, 5.6),
				cf * CFrame.new(i * 2.7, 10.4, sz * 2.4) * CFrame.Angles(math.rad(sz * 26), 0, 0),
				(i % 2 == 0) and colour or Color3.fromRGB(236, 228, 210), Enum.Material.Fabric)
		end
	end

	-- Goods on the counter
	for i = -2, 2 do
		odecor("Goods", Vector3.new(1.5, 1.7, 1.5),
			cf * CFrame.new(i * 2.4, 5.3, (i % 2) * 0.9 - 0.4)
				* CFrame.Angles(0, i * 0.4, 0),
			i % 2 == 0 and Color3.fromRGB(168, 146, 112) or colour, Enum.Material.Concrete)
	end
end

local function oreCart(x, z, ground, spin)
	local cf = CFrame.new(x, ground, z) * CFrame.Angles(0, spin, 0)

	opart("CartBed", Vector3.new(9, 0.7, 5.4), cf * CFrame.new(0, 3.4, 0), TIMBER, Enum.Material.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		opart("CartSide", Vector3.new(9, 3, 0.6), cf * CFrame.new(0, 5, sx * 2.7), PLANK, Enum.Material.WoodPlanks)
		opart("CartEnd", Vector3.new(0.6, 3, 5.4), cf * CFrame.new(sx * 4.5, 5, 0), PLANK, Enum.Material.WoodPlanks)

		for _, sz in ipairs({ -1, 1 }) do
			local wheel = odecor("Wheel", Vector3.new(5.2, 1, 5.2),
				cf * CFrame.new(sx * 3, 2.6, sz * 3) * CFrame.Angles(0, 0, math.rad(90)),
				TIMBER_D, Enum.Material.Wood)
			wheel.Shape = Enum.PartType.Cylinder
			odecor("Hub", Vector3.new(1.6, 1.3, 1.6), cf * CFrame.new(sx * 3, 2.6, sz * 3),
				IRON, Enum.Material.Metal)
		end
	end

	-- Loaded, with something glinting in it
	for i = -2, 2 do
		local ore = odecor("Load", Vector3.new(1.8, 1.5, 1.8),
			cf * CFrame.new(i * 1.7, 4.6, (i % 2) * 1.2 - 0.6) * CFrame.Angles(0, i * 0.5, 0.2),
			i == 0 and EMBER or Color3.fromRGB(74, 72, 76),
			i == 0 and Enum.Material.Neon or Enum.Material.Slate)
		if i == 0 then
			local g = Instance.new("PointLight")
			g.Color, g.Brightness, g.Range, g.Shadows = EMBER, 1.4, 12, false
			g.Parent = ore
		end
	end

	-- Shafts resting on the ground
	for _, sx in ipairs({ -1, 1 }) do
		odecor("Shaft", Vector3.new(0.7, 0.7, 8),
			cf * CFrame.new(sx * 1.6, 2.4, 8) * CFrame.Angles(math.rad(-9), 0, 0),
			TIMBER, Enum.Material.Wood)
	end
end

-- ── The approach ─────────────────────────────────────────────────────────────

local function outdoors()
	local ground = Y                    -- the plaza deck top
	local seed   = 0
	repeat
		seed = _G.StrataSeed or 0
		if seed == 0 then task.wait(0.1) end
	until seed ~= 0

	local h = (seed * 6779) % 2147483647
	local function rand()
		h = (h * 48271) % 2147483647
		return h / 2147483647
	end

	local deck = S.PlatformSize / 2

	-- A worn path from the doors out to the edge of the deck, and one round the
	-- building, in flags rather than planks so it reads as stone
	for i = 0, 16 do
		local z = L.HalfZ + 16 + i * 4.6
		if z < deck - 2 then
			odecor("Flag", Vector3.new(16 - (i % 3), 0.3, 4.2),
				CFrame.new((rand() - 0.5) * 1.6, ground + 0.16, z),
				i % 2 == 0 and Color3.fromRGB(148, 142, 132) or Color3.fromRGB(128, 122, 114),
				Enum.Material.Slate)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 22 do
			local x = sx * (L.HalfX + 8)
			local z = -deck + 10 + i * 8
			if math.abs(z) < deck - 8 then
				odecor("Flag", Vector3.new(9, 0.3, 7.4), CFrame.new(x, ground + 0.16, z),
					i % 2 == 0 and Color3.fromRGB(142, 136, 126) or Color3.fromRGB(124, 118, 110),
					Enum.Material.Slate)
			end
		end
	end

	-- Lamp posts down the approach, and bunting strung between them
	local heads = {}
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			local z = L.HalfZ + 22 + i * 22
			if z < deck - 6 then
				table.insert(heads, { lampPost(sx * 22, z, ground), sx, i })
			end
		end
	end
	for i = 1, #heads - 1 do
		local a, b = heads[i], heads[i + 1]
		if a[2] == b[2] then bunting(a[1], b[1], 9) end
	end
	-- And across the approach, over the path
	for i = 1, #heads do
		for j = i + 1, #heads do
			if heads[i][3] == heads[j][3] and heads[i][2] ~= heads[j][2] then
				bunting(heads[i][1], heads[j][1], 11)
			end
		end
	end

	-- Market stalls flanking the door
	stall(-40, L.HalfZ + 26, ground, math.rad(14), Color3.fromRGB(178, 66, 58))
	stall(40, L.HalfZ + 26, ground, math.rad(-14), Color3.fromRGB(96, 118, 74))
	stall(-52, -L.HalfZ - 24, ground, math.rad(180), Color3.fromRGB(212, 168, 76))

	-- Carts left about
	oreCart(58, L.HalfZ + 20, ground, math.rad(-28))
	oreCart(-66, 30, ground, math.rad(96))

	-- Trees, on the terrain beyond the deck, thinned as they go out
	for i = 1, 60 do
		local angle = rand() * math.pi * 2
		local dist  = deck + 14 + rand() * (StrataConfig.Mine.Radius - deck - 60)
		local x, z  = math.cos(angle) * dist, math.sin(angle) * dist
		local gy    = StrataConfig.SurfaceHeight(x, z, seed)
		tree(x, z, gy - 0.5, 0.8 + rand() * 0.8, rand() * math.pi * 2)
	end

	-- A ring of them close in, where the deck meets the ground
	for i = 0, 17 do
		local angle = (i / 18) * math.pi * 2 + 0.14
		local dist  = deck + 6 + rand() * 5
		local x, z  = math.cos(angle) * dist, math.sin(angle) * dist
		tree(x, z, StrataConfig.SurfaceHeight(x, z, seed) - 0.5, 1.1 + rand() * 0.5,
			rand() * math.pi * 2)
	end

	-- Grass tufts and flowers on the deck edges and the near ground
	for i = 1, 130 do
		local angle = rand() * math.pi * 2
		local dist  = deck * 0.6 + rand() * (StrataConfig.Mine.Radius * 0.7)
		local x, z  = math.cos(angle) * dist, math.sin(angle) * dist
		local gy    = StrataConfig.SurfaceHeight(x, z, seed)
		local s     = 0.7 + rand() * 0.9

		odecor("Tuft", Vector3.new(s * 2, s * 1.6, s * 2),
			CFrame.new(x, gy + s * 0.5, z) * CFrame.Angles(0, rand() * 3, 0),
			rand() < 0.5 and LEAF or LEAF_L, Enum.Material.Grass)

		if rand() < 0.16 then
			odecor("Bloom", Vector3.new(0.6, 0.6, 0.6),
				CFrame.new(x + s, gy + s * 1.2, z), CLOTH[math.floor(rand() * #CLOTH) + 1],
				Enum.Material.Neon)
		end
	end

	print(("[SurfaceBuilder] outdoors dressed (%d pieces)"):format(#outside:GetChildren()))
end

-- ── Putting it together ──────────────────────────────────────────────────────

local function buildLodge()
	-- Where the gallery edge sits: used for the stairs, the lanterns under it
	-- and the banners hung off its rail.
	local innerX = L.HalfX - L.Depth
	local innerZ = L.HalfZ - L.Depth
	groundFloor()
	shell()
	gallery()
	roof()
	shaftEdge()
	dressing()
	contractBoard()
	exterior()

	-- Stairs up to the gallery, one at each end of the hall
	-- Run in from the open middle and land on the gallery edge. Built the other
	-- way round they finish over the well with nothing under them.
	stair(CFrame.new(-56, LODGE_Y, -innerZ + 22),
		L.Gallery, 22, 14)
	stair(CFrame.new(56, LODGE_Y, innerZ - 22) * CFrame.Angles(0, math.rad(180), 0),
		L.Gallery, 22, 14)

	-- The four stations, each in its own hut, facing into the hall
	hut(CFrame.new(S.CraftPos.X - 14, LODGE_Y, 0) * CFrame.Angles(0, math.rad(90), 0),
		{ width = 34, depth = 26, height = 14, zone = ZONES.craft })
	forgeScene(CFrame.new(S.CraftPos.X - 16, LODGE_Y, 0) * CFrame.Angles(0, math.rad(90), 0), lodge, 0)

	hut(CFrame.new(S.SellPos.X + 14, LODGE_Y, 0) * CFrame.Angles(0, math.rad(-90), 0),
		{ width = 34, depth = 26, height = 14, zone = ZONES.sell })
	depotScene(CFrame.new(S.SellPos.X + 16, LODGE_Y, 0) * CFrame.Angles(0, math.rad(-90), 0), lodge, 0)

	hut(CFrame.new(0, LODGE_Y, S.PickPos.Z - 14), { width = 32, depth = 24, height = 13, zone = ZONES.pickaxe })
	pickScene(CFrame.new(0, LODGE_Y, S.PickPos.Z - 16), lodge, 0)

	hut(CFrame.new(S.LiftPos.X, LODGE_Y, S.LiftPos.Z + 14) * CFrame.Angles(0, math.rad(180), 0),
		{ width = 32, depth = 24, height = 13, zone = ZONES.lift })
	winchScene(CFrame.new(S.LiftPos.X, LODGE_Y, S.LiftPos.Z + 16) * CFrame.Angles(0, math.rad(180), 0), lodge, 0)


	-- Lantern boxes in a rank down each wall. Every other one is lit; the rest
	-- are props, so the row of lamps stays dense without the light count going
	-- past what the renderer will hold still.
	local n = 0
	for x = -L.HalfX + 14, L.HalfX - 14, 22 do
		for _, sz in ipairs({ -1, 1 }) do
			n += 1
			lanternBox(Vector3.new(x, LODGE_Y + L.Gallery + 14, sz * (L.HalfZ - 3)), 3, 26, n % 2 == 0)
		end
	end
	for z = -L.HalfZ + 20, L.HalfZ - 20, 22 do
		for _, sx in ipairs({ -1, 1 }) do
			n += 1
			lanternBox(Vector3.new(sx * (L.HalfX - 3), LODGE_Y + L.Gallery + 14, z), 3, 26, n % 2 == 0)
		end
	end

	-- Under the gallery it would be pitch dark, so these all carry a light —
	-- there are fewer of them and they are the ones you walk beneath.
	for x = -innerX, innerX, 42 do
		for _, sz in ipairs({ -1, 1 }) do
			lanternBox(Vector3.new(x, LODGE_Y + L.Gallery - 1, sz * (L.HalfZ - L.Depth)), 2, 31)
		end
	end
	for z = -innerZ + 16, innerZ - 16, 42 do
		for _, sx in ipairs({ -1, 1 }) do
			lanternBox(Vector3.new(sx * (L.HalfX - L.Depth), LODGE_Y + L.Gallery - 1, z), 2, 31)
		end
	end
	-- Two chandeliers over the floor, either side of the shaft
	chandelier(-40, 0, LODGE_Y + L.Height - 12)
	chandelier( 40, 0, LODGE_Y + L.Height - 12)

	-- Banners off the gallery rail
	for _, x in ipairs({ -52, -18, 18, 52 }) do
		banner(x, -innerZ, 0, BANNER)
		banner(x, innerZ, math.pi, BANNER)
	end
	for _, z in ipairs({ -28, 28 }) do
		banner(-innerX, z, math.rad(-90), BANNER)
		banner(innerX, z, math.rad(90), BANNER)
	end
end


plaza()
perimeter()
headframe()
spawnPlatform()
boundaryWall()

local set = S.BuildingSet

buildLodge()
task.spawn(outdoors)


-- ── Outlying ground ──────────────────────────────────────────────────────────
-- The claim is far wider than the camp, and bare ground out to the wall reads
-- as unfinished rather than as open. A thin scatter of rock, scrub and old
-- workings fills it without costing much: a few hundred parts, none of them
-- near where anyone stands.
--
-- Placed on the same surface curve the terrain was written from, so nothing
-- hovers and nothing sinks.

local scatter = Instance.new("Folder")
scatter.Name   = "Outlying"
scatter.Parent = camp

local function buildScatter()
	local seed = 0
	repeat
		seed = _G.StrataSeed or 0
		if seed == 0 then task.wait(0.1) end
	until seed ~= 0

	local h = (seed * 7919) % 2147483647
	local function rand()
		h = (h * 48271) % 2147483647
		return h / 2147483647
	end

	local inner = 120                              -- clear of the camp and its paths
	local outer = StrataConfig.Mine.Radius - 26    -- clear of the wall footing
	local ROCK  = Color3.fromRGB(128, 124, 116)
	local ROCK_D = Color3.fromRGB(98, 95, 90)
	local SCRUB = Color3.fromRGB(98, 116, 72)
	local DEAD  = Color3.fromRGB(104, 88, 68)

	for i = 1, 230 do
		local angle = rand() * math.pi * 2
		-- Square-rooted so the scatter is even across the ring rather than
		-- crowding the inner edge
		local dist  = math.sqrt(inner * inner + rand() * (outer * outer - inner * inner))
		local x, z  = math.cos(angle) * dist, math.sin(angle) * dist
		local y     = StrataConfig.SurfaceHeight(x, z, seed)
		local spin  = CFrame.Angles(0, rand() * math.pi * 2, 0)
		local roll  = rand()

		if roll < 0.42 then
			-- Boulders, half buried
			local s = 2.5 + rand() * 5
			decor("Boulder", Vector3.new(s, s * 0.8, s * 0.9),
				CFrame.new(x, y + s * 0.22, z) * spin, ROCK, Enum.Material.Rock, scatter)
			if rand() < 0.5 then
				local s2 = s * 0.5
				decor("Boulder", Vector3.new(s2, s2 * 0.8, s2),
					CFrame.new(x + s * 0.8, y + s2 * 0.2, z - s * 0.5) * spin,
					ROCK_D, Enum.Material.Rock, scatter)
			end

		elseif roll < 0.72 then
			-- Scrub: a low bush of two stacked blocks
			local s = 1.6 + rand() * 2.4
			decor("Scrub", Vector3.new(s, s * 0.7, s),
				CFrame.new(x, y + s * 0.3, z) * spin, SCRUB, Enum.Material.Grass, scatter)
			decor("Scrub", Vector3.new(s * 0.6, s * 0.6, s * 0.7),
				CFrame.new(x + s * 0.3, y + s * 0.8, z + s * 0.2) * spin,
				SCRUB, Enum.Material.Grass, scatter)

		elseif roll < 0.88 then
			-- Dead stump with a broken trunk
			local hgt = 2.5 + rand() * 3.5
			decor("Stump", Vector3.new(1.4, hgt, 1.4),
				CFrame.new(x, y + hgt / 2, z) * spin, DEAD, Enum.Material.Wood, scatter)
			decor("Branch", Vector3.new(0.7, 2.2, 0.7),
				CFrame.new(x + 0.8, y + hgt, z) * CFrame.Angles(math.rad(24), rand() * 3, 0),
				DEAD, Enum.Material.Wood, scatter)

		else
			-- An old prospect: a cairn of stacked slabs, marking where somebody
			-- dug before you did
			for j = 0, 2 + math.floor(rand() * 2) do
				local w = 3.2 - j * 0.55
				decor("Cairn", Vector3.new(w, 0.9, w),
					CFrame.new(x, y + 0.45 + j * 0.9, z) * CFrame.Angles(0, j * 0.7, 0),
					j % 2 == 0 and ROCK or ROCK_D, Enum.Material.Slate, scatter)
			end
		end
	end

	print(("[SurfaceBuilder] outlying ground scattered (%d pieces)"):format(#scatter:GetChildren()))
end

task.spawn(buildScatter)

print("[SurfaceBuilder] camp built")
