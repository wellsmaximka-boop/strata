-- ── StrataConfig ─────────────────────────────────────────────────────────────
-- Every tunable number in Phase 1 lives here. Nothing else should hold a
-- magic constant — the whole point is that tuning means editing this file.

local StrataConfig = {}

-- Prints why the server rejected a dig. Noisy by design — turn it off once the
-- loop is behaving.
StrataConfig.Debug = true

-- ── Saving ───────────────────────────────────────────────────────────────────
-- Progress is written to a DataStore, so credits, gear and strength survive
-- leaving the game. In Studio this needs "Allow Studio Access to API Services"
-- ticked under Game Settings > Security; without it saving quietly does
-- nothing, and the server says so once at startup rather than failing silently.
StrataConfig.Save = {
	Enabled     = true,
	StoreName   = "StrataPlayer",
	Version     = 1,     -- bump to abandon every existing save
	AutosaveSec = 120,
	Retries     = 3,
}

-- ── Test bench ───────────────────────────────────────────────────────────────
-- Hands every player one of everything on join, so a new item can be looked at
-- without earning it first. Debug grants are deliberately NOT written to the
-- save file: switch this off and you are back to exactly what you bought, with
-- nothing to clean up.
StrataConfig.GrantAll = {
	Enabled = true,
	Own     = false, -- own every item outright. Off: your inventory only holds what you
	                 -- actually bought, which is what makes the shop worth reading
	Credits = 8000,  -- topped up to at least this, never reduced
	OreEach = 12,    -- of every ore, so recipes can be tried
	Equip   = true,  -- wear the best armour owned in each slot
}

-- ── Mine bounds ──────────────────────────────────────────────────────────────
-- Region is centred on the origin in X/Z. Keep the voxel count sane: total
-- voxels = (SizeX/4) * (Height/4) * (SizeZ/4), and generation is a Lua loop.
StrataConfig.Mine = {
	SizeX      = 720,   -- bounding box of the generated region, centred on 0
	SizeZ      = 720,
	-- The claim is round, to match the wall around it. A square of rock inside
	-- a circular wall left the sides short of the wall and the corners poking
	-- out past it. Terrain runs to this radius and stops dead under the wall.
	Radius     = 359,
	SurfaceY   = 0,     -- nominal ground level
	CeilingY   = 16,    -- top of the generated region
	FloorY     = -960,  -- bottom of the generated region: the Frostline is not built yet,
	                    -- so the rock stops exactly where the depth chart says it does

	-- The mine is far too big to write in one go now, so it is written in two
	-- passes. The shell is everything from the sky down to ShellDepth below the
	-- surface, written at startup so the claim looks solid from the camp. Below
	-- that, chunks are written as players get near them — which is why the map
	-- can grow again later without the server start growing with it.
	ShellDepth   = 88,
	StreamRadius = 184,   -- how far ahead of a player the deep rock is written
	StreamBudget = 0.004, -- seconds per frame spent writing it
	ChunkStuds = 40,    -- must divide SizeX exactly, and SizeX/2 must be a multiple of 4
	SurfaceRelief = 4,  -- amplitude of the rolling surface (kept under the camp deck)

}
-- ── UI palette ───────────────────────────────────────────────────────────────
-- The old one was cut stone: warm greys, a granite speckle, one amber accent.
-- Read back, it was simply grey — and grey with a thin outline and a thin font
-- is the look of a placeholder, whoever made it.
--
-- Three rules now, taken off the games this is trying to sit next to:
--
--   1. The dark is not grey. It is a near-black with blue and violet in it, so
--      every accent laid on it reads as *lit* rather than as painted.
--   2. Accents are saturated to the point of being loud. A muted accent on a
--      dark panel is a smudge; the whole job of an accent is to be the thing
--      your eye goes to first.
--   3. Everything has a heavy black outline — panels, buttons and the text
--      itself. That single change does more than any colour: it is what makes
--      a flat rectangle read as an object with an edge.
StrataConfig.UI = {
	-- ── Surfaces ──
	Stone      = Color3.fromRGB(38, 35, 56),    -- panel face
	StoneDeep  = Color3.fromRGB(23, 21, 36),    -- recesses, wells, tracks
	StoneDark  = Color3.fromRGB(9, 8, 16),      -- outlines, and they are thick
	StoneLit   = Color3.fromRGB(72, 67, 104),   -- the lit top edge of a panel
	Speckle    = Color3.fromRGB(150, 142, 205), -- grain
	Vein       = Color3.fromRGB(104, 96, 148),

	Ink        = Color3.fromRGB(255, 252, 246),
	Dim        = Color3.fromRGB(176, 170, 208), -- lavender, not dead grey

	-- ── Accents ──
	-- Ore is the house colour and the one every heading, every total and every
	-- confirm button is painted in.
	Ore        = Color3.fromRGB(255, 186, 56),
	Copper     = Color3.fromRGB(255, 124, 58),
	Crystal    = Color3.fromRGB(76, 224, 255),
	Moss       = Color3.fromRGB(122, 236, 132),
	Warning    = Color3.fromRGB(255, 82, 96),
	Iron       = Color3.fromRGB(150, 156, 186),
	Violet     = Color3.fromRGB(190, 112, 255),
	Rose       = Color3.fromRGB(255, 96, 188),
	Sky        = Color3.fromRGB(88, 162, 255),

	-- ── Type ──
	-- Fredoka is the rounded, heavy face every game this is aiming at uses for
	-- anything short: headings, labels, buttons, quantities. Gotham keeps the
	-- prose, because a paragraph set in a poster face is a paragraph nobody
	-- reads, and Code keeps anything that counts — a monospaced digit is the
	-- only way a running timer does not jitter as it ticks.
	Head   = Enum.Font.FredokaOne,
	Body   = Enum.Font.GothamMedium,
	Number = Enum.Font.Code,

	-- ── Chrome ──
	-- One set of numbers so every panel in the game has the same edge, the same
	-- corner and the same drop shadow without any of them being typed twice.
	Outline   = 4,     -- panel border, in pixels
	EdgeThin  = 2.5,   -- and for the small stuff inside one
	Corner    = 14,
	CornerSm  = 8,
	TextEdge  = 2.5,   -- the black outline around text

	-- An inventory tile. Here rather than in UIKit because the grid that lays
	-- them out and the kit that draws them both need it, and a layout number is
	-- exactly what this file is for.
	TileW = 118,
	TileH = 136,
	Shadow    = 0.55,  -- transparency of the drop shadow behind a panel
	ShadowDrop = 6,    -- and how far it sits below it
}

-- ── Rarity ───────────────────────────────────────────────────────────────────
-- The six-step ladder every game in this genre uses, because using it means a
-- player already knows what a card is worth before they have read a word of it.
-- Colour does the telling; the name underneath is confirmation.
--
-- Nothing stores a rarity. It is derived — from what an ore sells for and from
-- what tier a piece of gear is — so adding an ore or a set puts it on the
-- ladder automatically and there is no second table to keep in step.
StrataConfig.Rarity = {
	{ id = "common",    name = "COMMON",    colour = Color3.fromRGB(150, 160, 186),
	  deep = Color3.fromRGB(52, 56, 74) },
	{ id = "uncommon",  name = "UNCOMMON",  colour = Color3.fromRGB(112, 226, 132),
	  deep = Color3.fromRGB(28, 72, 44) },
	{ id = "rare",      name = "RARE",      colour = Color3.fromRGB(84, 164, 255),
	  deep = Color3.fromRGB(24, 52, 104) },
	{ id = "epic",      name = "EPIC",      colour = Color3.fromRGB(190, 112, 255),
	  deep = Color3.fromRGB(62, 30, 104) },
	{ id = "legendary", name = "LEGENDARY", colour = Color3.fromRGB(255, 186, 56),
	  deep = Color3.fromRGB(96, 60, 10) },
	{ id = "mythic",    name = "MYTHIC",    colour = Color3.fromRGB(255, 86, 150),
	  deep = Color3.fromRGB(102, 20, 58) },
}

