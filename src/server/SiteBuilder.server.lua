local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local DigSite      = require(ReplicatedStorage:WaitForChild("DigSite"))
local Remotes      = require(script.Parent.Remotes)
local PlayerState  = require(script.Parent.PlayerState)

-- ── Site builder ─────────────────────────────────────────────────────────────
-- Turns the layout in DigSite into rock you can walk through, light you can
-- navigate by, and objectives you have to go and find.
--
-- Carving is three passes over the whole site, in this order and no other:
--
--   1. ensure    the deep rock is written on demand, so anything carved into a
--                chunk that has not been written yet gets filled straight back
--                in the moment a player walks near it. Every chunk the site
--                touches is written first, nearest chamber outwards.
--   2. lining    every hall and tunnel is filled *solid* with its archetype's
--                own material, a few studs oversize.
--   3. air       and then hollowed out. What is left between the two is a shell
--                of the room's own rock, which is what gives a Crystal Vault
--                walls that look like a Crystal Vault.
--
-- The passes are global rather than per-chamber. Doing one hall at a time would
-- mean the second hall's lining pass plugging the first hall's air wherever the
-- two come close — which, given halls are deliberately held closer than their
-- radii together, is most of the time.
--
-- The timing is not an accident either: this runs while the player is in the
-- cage. A sixteen-second ride down to the Magma Vents is the loading screen for
-- the map waiting at the bottom of it.

local CFG     = StrataConfig.Site
local terrain = workspace.Terrain

local siteMap      = Remotes.Event("SiteMap")       -- server → client, once per run
local siteProgress = Remotes.Event("SiteProgress")  -- server → client, on objectives
local depositHit   = Remotes.Event("DepositHit")    -- client → server
local nodeHit      = Remotes.Event("NodeHit")       -- reused: the shared hit feedback

local root = Instance.new("Folder")
root.Name   = "DigSites"
root.Parent = workspace

-- Deposits live in their own folder so the client can put it in the dig ray's
-- filter and tell an objective apart from a lump of ore.
local depositFolder = Instance.new("Folder")
depositFolder.Name   = "SiteDeposits"
depositFolder.Parent = workspace

local IRON   = Color3.fromRGB(78, 82, 88)
local IRON_D = Color3.fromRGB(44, 47, 52)
local HAZARD = Color3.fromRGB(214, 174, 72)
local LAMP   = Color3.fromRGB(255, 198, 126)

-- [player] = { site = ..., folder = ..., deposits = { ... } }
local openSites = {}

local function part(name, size, cf, colour, material, parent)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = cf
	p.Color         = colour
	p.Material      = material or Enum.Material.Metal
	p.Anchored      = true
	p.CanCollide    = false
	p.CanQuery      = false
	p.CastShadow    = false
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent        = parent
	return p
end

-- ── Carving ──────────────────────────────────────────────────────────────────

-- Nearest first, so the halls you can reach in the first twenty seconds are the
-- ones that exist first. The far end of the map has the whole walk to get ready.
local function byDistance(site)
	local order = {}
	for _, c in ipairs(site.chambers) do table.insert(order, c) end
	table.sort(order, function(a, b)
		return (a.centre - site.hub).Magnitude < (b.centre - site.hub).Magnitude
	end)
	return order
end

local function ensureSite(site)
	local ensure = _G.StrataEnsureRegion
	if not ensure then return end

	for _, chamber in ipairs(byDistance(site)) do
		ensure(chamber.centre, chamber.radius + 34)

		-- Sampled by distance, not by path point. Tunnel points are spaced off
		-- the tunnel's own width now, so a narrow drift has three times as many
		-- of them and stepping through every other one would ask for the same
		-- chunks over and over.
		for _, drift in ipairs(site.drifts) do
			if drift.to == chamber.index then
				local step = math.max(math.floor(40 / (drift.radius * CFG.DriftStep)), 1)
				for i = 1, #drift.points, step do
					ensure(drift.points[i], 46)
				end
			end
		end
	end
end

-- Yielded inside the loop rather than between halls. A hall is thirty spheres
-- of up to eighty studs now — over a million voxels a site — and doing one
-- hall's worth between two frames is a visible hitch for everybody on the
-- server, not just the person riding down to it.
local FILLS_PER_FRAME = 4

local function fillChamber(chamber, material, grow)
	for i, blob in ipairs(chamber.blobs) do
		terrain:FillBall(chamber.centre + blob.offset, blob.radius + grow, material)
		if i % FILLS_PER_FRAME == 0 then task.wait() end
	end
