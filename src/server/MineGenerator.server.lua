local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Caverns      = require(ReplicatedStorage:WaitForChild("Caverns"))

-- ── Mine generator ───────────────────────────────────────────────────────────
-- The mine is far too big to write in one go, so it is written in two passes.
--
--   The shell — everything from the sky down to a little below the surface — is
--   written at startup. It is what you see from the camp, so it has to be there
--   before anyone is looking.
--
--   The deep rock is written in chunks as players get near it. This is the part
--   that lets the claim be as large as it is: server start does not grow when
--   the map does, only the area people are actually standing in gets built.
--
-- Both passes use the same voxel function, so there is no seam between them.
-- Chunks are recorded once written and never written again — otherwise a
-- streaming pass would refill the tunnel somebody just dug.

local terrain = workspace.Terrain
local mine    = StrataConfig.Mine
local RES     = 4
local CHUNK   = mine.ChunkStuds

-- Round footprint: anything outside this is left as open air, so the rock
-- meets the boundary wall exactly instead of stopping short of it.
local RADIUS_SQ = mine.Radius * mine.Radius

-- Server seed: one number that makes this server's world its own.
local SEED = math.random(1, 1e6)
StrataConfig.Caves.Seed = SEED
_G.StrataSeed = SEED

-- Chunks at or above this one belong to the shell and are written at startup.
local SHELL_MIN_CY = math.floor(-mine.ShellDepth / CHUNK)

-- ── The bore ─────────────────────────────────────────────────────────────────
-- A shaft straight down the middle of the claim, and a station cut into the
-- rock at each layer. It is one extra condition in the voxel function, which is
-- why it can be a real hole in real terrain rather than a set dressed around a
-- teleport.
--
-- How deep it goes is not fixed. DescentService pushes `_G.StrataBoreFloor`
-- down as the crew discovers layers, and chunks written after that carve
-- themselves to match; the ones already written get opened directly. Look down
-- the shaft from the camp and its bottom is the bottom of what anybody here has
-- actually found.

local DESC     = StrataConfig.Descent
local BORE_R2  = DESC.BoreRadius * DESC.BoreRadius
local LAND_R2  = DESC.LandingRadius * DESC.LandingRadius

local LANDINGS = {}
for _, s in ipairs(StrataConfig.Strata) do
	table.insert(LANDINGS, StrataConfig.LandingY(s))
end

-- Starts at the first station and no further. Nobody has been anywhere yet.
_G.StrataBoreFloor = LANDINGS[1] - DESC.Overrun

-- How close a span comes to the axis. Used to skip the bore test entirely for
-- the overwhelming majority of chunks, which are nowhere near the middle.
local function axisGap(a, b)
	if a <= 0 and b >= 0 then return 0 end
	return math.min(math.abs(a), math.abs(b))
end

local function inShaft(wx, wy, wz)
	local floor = _G.StrataBoreFloor or 0
	if wy < floor then return false end

	local r2 = wx * wx + wz * wz
	if r2 <= BORE_R2 then return true end
	if r2 > LAND_R2 then return false end

	-- A station: wider than the bore, and only where the bore has got to
	for _, ly in ipairs(LANDINGS) do
		if ly >= floor and math.abs(wy - ly) <= DESC.LandingHalf then
			-- Eased at the roof and floor, so it reads as a chamber cut into the
			-- rock rather than a tin punched through it
			local t     = math.abs(wy - ly) / DESC.LandingHalf
			local reach = BORE_R2 + (LAND_R2 - BORE_R2) * (1 - t * t)
			return r2 <= reach
		end
	end
	return false
end

-- How far into the rock a room lines its own walls
local LINING_DEPTH = 5

-- ── Noise helpers ────────────────────────────────────────────────────────────

-- Shared with NodeGrid so ore can never be placed above the rock line
local function surfaceHeight(wx, wz)
	return StrataConfig.SurfaceHeight(wx, wz, SEED)
end

-- Shared with NodeGrid so ore is never placed in a cell that was carved hollow
local function isCave(wx, wy, wz)
	return StrataConfig.IsCave(wx, wy, wz, SEED)
end

-- ── Chunk bookkeeping ────────────────────────────────────────────────────────

local written = {}   -- [chunkKey] = true, written once and never rewritten

local function chunkKey(cx, cy, cz)
	return cx .. ":" .. cy .. ":" .. cz
end

-- A chunk whose whole 40-stud cube falls outside the round claim is nothing but
-- air, so there is no point writing it at all.
local function chunkInClaim(cx, cz)
	local x = (cx + 0.5) * CHUNK
	local z = (cz + 0.5) * CHUNK
	local corner = CHUNK * 0.71   -- half a chunk diagonal
	return (math.sqrt(x * x + z * z) - corner) <= mine.Radius
