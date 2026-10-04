local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── Dig sites ────────────────────────────────────────────────────────────────
-- The map a contract sends you into.
--
-- The ambient caverns in `Caverns` are weather: one candidate room per cell of
-- the whole world, most of which come to nothing, and none of which know or
-- care that you are on a job. A dig site is the opposite — a small, deliberate
-- layout built for one contract, hung off the station at the bottom of the
-- shaft, and laid out so that walking it is the mission.
--
--   the hub        the landing station, already cut by the bore
--   drifts         sloping tunnels leaving the hub, lit, wide enough to run
--   chambers       big open halls at the end of them, four to seven of them
--
-- Chambers are a tree rather than a star: the first few hang off the hub, the
-- rest hang off those. That is the difference between a map you read and a
-- corridor you walk — there is a near ring you clear quickly and a far one you
-- have to decide whether the clock allows.
--
-- Everything is derived from one number. The same seed on the server that
-- carves the rock, the decorator that furnishes it and the client that draws
-- the map produces the same site, so nothing has to be sent but the seed.
--
-- This module is pure layout and pure queries. It carves nothing, spawns
-- nothing, and holds no state beyond the list of sites currently open.

local DigSite = {}

local CFG = StrataConfig.Site

-- ── Randomness ───────────────────────────────────────────────────────────────
-- A site is generated once, in order, so a plain stream is enough — no spatial
-- hash needed. Lehmer with an xor-shift, same as everywhere else in the
-- project, so two sites one seed apart do not come out as near-copies.

local MOD = 2147483647

local function stream(seed)
	local h = (math.floor(seed) % MOD + 7919) % MOD
	if h == 0 then h = 104729 end

	return function(low, high)
		h = (h * 48271) % MOD
		h = bit32.bxor(h, bit32.rshift(h, 15))
		h = (h * 48271) % MOD
		local r = h / MOD
		if low then return low + r * ((high or 1) - low) end
		return r
	end
end

-- ── Archetypes ───────────────────────────────────────────────────────────────

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

-- The rarest thing this layer can hold, for the chamber at the far end of the
-- map. A site always has one room worth the walk even when nothing asked for it.
local function rarestArchetype(stratum)
	local best, bestWeight = nil, math.huge
	for _, entry in ipairs(stratum.archetypes or {}) do
		if entry.weight < bestWeight then best, bestWeight = entry.id, entry.weight end
	end
	return best
end

-- ── Naming ───────────────────────────────────────────────────────────────────
-- Chambers are named rather than numbered, because "go back to the Chokedamp"
-- is an instruction and "go back to chamber 4" is a chore.

local FIRST = {
	"Low", "Deep", "Long", "Black", "Cold", "Broken", "Old", "Far", "Wet",
	"Blind", "Crooked", "Still", "Hollow", "Quiet", "Rough",
}
local SECOND = {
	"Gallery", "Stope", "Drift", "Hollow", "Chamber", "Rise", "Cut", "Bench",
	"Sump", "Winze", "Crosscut", "Heading",
}