end

local function fillDrift(drift, material, grow)
	for i, point in ipairs(drift.points) do
		terrain:FillBall(point, drift.radius + grow, material)
		if i % (FILLS_PER_FRAME * 3) == 0 then task.wait() end
	end
end

-- The rock a hall is lined with. An archetype that has its own terrain material
-- uses it; anything else takes the layer's, which is what the wall would have
-- been anyway and costs nothing to write.
local function liningOf(chamber, stratum)
	local arch = chamber.archetype
	return (arch and arch.lining) or stratum.material
end

local function carve(site, stratum)
	local order = byDistance(site)

	-- Pass 2: solid, oversize, in each room's own rock
	for _, chamber in ipairs(order) do
		fillChamber(chamber, liningOf(chamber, stratum), CFG.LiningDepth)
		task.wait()
	end
	for _, drift in ipairs(site.drifts) do
		fillDrift(drift, liningOf(site.chambers[drift.to], stratum), CFG.LiningDepth * 0.6)
	end
	task.wait()

	-- Pass 3: and hollow it out again
	for _, chamber in ipairs(order) do
		fillChamber(chamber, Enum.Material.Air, 0)
		task.wait()
	end
	for _, drift in ipairs(site.drifts) do
		fillDrift(drift, Enum.Material.Air, 0)
	end
	task.wait()

	-- Relief: rock put back into the hole. Terraces are stepped floors, which is
	-- what every reference for a cave is and what a single fill pass never
	-- gives you; pillars are columns floor to ceiling, and they are the reason a
	-- two-hundred-stud hall reads as two hundred studs rather than as a dome —
	-- you cannot judge a space until something in it blocks your view across it.
	for _, chamber in ipairs(order) do
		for _, shelf in ipairs(chamber.shelves) do
			terrain:FillBlock(
				CFrame.new(chamber.centre + shelf.offset) * CFrame.Angles(0, shelf.spin, 0),
				shelf.size, stratum.material)
		end

		for _, pillar in ipairs(chamber.pillars) do
			terrain:FillCylinder(
				CFrame.new(chamber.centre + pillar.offset) * CFrame.Angles(0, 0, math.pi / 2),
				pillar.height, pillar.radius, stratum.material)
		end
		task.wait()
	end

	-- A shelf can land across the mouth of the drift that serves the hall, and
	-- a terrace you cannot get past is a chamber you cannot enter. The last few
	-- studs of every tunnel are cut again, after everything else.
	for _, drift in ipairs(site.drifts) do
		local tail = math.ceil(44 / (drift.radius * CFG.DriftStep))
		for i = math.max(#drift.points - tail, 1), #drift.points do
			terrain:FillBall(drift.points[i], drift.radius, Enum.Material.Air)
		end
	end

	-- And the station, which the lining pass will have bitten into wherever a
	-- drift leaves it
	local landing = StrataConfig.LandingY(stratum)
	local D = StrataConfig.Descent
	terrain:FillCylinder(CFrame.new(0, landing, 0) * CFrame.Angles(0, 0, math.pi / 2),
		D.LandingHalf * 2, D.BoreRadius + 3, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(0, landing, 0) * CFrame.Angles(0, 0, math.pi / 2),
		D.LandingHalf, D.LandingRadius, Enum.Material.Air)
end

-- ── Light and signs ──────────────────────────────────────────────────────────
-- A dig site you cannot navigate is a dig site you die in with a full pack.
-- Every drift is strung with lamps in the colour of the hall it leads to, so
-- picking a tunnel at the station is a decision you can actually make, and
-- finding your way back is a matter of following the lights the other way.

local function lamp(at, colour, lit, parent)
	part("LampPost", Vector3.new(0.5, 3.4, 0.5),
		CFrame.new(at + Vector3.new(0, 1.7, 0)), IRON_D, Enum.Material.Metal, parent)

	local glass = part("LampGlass", Vector3.new(1.5, 1.5, 1.5),
		CFrame.new(at + Vector3.new(0, 3.6, 0)), colour, Enum.Material.Neon, parent)

	-- Only some of them carry a light. Roblox renders a limited number at once
	-- and the rest pop in and out as you turn, which reads as flicker — the
	-- same lesson the lodge lanterns taught.
	if lit then
		local light = Instance.new("PointLight")
		light.Color      = colour
		light.Brightness = 2.2
		light.Range      = 34
		light.Shadows    = false
		light.Parent     = glass
	end
	return glass
end

local function signpost(at, facing, chamber, parent)
	local colour = chamber.archetype and chamber.archetype.light or HAZARD

	part("SignPost", Vector3.new(0.7, 9, 0.7),
		CFrame.new(at + Vector3.new(0, 4.5, 0)), IRON_D, Enum.Material.Metal, parent)

	local board = part("SignBoard", Vector3.new(11, 3, 0.4),
		CFrame.new(at + Vector3.new(0, 8.4, 0)) * CFrame.Angles(0, facing, 0),
		IRON, Enum.Material.Metal, parent)

	local gui = Instance.new("SurfaceGui")
	gui.Face           = Enum.NormalId.Front
	gui.CanvasSize     = Vector2.new(330, 90)
	gui.LightInfluence = 0
	gui.Parent         = board

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = string.upper(chamber.name)
	label.TextColor3             = colour
	label.TextScaled             = true
	label.Font                   = StrataConfig.UI.Head
	label.Parent                 = gui

	local glow = Instance.new("PointLight")
	glow.Color      = colour
	glow.Brightness = 1.8
	glow.Range      = 26
	glow.Shadows    = false
	glow.Parent     = board
end

-- The seams. A contract is for one layer and the rock above and below it will
-- not break while you are on the job — MineService enforces that. These are the
-- two sheets that say so, because a wall you cannot see is a wall players
-- report as a bug.
local function seams(stratum, folder)
	local top, bottom = StrataConfig.LayerBounds(stratum.id)
	local S = CFG.Seam
	local span = StrataConfig.Mine.Radius * 2

	for _, y in ipairs({ top, bottom }) do
		local sheet = part("Seam", Vector3.new(span, S.Thick, span),
			CFrame.new(0, y, 0), stratum.color:Lerp(Color3.fromRGB(255, 255, 255), 0.3),
			Enum.Material.Neon, folder)
		sheet.Transparency = S.Alpha
	end
end

local function lightDrifts(site, folder)
	for _, drift in ipairs(site.drifts) do
		local chamber = site.chambers[drift.to]
		local colour  = chamber.archetype and chamber.archetype.light or LAMP

		-- Walked as one continuous line rather than per path point, so lamps are
		-- evenly spaced however long or short the tunnel turned out
		local run, carried, lit = 0, 0, 0
		for i = 1, #drift.points - 1 do
			local a, b  = drift.points[i], drift.points[i + 1]
			local span  = (b - a).Magnitude
			local along = carried

			while along < span do
				local at = a + (b - a) * (along / math.max(span, 0.01))
				lit += 1
				lamp(at - Vector3.new(0, drift.radius - 0.4, 0), colour,
					lit % 2 == 1, folder)
				along += CFG.LampEvery
				run   += CFG.LampEvery
			end
			carried = along - span
		end

		-- A board at the station end saying where this one goes
		if drift.from == 0 then
			local out = drift.points[math.min(3, #drift.points)]
			signpost(Vector3.new(out.X, out.Y - drift.radius + 0.4, out.Z),
				math.atan2(out.X, out.Z) + math.pi, chamber, folder)
		end
	end
end

-- ── Objectives ───────────────────────────────────────────────────────────────
-- A deposit is a thing you walk to, stand at and break. Three to five of them,
-- one per hall, and you cannot have them all without walking the map — which is
-- the whole point of there being a map.

local function depositModel(chamber, index, hp, folder)
	local colour = chamber.archetype and chamber.archetype.light
		or Color3.fromRGB(240, 196, 110)

	local model = Instance.new("Model")
	model.Name = "Deposit" .. index

	-- On the floor of the hall, off to one side, so it is something you spot
	-- across the room rather than trip over on the way in. Stepped round the
	-- golden angle, so several deposits in one hall never line up — and pushed
	-- on again if the spot it lands on is inside a pillar, which would put the
	-- objective inside solid rock.
	local v  = chamber.radius / chamber.flatten
	local at = chamber.centre

	for attempt = 0, 7 do
		local a = (index + attempt) * 2.399
		local d = chamber.radius * (0.4 + (attempt % 3) * 0.12)
		at = chamber.centre + Vector3.new(math.cos(a) * d, -v * 0.72, math.sin(a) * d)

		local clear = true
		for _, pillar in ipairs(chamber.pillars) do
			local p = chamber.centre + pillar.offset
			local dx, dz = at.X - p.X, at.Z - p.Z
			if dx * dx + dz * dz < (pillar.radius + 8) ^ 2 then clear = false end
		end
		if clear then break end
	end

	local base = part("Base", Vector3.new(7, 2.4, 7), CFrame.new(at),
		Color3.fromRGB(52, 48, 44), Enum.Material.Slate, model)
	base.CanCollide = true
	base.CanQuery   = true
	model.PrimaryPart = base

	-- A cluster of shards, so it reads as something grown rather than placed
	for i = 1, 7 do
		local lean = math.rad((i - 4) * 11)
		local h    = 4 + (i % 3) * 2.6
		local w    = 1.1 + (i % 2) * 0.5
		local off  = (i - 4) * 1.1

		local shard = part("Shard", Vector3.new(w, h, w),
			CFrame.new(at + Vector3.new(off, 1.2 + h / 2, off * 0.4))
				* CFrame.Angles(lean * 0.5, lean, lean),
			colour, Enum.Material.Neon, model)
		shard.CanQuery = true
	end

	local light = Instance.new("PointLight")
	light.Color      = colour
	light.Brightness = 3
	light.Range      = 46
	light.Shadows    = false
	light.Parent     = base

	-- Visible through rock at a distance, which is how you decide which hall to
	-- clear next. DRG does exactly this and the alternative is wandering.
	local tag = Instance.new("BillboardGui")
	tag.Name          = "Marker"
	tag.Size          = UDim2.new(0, 190, 0, 46)
	tag.StudsOffset   = Vector3.new(0, 9, 0)
	tag.AlwaysOnTop   = true
	tag.MaxDistance   = CFG.Deposit.Marker
	tag.LightInfluence = 0
	tag.Parent        = base

	local name = Instance.new("TextLabel")
	name.Size                   = UDim2.new(1, 0, 0, 20)
	name.BackgroundTransparency = 1
	name.Text                   = "DEPOSIT"
	name.TextColor3             = colour
	name.TextSize               = 17
	name.Font                   = StrataConfig.UI.Head
	name.Parent                 = tag

	local bar = Instance.new("Frame")
	bar.Name             = "Track"
	bar.Size             = UDim2.new(0.66, 0, 0, 6)
	bar.Position         = UDim2.new(0.17, 0, 0, 24)
	bar.BackgroundColor3 = Color3.fromRGB(18, 17, 20)
	bar.BorderSizePixel  = 0
	bar.Parent           = tag

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel  = 0
	fill.Parent           = bar

	model:SetAttribute("Deposit", true)
	model:SetAttribute("Hp", hp)
	model:SetAttribute("MaxHp", hp)
	model.Parent = folder

	return { model = model, base = base, fill = fill, chamber = chamber,
		position = at, hp = hp, maxHp = hp }
end

local function placeDeposits(site, stratum, count, folder)
	local out = {}

	-- Spread across different halls, starting with the far ones: an objective
	-- in the chamber you can see from the station is not an objective.
	local order = byDistance(site)
	for i = #order, 1, -1 do
		if #out >= count then break end
		local hp = math.max(math.floor((stratum.hardness or 1) * CFG.Deposit.Hp), 12)
		table.insert(out, depositModel(order[i], #out + 1, hp, folder))
	end

	-- More deposits than halls: the rest double up in the biggest ones
	local i = #order
	while #out < count and i >= 1 do
		local hp = math.max(math.floor((stratum.hardness or 1) * CFG.Deposit.Hp), 12)
		table.insert(out, depositModel(order[i], #out + 1, hp, folder))
		i -= 1
	end

	return out
end

-- ── Opening and closing ──────────────────────────────────────────────────────

local SiteBuilder = {}

function SiteBuilder.Open(player, contract, stratum, tierIndex)
	SiteBuilder.Close(player)

	local hubY = StrataConfig.LandingY(stratum)
		- StrataConfig.Descent.LandingHalf + 1.4

	local seed = (contract.id or 1) * 7919
		+ (tierIndex or 1) * 104729
		+ (_G.StrataSeed or 0)

	local site = DigSite.Build(seed, stratum, tierIndex, hubY, contract.archetypeId)
	if #site.chambers == 0 then return nil end

	DigSite.Register(site)

	local folder = Instance.new("Folder")
	folder.Name   = "Site_" .. player.UserId
	folder.Parent = root

	local entry = { site = site, folder = folder, deposits = {}, player = player }
	openSites[player] = entry

	-- Everything from here yields, so the contract can start and the cage can
	-- descend while the rock is being written
	task.spawn(function()
		local ok, err = pcall(function()
			ensureSite(site)
			carve(site, stratum)
			lightDrifts(site, folder)
			seams(stratum, folder)

			-- Into the deposit folder, not the site folder: the client puts that
			-- folder in its dig ray's filter, and both ends check the parent to
			-- tell an objective apart from a lump of ore. Close() still takes
			-- them down, because it holds the list.
			if contract.kind == "extract" then
				entry.deposits = placeDeposits(site, stratum, contract.count or 3,
					depositFolder)
			end

			entry.ready = true
			siteMap:FireClient(player, DigSite.Summary(site))
		end)
		if not ok then warn("[SiteBuilder] " .. tostring(err)) end
	end)

	return site
end

function SiteBuilder.Close(player)
	local entry = openSites[player]
	if not entry then return end
	openSites[player] = nil

	DigSite.Unregister(entry.site)
	if entry.folder then entry.folder:Destroy() end
	for _, d in ipairs(entry.deposits) do
		if d.model.Parent then d.model:Destroy() end
	end
	siteMap:FireClient(player, nil)
end

function SiteBuilder.SiteFor(player)
	local entry = openSites[player]
	return entry and entry.site or nil
end

-- Which hall of their own site a player is standing in. Their own, not any
-- open one: two people on two contracts can be a hundred studs apart in rock
-- that belongs to both of their maps, and a survey contract that ticked off
-- somebody else's room would be a contract you could finish by standing still.
function SiteBuilder.ChamberFor(player, position)
	local entry = openSites[player]
	if not entry or not entry.ready then return nil end
	return DigSite.ChamberAt(entry.site, position)
end

_G.StrataSiteBuilder = SiteBuilder

-- The decorator furnishes anything shaped like a cavern room, and a chamber is
-- deliberately shaped like one. This is the whole integration: spikes, crystals,
-- fungus and pools turn up in dig sites for free.
_G.StrataSiteRooms = function()
	local rooms = {}
	for _, entry in pairs(openSites) do
		if entry.ready then
			for _, chamber in ipairs(entry.site.chambers) do
				table.insert(rooms, chamber)
			end
		end
	end
	return rooms
end

-- ── Breaking a deposit ───────────────────────────────────────────────────────

local function findDeposit(model)
	for player, entry in pairs(openSites) do
		for i, d in ipairs(entry.deposits) do
			if d.model == model then return player, entry, d, i end
		end
	end
	return nil
end

depositHit.OnServerEvent:Connect(function(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if model.Parent ~= depositFolder then return end

	local owner, entry, deposit = findDeposit(model)
	if owner ~= player or not deposit then return end
	-- Explicit rather than inferred from the model being gone. Two swings
	-- landing in the same frame would otherwise both find a deposit that is
	-- still parented and both count it.
	if deposit.taken then return end

	local run = PlayerState.Run(player)
	if not run then return end

	local root2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root2 then return end
	if (root2.Position - deposit.position).Magnitude > StrataConfig.Dig.MaxDistance then
		return
	end

	local power = PlayerState.MiningPower(player)
	deposit.hp = deposit.hp - power
	deposit.fill.Size = UDim2.fromScale(
		math.clamp(deposit.hp / deposit.maxHp, 0, 1), 1)

	-- The same sparks and the same number that come off an ore node, so a
	-- deposit reads as something you are mining rather than something you are
	-- clicking. Fired while the model is still there, because the client takes
	-- the hit position off it.
	nodeHit:FireClient(player, deposit.model, power, deposit.hp <= 0)

	if deposit.hp > 0 then return end

	-- It comes down, and what was in it goes straight into the manifest
	local yield = math.random(CFG.Deposit.Yield[1], CFG.Deposit.Yield[2])
	local stratum = StrataConfig.GetStratum(deposit.position.Y)
	for _ = 1, yield do
		local ore = StrataConfig.RollOre(math.random(), stratum,
			deposit.chamber.archetypeId)
		if ore then PlayerState.AddOre(player, ore.id) end
	end

	deposit.taken = true
	PlayerState.NoteDeposit(player)
	deposit.model:Destroy()

	local taken, need = 0, #entry.deposits
	for _, d in ipairs(entry.deposits) do
		if d.taken then taken += 1 end
	end
	siteProgress:FireClient(player, { taken = taken, need = need })

	if StrataConfig.Debug then
		print(("[SiteBuilder] %s cleared a deposit (%d/%d)")
			:format(player.Name, taken, need))
	end
end)

Players.PlayerRemoving:Connect(SiteBuilder.Close)

print("[SiteBuilder] online")
