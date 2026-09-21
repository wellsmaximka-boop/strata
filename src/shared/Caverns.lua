-- ── Caverns ──────────────────────────────────────────────────────────────────
-- Rooms in the rock, derived from the seed the same way ore nodes are: nothing
-- is stored, and the generator, the node grid, the decorator and the client all
-- work it out independently and agree.
--
-- One candidate room per cell of the world. Most cells come to nothing — that
-- is what makes the ones that do worth finding. A room that exists gets a
-- radius, an archetype, and tunnels to whichever neighbouring rooms exist, so
-- what you break into is a system you can walk through rather than a bubble.
--
-- Everything here answers one of two questions: "is this point open air?" and
-- "which room is this point in or near?" — the first for carving, the second
-- for what the place looks like and what its rock is worth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local Caverns = {}

local CFG  = StrataConfig.Cavern
local CELL = CFG.CellSize

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

-- The furthest a room can reach from its own cell centre, which is what every
-- range query has to be padded by.
local function maxReach()
	local biggest = CFG.MaxRadius

	-- Layers may set their own size band, and one of them setting a bigger max
	-- than the global default must not leave range queries reaching too short.
	for _, stratum in ipairs(StrataConfig.Strata) do
		if stratum.cavernRadius then
			biggest = math.max(biggest, stratum.cavernRadius.max)
		end
	end

	for _, arch in pairs(StrataConfig.Archetypes) do
		biggest = math.max(biggest, biggest * (arch.sizeBoost or 1))
	end
	return biggest * (1 + CFG.Wobble) + CELL * 0.32
end

local MAX_REACH = maxReach()
Caverns.MaxReach = MAX_REACH

-- ── Sites ────────────────────────────────────────────────────────────────────

local function pickArchetype(stratum, roll)
	local list = stratum and stratum.archetypes
	if not list or #list == 0 then return nil end

	local total = 0
	for _, entry in ipairs(list) do total += entry.weight end

	local target, run = roll * total, 0
	for _, entry in ipairs(list) do
		run += entry.weight
		if target <= run then return entry.id end
	end
	return list[1].id
end

-- The whole mine is only a few hundred cells, and neighbouring chunks ask about
-- the same ones over and over, so every answer is kept. This is what keeps the
-- cost of a chunk in the noise loop rather than in re-deriving rooms.
local memo, memoSeed = {}, nil

local function siteAt(cx, cy, cz, seed)
	if seed ~= memoSeed then
		memo, memoSeed = {}, seed
	end

	local key = cx .. ":" .. cy .. ":" .. cz
	local hit = memo[key]
	if hit ~= nil then
		return hit or nil
	end

	local jx = (hash01(cx, cy, cz, seed, 21) - 0.5) * 0.64 * CELL
	local jy = (hash01(cx, cy, cz, seed, 22) - 0.5) * 0.64 * CELL
	local jz = (hash01(cx, cy, cz, seed, 23) - 0.5) * 0.64 * CELL

	local centre = Vector3.new(
		(cx + 0.5) * CELL + jx,
		(cy + 0.5) * CELL + jy,
		(cz + 0.5) * CELL + jz
	)

	local room = nil
	local mine = StrataConfig.Mine

	if centre.Y <= mine.CeilingY and centre.Y >= mine.FloorY then
		local stratum = StrataConfig.GetStratum(centre.Y)
		local chance  = stratum.cavernChance or 0

		if chance > 0 and hash01(cx, cy, cz, seed, 24) <= chance then
			local archetypeId = pickArchetype(stratum, hash01(cx, cy, cz, seed, 25))
			local archetype   = StrataConfig.GetArchetype(archetypeId)

			-- Each layer sets its own room size: a thin layer near the surface
			-- cannot hold a room the size of one in the deep.
			local band   = stratum.cavernRadius
			local rMin   = band and band.min or CFG.MinRadius
			local rMax   = band and band.max or CFG.MaxRadius
			local radius = rMin + hash01(cx, cy, cz, seed, 26) * (rMax - rMin)
			if archetype and archetype.sizeBoost then radius *= archetype.sizeBoost end

			-- A room has to stay buried. Breaching the surface would leave a
			-- crater in the camp, and breaching the rim would open a hole in the
			-- boundary wall.
			local ceiling = StrataConfig.SurfaceHeight(centre.X, centre.Z, seed)
			local reach   = math.sqrt(centre.X * centre.X + centre.Z * centre.Z) + radius

			if centre.Y + radius <= ceiling - 12
				and centre.Y - radius >= mine.FloorY + 14
				and reach <= mine.Radius - 20 then

				room = {
					key         = key,
					cell        = { cx, cy, cz },
					centre      = centre,
					radius      = radius,
					archetypeId = archetypeId,
					archetype   = archetype,
					stratum     = stratum,
					-- The widest the wall can wander, worked out once so the
					-- voxel loop can reject distant points without touching noise
					slack       = radius * CFG.Wobble,
					-- Its own patch of noise, so two rooms of the same size are
					-- not the same shape
					noiseOffset = hash01(cx, cy, cz, seed, 27) * 512,
				}
			end
		end
	end

	memo[key] = room or false
	return room