local function chamberName(rand)
	return FIRST[math.floor(rand(1, #FIRST + 0.999))]
		.. " " .. SECOND[math.floor(rand(1, #SECOND + 0.999))]
end

-- ── Layout ───────────────────────────────────────────────────────────────────

-- ── Vertical budget ──────────────────────────────────────────────────────────
-- How much height a layer actually has to give. This is the constraint that
-- shapes everything: the Magma Vents are three hundred studs deep and can hold
-- a cathedral, the Topsoil is fifty and cannot.
--
-- A hall is kept inside its own layer rather than allowed to punch through the
-- one above. Not for tidiness — the ore table, the depth banner and the hazard
-- gates all read the layer off your Y, so a Topsoil hall whose floor is in the
-- Stonebed is a Topsoil contract handing out Stonebed ore in a room the HUD
-- calls by the wrong name.

local SURFACE_CAP = StrataConfig.Mine.SurfaceY
	- StrataConfig.Mine.SurfaceRelief
	- CFG.Roof

local function layerBand(stratum)
	local bottom = StrataConfig.Mine.FloorY
	for i, s in ipairs(StrataConfig.Strata) do
		if s.id == stratum.id and StrataConfig.Strata[i + 1] then
			bottom = StrataConfig.Strata[i + 1].top
		end
	end

	local ceiling = math.min(SURFACE_CAP, stratum.top - CFG.LayerMargin - 2)
	local floor   = bottom + CFG.LayerMargin
	return ceiling, floor, math.max((ceiling - floor) / 2, 4)
end

-- How big a hall this layer can hold, and how flat it has to lie to fit.
-- Size comes from the layer's own cavern band, scaled up because a dig site
-- should plainly be bigger than the rooms you stumble into on your own — then
-- cut back if the layer is too thin to hold it even lying flat.
local function radiusBand(stratum)
	local band = stratum.cavernRadius or
		{ min = StrataConfig.Cavern.MinRadius, max = StrataConfig.Cavern.MaxRadius }

	local _, _, budget = layerBand(stratum)
	local ceiling = math.min(band.max * CFG.RadiusScale.max, CFG.RadiusCap,
		budget * CFG.FlattenMax)

	return math.min(band.min * CFG.RadiusScale.min, ceiling), ceiling
end

-- A hall wider than it is tall, and wider still where the layer is thin. This
-- is the whole reason the Topsoil can have a dig site at all: the same
-- floor plan, pressed down into what the layer will take.
local function flattenFor(radius, stratum)
	local _, _, budget = layerBand(stratum)
	return math.clamp(radius / budget, CFG.Flatten, CFG.FlattenMax)
end

local function verticalOf(radius, flatten)
	return radius / flatten
end

-- Buried, inside its layer, and clear of the boundary wall.
local function fits(centre, radius, flatten, stratum)
	local ceiling, floor = layerBand(stratum)
	local v     = verticalOf(radius, flatten)
	local reach = math.sqrt(centre.X * centre.X + centre.Z * centre.Z) + radius
	return centre.Y + v <= ceiling
		and centre.Y - v >= floor
		and reach <= StrataConfig.Mine.Radius - 40
end

-- A drift is not a straight pipe. It leaves the hub level, sags, and arrives at
-- the floor of the chamber it serves, so you walk down into a hall rather than
-- stepping off a ledge into one.
-- `pinch`, when given as { at, span, radius }, squeezes part of the run down to
-- a throat. Only the radius moves — the path, the sway and the sag are the path,
-- the sway and the sag — and it eases in and out rather than stepping, so the
-- wall closes on you instead of changing gauge like a pipe fitting.
--
-- Returns the points and a parallel list of radii.
local function driftPath(from, to, radius, rand, pinch)
	local function radiusAt(t)
		if not pinch then return radius end
		-- How far off the middle of the throat, in half-spans
		local d = math.abs(t - pinch.at) / (pinch.span * 0.5)
		if d >= 1 then return radius end
		local k = 1 - d * d * (3 - 2 * d)   -- 1 in the throat, 0 at its edges
		return radius + (pinch.radius - radius) * k
	end

	-- Spacing comes from the tunnel's own width, not from a constant. The
	-- tunnel is carved as a run of overlapping balls, so points further apart
	-- than the ball is wide do not make a tunnel — they make a row of sealed
	-- pockets with rock between them.
	local want   = radius * CFG.DriftStep
	local length = (to - from).Magnitude
	local steps  = math.max(math.ceil(length / want), 3)

	local sway   = rand(-1, 1) * CFG.DriftSway
	local across = Vector3.new(-(to.Z - from.Z), 0, to.X - from.X)
	if across.Magnitude > 0.01 then across = across.Unit else across = Vector3.new(1, 0, 0) end

	local function at(t)
		local bend = math.sin(t * math.pi)
		return from:Lerp(to, t)
			+ across * (sway * bend)
			+ Vector3.new(0, -CFG.DriftSag * bend, 0)
	end

	-- The path parameter is carried alongside each point, because once the list
	-- has been subdivided there is no other way to know where on the run a
	-- point sits — and that is what its radius is read from.
	local points, ts = {}, {}
	for i = 0, steps do
		local t = i / steps
		table.insert(points, at(t))
		table.insert(ts, t)
	end

	-- The sway and the sag bow the path, so two points are further apart than
	-- the straight line they were spaced along — most of all near the ends,
	-- where the bend changes fastest. Anything still too far apart gets a point
	-- put between it, measured rather than assumed.
	--
	-- Spacing is judged against the *narrower* of the two balls, so a throat is
	-- packed tightly enough to stay open. Spacing the whole run at the throat's
	-- width instead would double the carve for nothing, since the wide parts
	-- are already overlapping.
	for _ = 1, 6 do
		local tight = true
		local outP  = { points[1] }
		local outT  = { ts[1] }

		for i = 1, #points - 1 do
			local span = math.min(radiusAt(ts[i]), radiusAt(ts[i + 1])) * CFG.DriftStep
			if (points[i + 1] - points[i]).Magnitude > span then
				local mid = (ts[i] + ts[i + 1]) * 0.5
				table.insert(outP, at(mid))
				table.insert(outT, mid)
				tight = false
			end
			table.insert(outP, points[i + 1])
			table.insert(outT, ts[i + 1])
		end

		points, ts = outP, outT
		if tight then break end
	end

	local radii = {}
	for i, t in ipairs(ts) do radii[i] = radiusAt(t) end

	return points, radii
end

-- Builds a whole site. `hubY` is the deck of the landing station; everything is
-- positioned relative to it.
function DigSite.Build(seed, stratum, tierIndex, hubY, wantArchetype)
	local rand = stream(seed)
	local tier = math.clamp(tierIndex or 1, 1, 4)

	local site = {
		seed      = seed,
		layerId   = stratum.id,
		layerName = stratum.name,
		hub       = Vector3.new(0, hubY, 0),
		hubRadius = StrataConfig.Descent.LandingRadius,
		chambers  = {},
		drifts    = {},
	}

	local ceiling, floor = layerBand(stratum)

	local count = CFG.Chambers.Base + math.floor(tier / 2)
	count = math.clamp(count, 4, CFG.Chambers.Max)

	-- The first ring leaves the hub on its own bearing. Spread evenly and then
	-- jittered, so two drifts never leave the station side by side.
	local primaries = math.min(CFG.Primaries, count)
	local turn      = rand() * math.pi * 2
	local driftY    = hubY + CFG.DriftRadius - 2

	-- Attempts, not chambers. A hall that cannot be placed on the bearing it
	-- drew gets another bearing rather than leaving a hole in the map — and
	-- since the vault is the last one placed, giving up would cost the site the
	-- one room that was worth the walk.
	local attempts = 0
	while #site.chambers < count and attempts < count * 4 do
		attempts += 1
		local index = #site.chambers + 1

		local parent, from, angle, distance

		-- The first chamber is the master cavern and it is cut around the
		-- station itself, so you arrive already standing in the biggest space
		-- the layer can hold rather than in a 34-stud hole with three pipes
		-- leaving it.
		local isMaster = #site.chambers == 0

		if isMaster then
			parent, from, angle, distance = 0, Vector3.new(0, driftY, 0), 0, 0

		elseif index <= primaries + 1 then
			-- Hung off the master's rim rather than off the station, and at less
			-- than its radius, so the hall bites into it and opens straight in.
			local m  = site.chambers[1]
			parent   = 1
			from     = m.centre - Vector3.new(0,
				verticalOf(m.radius, m.flatten) - m.driftRadius, 0)
			angle    = turn + (index - 2) / primaries * math.pi * 2
				+ rand(-1, 1) * CFG.BearingJitter
			distance = m.radius * rand(CFG.Master.Ring.min, CFG.Master.Ring.max)

		else
			-- Hung off one of the chambers already placed, which is what turns
			-- a star into a map
			-- From 2: branches hang off the halls, not off the master, or the
			-- far ring collapses back onto the middle of the map
			parent   = math.floor(rand(2, #site.chambers + 0.999))
			local p  = site.chambers[parent]
			-- Drifts leave a hall at its own floor, not through its middle
			from     = p.centre - Vector3.new(0,
				verticalOf(p.radius, p.flatten) - p.driftRadius, 0)
			angle    = math.atan2(p.centre.Z, p.centre.X) + rand(-1, 1) * CFG.BranchSpread
			distance = rand(CFG.FarRing.min, CFG.FarRing.max)
		end

		-- The last chamber is the one worth the walk: bigger, rarer, further.
		-- Where the layer has the height to hold one, it is not merely bigger —
		-- it is the void, carved past the cap and taller than it is wide, so its
		-- roof is hundreds of studs above a lamp that reaches thirty. The
		-- Topsoil can never have one, and a layer ladder whose layers all feel
		-- the same is a list.
		--
		-- It goes through the same fit, crowding and shrink loop as every other
		-- hall rather than getting its own. If the layer or its neighbours will
		-- not take it, it comes back down to a large ordinary vault instead of
		-- failing, and the site is still a site.
		local last   = index == count
		local rMin, rMax = radiusBand(stratum)
		local _, _, budget = layerBand(stratum)

		local isVoid = last
			and budget >= CFG.Void.MinBudget
			and rand(0, 1) < CFG.Void.Chance

		local radius, flatten
		if isMaster then
			flatten = CFG.Master.Flatten

			-- Sized by headroom, not by the layer's middle. The master's floor
			-- *is* the station deck — step off the cage and you are standing on
			-- it — so the room grows upward from hubY and the only question is
			-- how much space there is between the deck and the layer ceiling.
			-- Half of that is the half-height, and radius is half-height times
			-- flatten.
			--
			-- Sized any other way the floor lands wherever the band put it,
			-- which was seventy studs below the deck: you would walk out of the
			-- cage into open air.
			local head = math.max(ceiling - hubY, 24)
			radius = math.min(rMax * CFG.Master.Scale, CFG.Master.Cap,
				head * 0.5 * flatten, StrataConfig.Mine.Radius - 60)

		elseif isVoid then
			flatten = CFG.Void.Flatten
			-- Capped to what the layer will physically hold. A void is the one
			-- room that sets its own proportions instead of deriving them, so it
			-- is also the one that can ask for more height than the band has —
			-- and a half-height over budget puts the floor above the ceiling,
			-- which is a crash in the clamp below rather than an ugly room.
			-- The Stonebed has 143 studs to give and takes a 134 radius; the
			-- Magma Vents have 243 and are not limited by this at all.
			radius = math.min(rand(CFG.Void.Radius.min, CFG.Void.Radius.max),
				budget * flatten)
		elseif last then
			radius  = math.min(rMax * CFG.VaultBoost, CFG.RadiusCap)
			flatten = flattenFor(radius, stratum)
		else
			radius  = rand(rMin, rMax)
			flatten = flattenFor(radius, stratum)
		end

		local v = verticalOf(radius, flatten)

		-- Depth is measured off the layer rather than off the drift line, so a
		-- deep layer gets chambers at genuinely different levels and a thin one
		-- simply puts them all where they fit. Upper half of the band, so the
		-- drifts run down into the workings and there is always headroom above.
		local high = ceiling - v
		local low  = floor + v
		local y    = high - rand() * math.max(high - low, 0) * CFG.BandSpread

		local centre = Vector3.new(
			from.X + math.cos(angle) * distance,
			math.clamp(y, math.min(low, high), high),
			from.Z + math.sin(angle) * distance
		)


		-- A gallery has to be walkable. A branch hall sitting almost on top of
		-- its parent gave a tunnel at seventy degrees, which is a wall with a
		-- floor texture — so the drop is capped against the horizontal run and
		-- the hall is lifted or lowered to suit rather than the tunnel being
		-- bent into a staircase.
		--
		-- Measured to the drift's *mouth*, which is a hall's floor rather than
		-- its middle, or the cap is out by most of the hall's height.
		local run   = math.sqrt((centre.X - from.X) ^ 2 + (centre.Z - from.Z) ^ 2)
		local fall  = run * CFG.MaxGrade
		local mouth = v - math.min(CFG.DriftRadius, v * 0.5)
		centre = Vector3.new(centre.X,
			math.clamp(centre.Y, from.Y - fall + mouth, from.Y + fall + mouth),
			centre.Z)
		centre = Vector3.new(centre.X,
			math.clamp(centre.Y, floor + v, ceiling - v), centre.Z)

		-- The master does not get placed in the band like a hall. Its floor is
		-- the station deck, so its centre is one half-height above it, and that
		-- holds however the shrink below changes the size.
		if isMaster then centre = Vector3.new(0, hubY + v, 0) end

		-- Two constraints that fight each other: halls must not swallow one
		-- another, and none of them may reach the boundary wall. Pushing apart
		-- moves a chamber outward, pulling it off the wall moves it back in, so
		-- neither can be applied once — they are relaxed together, and whatever
		-- is still wrong at the end is fixed by making the hall smaller rather
		-- than by moving it somewhere it does not belong.
		local function crowding()
			local worst, push = 0, Vector3.new()
			for i, other in ipairs(site.chambers) do
				-- The master is the one thing every hall is *meant* to overlap.
				-- Holding halls off it the way they are held off each other
				-- would push them all back outside its rim and quietly rebuild
				-- the ring of rooms-down-corridors this replaced.
				if i > 1 then
					local apart = Vector3.new(centre.X - other.centre.X, 0,
						centre.Z - other.centre.Z)
					local want = (radius + other.radius) * CFG.Separation
					local have = apart.Magnitude
					if have < want then
						local away = have > 0.01 and apart.Unit or Vector3.new(1, 0, 0)
						push  = push + away * (want - have)
						worst = math.max(worst, want - have)
					end
				end
			end
			return worst, push
		end

		for _ = 1, 7 do
			local worst, push = crowding()
			if worst > 0 then centre = centre + push end

			if not fits(centre, radius, flatten, stratum) then
				centre = Vector3.new(
					site.hub.X + (centre.X - site.hub.X) * 0.84,
					math.clamp(centre.Y, floor + v, ceiling - v),
					site.hub.Z + (centre.Z - site.hub.Z) * 0.84)
			elseif worst <= 0 then
				break
			end
		end

		-- Whatever is left: shrink in place. A smaller hall in the right spot
		-- beats a full-sized one merged into its neighbour.
		local tries = 0
		while tries < 8 do
			local worst = crowding()
			if worst <= 0 and fits(centre, radius, flatten, stratum) then break end
			tries  += 1
			radius *= 0.86
			-- The void keeps its proportions as it shrinks. Re-deriving flatten
			-- here would widen it on the first retry and the tall room would
			-- quietly become another wide one.
			if not isVoid and not isMaster then flatten = flattenFor(radius, stratum) end
			v       = verticalOf(radius, flatten)
			centre  = isMaster
				and Vector3.new(0, hubY + v, 0)
				or Vector3.new(centre.X,
					math.clamp(centre.Y, floor + v, ceiling - v), centre.Z)
		end

		-- Shrunk past being a room: drop it and take another bearing. The
		-- attempt is spent either way, and a site with five real halls beats one
		-- with six where the sixth is a pocket.
		if fits(centre, radius, flatten, stratum) and radius >= CFG.MinRadius then
			local archetypeId
			if wantArchetype and index == primaries then
				-- A survey contract names a room type. Putting it on the last
				-- primary means it is findable without being the first thing
				-- you trip over.
				archetypeId = wantArchetype
			elseif last then
				archetypeId = rarestArchetype(stratum) or pickArchetype(stratum, rand())
			else
				archetypeId = pickArchetype(stratum, rand())
			end

			local chamber = {
				index       = index,
				key         = ("site%d_%d"):format(seed % 100000, index),
				parent      = parent,
				centre      = centre,
				radius      = radius,
				flatten     = flatten,
				-- Narrow enough not to be taller than the hall it serves, which in
				-- a thin layer it otherwise would be
				driftRadius = math.min(CFG.DriftRadius, v * 0.5),
				archetypeId = archetypeId,
				archetype   = StrataConfig.GetArchetype(archetypeId),
				stratum     = stratum,
				name        = chamberName(rand),
				role        = last and "vault" or "cache",
				-- True only while the room is still tall enough to deserve the
				-- name: the crowding shrink runs on a void like any other hall
				-- and can hand back something a lamp would light end to end.
				--
				-- Nothing has to be done to keep the roof dark. Lamps are strung
				-- down galleries and props sit on floors, so no light in the
				-- game is ever placed near a ceiling — the height does the work
				-- on its own. This is here for the map and the banner to read.
				void        = (isVoid and v * 2 >= CFG.Void.KeepAbove) or nil,
				-- The enclosing cavern. The map draws it as a boundary rather
				-- than a room, because a filled circle that contains every other
				-- circle is not information.
				master      = isMaster or nil,
				-- Blobs, so a hall is a lumpy open space rather than a ball.
				-- Spread wide and kept shallow, which is what makes it read as
				-- a cavern and not a bubble.
				blobs       = {},
				pillars     = {},
				shelves     = {},
				rough       = {},
			}

			-- Blobs are true spheres, not squashed ones, because the only tool
			-- for carving terrain in bulk is a ball. A flat hall is therefore
			-- made of many small spheres laid out across a disc rather than one
			-- big squashed one — which is also why the query below can be a
			-- plain distance test and agree with the rock exactly.
			--
			-- Ring spacing is derived from the sphere size rather than picked,
			-- so coverage and connectivity are guaranteed instead of hoped for:
			-- the Topsoil ends up with two dozen small spheres and the Magma
			-- Vents with four big ones, from the same four lines.
			local br    = v * rand(0.82, 1.0)
			local spread = math.max(radius - br, 0)
			local rings  = math.max(math.ceil(spread / (br * 1.15)), 1)

			table.insert(chamber.blobs, {
				offset = Vector3.new(0, rand(-0.05, 0.05) * v, 0),
				radius = br * rand(1.0, 1.12),
			})

			for ring = 1, rings do
				local rr    = spread * ring / rings
				local count = math.max(3, math.ceil(rr * 2 * math.pi / (br * 1.25)))
				local twist = rand() * math.pi * 2

				for k = 1, count do
					local a = twist + (k - 1) / count * math.pi * 2
					local d = rr * rand(0.9, 1.06)
					table.insert(chamber.blobs, {
						offset = Vector3.new(
							math.cos(a) * d,
							rand(-0.24, 0.10) * v,
							math.sin(a) * d),
						radius = br * rand(0.84, 1.04),
					})
				end
			end

			-- Everything from here hangs off a sphere that is already part of
			-- the hall, pushed out by less than the two radii together. Placing
			-- alcoves and pits at an absolute distance instead left some of
			-- them floating in the rock as sealed pockets — visible on the map
			-- and impossible to reach.
			local core = #chamber.blobs

			local function hangOff(direction, size, reach)
				local host = chamber.blobs[math.floor(rand(1, core + 0.999))]
				return {
					offset = host.offset + direction * ((host.radius + size) * reach),
					radius = size,
				}
			end

			-- Alcoves: pockets bitten out past the wall, at every height. This
			-- is the perimeter detail — without it a hall is a clean sphere and
			-- reads as a room, and there is nowhere dark to throw a flare.
			local alcoves = math.floor(rand(CFG.Alcoves.min, CFG.Alcoves.max + 0.999))
			for _ = 1, alcoves do
				local a   = rand() * math.pi * 2
				local dir = Vector3.new(math.cos(a), rand(-0.45, 0.4), math.sin(a)).Unit
				table.insert(chamber.blobs, hangOff(dir,
					radius * rand(CFG.AlcoveSize.min, CFG.AlcoveSize.max),
					rand(0.72, 0.92)))
			end

			-- Pits: holes in the floor deep enough that you cannot see the
			-- bottom from the rim. Carved as blobs so they are lined and
			-- hollowed by the same two passes as everything else, and so the
			-- ore grid knows they are open air.
			local pits = math.floor(rand(CFG.Pits.min, CFG.Pits.max + 0.999))
			for _ = 1, pits do
				local size = radius * rand(CFG.PitSize.min, CFG.PitSize.max)
				local deep = hangOff(Vector3.new(0, -1, 0), size,
					rand(CFG.PitDepth.min, CFG.PitDepth.max))
				table.insert(chamber.blobs, deep)

				-- And a smaller one under that half the time, so the deepest
				-- are more than one sphere down and genuinely dark at the bottom
				if rand() < 0.5 then
					table.insert(chamber.blobs, {
						offset = deep.offset - Vector3.new(0, size * 1.2, 0),
						radius = size * rand(0.62, 0.86),
					})
				end
			end

			-- Pillars are the opposite: solid rock left standing floor to
			-- ceiling, put back after the air is carved. The single biggest
			-- thing for scale — you cannot tell how big a space is until
			-- something inside it blocks your view of the far side.
			local pillars = math.floor(rand(CFG.Pillars.min, CFG.Pillars.max + 0.999))
			for _ = 1, pillars do
				local a = rand() * math.pi * 2
				local d = radius * rand(0.28, 0.82)
				table.insert(chamber.pillars, {
					offset = Vector3.new(math.cos(a) * d, 0, math.sin(a) * d),
					radius = radius * rand(CFG.PillarWidth.min, CFG.PillarWidth.max),
					height = v * 2 + 14,
				})
			end


			-- Grain. The hall is built from spheres and a sphere has no
			-- features, which is why a two-hundred-stud cavern still photographs
			-- as a smooth brown dome: the pillars and terraces give the room a
			-- shape, but nothing gives the rock a surface.
			--
			-- Each of these is a small sphere sitting half-buried in a wall.
			-- About half put rock back and bulge out of it; the rest take rock
			-- away and bite into it. Half-buried is the whole trick — centred on
			-- the surface rather than outside it, so a bump is part of the wall
			-- instead of a ball stuck to one.
			--
			-- Taken off the blobs, so alcoves and pit shafts get their own grain
			-- for free rather than staying the one smooth part of the room.
			local grains = math.floor(rand(CFG.Rough.Count.min, CFG.Rough.Count.max + 0.999))
			for _ = 1, grains do
				local host = chamber.blobs[math.floor(rand(1, #chamber.blobs + 0.999))]
				local a    = rand() * math.pi * 2
				local lift = rand(-1, 1)
				local flat = math.sqrt(math.max(1 - lift * lift, 0))
				local dir  = Vector3.new(math.cos(a) * flat, lift, math.sin(a) * flat)

				table.insert(chamber.rough, {
					offset = host.offset + dir * host.radius,
					radius = math.min(
						host.radius * rand(CFG.Rough.Size.min, CFG.Rough.Size.max),
						CFG.Rough.Max),
					solid  = rand(0, 1) < CFG.Rough.Solid,
				})
			end

			-- The furthest any blob reaches from the chamber centre, so the
			-- depth test can reject a distant point with one comparison
			local reach = 0
			for _, blob in ipairs(chamber.blobs) do
				reach = math.max(reach, blob.offset.Magnitude + blob.radius)
			end
			chamber.blobReach = reach - chamber.radius
			-- Terraces. The references are all stepped floors rather than flat
			-- ones, and a slab dropped back in after the air is cut is the
			-- cheapest possible way to get them.
			local shelves = math.floor(rand(CFG.Shelves.min, CFG.Shelves.max + 0.999))
			for _ = 1, shelves do
				table.insert(chamber.shelves, {
					offset = Vector3.new(
						rand(-1, 1) * radius * 0.55,
						-- Measured against the hall's height, not its width. A
						-- terrace placed by radius in a hall twice as wide as it
						-- is tall ends up under the floor.
						rand(-0.78, -0.05) * v,
						rand(-1, 1) * radius * 0.55),
					size = Vector3.new(
						radius * rand(0.45, 1.05),
						rand(4, 11),
						radius * rand(0.45, 1.05)),
					spin = rand() * math.pi,
				})
			end

			table.insert(site.chambers, chamber)

			-- The drift arrives at the hall's floor, not above it. Arriving on
			-- a ledge twenty studs up looks better for about one second and
			-- then you are in a room you cannot climb out of.
			local mouth = centre - Vector3.new(0, v - chamber.driftRadius, 0)

			-- Roughly half of the galleries pinch somewhere along their run. Not
			-- all of them, because a throat is only a throat if the gallery
			-- before it was wide.
			local pinch
			if rand(0, 1) < CFG.Choke.Chance then
				pinch = {
					at     = rand(CFG.Choke.At.min, CFG.Choke.At.max),
					span   = CFG.Choke.Span,
					-- min, so a "pinch" is never wider than the gallery it is in.
					-- A thin layer already narrows driftRadius on its own.
					radius = math.min(chamber.driftRadius,
						rand(CFG.Choke.Radius.min, CFG.Choke.Radius.max)),
				}
			end

			local points, radii = driftPath(from, mouth, chamber.driftRadius, rand, pinch)
			table.insert(site.drifts, {
				from   = parent,
				to     = chamber.index,
				a      = from,
				b      = mouth,
				radius = chamber.driftRadius,
				points = points,
				radii  = radii,
				choke  = pinch and pinch.radius or nil,
			})
		end
	end

	return site
end

-- ── Registry ─────────────────────────────────────────────────────────────────
-- Which sites are open right now. The node grid asks this so the rock around a
-- chamber is worth mining; the generator asks it so a chunk written after the
-- site was cut does not fill it back in.

local open = {}

function DigSite.Register(site)
	open[site] = true
end

function DigSite.Unregister(site)
	open[site] = nil
end

function DigSite.Active()
	local list = {}
	for site in pairs(open) do table.insert(list, site) end
	return list
end

-- ── Queries ──────────────────────────────────────────────────────────────────
-- Cheap enough to call per ore cell: a handful of chambers, each rejected by a
-- single squared distance.

-- How far inside the hall a point is, in studs; negative is rock. Plain
-- spheres, because plain spheres are what was carved.
--
-- The early-out matters: this is called once per candidate ore cell, and all
-- but a handful of them are nowhere near any chamber.
local function blobDepth(chamber, x, y, z)
	local dx = x - chamber.centre.X
	local dy = y - chamber.centre.Y
	local dz = z - chamber.centre.Z
	local reach = chamber.radius + chamber.blobReach
	if dx * dx + dy * dy + dz * dz > reach * reach then return -math.huge end

	local best = -math.huge
	for _, blob in ipairs(chamber.blobs) do
		local c  = chamber.centre + blob.offset
		local ox, oy, oz = x - c.X, y - c.Y, z - c.Z
		local at = blob.radius - math.sqrt(ox * ox + oy * oy + oz * oz)
		if at > best then best = at end
	end
	return best
end

local function driftDepth(drift, x, y, z)
	local p    = Vector3.new(x, y, z)
	local best = -math.huge

	for i = 1, #drift.points - 1 do
		local a, b = drift.points[i], drift.points[i + 1]
		local ab   = b - a
		local len2 = ab:Dot(ab)
		if len2 > 0 then
			local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
			local d = drift.radius - (p - (a + ab * t)).Magnitude
			if d > best then best = d end
		end
	end
	return best
end

-- Is this point inside any open site? Used to keep ore out of thin air.
function DigSite.Hollow(pos)
	for site in pairs(open) do
		for _, chamber in ipairs(site.chambers) do
			if blobDepth(chamber, pos.X, pos.Y, pos.Z) > 0 then return true, chamber end
		end
		for _, drift in ipairs(site.drifts) do
			if driftDepth(drift, pos.X, pos.Y, pos.Z) > 0 then
				return true, site.chambers[drift.to]
			end
		end
	end
	return false, nil
end

-- Solid rock close enough to a chamber to take its character — the band that
-- carries the room's own ore. Same contract as Caverns.Halo.
function DigSite.Halo(pos, depth)
	local limit = depth or StrataConfig.Cavern.HaloDepth
	for site in pairs(open) do
		for _, chamber in ipairs(site.chambers) do
			local d = blobDepth(chamber, pos.X, pos.Y, pos.Z)
			if d <= 0 and d > -limit then return chamber, -d end
		end
	end
	return nil, nil
end

-- The chamber a point is standing in, for "you have arrived" and for the map.
function DigSite.ChamberAt(site, pos)
	if not site then return nil end
	for _, chamber in ipairs(site.chambers) do
		if blobDepth(chamber, pos.X, pos.Y, pos.Z) > -6 then return chamber end
	end
	return nil
end

-- What the client needs to draw the map. Deliberately flat and small: this goes
-- over the wire once per run.
function DigSite.Summary(site)
	local out = {
		layerName = site.layerName,
		hubY      = site.hub.Y,
		chambers  = {},
		drifts    = {},
	}

	for _, c in ipairs(site.chambers) do
		table.insert(out.chambers, {
			index  = c.index,
			name   = c.name,
			role   = c.role,
			x      = c.centre.X,
			y      = c.centre.Y,
			z      = c.centre.Z,
			radius = c.radius,
			colour = c.archetype and c.archetype.light or nil,
			arch   = c.archetype and c.archetype.name or nil,
		})
	end

	for _, d in ipairs(site.drifts) do
		table.insert(out.drifts, {
			ax = d.a.X, az = d.a.Z,
			bx = d.b.X, bz = d.b.Z,
			to = d.to,
		})
	end

	return out
end

return DigSite