end

-- ── Generation ───────────────────────────────────────────────────────────────

local function generateChunk(cx, cy, cz)
	local key = chunkKey(cx, cy, cz)
	if written[key] then return false end
	written[key] = true

	if not chunkInClaim(cx, cz) then return false end

	local minX = cx * CHUNK
	local minZ = cz * CHUNK
	local minY = math.max(cy * CHUNK, mine.FloorY)
	local maxY = math.min(cy * CHUNK + CHUNK, mine.CeilingY)
	if maxY <= minY then return false end

	local region = Region3.new(
		Vector3.new(minX, minY, minZ),
		Vector3.new(minX + CHUNK, maxY, minZ + CHUNK)
	):ExpandToGrid(RES)

	local size   = region.Size
	local origin = region.CFrame.Position - size / 2
	local sx, sy, sz = size.X / RES, size.Y / RES, size.Z / RES

	-- Every room and tunnel that could reach into this chunk, worked out once
	-- instead of per voxel
	local field = Caverns.Field(origin, origin + size, SEED)

	-- The bore is a thin column down the middle of a very wide claim. A chunk
	-- that cannot reach it never asks.
	local nearAxis = axisGap(origin.X, origin.X + size.X) <= DESC.LandingRadius
		and axisGap(origin.Z, origin.Z + size.Z) <= DESC.LandingRadius

	local materials   = {}
	local occupancies = {}

	for x = 1, sx do
		materials[x]   = {}
		occupancies[x] = {}
		local wx = origin.X + (x - 0.5) * RES

		for y = 1, sy do
			materials[x][y]   = {}
			occupancies[x][y] = {}
			local wy = origin.Y + (y - 0.5) * RES

			for z = 1, sz do
				local wz = origin.Z + (z - 0.5) * RES

				local mat, occ = Enum.Material.Air, 0
				if wx * wx + wz * wz <= RADIUS_SQ
					and wy <= surfaceHeight(wx, wz)
					and not (nearAxis and inShaft(wx, wy, wz))
					and not isCave(wx, wy, wz)
					and not Caverns.Hollow(field, wx, wy, wz) then

					mat = StrataConfig.GetStratum(wy).material

					-- Turf on top. Only the few studs right under the sky, so the
					-- moment you break ground you are into dirt again.
					if wy > surfaceHeight(wx, wz) - StrataConfig.Look.TurfDepth then
						mat = Enum.Material.Grass
					end
					occ = 1

					-- A room lines the rock immediately around it, which is what
					-- makes walking into one feel like arriving somewhere rather
					-- than finding a gap.
					local room = Caverns.Halo(field, wx, wy, wz, LINING_DEPTH)
					if room and room.archetype and room.archetype.lining then
						mat = room.archetype.lining
					end
				end

				materials[x][y][z]   = mat
				occupancies[x][y][z] = occ
			end
		end
	end

	terrain:WriteVoxels(region, RES, materials, occupancies)
	return true
end

-- ── Startup shell ────────────────────────────────────────────────────────────

local function generateShell()
	local started = os.clock()
	local half    = mine.SizeX / 2
	local minC    = math.floor(-half / CHUNK)
	local maxC    = math.ceil(half / CHUNK) - 1
	local maxCy   = math.floor(mine.CeilingY / CHUNK)

	local count = 0
	for cx = minC, maxC do
		for cz = minC, maxC do
			if chunkInClaim(cx, cz) then
				for cy = SHELL_MIN_CY, maxCy do
					if generateChunk(cx, cy, cz) then count += 1 end
				end
				task.wait()  -- keep the server responsive during generation
			end
		end
	end

	print(("[MineGenerator] shell written in %.2fs, %d chunks (seed %d)")
		:format(os.clock() - started, count, SEED))
end

-- ── Streaming the deep rock ──────────────────────────────────────────────────

local queue  = {}   -- nearest-last, so the next job is a cheap table.remove
local queued = {}   -- [chunkKey] = true while it sits in the queue