end

-- The room in one cell, or nil. A pure function of the cell and the seed.
function Caverns.At(cx, cy, cz, seed)
	return siteAt(cx, cy, cz, seed)
end

-- ── Shape ────────────────────────────────────────────────────────────────────

-- How far inside the room a point is, in studs. Positive is open air, negative
-- is rock, and the magnitude either side is close enough to a real distance to
-- use for the ore halo and for lining the walls.
--
-- The noise call is the expensive part of generating anything, and nearly every
-- voxel asked about is nowhere near a room. Outside the band the wall can
-- possibly wander into, the answer cannot change, so it is answered by distance
-- alone and the noise is never touched.
function Caverns.RoomDepth(room, x, y, z)
	local c  = room.centre
	local dx = x - c.X
	local dy = (y - c.Y) * CFG.Flatten
	local dz = z - c.Z
	local d  = math.sqrt(dx * dx + dy * dy + dz * dz)

	local slack = room.slack
	if d > room.radius + slack then return room.radius + slack - d end
	if d < room.radius - slack then return room.radius - slack - d end

	local s   = CFG.WobbleScale
	local o   = room.noiseOffset
	local wob = math.noise((x + o) / s, (y + o) / s, (z + o) / s) * room.radius * CFG.Wobble

	return room.radius + wob - d
end

local function segmentDepth(tunnel, x, y, z)
	local a, b = tunnel.a, tunnel.b
	local ab   = b - a
	local len2 = ab:Dot(ab)
	if len2 <= 0 then return -math.huge end

	local p = Vector3.new(x, y, z)
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	local d = (p - (a + ab * t)).Magnitude

	local wob = CFG.TunnelWobble
	if d > tunnel.radius + wob then return tunnel.radius + wob - d end
	if d < tunnel.radius - wob then return tunnel.radius - wob - d end

	local s = CFG.WobbleScale
	return tunnel.radius + math.noise(x / s, (y + tunnel.offset) / s, z / s) * wob - d
end

-- ── Fields ───────────────────────────────────────────────────────────────────
-- Every room and tunnel that could reach into a box, gathered once so a voxel
-- loop tests a handful of things instead of re-deriving the world each time.
--
-- Gathering is deliberately narrow. A cell is visited if a room in it could
-- possibly reach the box, but it is only kept if it actually does — so a chunk
-- usually carries one or two rooms rather than every room in the district.

-- Tunnels run to the neighbour one cell along, so an origin cell up to one cell
-- outside the box can still reach into it.
local PAD = MAX_REACH + CELL

local NEIGHBOURS = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

local function sphereHitsBox(centre, radius, minV, maxV)
	local dx = math.max(minV.X - centre.X, 0, centre.X - maxV.X)
	local dy = math.max(minV.Y - centre.Y, 0, centre.Y - maxV.Y)
	local dz = math.max(minV.Z - centre.Z, 0, centre.Z - maxV.Z)
	return dx * dx + dy * dy + dz * dz <= radius * radius
end