function StrataConfig.RarityAt(index)
	local list = StrataConfig.Rarity
	return list[math.clamp(index or 1, 1, #list)]
end

-- What an ore is worth decides where it sits. The bands are drawn around the
-- gaps in the real value table rather than on round numbers, so each step up
-- actually separates one group of ores from the next.
function StrataConfig.OreRarity(material)
	local value = material and material.value or 0
	if value >= 1500 then return StrataConfig.RarityAt(6) end
	if value >= 450  then return StrataConfig.RarityAt(5) end
	if value >= 200  then return StrataConfig.RarityAt(4) end
	if value >= 90   then return StrataConfig.RarityAt(3) end
	if value >= 30   then return StrataConfig.RarityAt(2) end
	return StrataConfig.RarityAt(1)
end

-- Gear starts a step up the ladder: common is kept for loose rock, because a
-- starter helmet painted the same grey as the gravel in your pack is a starter
-- helmet nobody feels good about buying.
function StrataConfig.GearRarity(gear)
	return StrataConfig.RarityAt((gear and gear.tier or 1) + 1)
end

-- ── HUD layout ───────────────────────────────────────────────────────────────
-- The left-hand column is split across two scripts — power and pack in
-- MineClient, the button grid in SurfaceUI — so both read their positions from
-- here and can never drift into each other. Y values are offsets from the
-- vertical centre of the screen, which keeps the column clear of Roblox's own
-- buttons in the top-left corner.
StrataConfig.Hud = {
	Left     = 16,
	Width    = 190,           -- the width of a 3-wide grid of 58px buttons
	-- Bottom left, the corner games put the player in. The run manifest stacks
	-- directly above it, so the corner reads as you and what you are carrying.
	Card     = { X = 16, Bottom = 16, W = 326, H = 104 },
	Strength = { Y = -141, H = 54 },
	Pack     = { Y = -79,  H = 84 },
	Grid     = { Y = 17 },
}


-- ── Look ─────────────────────────────────────────────────────────────────────
-- The whole mood in one place. The rule the references all follow: warm light,
-- cool shadow. Lamps are amber and the dark between them is blue, so the two
-- read against each other. Make the shadows brown as well and the room turns
-- into one flat sheet of the same colour, which is what it was.
StrataConfig.Look = {
	-- Deliberately dark and cool. This is what fills every surface no lamp
	-- reaches, and it is what makes a lamp look like a lamp.
	Ambient        = Color3.fromRGB(13, 16, 26),
	OutdoorAmbient = Color3.fromRGB(78, 90, 112),
	Brightness     = 2.6,
	ExposureBias   = -0.12,

	-- Skylight bounce. Turned well down, or the interior gets a free wash of
	-- daylight it has not earned and the lamps stop mattering.
	EnvironmentDiffuse  = 0.22,
	EnvironmentSpecular = 0.45,

	-- Sun low and warm, so it rakes through the roof opening rather than
	-- dropping straight down
	ClockTime      = 16.4,
	GeographicLatitude = 22,

	Atmosphere = {
		Density = 0.28,
		Haze    = 1.1,
		Glare   = 0.25,
		Colour  = Color3.fromRGB(208, 190, 168),
		Decay   = Color3.fromRGB(94, 82, 92),
	},

	-- Lamps are neon, so they bloom. This is most of the warmth.
	Bloom = { Intensity = 0.62, Size = 22, Threshold = 1.15 },

	-- A light grade: a touch more contrast so the darks stay dark, a touch
	-- more saturation so the amber is amber, and a warm tint over everything.
	Grade = {
		Contrast   = 0.14,
		Saturation = 0.09,
		Brightness = -0.015,
		Tint       = Color3.fromRGB(255, 246, 236),
	},

	-- Shafts of light through the hole in the lodge roof
	SunRays = { Intensity = 0.07, Spread = 0.72 },

	-- The top few studs of the world are turf rather than bare dirt. One line in
	-- the generator, and the whole surface stops looking like a building site.
	TurfDepth  = 5,
	TurfColour = Color3.fromRGB(96, 122, 62),
}

-- ── Strata ───────────────────────────────────────────────────────────────────
-- Ordered surface-first. `top` is the Y at which the band begins.
-- `color` recolours the terrain material at runtime, which is where each
-- band gets its identity for free.
StrataConfig.Strata = {
	{
		id       = "Topsoil",
		name     = "Topsoil",
		top      = 0,
		material = Enum.Material.Ground,
		color    = Color3.fromRGB(122, 106, 79),
		nodeDensity = 0.18,   -- fraction of node cells that hold ore
		valuePerDig = 1,
		hardness    = 1,    -- mining power needed to break it
		strengthGain = 1,   -- strength earned per successful dig
		tierBias    = 0.85, -- under 1 favours common ore, over 1 favours rare
		cavernChance = 0.75,
		-- Topsoil is only 50 studs thick. Rooms the size of the ones below would
		-- punch through into the camp, so this layer gets hollows instead.
		cavernRadius = { min = 24, max = 42 },
		archetypes  = {
			{ id = "RootHollow", weight = 70 },
			{ id = "SinkPool",   weight = 30 },
		},
		fog      = { color = Color3.fromRGB(120, 115, 100), start = 40, ending = 260 },
	},
	{
		id       = "Stonebed",
		name     = "Stonebed",
		top      = -160,
		material = Enum.Material.Rock,
		color    = Color3.fromRGB(107, 112, 121),
		nodeDensity = 0.24,
		valuePerDig = 3,
		hardness    = 25,
		strengthGain = 3,
		tierBias    = 1.10,
		cavernChance = 0.45,
		cavernRadius = { min = 34, max = 64 },
		archetypes  = {
			{ id = "Dripstone",    weight = 52 },
			{ id = "FungalHollow", weight = 30 },
			{ id = "CrystalVault", weight = 18 },
		},
		fog      = { color = Color3.fromRGB(46, 52, 60), start = 18, ending = 150 },
	},
	{
		id       = "MagmaVents",
		name     = "Magma Vents",
		top      = -460,
		material = Enum.Material.Basalt,
		color    = Color3.fromRGB(88, 62, 55),
		nodeDensity = 0.30,
		valuePerDig = 8,
		hardness    = 120,
		strengthGain = 9,
		tierBias    = 1.32,
		cavernChance = 0.58,
		cavernRadius = { min = 40, max = 76 },
		archetypes  = {
			{ id = "LavaChamber",     weight = 58 },
			{ id = "ObsidianHollow",  weight = 34 },
			{ id = "CinderCathedral", weight = 8 },
		},
		fog      = { color = Color3.fromRGB(58, 26, 18), start = 12, ending = 110 },
	},
}

-- Returns the stratum table for a world Y.
function StrataConfig.GetStratum(worldY)
	local found = StrataConfig.Strata[1]
	for _, s in ipairs(StrataConfig.Strata) do
		if worldY <= s.top then
			found = s
		end
	end
	return found
end

-- ── Cavern archetypes ────────────────────────────────────────────────────────
-- A stratum says what the rock is. An archetype says what an opening *in* that
-- rock turns out to be — and that is where the surprise lives. Two players at
-- the same depth can break into completely different rooms.
--
--   lining   what the cavern walls are made of, so it reads as a place
--   light    the colour everything in it glows
--   decor    which props get built, thickest first
--   oreBonus how much richer the rock around it is (the reason to look)
--   rare     announced to the whole server the first time anyone walks in
StrataConfig.Archetypes = {
	RootHollow = {
		name    = "Root Hollow",
		blurb   = "Roots have got down this far and pulled the soil apart.",
		lining  = Enum.Material.Mud,
		tint    = Color3.fromRGB(96, 104, 62),
		light   = Color3.fromRGB(150, 220, 130),
		fog     = Color3.fromRGB(58, 74, 46),
		decor   = { "vines", "mushrooms", "boulders" },
		oreBonus = 1.6,
		tierBoost = 1.1,
	},
	SinkPool = {
		name    = "Sink Pool",
		blurb   = "Groundwater found the low point and stayed there.",
		lining  = Enum.Material.Slate,
		tint    = Color3.fromRGB(96, 110, 118),
		light   = Color3.fromRGB(130, 200, 230),
		fog     = Color3.fromRGB(38, 60, 72),
		decor   = { "water", "stalagmites", "vines" },
		oreBonus = 1.8,
		tierBoost = 1.15,
	},
	Dripstone = {
		name    = "Dripstone Gallery",
		blurb   = "Spikes above and below, growing towards each other.",
		lining  = Enum.Material.Limestone,
		tint    = Color3.fromRGB(132, 124, 108),
		light   = Color3.fromRGB(190, 200, 215),
		fog     = Color3.fromRGB(40, 44, 50),
		decor   = { "stalagmites", "stalactites", "boulders" },
		oreBonus = 1.9,
		tierBoost = 1.15,
	},
	FungalHollow = {
		name    = "Fungal Hollow",
		blurb   = "Something down here is alive, and it glows.",
		lining  = Enum.Material.LeafyGrass,
		tint    = Color3.fromRGB(74, 92, 74),
		light   = Color3.fromRGB(120, 255, 180),
		fog     = Color3.fromRGB(26, 54, 42),
		decor   = { "mushrooms", "vines", "stalagmites" },
		oreBonus = 2.1,
		tierBoost = 1.25,
	},
	CrystalVault = {
		name    = "Crystal Vault",
		blurb   = "The whole room is lit by what is growing out of the walls.",
		lining  = Enum.Material.Glacier,
		tint    = Color3.fromRGB(120, 150, 190),
		light   = Color3.fromRGB(120, 190, 255),
		fog     = Color3.fromRGB(26, 44, 74),
		decor   = { "crystals", "stalagmites", "crystals" },
		oreBonus = 2.8,
		tierBoost = 1.5,
	},
	LavaChamber = {
		name    = "Lava Chamber",
		blurb   = "Open magma, and the walls are worth breaking.",
		lining  = Enum.Material.CrackedLava,
		tint    = Color3.fromRGB(122, 58, 40),
		light   = Color3.fromRGB(255, 140, 50),
		fog     = Color3.fromRGB(72, 24, 12),
		decor   = { "lava", "stalagmites", "crystals", "boulders" },
		oreBonus = 2.6,
		tierBoost = 1.45,
	},
	ObsidianHollow = {
		name    = "Obsidian Hollow",
		blurb   = "Cooled black glass, sharp underfoot.",
		lining  = Enum.Material.Asphalt,
		tint    = Color3.fromRGB(48, 42, 48),
		light   = Color3.fromRGB(190, 120, 255),
		fog     = Color3.fromRGB(28, 18, 32),
		decor   = { "crystals", "stalagmites", "stalactites" },
		oreBonus = 2.4,
		tierBoost = 1.4,
	},
	CinderCathedral = {
		name    = "Cinder Cathedral",
		blurb   = "A chamber the size of a church, and every wall is burning.",
		lining  = Enum.Material.Salt,
		tint    = Color3.fromRGB(168, 66, 34),
		light   = Color3.fromRGB(255, 200, 90),
		fog     = Color3.fromRGB(96, 30, 10),
		decor   = { "lava", "crystals", "stalactites", "stalagmites" },
		oreBonus = 4.0,
		tierBoost = 2.0,
		exclusiveShare = 0.26,   -- the whole point of the room
		sizeBoost = 1.45,   -- genuinely bigger than anything else down there
		rare    = true,
	},
}

function StrataConfig.GetArchetype(id)
	return id and StrataConfig.Archetypes[id] or nil
end

-- ── Surface height ───────────────────────────────────────────────────────────
-- Shared by the generator that writes the terrain and the node grid that has to
-- know where the rock actually starts. Both must agree or ore ends up floating
-- in open sky, where "is this voxel air?" is trivially true.
function StrataConfig.SurfaceHeight(wx, wz, seed)
	local offset = (seed or 0) % 4096
	local n = math.noise((wx + offset) / 120, 0.5, (wz + offset) / 120)
	return StrataConfig.Mine.SurfaceY + n * StrataConfig.Mine.SurfaceRelief
end

-- ── Cave carving ─────────────────────────────────────────────────────────────
StrataConfig.Caves = {
	Scale     = 42,    -- larger = broader caverns
	Threshold = 0.28,  -- higher = fewer caves
	Seed      = 0,     -- filled in at runtime from the server seed
}

-- Shared with NodeGrid the same way SurfaceHeight is. A node sitting in a
-- naturally hollow cell was never inside rock, so the moment a player walked
-- past it would "expose" and hang in mid-air inside the cavern. Asking the same
-- question the generator asked is the only reliable way to rule that out.
function StrataConfig.IsCave(wx, wy, wz, seed)
	local offset = (seed or 0) % 4096
	local s = StrataConfig.Caves.Scale
	local n = math.noise((wx + offset) / s, (wy + offset) / s, (wz + offset) / s)
	return n > StrataConfig.Caves.Threshold
end


-- ── Caverns ──────────────────────────────────────────────────────────────────
-- Distinct from the worm caves above. Those are texture — narrow, everywhere,
-- and they make the rock feel less like a solid block. These are rooms: one
-- candidate site per cell, most of which come to nothing, and the ones that do
-- are big enough to stand in, look around, and want to have found.
--
-- Sites are derived from the seed exactly like ore nodes are, so nothing is
-- stored and every part of the server agrees about where the rooms are.
StrataConfig.Cavern = {
	CellSize   = 96,    -- one candidate room per cell of this size, in all three axes
	MinRadius  = 24,
	MaxRadius  = 52,
	Flatten    = 1.5,   -- over 1 makes rooms wider than they are tall
	Wobble     = 0.3,   -- how far the wall wanders off a sphere, as a fraction of radius
	WobbleScale = 26,   -- size of the bumps in that wander

	-- Rooms are joined to their neighbours, so a cave system is something you
	-- can walk through rather than a set of sealed bubbles.
	TunnelRadius = 7,
	TunnelWobble = 2.5,

	-- Ore sits in the rock *around* a room, never in its open air. This is how
	-- far into the wall the rich band reaches.
	HaloDepth = 14,
}

-- ── Ore node grid ────────────────────────────────────────────────────────────
-- Nodes are not stored — they are derived deterministically from cell
-- coordinates plus the server seed, so the world is consistent without a
-- lookup table. Only *mined* cells get recorded.
StrataConfig.Nodes = {
	CellSize    = 8,    -- studs between candidate node cells
	Jitter      = 2.4,  -- deterministic offset inside the cell
	ExposeRadius = 22,  -- how close a player must be for a node to materialise
	CollectRadius = 9,  -- auto-pickup distance
	MaxExposedPerPlayer = 40,
}

-- ── Ore ──────────────────────────────────────────────────────────────────────
-- `strata` is the heart of it: an ore's weight is listed per layer, so where a
-- thing is found is a property of the thing, not a global rarity curve. An ore
-- missing from a layer simply never appears there, which is what makes a layer
-- worth travelling to rather than just harder.
--
-- `archetype` marks an ore exclusive to one kind of cavern. It cannot be found
-- in ordinary rock at any depth — only in the walls around that room. Those are
-- the finds worth telling someone about.
StrataConfig.Ores = {
	{
		id     = "Coalbit",
		name   = "Coalbit",
		family = "Commons",
		tier   = 1,
		value  = 12,
		hp     = 18,
		strata = { Topsoil = 120, Stonebed = 40 },
		color  = Color3.fromRGB(58, 56, 60),
		glow   = false,
	},
	{
		id     = "Ember",
		name   = "Ember",
		family = "Thermals",
		tier   = 1,
		value  = 25,
		hp     = 25,   -- damage needed to break the node; damage per swing = mining power
		strata = { Topsoil = 62, Stonebed = 80, MagmaVents = 38 },
		color  = Color3.fromRGB(226, 112, 48),
		glow   = true,
	},
	{
		id     = "Bloomquartz",
		name   = "Bloomquartz",
		family = "Commons",
		tier   = 2,
		value  = 60,
		hp     = 55,
		strata = { Topsoil = 16, Stonebed = 30 },
		color  = Color3.fromRGB(198, 226, 196),
		glow   = true,
	},
	{
		id     = "Ironvein",
		name   = "Ironvein",
		family = "Metals",
		tier   = 2,
		value  = 95,
		hp     = 85,
		strata = { Stonebed = 66, MagmaVents = 28 },
		color  = Color3.fromRGB(148, 152, 160),
		glow   = false,
	},
	{
		id     = "EmberRich",
		name   = "Rich Ember",
		family = "Thermals",
		tier   = 2,
		value  = 90,
		hp     = 90,
		strata = { Topsoil = 7, Stonebed = 28, MagmaVents = 58 },
		color  = Color3.fromRGB(255, 158, 60),
		glow   = true,
	},
	{
		id     = "Silverthread",
		name   = "Silverthread",
		family = "Metals",
		tier   = 3,
		value  = 190,
		hp     = 150,
		strata = { Stonebed = 13, MagmaVents = 17 },
		color  = Color3.fromRGB(226, 232, 240),
		glow   = true,
	},
	{
		id     = "Magmastone",
		name   = "Magmastone",
		family = "Thermals",
		tier   = 3,
		value  = 240,
		hp     = 200,
		strata = { MagmaVents = 52 },
		color  = Color3.fromRGB(196, 64, 36),
		glow   = true,
	},
	{
		id     = "Nightglass",
		name   = "Nightglass",
		family = "Glass",
		tier   = 3,
		value  = 330,
		hp     = 260,
		strata = { MagmaVents = 20 },
		color  = Color3.fromRGB(128, 84, 176),
		glow   = true,
	},
	{
		id     = "Cinderheart",
		name   = "Cinderheart",
		family = "Thermals",
		tier   = 4,
		value  = 420,
		hp     = 350,
		strata = { Stonebed = 2, MagmaVents = 11 },
		color  = Color3.fromRGB(255, 96, 40),
		glow   = true,
	},

	-- ── Cavern exclusives ──
	{
		id     = "Amberseed",
		name   = "Amberseed",
		family = "Growth",
		tier   = 2,
		value  = 150,
		hp     = 110,
		strata = {},
		archetype = "RootHollow",
		color  = Color3.fromRGB(240, 178, 64),
		glow   = true,
	},
	{
		id     = "Tidepearl",
		name   = "Tidepearl",
		family = "Growth",
		tier   = 2,
		value  = 175,
		hp     = 120,
		strata = {},
		archetype = "SinkPool",
		color  = Color3.fromRGB(150, 224, 232),
		glow   = true,
	},
	{
		id     = "Sporegold",
		name   = "Sporegold",
		family = "Growth",
		tier   = 3,
		value  = 260,
		hp     = 190,
		strata = {},
		archetype = "FungalHollow",
		color  = Color3.fromRGB(178, 255, 150),
		glow   = true,
	},
	{
		id     = "GeodeCore",
		name   = "Geode Core",
		family = "Glass",
		tier   = 4,
		value  = 520,
		hp     = 380,
		strata = {},
		archetype = "CrystalVault",
		color  = Color3.fromRGB(120, 200, 255),
		glow   = true,
	},
	{
		id     = "Heartflame",
		name   = "Heartflame",
		family = "Thermals",
		tier   = 5,
		value  = 1200,
		hp     = 700,
		strata = {},
		archetype = "LavaChamber",
		color  = Color3.fromRGB(255, 226, 148),
		glow   = true,
	},
	{
		id     = "Emberglass",
		name   = "Emberglass",
		family = "Glass",
		tier   = 5,
		value  = 2000,
		hp     = 950,
		strata = {},
		archetype = "CinderCathedral",
		color  = Color3.fromRGB(255, 148, 96),
		glow   = true,
	},
}

-- How much of a room's ore is the ore only that room has. Expressed as a share
-- of the table rather than a raw weight, because the layers do not have
-- comparable weight totals — the same number would mean something different in
-- the Topsoil than in the Magma Vents.
local EXCLUSIVE_SHARE = 0.13

-- Picks an ore from a deterministic 0..1 roll.
--
-- Three things shape it. The layer decides which ores are on the table at all.
-- `tierBias` skews what is left towards the better end the deeper you are, so
-- depth is worth something on its own. And a cavern archetype adds its own
-- exclusive ore plus a push towards higher tiers in the rock around it — which
-- is the entire reason to go looking for rooms instead of digging straight down.
function StrataConfig.RollOre(roll01, stratum, archetypeId)
	local bias = (stratum and stratum.tierBias) or 1
	local arch = StrataConfig.GetArchetype(archetypeId)
	if arch and arch.tierBoost then bias *= arch.tierBoost end

	local strataId = stratum and stratum.id

	local weights, total = {}, 0
	local exclusive = nil

	for i, o in ipairs(StrataConfig.Ores) do
		local w = 0
		if o.archetype then
			-- Weighed at the end, once the rest of the table is known
			if o.archetype == archetypeId then exclusive = i end
		elseif strataId then
			w = (o.strata and o.strata[strataId]) or 0
			-- Depth bias is for the ordinary table only. An exclusive is already
			-- placed by hand, and running it through a tier curve as well made
			-- the rarest ore in the game the commonest thing in its own room.
			if w > 0 then w *= bias ^ ((o.tier or 1) - 1) end
		end
		weights[i] = w
		total += w
	end

	if exclusive then
		local share = (arch and arch.exclusiveShare) or EXCLUSIVE_SHARE
		local w = total > 0 and (total * share / (1 - share)) or 1
		weights[exclusive] = w
		total += w
	end

	if total <= 0 then return StrataConfig.Ores[1] end

	local target, run = roll01 * total, 0
	for i, o in ipairs(StrataConfig.Ores) do
		run += weights[i]
		if target <= run then
			return o
		end
	end
	return StrataConfig.Ores[1]
end

function StrataConfig.GetOre(oreId)
	for _, o in ipairs(StrataConfig.Ores) do
		if o.id == oreId then return o end
	end
	return nil
end

-- ── Loose rock ───────────────────────────────────────────────────────────────
-- Every dig breaks off rock from the layer you're in, and it sells at the Depot
-- for that layer's valuePerDig. Without it, digging earned strength and nothing
-- else: you could mine for minutes and arrive at the Depot with nothing to
-- sell, because only ore paid and ore has to be found first.
-- Rock never takes a pack slot. Slots stay reserved for ore, so rock can't
-- crowd out the finds that matter.
StrataConfig.Rocks = {
	Topsoil    = { id = "Soil",   name = "Soil",   color = Color3.fromRGB(150, 128, 92) },
	Stonebed   = { id = "Stone",  name = "Stone",  color = Color3.fromRGB(140, 146, 156) },
	MagmaVents = { id = "Basalt", name = "Basalt", color = Color3.fromRGB(128, 96, 86) },
}

-- Anything that can sit in the pack: an ore, or a layer's loose rock.
function StrataConfig.GetMaterial(id)
	local ore = StrataConfig.GetOre(id)
	if ore then return ore end

	for _, s in ipairs(StrataConfig.Strata) do
		local rock = StrataConfig.Rocks[s.id]
		if rock and rock.id == id then
			return { id = id, name = rock.name, value = s.valuePerDig, color = rock.color, rock = true }
		end
	end
	return nil
end

-- ── Digging ──────────────────────────────────────────────────────────────────
-- Terrain resolves at 4 studs, so a radius below ~4 barely does anything.
-- This is the number to play with first.
StrataConfig.Dig = {
	Radius      = 5.0,
	Cooldown    = 0.28,  -- seconds between server-accepted digs
	MaxDistance = 22,    -- studs from character; server-enforced
}

-- ── Feel ─────────────────────────────────────────────────────────────────────
StrataConfig.Feel = {
	CameraKick = 0.4,   -- degrees of pitch per dig. Set to 0 to switch it off.
	KickDecay  = 12,    -- higher = snappier; the kick lasts roughly 1/this seconds
	DebrisMin  = 3,
	DebrisMax  = 5,
}

-- ── Scanner ──────────────────────────────────────────────────────────────────
-- Every sweep is a roll. Cooldown is the single most important pacing number
-- in the game — if this feels slow, the whole design feels slow.
StrataConfig.Scanner = {
	Cooldown   = 2.4,
	Radius     = 48,
	-- Reported distance bands. The scanner never returns coordinates.
	Bands = {
		{ max = 12,   label = "ON TOP OF IT" },
		{ max = 24,   label = "CLOSE" },
		{ max = 40,   label = "NEARBY" },
		{ max = 9e9,  label = "DISTANT" },
	},
}

function StrataConfig.DistanceBand(d)
	for _, b in ipairs(StrataConfig.Scanner.Bands) do
		if d <= b.max then return b.label end
	end
	return "DISTANT"
end

-- ── Depth chart ──────────────────────────────────────────────────────────────
-- The full ladder, including the layers that are designed but not generated
-- yet. Kept separate from `Strata` on purpose: the generator and GetStratum
-- must only ever see what actually exists, while the chart is allowed to show
-- what is coming. The unbuilt entries are what make the bottom of the screen
-- read as somewhere still to go.
StrataConfig.DepthChart = {
	{ id = "Topsoil",    name = "Topsoil",     top = 0,     built = true,
	  color = Color3.fromRGB(150, 128, 92),
	  hardness = 1,   blurb = "Loose dirt. Anything can break it.",
	  finds = { "Ember" } },

	{ id = "Stonebed",   name = "Stonebed",    top = -160,  built = true,
	  color = Color3.fromRGB(126, 132, 142),
	  hardness = 25,  blurb = "Proper rock. The first wall you hit.",
	  finds = { "Ember", "EmberRich" } },

	{ id = "MagmaVents", name = "Magma Vents", top = -460,  built = true,
	  color = Color3.fromRGB(196, 92, 56), requires = "HEAT 3",
	  hardness = 120, blurb = "Basalt and lava pockets. Rich, and it cooks you.",
	  finds = { "Ember", "EmberRich", "Cinderheart" } },

	{ id = "Frostline",  name = "Frostline",   top = -960,  built = false,
	  color = Color3.fromRGB(104, 168, 200), requires = "COLD gear",
	  hardness = 400, blurb = "Glacier ice over buried caverns.",
	  finds = { "Insulite family" } },

	{ id = "TheCrush",   name = "The Crush",   top = -1600, built = false,
	  color = Color3.fromRGB(122, 116, 148), requires = "PRESSURE gear",
	  hardness = 1200, blurb = "Salt and limestone under enormous weight.",
	  finds = { "Densite family" } },

	{ id = "TheNull",    name = "The Null",    top = -2600, built = false,
	  color = Color3.fromRGB(138, 92, 190), requires = "unknown",
	  hardness = 4000, blurb = "Nobody has come back with a description.",
	  finds = { "???" } },
}

-- What each built layer is listed as holding is read off the ore table rather
-- than typed out twice. Adding an ore to a layer updates the chart with it, and
-- the two can never disagree about what is down there.
--
-- Cavern exclusives are left off on purpose. They have no layer, they belong to
-- a room you have to find, and a chart that named them in advance would give
-- away the one thing worth being surprised by.
for _, layer in ipairs(StrataConfig.DepthChart) do
	if layer.built then
		local list = {}
		for _, ore in ipairs(StrataConfig.Ores) do
			if not ore.archetype and (ore.strata[layer.id] or 0) > 0 then
				table.insert(list, ore.id)
			end
		end
		layer.finds = list
	end
end

StrataConfig.ChartFloor = -3400   -- where the chart bottoms out

-- ── Surface ──────────────────────────────────────────────────────────────────
-- Shared by the builder that puts the camp up and the service that watches it,
-- so the pads and the buildings can never drift apart.
StrataConfig.Surface = {
	PlatformY    = 9,
	PlatformSize = 200,
	ShaftSize    = 26,   -- the open square in the middle: the way down
	-- Everything now lives inside the lodge, so these are places on its floor
	-- rather than pads out in the open.
	SellPos      = Vector3.new(46, 9.5, 0),
	CraftPos     = Vector3.new(-46, 9.5, 0),
	LiftPos      = Vector3.new(-44, 9.5, 32),
	PickPos      = Vector3.new(0, 9.5, -32),
	RunsPos      = Vector3.new(42, 9.5, 50),
	BuildingSet  = 50,   -- how far out the buildings sit from the centre
	RingSize     = 13,   -- diameter of the rug that marks each station
	ZoneRange    = 7,    -- horizontal reach: half the rug, so the whole of it counts

	-- ── The lodge ──
	-- One timber hall built around the mine head, rather than four sheds in a
	-- field. You walk in, and everything you need is a piece of furniture along
	-- a wall: the forge at the far end where the fire is, the depot by the door,
	-- the shaft open in the middle of the floor with the winch over it.
	Lodge = {
		HalfX  = 84,
		HalfZ  = 62,
		Wall   = 1.6,

		-- Two floors. The ground is where the work is; the gallery runs right
		-- round above it, open to the middle, so you can stand at the rail and
		-- look down on the shaft.
		Gallery = 20,   -- height of the gallery floor above the deck
		Depth   = 20,   -- how far the gallery reaches in from the wall
		Height  = 42,   -- underside of the roof

		Opening = 34,   -- square hole in the roof the headframe stands through
		DoorX   = 0,    -- centre of the doorway on the +Z wall
		DoorW   = 16,
	},
}

-- Each zone owns a colour, and the pad, the building, the floor inlay and the
-- sign all take it from here — so the camp reads as three destinations rather
-- than three sheds.
StrataConfig.Zones = {
	runs = {
		title  = "CONTRACTS",
		blurb  = "take work underground",
		accent = Color3.fromRGB(255, 186, 56),
		deep   = Color3.fromRGB(122, 84, 18),
	},
	sell = {
		title  = "DEPOT",
		blurb  = "sell your haul",
		accent = Color3.fromRGB(122, 236, 132),
		deep   = Color3.fromRGB(28, 104, 54),
	},
	craft = {
		title  = "FORGE",
		blurb  = "spend ore on gear",
		accent = Color3.fromRGB(255, 124, 58),
		deep   = Color3.fromRGB(124, 52, 16),
	},
	lift = {
		title  = "LIFT",
		blurb  = "descend to unlocked depths",
		accent = Color3.fromRGB(76, 224, 255),
		deep   = Color3.fromRGB(18, 92, 124),
	},
	pickaxe = {
		title  = "PICK WORKS",
		blurb  = "stronger picks break harder rock",
		accent = Color3.fromRGB(190, 112, 255),
		deep   = Color3.fromRGB(86, 32, 134),
	},
}

-- ── Player ───────────────────────────────────────────────────────────────────
StrataConfig.Player = {
	-- Sits just clear of the tallest surface relief, so the pad never buries.
	-- On a diagonal, so it never sits on one of the four paths running from the
	-- shaft out to the stations.
	SpawnPosition = Vector3.new(24, 12, -24),
	BackpackSlots = 60,  -- Phase 1: a simple count, no weight classes yet

	-- Enough to break topsoil on the first swing and nothing else. Strength is
	-- earned by mining, so the activity is the progression.
	StartingStrength = 5,
}


-- ── Pack light ───────────────────────────────────────────────────────────────
-- A mast on the side of the backpack with a glowing head, like the antenna in
-- Ghost Simulator: it is the first thing anybody notices about your kit, and it
-- says what you have earned without a number on screen.
--
-- The level never rises from mining. It is a prestige reward, so every level is
-- a visible mark of having gone round again.
StrataConfig.PackLight = {
	Levels = {
		{ mast = 1.1, heads = 1, range = 16, brightness = 1.1,
		  -- Never zero. The ambient underground is deliberately black, so level one
		  -- still has to be enough to see the rock in front of you.
		  colour = Color3.fromRGB(255, 78, 62),  name = "Ember",    grants = { light = 11, walkSpeed = 0 } },
		{ mast = 1.5, heads = 2, range = 26, brightness = 1.5,
		  colour = Color3.fromRGB(255, 146, 52), name = "Flare",    grants = { light = 18, walkSpeed = 1 } },
		{ mast = 1.9, heads = 2, range = 38, brightness = 1.9,
		  colour = Color3.fromRGB(255, 214, 86), name = "Beacon",   grants = { light = 28, walkSpeed = 2 } },
		{ mast = 2.3, heads = 3, range = 52, brightness = 2.3,
		  colour = Color3.fromRGB(126, 222, 255), name = "Arclight", grants = { light = 42, walkSpeed = 3 } },
		{ mast = 2.7, heads = 4, range = 70, brightness = 2.8,
		  colour = Color3.fromRGB(196, 140, 255), name = "Nova",    grants = { light = 62, walkSpeed = 5 } },
	},
}


-- What mining power a layer really wants, before the tier multiplies it.
--
-- Two things set the floor. You cannot break the layer's rock at all below its
-- hardness, and you want a node down in about four swings or the clock beats
-- you — so it is whichever of those is larger, worked out from the ore actually
-- in that layer rather than typed in and left to rot.
function StrataConfig.RecommendedPower(stratum, tierIndex)
	if not stratum then return 0 end

	local weighted, weight = 0, 0
	for _, ore in ipairs(StrataConfig.Ores) do
		local w = (not ore.archetype) and (ore.strata[stratum.id] or 0) or 0
		if w > 0 then
			weighted += ore.hp * w
			weight   += w
		end
	end

	local perNode = weight > 0 and (weighted / weight) / 4 or 0
	local base    = math.max(stratum.hardness or 1, perNode)
	local tier    = StrataConfig.Difficulty(tierIndex)

	return math.floor(base * (tier.power or 1) + 0.5)
end

function StrataConfig.Difficulty(index)
	local list = StrataConfig.Expedition.Difficulties
	return list[math.clamp(index or 1, 1, #list)]
end

function StrataConfig.PackLightLevel(level)
	local list = StrataConfig.PackLight.Levels
	return list[math.clamp(level or 1, 1, #list)]
end


-- ── Expeditions ──────────────────────────────────────────────────────────────
-- A run is a contract taken at the camp, a drop to a layer, a clock, and a walk
-- back to the shaft. Ore mined during one is raw: it only becomes yours when
-- you extract. See DESIGN-EXPEDITIONS.md for where these numbers come from.
StrataConfig.Expedition = {
	-- What survives a failed run. Deliberately generous — total loss reads as
	-- punishment in a simulator, a partial haul reads as a bad day.
	FailKeep = 0.4,

	BoardSize  = 3,     -- contracts offered at once
	RefreshSec = 300,   -- how often the board turns over

	-- How close to the central shaft you have to be to call the pod
	ExtractRange = 16,

	-- Measured against the live ore table: a Topsoil chamber is worth about
	-- 4,000, a Stonebed one 26,000, a Magma one 279,000. Clocks are set so the
	-- deeper you go the less of a chamber you can take.
	Layers = {
		Topsoil    = { duration = 380, payout = 400,  bonus = 250,  haul = { 18, 34 } },
		Stonebed   = { duration = 600, payout = 1800, bonus = 900,  haul = { 26, 48 } },
		MagmaVents = { duration = 780, payout = 9000, bonus = 4500, haul = { 34, 60 } },
	},


	-- ── Difficulty ──
	-- Chosen when you take a contract, the way a hazard level is in Deep Rock.
	-- Less time and a bigger quota, for a great deal more money. The clock is
	-- what actually bites: the quota scales slower than the pay, so the hard
	-- tiers are a bet on how fast you are rather than a wall.
	Difficulties = {
		{ id = "steady", name = "STEADY", time = 1.00, pay = 1.0, quota = 1.00, power = 1.0, xp = 1.0,
		  colour = Color3.fromRGB(142, 192, 142), blurb = "no rush" },
		{ id = "hard", name = "HARD", time = 0.86, pay = 1.7, quota = 1.25, power = 1.8, xp = 1.5,
		  colour = Color3.fromRGB(226, 178, 108), blurb = "tight" },
		{ id = "brutal", name = "BRUTAL", time = 0.72, pay = 2.9, quota = 1.55, power = 3.0, xp = 2.2,
		  colour = Color3.fromRGB(224, 112, 92), blurb = "no mistakes" },
		{ id = "nightmare", name = "NIGHTMARE", time = 0.58, pay = 5.2, quota = 2.0, power = 5.0, xp = 3.2,
		  colour = Color3.fromRGB(178, 132, 232), blurb = "do not come back empty" },
	},

	Kinds = {
		{ id = "haul",    weight = 42 },
		{ id = "extract", weight = 36 },
		{ id = "survey",  weight = 22 },
	},
}

-- ── Descent ──────────────────────────────────────────────────────────────────
-- Taking a contract is not a teleport. There is a bore straight down the middle
-- of the claim, a cage that runs in it, and you stand in the cage while the
-- layers go past. The whole point of it is the wait: by the time the gate opens
-- you have watched the Stonebed give way to basalt and you know where you are.
--
-- The bore is real terrain, carved by the same voxel function that writes
-- everything else, so it costs one extra condition per voxel and nothing else.
-- It only runs as deep as the deepest layer anybody on this server has stood
-- in — look down it from the camp and the bottom of it is the bottom of what
-- the crew has found.
StrataConfig.Descent = {
	BoreRadius = 11,     -- must stay under Surface.ShaftSize / 2, or it undercuts the deck

	-- A station cut into the rock at each layer, so the gate opens onto a floor
	-- rather than onto a wall.
	-- How far below a layer's roof its station sits. A share of the layer rather
	-- than a constant: twenty-four studs into a five-hundred-stud layer puts the
	-- station in the ceiling, and every hall in the site then sits a hundred and
	-- fifty studs below the place you arrive at.
	LandingDrop   = { Share = 0.35, Min = 30, Max = 150 },
	LandingRadius = 34,
	LandingHalf   = 16,  -- half the height of the station chamber
	Overrun       = 30,  -- how far the bore runs past the deepest station

	-- The cage. Sized to run clear of the bore wall with room to look out.
	Cage = { Half = 7.2, Height = 13 },

	-- Ride length is not linear in depth. Two seconds to the Topsoil would read
	-- as a teleport with a wipe over it, and nobody wants to stand still for
	-- more than about a quarter of a minute, so it is a fixed cost plus a rate,
	-- clamped at both ends.
	MinRide    = 5.0,
	Speed      = 46,     -- studs per second, on top of the minimum
	MaxRide    = 18,
	RiseFactor = 0.62,   -- coming up is shorter: the tension is already spent

	GateTime = 1.0,      -- how long the gates take to run open or shut
	Park     = 4.0,      -- how long the cage waits at a station before leaving

	-- Shaft furniture. Guide rails run the full bore; ribs and lamps are spaced
	-- so there is always something passing the gate.
	RibEvery  = 13,
	LampEvery = 58,
}

-- Where the cage stops for a layer, and how long it takes to get there. Both
-- are read by the service that drives the cage and the client that draws the
-- gauge, so the number on screen and the number of seconds can never disagree.

-- The top and bottom of a layer. Several files were each working this out from
-- the strata list in their own slightly different way; a contract that confines
-- you to a layer needs everyone to agree on where it ends.
function StrataConfig.LayerBounds(layerId)
	for i, s in ipairs(StrataConfig.Strata) do
		if s.id == layerId then
			local below = StrataConfig.Strata[i + 1]
			return s.top, below and below.top or StrataConfig.Mine.FloorY
		end
	end
	return StrataConfig.Mine.CeilingY, StrataConfig.Mine.FloorY
end

function StrataConfig.LandingY(stratum)
	local D      = StrataConfig.Descent
	local bottom = StrataConfig.Mine.FloorY

	for i, s in ipairs(StrataConfig.Strata) do
		if s.id == stratum.id and StrataConfig.Strata[i + 1] then
			bottom = StrataConfig.Strata[i + 1].top
		end
	end

	local thickness = (stratum.top or 0) - bottom
	local drop = math.clamp(thickness * D.LandingDrop.Share,
		D.LandingDrop.Min, D.LandingDrop.Max)

	return (stratum.top or 0) - drop
end

function StrataConfig.RideSeconds(fromY, toY, rising)
	local D = StrataConfig.Descent
	local t = D.MinRide + math.abs(fromY - toY) / D.Speed
	t = math.min(t, D.MaxRide)
	return rising and t * D.RiseFactor or t
end

-- ── Dig sites ────────────────────────────────────────────────────────────────
-- The map a contract drops you into: a handful of big open halls hung off the
-- landing station on sloping lit tunnels. See DigSite.lua for the layout and
-- DESIGN-EXPEDITIONS.md section 7 for why it is shaped like this.
--
-- The one rule behind these numbers: a site has to be bigger than you can
-- clear. Walking the near ring and one far chamber is about what a steady
-- clock allows, so which far chamber is the decision the run is made of.
StrataConfig.Site = {
	Chambers  = { Base = 5, Max = 8 },
	Primaries = 3,     -- how many galleries leave the station itself

	-- Distance from the hub for the first ring, and from a parent hall for the
	-- branches hanging off it. Halls are big enough now that these are mostly
	-- deciding how much they overlap rather than how far apart they sit.
	NearRing = { min = 118, max = 188 },
	FarRing  = { min = 108, max = 172 },

	BearingJitter = 0.34,   -- radians either side of an even spread
	BranchSpread  = 0.95,   -- how far a branch swings off its parent's bearing
	MaxGrade      = 0.62,   -- steepest gallery, as a fall over its horizontal run

	-- How far apart halls are held, as a share of their radii. Under 1 they
	-- overlap, and overlapping is the point: a site should read as one cave
	-- system with lobes, not as rooms joined by corridors. At 0.72 adjacent
	-- halls share a wide mouth and you can see from one into the next.
	Separation = 0.72,

	-- Chamber size comes from the layer's own cavern band, scaled up, then cut
	-- back if the layer is too thin to hold it even lying flat.
	RadiusScale = { min = 1.5, max = 1.6 },
	RadiusCap   = 112,      -- the biggest hall anywhere, so one fill stays cheap
	VaultBoost  = 1.2,      -- the hall at the far end of the map

	Flatten    = 1.32,  -- over 1 makes a hall wider than it is tall
	FlattenMax = 3.2,   -- and how flat a thin layer is allowed to squash one
	BandSpread = 0.55,  -- how much of the layer's usable depth halls spread over

	Roof        = 14,   -- cover kept under the rock surface, always
	LayerMargin = 6,    -- and clearance kept off the layer above and below

	-- ── Relief ──
	-- An empty hall is a room. What makes it a cave is what is left standing in
	-- it and what is cut out of it, and all three of these are the same trick:
	-- put solid rock back after the air is carved, or take more away.

	-- Columns floor to ceiling. The single biggest thing for scale — you cannot
	-- tell how big a space is until something in it blocks your view of the far
	-- side.
	Pillars     = { min = 3, max = 7 },
	PillarWidth = { min = 0.09, max = 0.2 },   -- as a share of hall radius

	-- Stepped floors. Every reference for this is a terrace rather than a flat
	-- pan, and a slab put back after the air is cut is the cheapest way there is.
	Shelves = { min = 3, max = 6 },

	-- Pockets bitten out of the wall. This is the perimeter detail: it stops the
	-- hall being a clean sphere, and it is where the dark corners are.
	-- Fewer and much bigger than they were. Ten small bites out of a wall is
	-- noise you walk past; three wide ones are bays you walk *into*, which is
	-- the difference between detail and clutter.
	Alcoves    = { min = 2, max = 4 },
	AlcoveSize = { min = 0.3, max = 0.5 },     -- as a share of hall radius

	-- And one hole in the floor at most, wide enough to be a feature of the
	-- room rather than a thing you fall in by accident
	Pits     = { min = 0, max = 2 },
	PitSize  = { min = 0.3, max = 0.48 },
	-- How far a pit is pushed below the sphere it hangs off, as a share of the
	-- two radii together. Must stay under one, or the pit does not touch the
	-- hall and becomes a sealed pocket in the rock.
	PitDepth = { min = 0.55, max = 0.94 },

	-- ── Galleries ──
	-- Wide enough that walking one does not feel like a corridor. The old ten
	-- was a pipe; at eighteen you can see the hall you are heading for from the
	-- middle of the one you are leaving.
	DriftRadius = 18,
	DriftStep   = 0.9,  -- spacing of the path points, as a share of tunnel width
	DriftSway   = 42,   -- how far the tunnel wanders off the straight line
	DriftSag    = 20,
	LampEvery   = 34,   -- lamps down a gallery, in studs

	-- The rock around a hall is worth mining. Sites are the reason to take a
	-- contract rather than dig a hole in the Topsoil for an hour.
	OreBonus    = 1.5,
	LiningDepth = 4,    -- how thick the shell of a room's own rock is


	-- Confinement. A contract is for one layer, and the seams above and below
	-- are where it stops: the rock there will not break while you are on the
	-- job. The rule lives in MineService; these are the two sheets that say so,
	-- because a wall you cannot see is a wall players report as a bug.
	Seam = {
		Margin  = 4,     -- studs of slack either side, so the floor of a hall is diggable
		Alpha   = 0.88,
		Thick   = 1.2,
	},

	-- ── Objectives ──
	-- A deposit is a thing you find, stand at and break. Three to five of them,
	-- one per hall, and you cannot have them all without walking the map.
	Deposit = {
		Count   = { 3, 5 },
		Hp      = 7,        -- multiplied by the layer hardness
		Yield   = { 5, 9 },  -- ore dropped when it comes down
		Marker  = 300,      -- how far off you can see its marker, in studs
	},
}

-- ── Flares ───────────────────────────────────────────────────────────────────
-- Three of them, one back every half minute, thrown by hand.
--
-- The whole reason they exist is that the halls are now big enough and dark
-- enough to have corners you cannot see into. A pack light follows you around
-- and lights what you are already looking at; a flare is light you *place*, and
-- placing it is a decision — into the pit, across the hall, or down the gallery
-- you are about to walk back up.
--
-- Held to charge, released to throw, with the arc drawn while you hold. The arc
-- matters more than the flare: it is what turns "press a button" into aiming.
StrataConfig.Flare = {
	Charges  = 3,
	Recharge = 30,     -- seconds to get one back, counted per charge

	ChargeTime = 1.05, -- hold this long for a full-power throw
	MinSpeed   = 70,   -- a tap drops it at your feet
	MaxSpeed   = 205,
	Lift       = 0.33, -- how much of the throw is turned upward, so it arcs

	Life = 62,         -- seconds it burns for
	Fade = 5,          -- and how long it takes to go out at the end

	Colour     = Color3.fromRGB(255, 208, 138),
	Range      = 82,
	Brightness = 5.5,

	-- The dotted line, Angry Birds style: simulated forward under real gravity
	-- and stopped at the first thing it would hit, so it shows where the flare
	-- actually lands rather than where it would go in a vacuum.
	Arc = { Dots = 34, Step = 0.055, Size = 0.6 },

	-- Only underground and only on a contract. On the surface there is nothing
	-- to light and it would just be litter on the camp deck.
	MinDepth = 8,
}
-- ── Stability ────────────────────────────────────────────────────────────────
-- The mine is the antagonist. Stability drains per dig and knits back together
-- over time, so what bites is hammering one spot rather than taking too much
-- overall — the pack already limits the total.
--
-- Flat out, a chamber comes down in 54 to 130 seconds depending on its size,
-- while a full pack takes about 2.4 minutes of digging. You cannot fill a pack
-- from one chamber, which is the decision the whole run is built around.
StrataConfig.Stability = {
	DigCost   = 0.0152,   -- divided by the square root of the chamber radius
	NodeMult  = 3,        -- breaking ore shakes it three times as hard
	Recover   = 0.004,    -- per second
	Reach     = 14,       -- studs past the chamber wall that still counts as inside it

	-- What the rock does on the way down
	Stages = {
		{ at = 0.65, id = "creak",    label = "the rock creaks" },
		{ at = 0.40, id = "debris",   label = "debris falling" },
		{ at = 0.20, id = "rockfall", label = "ROCKFALL — get out", damage = 4 },
		{ at = 0.00, id = "collapse", label = "COLLAPSE",           damage = 34 },
	},

	-- A collapsed chamber stays shut for the session
	CollapseFill = 0.72,   -- how much of the chamber the fall fills
}


-- ── Levels ───────────────────────────────────────────────────────────────────
-- Experience comes from finishing runs, not from swinging a pick. Mining pays
-- in ore and strength already; this is the number that says how many times you
-- have gone down there and come back, which is a different kind of progress.
--
-- Deliberately not tied to the payout. Credits scale enormously with depth and
-- tier — a Nightmare Magma haul is a hundred times a Topsoil one — and a level
-- bar that moves a hundred times faster at the bottom is not a bar, it is a
-- formality. The layer and the tier set it directly instead.
StrataConfig.Levels = {
	-- To go from level n to n+1: Base * n^Curve
	Base  = 120,
	Curve = 1.5,
	Max   = 60,

	Run = {
		Topsoil    = 140,
		Stonebed   = 320,
		MagmaVents = 700,
	},

	FailShare      = 0.25,   -- what a run you did not finish still pays
	ObjectiveBonus = 0.5,    -- extra share for actually meeting the contract

	-- The first time you stand in a layer is worth something on its own
	Discovery = 150,
}

function StrataConfig.XpForLevel(level)
	local L = StrataConfig.Levels
	return math.floor(L.Base * (math.max(level, 1) ^ L.Curve))
end

-- How much a finished run is worth, before the objective bonus
function StrataConfig.RunXp(layerId, tierIndex)
	local L    = StrataConfig.Levels
	local base = L.Run[layerId] or L.Run.Topsoil
	local tier = StrataConfig.Difficulty(tierIndex)
	return math.floor(base * (tier.xp or 1))
end


-- ── Sprint ───────────────────────────────────────────────────────────────────
-- Hold shift. Stamina exists so that walk speed from gear still means something
-- — with unlimited sprint the base speed is a number nobody ever experiences —
-- and so the walk back to the shaft with a full pack is a decision rather than
-- a formality.
StrataConfig.Sprint = {
	Multiplier = 1.55,
	Max        = 100,
	Drain      = 17,    -- per second while sprinting
	Recover    = 12,    -- per second while not
	Delay      = 0.7,   -- seconds after sprinting before it starts coming back
	MinToStart = 18,    -- cannot set off again below this, so it is not a stutter
}

-- ── Held gear placement ──────────────────────────────────────────────────────
-- These are pure taste and impossible to get right without looking at them.
-- Tweak freely: the first CFrame is position relative to the limb, the
-- CFrame.Angles is rotation in degrees-converted radians.
StrataConfig.Grip = {
	-- Pickaxe in the right hand. Handle runs along its own Y, head at the top.
	PickaxeR15 = CFrame.new(0, -0.1, -0.7) * CFrame.Angles(math.rad(-60), 0, 0),
	PickaxeR6  = CFrame.new(0, -0.9, -0.6) * CFrame.Angles(math.rad(-60), 0, 0),

	-- Backpack on the upper back.
	PackR15 = CFrame.new(0, 0.15, 0.75) * CFrame.Angles(0, 0, 0),
	PackR6  = CFrame.new(0, 0.25, 0.85) * CFrame.Angles(0, 0, 0),
}

-- ── Swing ────────────────────────────────────────────────────────────────────
-- Procedural, driven straight onto the shoulder and elbow joints each frame.
-- Phase lengths sum to roughly the dig cooldown so swings chain into a rhythm
-- instead of interrupting each other.
StrataConfig.Swing = {
	Windup  = 0.07,
	Chop    = 0.08,
	Recover = 0.13,

	RaiseDeg = 52,    -- how far back the arm cocks
	ChopDeg  = -118,  -- how far forward it drives
	ElbowDeg = 62,    -- bend at the top of the windup
	LeanDeg  = 9,     -- torso pitch into the swing

	-- The tool swings around the hand, which works on any rig. Gain above 1
	-- compensates for the arm not moving on rigs with no exposed joints.
	ToolGain = 1.5,

	-- Flip to 1 if the swing goes backwards on your rig.
	Direction = -1,
}

return StrataConfig
