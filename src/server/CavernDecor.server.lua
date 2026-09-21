local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Caverns      = require(ReplicatedStorage:WaitForChild("Caverns"))
local Remotes      = require(script.Parent.Remotes)
local PlayerState  = require(script.Parent.PlayerState)

-- ── Cavern decor ─────────────────────────────────────────────────────────────
-- A room carved out of rock is a hole. What makes it a place is what is
-- standing in it — spikes, crystals, fungus, a pool of something.
--
-- Props are blocky on purpose. Everything here is built out of plain parts, so
-- there is no modelling and nothing to import, and the chunky silhouette is the
-- look rather than a compromise.
--
-- Rooms are furnished when a player gets near and stripped again when everyone
-- leaves, so a map this size never has more than a few rooms of props in it.
-- Every prop position comes from the room key, so a room looks the same every
-- time it is rebuilt.

local BUILD_RADIUS = 190   -- furnish rooms this close to a player
local KEEP_RADIUS  = 300   -- strip them again past this
local ROOMS_PER_PASS = 2   -- built per sweep, so a busy descent never hitches

local folder = Instance.new("Folder")
folder.Name   = "CavernDecor"
folder.Parent = workspace

local cavernEntered = Remotes.Event("CavernEntered")   -- server → one client
local cavernFound   = Remotes.Event("CavernFound")     -- server → everyone

local seed = 0
repeat
	seed = _G.StrataSeed or 0
	if seed == 0 then task.wait(0.1) end
until seed ~= 0

local built     = {}   -- [roomKey] = Folder
local builtAt   = {}   -- [roomKey] = Vector3, so distance can be checked after the fact
local announced = {}   -- [roomKey] = true, so a rare room is news only once
local inside    = {}   -- [player] = roomKey

-- ── Deterministic randomness ─────────────────────────────────────────────────
-- Props must land in the same spots every time a room is rebuilt, so they are
-- drawn from a counter seeded by the room rather than from math.random.

local MOD = 2147483647

local function streamFrom(room)
	local h = 0
	for i = 1, #room.key do
		h = (h * 31 + room.key:byte(i)) % MOD
	end
	h = (h + seed * 104729) % MOD

	return function()
		h = (h * 48271) % MOD
		return h / MOD
	end
end

-- ── Ground finding ───────────────────────────────────────────────────────────

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include
castParams.FilterDescendantsInstances = { workspace.Terrain }
castParams.IgnoreWater = true

local function floorUnder(pos, reach)
	local hit = workspace:Raycast(pos, Vector3.new(0, -(reach or 60), 0), castParams)
	return hit and hit.Position or nil
end

local function ceilingOver(pos, reach)
	local hit = workspace:Raycast(pos, Vector3.new(0, reach or 60, 0), castParams)
	return hit and hit.Position or nil
end

-- ── Parts ────────────────────────────────────────────────────────────────────

-- ── How bright a cave is ─────────────────────────────────────────────────────
-- Raising the prop count to forty-odd a hall and giving every glowing one its
-- own PointLight turned the Topsoil into daylight — dozens of overlapping
-- lights, each one full strength, all of it through a bloom pass.
--
-- So: the props still glow, because neon is free and it is what makes a cave
-- look alive. But only a minority of them *light the room*, and the ones that
-- do are dimmer. Darkness is the point of being underground; a flare is only
-- worth throwing into somewhere dark.
local GLOW = {
	Share      = 0.34,   -- how many glowing props actually carry a light
	Brightness = 0.85,
	Reach      = 1.5,    -- multiplier on the prop's own size
	PoolBright = 1.2,
	PoolReach  = 3.2,
}

local litCount = 0

-- Every third one, counted rather than rolled: a random share clumps, and a
-- hall with six lights in one corner and none in the other is worse than a
-- hall with two evenly spread.
local function takesALight()
	litCount += 1
	return (litCount % math.floor(1 / GLOW.Share)) == 0
end