local function segmentHitsBox(a, b, pad, minV, maxV)
	return math.min(a.X, b.X) - pad <= maxV.X and math.max(a.X, b.X) + pad >= minV.X
	   and math.min(a.Y, b.Y) - pad <= maxV.Y and math.max(a.Y, b.Y) + pad >= minV.Y
	   and math.min(a.Z, b.Z) - pad <= maxV.Z and math.max(a.Z, b.Z) + pad >= minV.Z
end

function Caverns.Field(minV, maxV, seed)
	local minCx = math.floor((minV.X - PAD) / CELL)
	local maxCx = math.floor((maxV.X + PAD) / CELL)
	local minCy = math.floor((minV.Y - PAD) / CELL)
	local maxCy = math.floor((maxV.Y + PAD) / CELL)
	local minCz = math.floor((minV.Z - PAD) / CELL)
	local maxCz = math.floor((maxV.Z + PAD) / CELL)

	local rooms, tunnels = {}, {}

	-- Rooms are kept if their wall, or the rich band of rock just outside it,
	-- reaches the box
	local halo = CFG.HaloDepth

	for cx = minCx, maxCx do
		for cy = minCy, maxCy do
			for cz = minCz, maxCz do
				local room = siteAt(cx, cy, cz, seed)
				if room then
					if sphereHitsBox(room.centre, room.radius + room.slack + halo, minV, maxV) then
						table.insert(rooms, room)
					end

					-- Joined only forwards, so each pair of rooms is considered
					-- once no matter which cell the query started from.
					for i, step in ipairs(NEIGHBOURS) do
						local other = siteAt(cx + step[1], cy + step[2], cz + step[3], seed)
						if other then
							local radius = CFG.TunnelRadius
								* (0.8 + hash01(cx, cy, cz, seed, 30 + i) * 0.7)
							if segmentHitsBox(room.centre, other.centre,
								radius + CFG.TunnelWobble, minV, maxV) then
								table.insert(tunnels, {
									a      = room.centre,
									b      = other.centre,
									radius = radius,
									offset = hash01(cx, cy, cz, seed, 40 + i) * 512,
									room   = room,
								})
							end
						end
					end
				end
			end
		end
	end

	return { rooms = rooms, tunnels = tunnels, seed = seed }
end

-- Is this point open air, and if so which room does it belong to? The room is
-- what a tunnel is lined and lit by, so a passage reads as leading somewhere.
function Caverns.Hollow(field, x, y, z)
	for _, room in ipairs(field.rooms) do
		if Caverns.RoomDepth(room, x, y, z) > 0 then return true, room end
	end
	for _, tunnel in ipairs(field.tunnels) do
		if segmentDepth(tunnel, x, y, z) > 0 then return true, tunnel.room end
	end
	return false, nil
end

-- Solid rock close enough to a room to take its character: the band the walls
-- are lined from, and the band where the ore is worth the walk.
-- Returns the room and how deep into the rock the point is, or nil.
function Caverns.Halo(field, x, y, z, depth)
	local limit = depth or CFG.HaloDepth
	local best, bestDepth = nil, -math.huge

	for _, room in ipairs(field.rooms) do
		local d = Caverns.RoomDepth(room, x, y, z)
		if d <= 0 and d > -limit and d > bestDepth then
			best, bestDepth = room, d
		end
	end

	if best then return best, -bestDepth end
	return nil, nil
end

-- ── Single-point queries ─────────────────────────────────────────────────────
-- For everything that asks about one place rather than a whole chunk: which
-- room a player is standing in, whether one ore node sits in open air.

local function pointField(pos, seed)
	return Caverns.Field(pos, pos, seed)
end

-- The room a point is inside, or nil. This is the one the client names on
-- screen when you walk in.
function Caverns.RoomAt(pos, seed)
	local field = pointField(pos, seed)
	local _, room = Caverns.Hollow(field, pos.X, pos.Y, pos.Z)
	return room
end

function Caverns.IsHollowAt(pos, seed)
	local field = pointField(pos, seed)
	return (Caverns.Hollow(field, pos.X, pos.Y, pos.Z))
end

return Caverns