local function enqueueAround(pos, radius)
	local span = math.ceil(radius / CHUNK)
	local pcx  = math.floor(pos.X / CHUNK)
	local pcy  = math.floor(pos.Y / CHUNK)
	local pcz  = math.floor(pos.Z / CHUNK)
	local r2   = radius * radius

	for cx = pcx - span, pcx + span do
		for cy = math.max(pcy - span, math.floor(mine.FloorY / CHUNK)), math.min(pcy + span, SHELL_MIN_CY - 1) do
			for cz = pcz - span, pcz + span do
				local key = chunkKey(cx, cy, cz)
				if not written[key] and not queued[key] and chunkInClaim(cx, cz) then
					local dx = (cx + 0.5) * CHUNK - pos.X
					local dy = (cy + 0.5) * CHUNK - pos.Y
					local dz = (cz + 0.5) * CHUNK - pos.Z
					local d2 = dx * dx + dy * dy + dz * dz
					if d2 <= r2 then
						queued[key] = true
						table.insert(queue, { cx = cx, cy = cy, cz = cz, key = key, d2 = d2 })
					end
				end
			end
		end
	end
end

-- Furthest first, so the nearest chunk is the one table.remove takes off the end
local function sortQueue()
	table.sort(queue, function(a, b) return a.d2 > b.d2 end)
end

-- Writes everything within `radius` of a point before returning. The lift uses
-- this: arriving 200 studs down inside unwritten rock would mean falling
-- through a world that has not been built yet.
local function ensure(pos, radius)
	enqueueAround(pos, radius or 90)
	sortQueue()

	local guard = 0
	while #queue > 0 and guard < 4000 do
		local job = table.remove(queue)
		queued[job.key] = nil
		generateChunk(job.cx, job.cy, job.cz)
		guard += 1
		if guard % 12 == 0 then task.wait() end
	end
end

_G.StrataEnsureRegion = ensure

local function streamLoop()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < 0 then
				enqueueAround(root.Position, mine.StreamRadius)
			end
		end
		if #queue > 0 then sortQueue() end
		task.wait(0.4)
	end
end

local function drainQueue()
	local budget = mine.StreamBudget or 0.004
	local t0 = os.clock()
	while os.clock() - t0 < budget do
		local job = table.remove(queue)
		if not job then return end
		queued[job.key] = nil
		generateChunk(job.cx, job.cy, job.cz)
	end
end

-- ── Look ─────────────────────────────────────────────────────────────────────
-- Each stratum recolours its own terrain material. This is where the bands get
-- their identity, and it costs nothing. Archetypes do the same with theirs —
-- terrain material colours are global, so every archetype was given a material
-- nothing else uses.

local function applyPalette()
	for _, s in ipairs(StrataConfig.Strata) do
		terrain:SetMaterialColor(s.material, s.color)
	end

	for _, arch in pairs(StrataConfig.Archetypes) do
		if arch.lining and arch.tint then
			terrain:SetMaterialColor(arch.lining, arch.tint)
		end
	end

	terrain:SetMaterialColor(Enum.Material.Grass, StrataConfig.Look.TurfColour)

	local look = StrataConfig.Look

	Lighting.Ambient        = look.Ambient
	Lighting.OutdoorAmbient = look.OutdoorAmbient
	Lighting.Brightness     = look.Brightness
	Lighting.GlobalShadows  = true
	Lighting.ExposureCompensation  = look.ExposureBias
	Lighting.EnvironmentDiffuseScale  = look.EnvironmentDiffuse
	Lighting.EnvironmentSpecularScale = look.EnvironmentSpecular
	Lighting.ClockTime          = look.ClockTime
	Lighting.GeographicLatitude = look.GeographicLatitude

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = look.Atmosphere.Density
	atmosphere.Haze    = look.Atmosphere.Haze
	atmosphere.Glare   = look.Atmosphere.Glare
	atmosphere.Color   = look.Atmosphere.Colour
	atmosphere.Decay   = look.Atmosphere.Decay

	-- Bloom is where most of the warmth comes from: every lamp is a Neon part,
	-- and this is what makes them read as burning rather than as painted.
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Intensity = look.Bloom.Intensity
	bloom.Size      = look.Bloom.Size
	bloom.Threshold = look.Bloom.Threshold

	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Parent = Lighting
	end
	grade.Contrast   = look.Grade.Contrast
	grade.Saturation = look.Grade.Saturation
	grade.Brightness = look.Grade.Brightness
	grade.TintColor  = look.Grade.Tint

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not rays then
		rays = Instance.new("SunRaysEffect")
		rays.Parent = Lighting
	end
	rays.Intensity = look.SunRays.Intensity
	rays.Spread    = look.SunRays.Spread
end

-- ── Surface staging ──────────────────────────────────────────────────────────
-- The camp, the spawn and everything else above ground belong to
-- SurfaceBuilder. This script owns the rock and nothing else.

applyPalette()
generateShell()

_G.StrataMineReady = true
print("[MineGenerator] ready")

task.spawn(streamLoop)
RunService.Heartbeat:Connect(drainQueue)