local function block(parent, size, cframe, colour, material, glow)
	local p = Instance.new("Part")
	p.Size        = size
	p.CFrame      = cframe
	p.Color       = colour
	p.Material    = material or Enum.Material.Slate
	p.Anchored    = true
	p.CanCollide  = false
	p.CanQuery    = false
	p.CanTouch    = false
	p.CastShadow  = false
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if glow then p.Material = Enum.Material.Neon end
	p.Parent = parent
	return p
end

local function shade(colour, amount)
	return Color3.new(
		math.clamp(colour.R + amount, 0, 1),
		math.clamp(colour.G + amount, 0, 1),
		math.clamp(colour.B + amount, 0, 1)
	)
end

-- ── Props ────────────────────────────────────────────────────────────────────
-- Each takes the spot it stands on and the room it belongs to, and adds itself
-- to that room folder.

local function spike(parent, base, height, width, colour, up)
	-- Stacked boxes narrowing towards the tip. Blocky, and it reads as a spike
	-- from any distance without a single triangle of geometry.
	local steps = math.clamp(math.floor(height / 1.6), 3, 7)
	local dir   = up and 1 or -1

	for i = 0, steps - 1 do
		local t = i / steps
		local w = width * (1 - t * 0.78)
		local h = height / steps
		local y = base.Y + dir * (i + 0.5) * h
		block(parent,
			Vector3.new(w, h, w),
			CFrame.new(base.X, y, base.Z),
			shade(colour, -0.04 + t * 0.12),
			Enum.Material.Slate)
	end
end

local function crystal(parent, base, height, colour, light)
	local shards = 3 + math.floor(height / 6)
	for i = 1, shards do
		local lean  = math.rad((i - shards / 2) * 9)
		local h     = height * (0.5 + (i % 3) * 0.25)
		local w     = math.max(height * 0.13, 0.6)
		local off   = (i - shards / 2) * w * 1.2

		local cf = CFrame.new(base + Vector3.new(off, h / 2, off * 0.4))
			* CFrame.Angles(lean * 0.6, lean, lean)

		block(parent, Vector3.new(w, h, w), cf, colour, nil, true)
	end

	if light and takesALight() then
		local pl = Instance.new("PointLight")
		pl.Color      = colour
		pl.Brightness  = GLOW.Brightness
		pl.Range       = height * GLOW.Reach
		pl.Shadows     = false
		pl.Parent      = block(parent, Vector3.new(0.4, 0.4, 0.4),
			CFrame.new(base + Vector3.new(0, height * 0.5, 0)), colour, nil, true)
	end
end

local function mushroom(parent, base, height, colour)
	local stem = math.max(height * 0.22, 0.5)
	block(parent, Vector3.new(stem, height, stem),
		CFrame.new(base + Vector3.new(0, height / 2, 0)),
		Color3.fromRGB(214, 206, 186), Enum.Material.Sand)

	local capW = height * 0.9
	block(parent, Vector3.new(capW, height * 0.28, capW),
		CFrame.new(base + Vector3.new(0, height + height * 0.1, 0)),
		colour, nil, true)
	block(parent, Vector3.new(capW * 0.6, height * 0.2, capW * 0.6),
		CFrame.new(base + Vector3.new(0, height + height * 0.3, 0)),
		shade(colour, 0.1), nil, true)
end

local function vine(parent, top, length, colour)
	local w = 0.35
	local segments = math.clamp(math.floor(length / 2.5), 2, 6)
	for i = 0, segments - 1 do
		local h = length / segments
		block(parent,
			Vector3.new(w, h, w),
			CFrame.new(top - Vector3.new(0, (i + 0.5) * h, 0))
				* CFrame.Angles(0, math.rad(i * 20), 0),
			shade(colour, -0.05 + (i % 2) * 0.08),
			Enum.Material.Grass)
	end
end

local function boulder(parent, base, size, colour)
	block(parent, Vector3.new(size, size * 0.8, size * 0.9),
		CFrame.new(base + Vector3.new(0, size * 0.3, 0))
			* CFrame.Angles(0, math.rad(size * 17), 0),
		colour, Enum.Material.Rock)
	block(parent, Vector3.new(size * 0.6, size * 0.5, size * 0.7),
		CFrame.new(base + Vector3.new(size * 0.3, size * 0.7, -size * 0.2))
			* CFrame.Angles(0, math.rad(size * 31), 0),
		shade(colour, 0.06), Enum.Material.Rock)
