local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- Where a layer starts, by id. Gates and lift stops used to carry their own
-- copies of these numbers, and deepening the layers left both of them pointing
-- at rock that had moved.
local function layerTop(id)
	for _, s in ipairs(StrataConfig.Strata) do
		if s.id == id then return s.top end
	end
	return 0
end

-- ── GearConfig ───────────────────────────────────────────────────────────────
-- Two kinds of gear.
--
--   Armour goes into a slot — helmet, chest, legs — and only counts while it is
--   equipped. That is where the choice lives: a full Thermal set opens the
--   Magma Vents, and later families will trade heat for cold or pressure.
--
--   Tools (lamp, pack, scanner) are passive. Owning one is enough.
--
-- Being "stuck" should always be specific: you are one piece short of a set,
-- and the armour screen tells you which.

local GearConfig = {}

-- ── Armour slots ─────────────────────────────────────────────────────────────
GearConfig.ArmorSlots = {
	{ id = "helmet", name = "Helmet",     glyph = "▲" },
	{ id = "chest",  name = "Chestplate", glyph = "■" },
	{ id = "legs",   name = "Leggings",   glyph = "▼" },
}

function GearConfig.IsArmorSlot(slot)
	for _, s in ipairs(GearConfig.ArmorSlots) do
		if s.id == slot then return true end
	end
	return false
end

function GearConfig.SlotName(slot)
	for _, s in ipairs(GearConfig.ArmorSlots) do
		if s.id == slot then return s.name end
	end
	return slot
end

-- ── Depth gates ──────────────────────────────────────────────────────────────
-- Level 3 with one point per Thermal piece means the full set is the key, not
-- a single purchase. Completing a set is a better goal than buying one item.
GearConfig.DepthGates = {
	{
		-- The moment you break the roof of the Magma Vents, not a stud before
		belowY     = layerTop("MagmaVents"),
		resistance = "heat",
		level      = 3,
		label      = "HEAT",
		warning    = "HEAT WARNING — full thermal set required",
		damage     = 5,
	},
}

function GearConfig.GateAt(worldY)
	local active = nil
	for _, gate in ipairs(GearConfig.DepthGates) do
		if worldY <= gate.belowY then
			active = gate
		end
	end
	return active
end

-- ── Gear ─────────────────────────────────────────────────────────────────────
GearConfig.Gear = {
	-- ── Canvas: the starter kit. Small perks, a modest set bonus, no biome. ──
	{
		id = "CanvasHood", name = "Canvas Hood", slot = "helmet", tier = 1,
		blurb  = "A lamp clip above the brow.",
		grants = { light = 6 },
		cost   = { credits = 60, ore = {} },
	},
	{
		id = "CanvasVest", name = "Canvas Vest", slot = "chest", tier = 1,
		blurb  = "Pockets, mostly.",
		grants = { capacity = 10 },
		cost   = { credits = 110, ore = {} },
	},
	{
		id = "CanvasLegs", name = "Canvas Trousers", slot = "legs", tier = 1,
		blurb  = "Reinforced at the knee, for obvious reasons.",
		grants = { walkSpeed = 2 },
		cost   = { credits = 80, ore = {} },
	},

	-- ── Thermal: each piece earns its keep alone; the set opens the Vents. ──
	{
		id = "ThermalVisor", name = "Thermal Visor", slot = "helmet", tier = 2,
		blurb  = "Smoked glass cuts the haze — you see further in the dark.",
		grants = { light = 12 },
		cost   = { credits = 320, ore = { Ember = 10 } },
	},
	{
		id = "ThermalPlate", name = "Thermal Plating", slot = "chest", tier = 2,
		blurb  = "Rigid shell, and somewhere to hang more rock.",
		grants = { capacity = 14 },
		cost   = { credits = 520, ore = { Ember = 18, EmberRich = 4 } },
	},
	{
		id = "ThermalGreaves", name = "Thermal Greaves", slot = "legs", tier = 2,
		blurb  = "Light enough to move quickly over hot ground.",
		grants = { walkSpeed = 3 },
		cost   = { credits = 380, ore = { Ember = 14 } },
	},

	-- ── Pickaxes: raw mining power. The best one you own is always the one in
	-- your hands, so there is never a reason to fiddle with equipping. ──
	{
		id = "IronPick", name = "Iron Pick", slot = "pickaxe", tier = 2,
		blurb  = "Heavier head, and it holds an edge.",
		grants = { power = 15 },
		cost   = { credits = 180, ore = {} },
	},
	{
		id = "TemperedPick", name = "Tempered Pick", slot = "pickaxe", tier = 3,
		blurb  = "Quenched steel. The Stonebed stops being a wall.",
		grants = { power = 50 },
		cost   = { credits = 700, ore = { Ember = 12 } },
	},
	{
		id = "ThermalPick", name = "Thermal Pick", slot = "pickaxe", tier = 4,
		blurb  = "Cinder-forged, and it swings faster than it has any right to.",
		grants = { power = 150, digCooldown = -0.06 },
		cost   = { credits = 1800, ore = { EmberRich = 10, Cinderheart = 1 } },
	},

	-- ── Tools: passive, no slot to equip ──
	{
		id = "LampI", name = "Carbide Lamp", slot = "lamp", tier = 1,
		blurb  = "Turns the dark from a wall into an inconvenience.",
		grants = { light = 22 },
		cost   = { credits = 120, ore = {} },
	},
	{
		id = "PackI", name = "Braced Pack", slot = "pack", tier = 1,
		blurb  = "Forty more stones before the walk back.",
		grants = { capacity = 40 },
		cost   = { credits = 260, ore = { Ember = 8 } },
	},
	{
		id = "ScannerII", name = "Tuned Array", slot = "scanner", tier = 2,
		blurb  = "Wider sweep, and it recovers faster between pulses.",
		grants = { scanRadius = 26, scanCooldown = -0.7 },
		cost   = { credits = 480, ore = { Ember = 14 } },
	},
}

