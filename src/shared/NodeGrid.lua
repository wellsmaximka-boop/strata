-- ── NodeGrid ─────────────────────────────────────────────────────────────────
-- Ore nodes are derived, not stored. Every candidate cell in the mine hashes
-- deterministically to "is there ore here, and what is it" — so the server
-- keeps no table of nodes, only a set of the cells that have been mined out.
--
-- Same hash on the server every time means the world is consistent for the
-- life of the server without any of it living in memory.
--
-- Caverns change what a cell is worth. Rock within reach of a room carries more
-- ore, better ore, and the one ore that room is the only place to find — which
-- is the whole reason to go looking for rooms instead of digging in a line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Caverns      = require(ReplicatedStorage:WaitForChild("Caverns"))
local DigSite      = require(ReplicatedStorage:WaitForChild("DigSite"))

local NodeGrid = {}

local CELL = StrataConfig.Nodes.CellSize

-- ── Hashing ──────────────────────────────────────────────────────────────────
-- Two independent streams per cell: one decides existence, one picks the ore.

-- Multipliers are kept small enough that every intermediate product stays
-- under 2^53, so the arithmetic is exact and the world is reproducible.
--
-- The xor-shifts matter. A pure multiply-and-add chain is affine in its input,
-- which means two salts always differ by the same constant: the stream that
-- decides "is there ore here" and the stream that decides "which ore" would
-- move in lockstep, and the answer to the second would be decided by the first.
-- The shifts break that, so each salt is genuinely its own stream.
local MOD = 2147483647

local function hash01(cx, cy, cz, seed, salt)
	local h = (cx * 374761393
		+ cy * 668265263
		+ cz * 1274126177
		+ seed * 104729
		+ salt * 6151) % MOD
	h = (h * 48271) % MOD
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 48271) % MOD
	h = bit32.bxor(h, bit32.rshift(h, 17))
	h = (h * 48271) % MOD
	return h / MOD
end

-- ── Cell <-> world ───────────────────────────────────────────────────────────

function NodeGrid.WorldToCell(pos)
	return math.floor(pos.X / CELL),
	       math.floor(pos.Y / CELL),
	       math.floor(pos.Z / CELL)
end

function NodeGrid.CellKey(cx, cy, cz)
	return cx .. ":" .. cy .. ":" .. cz
end

-- Deterministic position inside the cell, so nodes are not on a visible lattice.
function NodeGrid.CellPosition(cx, cy, cz, seed)
	local j = StrataConfig.Nodes.Jitter
	local jx = (hash01(cx, cy, cz, seed, 11) - 0.5) * 2 * j
	local jy = (hash01(cx, cy, cz, seed, 12) - 0.5) * 2 * j
	local jz = (hash01(cx, cy, cz, seed, 13) - 0.5) * 2 * j
	return Vector3.new(
		(cx + 0.5) * CELL + jx,
		(cy + 0.5) * CELL + jy,
		(cz + 0.5) * CELL + jz
	)
end

-- ── Node lookup ──────────────────────────────────────────────────────────────
-- `field` is a Caverns field covering the area being asked about. Passing one
-- in matters: a query over a few hundred cells would otherwise rebuild the same
-- list of rooms for every one of them.
--
-- Returns nil, or { ore = <ore config>, position = Vector3, key = string }.
function NodeGrid.NodeAt(cx, cy, cz, seed, field)
	local pos = NodeGrid.CellPosition(cx, cy, cz, seed)

	-- Ore has to start buried. Exposure asks "is this voxel air?", and open sky
	-- answers yes — so anything above the real rock line would spawn instantly,
	-- floating over the camp. Bound by the generated surface, not by Y=0 (which
	-- excluded the whole Topsoil layer) and not by the region ceiling (which
	-- put crystals in the air).
	local mine = StrataConfig.Mine
	if pos.Y < mine.FloorY then return nil end

	local rock = StrataConfig.SurfaceHeight(pos.X, pos.Z, seed)
	if pos.Y > rock - 4 then return nil end

	-- And it must be inside solid rock, not inside a hollow — otherwise it has
	-- nothing holding it up and floats in the open.
	if StrataConfig.IsCave(pos.X, pos.Y, pos.Z, seed) then return nil end
	-- Inside the round footprint, and clear of the sealed rim at its edge
	if pos.X * pos.X + pos.Z * pos.Z > (mine.Radius - 8) ^ 2 then return nil end

	field = field or Caverns.Field(pos, pos, seed)
	if Caverns.Hollow(field, pos.X, pos.Y, pos.Z) then return nil end

	-- A dig site is carved into the rock after the world was generated, so the
	-- ambient cavern field knows nothing about it. Ore inside one would be ore
	-- hanging in mid-air in the middle of a hall.
	if DigSite.Hollow(pos) then return nil end

	local stratum = StrataConfig.GetStratum(pos.Y)
	local density = stratum.nodeDensity

	-- The walls of a room are richer than the rock between rooms, and they are
	-- the only place that room's own ore turns up.
	local room = Caverns.Halo(field, pos.X, pos.Y, pos.Z)
	local archetypeId = nil
	if room and room.archetype then
		density    *= room.archetype.oreBonus or 1
		archetypeId = room.archetypeId
	end


	-- And the walls of a dig site are the richest rock in the mine, which is
	-- the whole argument for taking a contract over digging a hole of your own.
	if not room then
		local chamber = DigSite.Halo(pos)
		if chamber then
			density *= StrataConfig.Site.OreBonus
			if chamber.archetype then
				density    *= chamber.archetype.oreBonus or 1
				archetypeId = chamber.archetypeId
			end
		end
	end
	if hash01(cx, cy, cz, seed, 1) > math.min(density, 0.85) then return nil end

	-- Rolled against the stratum, so deeper rock genuinely carries better ore
	local ore = StrataConfig.RollOre(hash01(cx, cy, cz, seed, 2), stratum, archetypeId)
	return {
		ore       = ore,
		position  = pos,
		key       = NodeGrid.CellKey(cx, cy, cz),
		cell      = { cx, cy, cz },
		room      = room,
		archetype = archetypeId,
	}
end

-- ── Range queries ────────────────────────────────────────────────────────────

-- The cavern field covering a sphere, built once and handed to every lookup
-- inside it.
function NodeGrid.FieldFor(origin, radius, seed)
	local pad = Vector3.new(radius, radius, radius)
	return Caverns.Field(origin - pad, origin + pad, seed)
end

-- Iterates every node whose cell centre falls within `radius` of `origin`.
-- `fn(node)` may return true to stop early.
function NodeGrid.ForEachNear(origin, radius, seed, fn)
	local minCx = math.floor((origin.X - radius) / CELL)
	local maxCx = math.floor((origin.X + radius) / CELL)
	local minCy = math.floor((origin.Y - radius) / CELL)
	local maxCy = math.floor((origin.Y + radius) / CELL)
	local minCz = math.floor((origin.Z - radius) / CELL)
	local maxCz = math.floor((origin.Z + radius) / CELL)

	local field = NodeGrid.FieldFor(origin, radius, seed)

	local r2 = radius * radius
	for cx = minCx, maxCx do
		for cy = minCy, maxCy do
			for cz = minCz, maxCz do
				local node = NodeGrid.NodeAt(cx, cy, cz, seed, field)
				if node and (node.position - origin).Magnitude ^ 2 <= r2 then
					if fn(node) then return end
				end
			end
		end
	end
end

return NodeGrid