end

-- A pool of molten rock: a glowing surface with a rim, and the light that
-- makes the whole room orange.
local function lavaPool(parent, base, radius, colour)
	local surface = block(parent, Vector3.new(radius * 2, 0.6, radius * 2),
		CFrame.new(base + Vector3.new(0, 0.3, 0)), colour, nil, true)
	surface.Transparency = 0.08

	for i = 0, 5 do
		local a = math.rad(i * 60)
		block(parent, Vector3.new(radius * 0.5, 0.9, radius * 0.5),
			CFrame.new(base + Vector3.new(math.cos(a) * radius, 0.2, math.sin(a) * radius))
				* CFrame.Angles(0, a, 0),
			Color3.fromRGB(46, 32, 30), Enum.Material.Basalt)
	end

	local pl = Instance.new("PointLight")
	pl.Color      = colour
	pl.Brightness = GLOW.PoolBright
	pl.Range      = radius * GLOW.PoolReach
	pl.Shadows    = false
	pl.Parent     = surface
end

local function waterPool(parent, base, radius)
	workspace.Terrain:FillBall(base - Vector3.new(0, radius * 0.45, 0), radius, Enum.Material.Water)
end

-- ── Furnishing a room ────────────────────────────────────────────────────────

local function furnish(room)
	if built[room.key] then return end

	local arch = room.archetype
	if not arch then return end

	local roomFolder = Instance.new("Folder")
	roomFolder.Name = "Room_" .. room.key
	built[room.key]   = roomFolder
	builtAt[room.key] = room.centre

	local rand  = streamFrom(room)
	local decor = arch.decor or {}
	local light = arch.light or Color3.fromRGB(200, 200, 200)

	-- Bigger rooms get more in them, and a cap keeps the part count sane
	-- Scaled to the room. A dig site hall is four times the width of an ambient
	-- cavern now, and twenty-six props scattered through one of those is an
	-- empty room with some ornaments in it.
	local count  = math.clamp(math.floor(room.radius * 0.55), 8, 46)
	local lights = 0

	for i = 1, count do
		local kind = decor[1 + (i - 1) % #decor]

		-- A point somewhere in the room, biased away from dead centre so the
		-- middle stays walkable
		local angle = rand() * math.pi * 2
		local dist  = room.radius * (0.25 + rand() * 0.7)
		local spot  = room.centre + Vector3.new(
			math.cos(angle) * dist,
			-- Half the room's *height*, not its width. A flattened hall is much
			-- wider than it is tall, and starting the cast above its roof finds
			-- nothing to stand a prop on.
			(room.flatten and room.radius / room.flatten or room.radius) * 0.5,
			math.sin(angle) * dist
		)

		if kind == "stalactites" then
			local top = ceilingOver(spot, room.radius)
			if top then
				spike(roomFolder, top, 3 + rand() * 9, 1 + rand() * 2.2, arch.tint or light, false)
			end
		elseif kind == "vines" then
			local top = ceilingOver(spot, room.radius)
			if top then
				vine(roomFolder, top, 3 + rand() * 8, Color3.fromRGB(78, 128, 58))
			end
		else
			local ground = floorUnder(spot, room.radius * 1.6)
			if ground then
				if kind == "stalagmites" then
					spike(roomFolder, ground, 3 + rand() * 10, 1.2 + rand() * 2.4, arch.tint or light, true)
				elseif kind == "crystals" then
					local wantsLight = lights < 5 and rand() < 0.55
					if wantsLight then lights += 1 end
					crystal(roomFolder, ground, 4 + rand() * 8, light, wantsLight)
				elseif kind == "mushrooms" then
					mushroom(roomFolder, ground, 2 + rand() * 5, light)
				elseif kind == "boulders" then
					boulder(roomFolder, ground, 2 + rand() * 4, arch.tint or light)
				elseif kind == "lava" and lights < 4 then
					lights += 1
					lavaPool(roomFolder, ground, room.radius * (0.18 + rand() * 0.16), light)
				elseif kind == "water" then
					waterPool(roomFolder, ground, room.radius * (0.22 + rand() * 0.18))
				end
			end
		end
	end

	roomFolder.Parent = folder
end

local function strip(key)
	local roomFolder = built[key]
	if roomFolder then
		roomFolder:Destroy()
		built[key]   = nil
		builtAt[key] = nil
	end
end

-- ── Presence ─────────────────────────────────────────────────────────────────

local function announce(player, room)
	local arch = room.archetype
	if not arch then return end

	cavernEntered:FireClient(player, {
		id    = room.archetypeId,
		name  = arch.name,
		blurb = arch.blurb,
		fog   = arch.fog,
		light = arch.light,
		rare  = arch.rare == true,
	})

	-- A rare room is news for the whole server, once, the first time anybody
	-- walks into it. That is the moment worth telling people about.
	if arch.rare and not announced[room.key] then
		announced[room.key] = true
		cavernFound:FireAllClients({
			name   = arch.name,
			blurb  = arch.blurb,
			finder = player.Name,
			light  = arch.light,
			depth  = math.floor(-room.centre.Y),
		})
	end
end

local function sweep()
	local wanted = {}   -- [roomKey] = room, everything that should be furnished

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < StrataConfig.Mine.CeilingY then
			local pos = root.Position
			local pad = Vector3.new(BUILD_RADIUS, BUILD_RADIUS, BUILD_RADIUS)
			local field = Caverns.Field(pos - pad, pos + pad, seed)

			for _, room in ipairs(field.rooms) do
				if (room.centre - pos).Magnitude <= BUILD_RADIUS + room.radius then
					wanted[room.key] = room
				end
			end


			-- Dig site halls are shaped exactly like cavern rooms — key,
			-- centre, radius, archetype — so they are furnished by the same
			-- code with nothing added to it. Spikes, crystals, fungus and pools
			-- turn up in a contract's map for free.
			if _G.StrataSiteRooms then
				for _, chamber in ipairs(_G.StrataSiteRooms()) do
					if (chamber.centre - pos).Magnitude <= BUILD_RADIUS + chamber.radius then
						wanted[chamber.key] = chamber
					end
				end
			end

			-- Which room the player is standing in, if any. A dig site hall
			-- counts: the halls are carved after the world was made, so the
			-- ambient cavern field has never heard of them, and a survey
			-- contract sent into one would be unfinishable.
			local _, here = Caverns.Hollow(field, pos.X, pos.Y, pos.Z)
			if not here and _G.StrataSiteBuilder then
				here = _G.StrataSiteBuilder.ChamberFor(player, pos)
			end
			local key = here and here.key or nil
			-- A survey contract is asking you to walk into one of these
			if here then PlayerState.NoteRoom(player, here.archetypeId) end

			if key ~= inside[player] then
				inside[player] = key
				if here then announce(player, here) else cavernEntered:FireClient(player, nil) end
			end
		end
	end

	-- Furnish a couple per sweep. Rooms come into range gradually, so there is
	-- no need to do them all in one frame.
	local made = 0
	for key, room in pairs(wanted) do
		if not built[key] then
			furnish(room)
			made += 1
			if made >= ROOMS_PER_PASS then break end
		end
	end

	-- And strip anything nobody is near any more
	for key, roomFolder in pairs(built) do
		if not wanted[key] then
			local keep = false
			local centre = builtAt[key]
			for _, player in ipairs(Players:GetPlayers()) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and centre and (root.Position - centre).Magnitude < KEEP_RADIUS then
					keep = true
					break
				end
			end
			if not keep then strip(key) end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	inside[player] = nil
end)

task.spawn(function()
	while true do
		local ok, err = pcall(sweep)
		if not ok then warn("[CavernDecor] " .. tostring(err)) end
		task.wait(0.5)
	end
end)

print("[CavernDecor] online")