-- ── Sets ─────────────────────────────────────────────────────────────────────
-- Individual pieces carry a perk you feel the moment you buy them. The set
-- bonus is what grants resistance — so a biome is opened by completing a set,
-- never by a single purchase, and partial progress is still worth wearing.
GearConfig.Sets = {
	{
		id     = "Canvas",
		name   = "Canvas Kit",
		blurb  = "Nothing special, but it adds up.",
		pieces = { "CanvasHood", "CanvasVest", "CanvasLegs" },
		bonus  = { capacity = 12 },
	},
	{
		id      = "Thermal",
		name    = "Thermal Set",
		blurb   = "Rated for sustained contact with molten rock.",
		pieces  = { "ThermalVisor", "ThermalPlate", "ThermalGreaves" },
		bonus   = { heat = 3, capacity = 16, light = 8 },
		unlocks = "Magma Vents",
	},
}

function GearConfig.SetFor(gearId)
	for _, set in ipairs(GearConfig.Sets) do
		for _, id in ipairs(set.pieces) do
			if id == gearId then return set end
		end
	end
	return nil
end

-- How much of each set is currently worn.
-- Returns { { set, worn, total, complete }, ... }
function GearConfig.SetProgress(equipped)
	local out = {}
	for _, set in ipairs(GearConfig.Sets) do
		local worn = 0
		for _, id in ipairs(set.pieces) do
			for _, equippedId in pairs(equipped or {}) do
				if equippedId == id then worn += 1 end
			end
		end
		table.insert(out, {
			set      = set,
			worn     = worn,
			total    = #set.pieces,
			complete = worn == #set.pieces,
		})
	end
	return out
end

function GearConfig.Get(gearId)
	for _, g in ipairs(GearConfig.Gear) do
		if g.id == gearId then return g end
	end
	return nil
end

-- Every piece that fits a given armour slot, cheapest first.
function GearConfig.ForSlot(slot)
	local list = {}
	for _, g in ipairs(GearConfig.Gear) do
		if g.slot == slot then table.insert(list, g) end
	end
	table.sort(list, function(a, b) return (a.tier or 0) < (b.tier or 0) end)
	return list
end

-- ── Lift stops ───────────────────────────────────────────────────────────────
GearConfig.LiftStops = {
	{ y = StrataConfig.Surface.PlatformY - 1, name = "Surface", requires = nil },
	{ y = layerTop("Stonebed") - 10,   name = "Stonebed",    layerId = "Stonebed",   requires = nil },
	{ y = layerTop("MagmaVents") - 10, name = "Magma Vents", layerId = "MagmaVents", requires = { heat = 3 } },
}

return GearConfig
