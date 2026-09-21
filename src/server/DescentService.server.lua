local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Remotes      = require(script.Parent.Remotes)
local PlayerState  = require(script.Parent.PlayerState)

-- ── Descent service ──────────────────────────────────────────────────────────
-- Taking a contract used to be a teleport with a quarter-second wait in it.
-- This is the same journey made literally: a bore straight down the middle of
-- the claim, a cage that runs in it, and you standing in the cage while the
-- topsoil turns to rock and the rock turns to basalt.
--
-- Three things own themselves here and nothing else touches them:
--
--   The bore    real terrain, carved by MineGenerator's voxel function. This
--               file only decides how deep it goes, and opens the new section
--               in chunks that were written before it moved.
--   The grate   the plug over the shaft mouth in the lodge floor. Without it
--               the camp has a two-hundred-stud hole in the middle of it.
--   The cage    built per rider and thrown away after, so two people can be in
--               the shaft at once without sharing a lift.
--
-- ExpeditionService asks for a ride through _G.StrataDescent and carries on
-- without one if this file is not there. A descent that fails is still a
-- contract that starts.

local D       = StrataConfig.Descent
local SURF    = StrataConfig.Surface
local terrain = workspace.Terrain

local descentStarted = Remotes.Event("DescentStarted")
local descentEnded   = Remotes.Event("DescentEnded")

-- Top of the lodge floor boards: where the grate sits and where the cage parks
local DECK_Y  = SURF.PlatformY + 0.12
local FLOOR_T = 0.8
local HALF    = D.Cage.Half
local CAGE_H  = D.Cage.Height

-- ── Palette ──────────────────────────────────────────────────────────────────
local IRON    = Color3.fromRGB(74, 78, 84)
local IRON_L  = Color3.fromRGB(116, 122, 130)
local IRON_D  = Color3.fromRGB(44, 47, 52)
local RUST    = Color3.fromRGB(122, 80, 54)
local HAZARD  = Color3.fromRGB(214, 174, 72)
local LAMP    = Color3.fromRGB(255, 198, 126)
local TIMBER  = Color3.fromRGB(112, 78, 48)

local root = Instance.new("Folder")
root.Name   = "Descent"
root.Parent = workspace

local shaftFolder = Instance.new("Folder")
shaftFolder.Name   = "Shaft"
shaftFolder.Parent = root

-- ── Primitives ───────────────────────────────────────────────────────────────

local function part(name, size, cf, colour, material, parent)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = cf
	p.Color         = colour
	p.Material      = material or Enum.Material.Metal
	p.Anchored      = true
	p.CanCollide    = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent        = parent or shaftFolder
	return p
end

local function decor(name, size, cf, colour, material, parent)
	local p = part(name, size, cf, colour, material, parent)
	p.CanCollide = false
	p.CanQuery   = false
	p.CastShadow = false
	return p
end

-- ── The bore ─────────────────────────────────────────────────────────────────
-- How deep it runs is not a constant: it follows the deepest layer anybody on
-- this server has stood in. Chunks written after the floor moves carve
-- themselves from the voxel function; the ones already written get opened here,
-- which is the only reason the shaft can grow in a live world.

local LANDINGS = {}
for _, s in ipairs(StrataConfig.Strata) do
	table.insert(LANDINGS, { stratum = s, y = StrataConfig.LandingY(s) })
end

-- Where the cage stops for a station: a stud above the chamber floor, so
-- stepping out is a step rather than a drop.
local function stopYFor(landingY)
	return landingY - D.LandingHalf + 1.4
end

local furnishedTo  = DECK_Y   -- how far down the shaft furniture has been built
local stationBuilt = {}       -- [layerId] = true

-- A ring of timbering. The same set a real shaft gets, and the thing that gives
-- the eye something to measure the fall against.
local function rib(y)
	local r      = D.BoreRadius - 0.45
	local colour = (math.floor(y / D.RibEvery) % 3 == 0) and RUST or TIMBER

	for _, s in ipairs({ -1, 1 }) do
		decor("Rib", Vector3.new(r * 2 + 1.6, 1.1, 1.2),
			CFrame.new(0, y, s * r), colour, Enum.Material.Wood)
		decor("Rib", Vector3.new(1.2, 1.1, r * 2 + 1.6),
			CFrame.new(s * r, y, 0), colour, Enum.Material.Wood)
	end
end

local function shaftLamp(y, side)
	local x = side * (D.BoreRadius - 0.7)
	decor("LampBox", Vector3.new(1.1, 2.2, 2.2), CFrame.new(x, y, 0),
		IRON_D, Enum.Material.Metal)

	local glass = decor("LampGlass", Vector3.new(0.5, 1.5, 1.5),
		CFrame.new(x - side * 0.7, y, 0), LAMP, Enum.Material.Neon)

	local light = Instance.new("PointLight")
	light.Color      = LAMP
	light.Brightness = 2.2
	light.Range      = 30
	light.Shadows    = false
	light.Parent     = glass
end

-- Guide rails run the full height, which is what makes the shaft read as one
-- continuous thing rather than a stack of rings.
local function rails(fromY, toY)
	local height = fromY - toY
	if height <= 0 then return end

	for _, s in ipairs({ -1, 1 }) do
		decor("Rail", Vector3.new(0.9, height, 1.8),
			CFrame.new(s * (D.BoreRadius - 1.1), (fromY + toY) / 2, 0),
			IRON_L, Enum.Material.Metal)
	end
end

-- ── Station gates ────────────────────────────────────────────────────────────
-- The bore runs past every station down to the deepest one anybody has found.
-- Without something across it, being set down at the Topsoil means standing on
-- the lip of an open five-hundred-stud hole to the Magma Vents — which is a
-- contract for one layer with a ladder out of it.
--
-- So every station gets the same plug the camp deck has: shut by default, open
-- only for the width of a cage going past, shut again the moment it has. The
-- cage is the only thing that ever moves through the shaft.

local stationGates = {}

local function buildStationGate(deck)
	local r    = D.BoreRadius + 1
	local gate = { y = deck, open = false, halves = {} }

	for _, s in ipairs({ -1, 1 }) do
		local half = part("StationGate", Vector3.new(r, 0.6, r * 2),
			CFrame.new(s * r / 2, deck - 0.3, 0), IRON_D, Enum.Material.DiamondPlate)
		half:SetAttribute("Side", s)
		table.insert(gate.halves, half)
	end

	table.insert(stationGates, gate)
	return gate
end

local function setGate(gate, open)
	if gate.open == open then return end
	gate.open = open

	local r = D.BoreRadius + 1
	for _, half in ipairs(gate.halves) do
		local s = half:GetAttribute("Side")
		half.CanCollide = not open
		TweenService:Create(half, TweenInfo.new(0.35, Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut), {
				CFrame = open
					and CFrame.new(s * (r + 9), gate.y - 1.7, 0)
					or  CFrame.new(s * r / 2, gate.y - 0.3, 0),
			}):Play()
	end
end

-- Open for anything within a cage-and-a-half, shut for everything else. Called
-- every frame of a ride, which is the only time a gate has any business moving.
local function gatesNear(y)
	for _, gate in ipairs(stationGates) do
		setGate(gate, math.abs(y - gate.y) < 30)
	end
end

local function closeGates()
	for _, gate in ipairs(stationGates) do setGate(gate, false) end
end

-- A station: a steel floor ring round the bore so you step out onto something,
-- a lamp, and the layer's name on a plate.
local function station(entry)
	local s = entry.stratum
	if stationBuilt[s.id] then return end
	stationBuilt[s.id] = true

	local deck  = stopYFor(entry.y)
	-- Just clear of the cage's own corners (half-width times root two), so the
	-- lip still overhangs the bore without the cage growing through it
	local inner = D.BoreRadius - 0.6
	local outer = D.LandingRadius - 3

	for i = 0, 7 do
		local a   = (i / 8) * math.pi * 2
		local mid = (inner + outer) / 2
		part("Landing", Vector3.new(outer - inner, 0.7, (outer + inner) * 0.42),
			CFrame.new(math.cos(a) * mid, deck - 0.35, math.sin(a) * mid)
				* CFrame.Angles(0, -a, 0),
			IRON, Enum.Material.DiamondPlate)
	end

	-- Hazard edging on the lip of the bore, the way the camp deck has it
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + math.pi / 8
		decor("Edge", Vector3.new(2.4, 0.22, 3.6),
			CFrame.new(math.cos(a) * (inner + 1.4), deck + 0.15, math.sin(a) * (inner + 1.4))
				* CFrame.Angles(0, -a, 0),
			HAZARD, Enum.Material.Metal)
	end

	local post = decor("StationPost", Vector3.new(1, 9, 1),
		CFrame.new(0, deck + 4.5, outer - 2), IRON_D, Enum.Material.Metal)

	local plate = decor("StationPlate", Vector3.new(13, 3.4, 0.4),
		CFrame.new(0, deck + 8, outer - 2.2), IRON_D, Enum.Material.Metal)

	local sign = Instance.new("SurfaceGui")
	sign.Face           = Enum.NormalId.Back
	sign.CanvasSize     = Vector2.new(390, 100)
	sign.LightInfluence = 0
	sign.Parent         = plate

	local text = Instance.new("TextLabel")
	text.Size                   = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text                   = string.upper(s.name)
	text.TextColor3             = s.color:Lerp(Color3.fromRGB(255, 255, 255), 0.55)
	text.TextScaled             = true
	text.Font                   = StrataConfig.UI.Head
	text.Parent                 = sign

	buildStationGate(deck)

	local glow = Instance.new("PointLight")
	glow.Color      = s.color:Lerp(Color3.fromRGB(255, 220, 180), 0.4)
	glow.Brightness = 2.4
	glow.Range      = 44
	glow.Shadows    = false
	glow.Parent     = post

	if StrataConfig.Debug then
		print(("[Descent] station at the %s, deck %.1f"):format(s.name, deck))
	end
end

local function furnish(toY)
	if toY >= furnishedTo then return end

	rails(furnishedTo, toY)

	local firstRib = math.floor(furnishedTo / D.RibEvery) * D.RibEvery
	for y = firstRib, toY, -D.RibEvery do
		if y < furnishedTo and y >= toY then rib(y) end
	end

	local firstLamp = math.floor(furnishedTo / D.LampEvery) * D.LampEvery
	local side = 1
	for y = firstLamp, toY, -D.LampEvery do
		if y < furnishedTo and y >= toY then shaftLamp(y, side) end
		side = -side
	end

	furnishedTo = toY

	for _, entry in ipairs(LANDINGS) do
		if entry.y - D.LandingHalf >= toY then station(entry) end
	end
end

-- Opens the new section of bore in terrain that has already been written. New
-- chunks pick the shape up from the voxel function on their own.
local function extendBore(toLandingY)
	local floor = toLandingY - D.Overrun
	local from  = _G.StrataBoreFloor or (LANDINGS[1].y - D.Overrun)

	if floor < from then
		_G.StrataBoreFloor = floor

		terrain:FillCylinder(
			CFrame.new(0, (from + floor) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			from - floor, D.BoreRadius, Enum.Material.Air)

		-- Two stacked cylinders rather than one, because the voxel function
		-- eases the station in at its roof and floor and a single flat disc
		-- would leave a step where written rock meets rock written later.
		for _, entry in ipairs(LANDINGS) do
			if entry.y < from and entry.y >= floor then
				terrain:FillCylinder(
					CFrame.new(0, entry.y, 0) * CFrame.Angles(0, 0, math.pi / 2),
					D.LandingHalf * 2, D.BoreRadius + 3, Enum.Material.Air)
				terrain:FillCylinder(
					CFrame.new(0, entry.y, 0) * CFrame.Angles(0, 0, math.pi / 2),
					D.LandingHalf, D.LandingRadius, Enum.Material.Air)
			end
		end
	end

	furnish(math.min(floor, furnishedTo))
end

-- The column has to exist before anybody falls through it, so the rock is
-- written ahead of the cage rather than around it.
local function prebuild(toY)
	task.spawn(function()
		local ensure = _G.StrataEnsureRegion
		if not ensure then return end
		for y = DECK_Y, toY, -56 do
			ensure(Vector3.new(0, y, 0), 56)
		end
		ensure(Vector3.new(0, toY, 0), 96)
	end)
end

-- ── The grate ────────────────────────────────────────────────────────────────
-- Two halves over the shaft mouth. They are the reason the bore can be a real
-- hole: with them shut the lodge floor is a floor, and they only come apart
-- when there is a cage to step into.

local grateHolds  = 0
local grateHalves = {}

local function buildGrate()
	local h = SURF.ShaftSize / 2

	for _, s in ipairs({ -1, 1 }) do
		local leaf = Instance.new("Model")
		leaf.Name   = "GrateHalf"
		leaf.Parent = shaftFolder

		local slab = part("Grate", Vector3.new(h, 0.7, h * 2),
			CFrame.new(s * h / 2, DECK_Y - 0.35, 0), IRON,
			Enum.Material.DiamondPlate, leaf)
		leaf.PrimaryPart = slab

		for i = -1, 1 do
			decor("Chevron", Vector3.new(h - 2.2, 0.18, 2),
				CFrame.new(s * h / 2, DECK_Y + 0.1, i * 7), HAZARD,
				Enum.Material.Metal, leaf)
		end

		decor("Lip", Vector3.new(0.7, 1.1, h * 2),
			CFrame.new(s * 0.35, DECK_Y - 0.2, 0), IRON_D,
			Enum.Material.Metal, leaf)

		table.insert(grateHalves, { model = leaf, side = s, slab = slab })
	end
end

local function moveGrate(open)
	local h = SURF.ShaftSize / 2

	for _, half in ipairs(grateHalves) do
		local to = open
			and CFrame.new(half.side * (h + 7), DECK_Y - 1.6, 0)
			or  CFrame.new(half.side * h / 2, DECK_Y - 0.35, 0)

		half.slab.CanCollide = not open

		-- Models have no tweenable CFrame, so the slab is tweened and the model
		-- is pivoted to follow it. One tween, and the chevrons come with it.
		local ghost = Instance.new("CFrameValue")
		ghost.Value = half.slab.CFrame
		ghost.Parent = half.model

		local conn
		conn = ghost.Changed:Connect(function(value)
			half.model:PivotTo(value)
		end)

		local tween = TweenService:Create(ghost, TweenInfo.new(D.GateTime,
			Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = to })
		tween.Completed:Connect(function()
			conn:Disconnect()
			ghost:Destroy()
		end)
		tween:Play()
	end
end

local function grate(open)
	local before = grateHolds
	grateHolds = math.max(grateHolds + (open and 1 or -1), 0)

	if before == 0 and grateHolds > 0 then
		moveGrate(true)
	elseif before > 0 and grateHolds == 0 then
		moveGrate(false)
	end
end

-- ── The cage ─────────────────────────────────────────────────────────────────
-- Built for one rider and thrown away after. Its pivot is the centre of the
-- floor slab, so the surface you stand on is half the slab above it.

local function cageGuts(model)
	local H, T = HALF, CAGE_H
	local deck = FLOOR_T / 2

	local floor = part("Floor", Vector3.new(H * 2, FLOOR_T, H * 2),
		CFrame.new(), IRON_D, Enum.Material.DiamondPlate, model)
	model.PrimaryPart = floor

	decor("Tread", Vector3.new(H * 2 - 1.2, 0.14, H * 2 - 1.2),
		CFrame.new(0, deck + 0.06, 0), IRON, Enum.Material.Metal, model)

	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			decor("Post", Vector3.new(0.8, T, 0.8),
				CFrame.new(sx * (H - 0.5), deck + T / 2, sz * (H - 0.5)),
				IRON_L, Enum.Material.Metal, model)
		end
	end

	part("Roof", Vector3.new(H * 2, 0.7, H * 2),
		CFrame.new(0, deck + T, 0), IRON_D, Enum.Material.DiamondPlate, model)

	-- Three walls of bars and one open face. The open face is where the gates
	-- are and where the gauge is, so there is exactly one thing to look at.
	local walls = {
		{ x = 0,  z = -1, rot = 0 },
		{ x = -1, z = 0,  rot = math.pi / 2 },
		{ x = 1,  z = 0,  rot = math.pi / 2 },
	}

	for _, wall in ipairs(walls) do
		local ax = wall.x * (H - 0.4)
		local az = wall.z * (H - 0.4)

		for i = -2, 2 do
			decor("Bar", Vector3.new(0.32, T - 1.4, 0.32),
				CFrame.new(ax, deck + T / 2, az)
					* CFrame.Angles(0, wall.rot, 0)
					* CFrame.new(i * 2.7, 0, 0),
				IRON_L, Enum.Material.Metal, model)
		end

		part("Kick", Vector3.new(H * 2 - 1, 2.6, 0.4),
			CFrame.new(ax, deck + 1.3, az) * CFrame.Angles(0, wall.rot, 0),
			IRON, Enum.Material.Metal, model)

		decor("Cap", Vector3.new(H * 2 - 1, 0.5, 0.4),
			CFrame.new(ax, deck + T - 0.9, az) * CFrame.Angles(0, wall.rot, 0),
			IRON, Enum.Material.Metal, model)
	end

	-- One light, no shadows: the shaft's own lamps do the rest of the work
	local bulb = decor("CageLamp", Vector3.new(2.6, 0.5, 2.6),
		CFrame.new(0, deck + T - 1.1, 0), LAMP, Enum.Material.Neon, model)

	local light = Instance.new("PointLight")
	light.Color      = LAMP
	light.Brightness = 2.6
	light.Range      = 26
	light.Shadows    = false
	light.Parent     = bulb

	-- The gate rises rather than sliding apart. A pair of leaves running
	-- sideways would have to end up somewhere, and the only somewhere is the
	-- rock two studs beyond the cage; straight up there is nothing but shaft.
	-- Only as tall as it has to be: the gauge board fills the top of the face,
	-- so a full-height gate would have nowhere to retract that was not already
	-- occupied, and would stand nine studs proud of the roof when open.
	local gateH = 7
	local lift  = gateH + 0.4
	local gates = {}

	local leaf = Instance.new("Model")
	leaf.Name   = "GateLeaf"
	leaf.Parent = model

	-- Built in the raised position and shut on the way down, so the rider sees
	-- the gate come across rather than finding themselves already caged
	local gateY = deck + 0.5 + gateH / 2 + lift

	local slab = part("Gate", Vector3.new(H * 2 - 1.1, gateH, 0.45),
		CFrame.new(0, gateY, H - 0.45), IRON, Enum.Material.DiamondPlate, leaf)
	leaf.PrimaryPart = slab

	for i = -2, 2 do
		decor("GateBar", Vector3.new(0.34, gateH - 1.4, 0.34),
			CFrame.new(i * 2.7, gateY, H - 0.78),
			IRON_L, Enum.Material.Metal, leaf)
	end
	decor("GateRail", Vector3.new(H * 2 - 1.1, 0.5, 0.7),
		CFrame.new(0, gateY - gateH / 2 + 0.25, H - 0.78),
		HAZARD, Enum.Material.Metal, leaf)

	-- The housing the gate retracts into, so a slab standing above the roof
	-- reads as mechanism rather than as a part in the wrong place
	decor("GateHousing", Vector3.new(H * 2 + 0.4, 2.6, 1.7),
		CFrame.new(0, deck + T + 0.9, H - 0.45), IRON_D, Enum.Material.Metal, model)

	table.insert(gates, { model = leaf, slab = slab, lift = lift, open = true })

	return floor, gates
end

-- The gauge, across the top of the open face and tipped down at the rider. The
-- meters on the very top of the pod: it is the only reason a sixteen-second
-- lift ride is worth standing through.
local function cageGauge(model)
	local deck = FLOOR_T / 2

	local board = decor("Gauge", Vector3.new(HALF * 2 - 0.6, 4.6, 0.45),
		CFrame.new(0, deck + CAGE_H - 3.1, HALF - 1.2)
			* CFrame.Angles(0, math.pi, 0)
			* CFrame.Angles(math.rad(16), 0, 0),
		IRON_D, Enum.Material.Metal, model)

	local gui = Instance.new("SurfaceGui")
	gui.Name           = "GaugeFace"
	gui.Face           = Enum.NormalId.Front
	gui.CanvasSize     = Vector2.new(520, 168)
	gui.LightInfluence = 0
	gui.Parent         = board

	local back = Instance.new("Frame")
	back.Size             = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(12, 11, 10)
	back.BorderSizePixel  = 0
	back.Parent           = gui

	local depth = Instance.new("TextLabel")
	depth.Name                   = "Depth"
	depth.Size                   = UDim2.new(1, -24, 0, 104)
	depth.Position               = UDim2.new(0, 12, 0, 6)
	depth.BackgroundTransparency = 1
	depth.Text                   = "0 m"
	depth.TextColor3             = Color3.fromRGB(255, 176, 74)
	depth.TextScaled             = true
	depth.Font                   = StrataConfig.UI.Number
	depth.Parent                 = back

	local where = Instance.new("TextLabel")
	where.Name                   = "Where"
	where.Size                   = UDim2.new(1, -24, 0, 46)
	where.Position               = UDim2.new(0, 12, 0, 112)
	where.BackgroundTransparency = 1
	where.Text                   = "SURFACE"
	where.TextColor3             = Color3.fromRGB(170, 162, 152)
	where.TextScaled             = true
	where.Font                   = StrataConfig.UI.Head
	where.Parent                 = back

	local light = Instance.new("PointLight")
	light.Color      = Color3.fromRGB(255, 176, 74)
	light.Brightness = 1.1
	light.Range      = 12
	light.Shadows    = false
	light.Parent     = board
end

local function buildCage(player)
	local model = Instance.new("Model")
	model.Name = "Cage_" .. player.UserId

	local floor, gates = cageGuts(model)
	cageGauge(model)

	model.Parent = root
	return model, floor, gates
end

-- Moved by offset rather than to an absolute height: the cage may be two
-- hundred studs from where it was built. Gates only ever move while the cage is
-- parked, so a tween can never fight the ride loop for the same CFrame.
local function moveGates(gates, open)
	for _, gate in ipairs(gates) do
		if gate.open ~= open then
			gate.open = open

			local to = gate.slab.CFrame
				+ Vector3.new(0, open and gate.lift or -gate.lift, 0)

			local ghost = Instance.new("CFrameValue")
			ghost.Value  = gate.slab.CFrame
			ghost.Parent = gate.model

			local conn
			conn = ghost.Changed:Connect(function(value)
				gate.model:PivotTo(value)
			end)

			local tween = TweenService:Create(ghost, TweenInfo.new(D.GateTime,
				Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = to })
			tween.Completed:Connect(function()
				conn:Disconnect()
				ghost:Destroy()
			end)
			tween:Play()
		end
	end
end

-- ── Riders ───────────────────────────────────────────────────────────────────

local riding = {}   -- [player] = true while they are in the shaft

local function rig(player)
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return hrp, hum
end

-- Anchoring the root and writing its CFrame every frame is the only way a
-- moving platform stops being a physics argument. The limbs follow through the
-- Motor6Ds, so the character still animates.
local function board(player)
	local hrp, hum = rig(player)
	if not hrp then return nil end

	hum.WalkSpeed  = 0
	hum.JumpHeight = 0
	hum.JumpPower  = 0
	hum.AutoRotate = false
	hrp.Anchored   = true

	local stand = hum.HipHeight + hrp.Size.Y * 0.5

	return function(deck)
		if hrp.Parent then
			local at = Vector3.new(0, deck + stand, -2.2)
			hrp.CFrame = CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
		end
	end
end

local function unboard(player)
	local hrp, hum = rig(player)
	if not hrp then return end
	hrp.Anchored   = false
	hum.AutoRotate = true
	hum.JumpHeight = 7.2
	hum.JumpPower  = 50
	hum.WalkSpeed  = PlayerState.WalkSpeed(player)
end

-- Standing in a cage that is about to be deleted is a long fall. Anyone still
-- inside is put out onto the floor beside it first.
local function stepOut(player, deck)
	local hrp = rig(player)
	if not hrp then return end

	local p = hrp.Position
	if math.abs(p.X) <= HALF and math.abs(p.Z) <= HALF and math.abs(p.Y - deck) < 9 then
		hrp.CFrame = CFrame.new(0, deck + 3.4, HALF + 6)
	end
end

local function dismiss(cage)
	task.spawn(function()
		for _, p in ipairs(cage:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.6)
		cage:Destroy()
	end)
end

-- ── The ride ─────────────────────────────────────────────────────────────────

local function travel(cage, place, fromY, toY, seconds, onFrame)
	local started = os.clock()

	while true do
		local a = math.clamp((os.clock() - started) / seconds, 0, 1)
		-- Smoothstep: a lift leans on you when it starts and again when it
		-- stops, and constant speed reads as a camera pan rather than a ride
		local e = a * a * (3 - 2 * a)
		local y = fromY + (toY - fromY) * e

		cage:PivotTo(CFrame.new(0, y, 0))
		if place then place(y + FLOOR_T / 2) end
		gatesNear(y)
		if onFrame then onFrame(y, a) end

		if a >= 1 then return end
		RunService.Heartbeat:Wait()
	end
end

local Descent = {}

function Descent.Riding(player)
	return riding[player] == true
end

-- Down. `onArrive` fires the moment the gates open, which is when the contract
-- clock is meant to start: the ride is not part of your time.
function Descent.Descend(player, stratum, contract, onArrive)
	if riding[player] then return false end
	if not rig(player) then return false end

	local landing = StrataConfig.LandingY(stratum)
	local stop    = stopYFor(landing)

	riding[player] = true
	extendBore(landing)
	prebuild(stop - 40)

	local ok, err = pcall(function()
		local seconds = StrataConfig.RideSeconds(DECK_Y, stop, false)

		grate(true)
		task.wait(D.GateTime * 0.75)

		local cage, _, gates = buildCage(player)
		cage:PivotTo(CFrame.new(0, DECK_Y - FLOOR_T / 2, 0))

		-- `hold` is how long the cage stands still with the gate coming down.
		-- The client runs the same easing curve locally so the ride is smooth
		-- rather than replicated in twenty-hertz steps, and it cannot do that
		-- without knowing when the fall actually begins.
		local hold = D.GateTime + 0.45

		descentStarted:FireClient(player, {
			mode      = "down",
			cage      = cage.Name,
			fromY     = DECK_Y,
			toY       = stop,
			seconds   = seconds,
			hold      = hold,
			layerId   = stratum.id,
			layerName = stratum.name,
			colour    = stratum.color,
			contract  = contract,
		})

		-- Boarding after the client has been told, not before: otherwise you
		-- spend a frame standing in a cage with the ordinary camera on it,
		-- which is the one frame that gives away the teleport.
		local place = board(player)
		if place then place(DECK_Y) end

		moveGates(gates, false)
		task.wait(hold)

		local shut = false
		travel(cage, place, DECK_Y - FLOOR_T / 2, stop - FLOOR_T / 2, seconds,
			function(y)
				if not shut and y < DECK_Y - 26 then
					shut = true
					grate(false)
				end
			end)
		if not shut then grate(false) end

		-- Shut the moment the cage is parked, not once it has faded. The
		-- cage floor is square and the station ring is round, so there is a
		-- three-stud gap between them on each axis — open, that is a hole
		-- you can step through on your way off the lift.
		closeGates()

		moveGates(gates, true)
		descentEnded:FireClient(player, { mode = "down", layerName = stratum.name })
		if onArrive then onArrive() end

		unboard(player)
		task.wait(D.Park)
		stepOut(player, stop)
		task.wait(0.25)
		dismiss(cage)
		closeGates()
	end)

	riding[player] = nil

	if not ok then
		warn("[Descent] ride down failed: " .. tostring(err))
		unboard(player)
		grate(false)
		closeGates()
		if onArrive then onArrive() end
	end
	return ok
end

-- Up, from wherever in the shaft it was called. `onTop` banks the run.
function Descent.Ascend(player, onTop)
	if riding[player] then return false end

	local hrp = rig(player)
	if not hrp then return false end

	local floorY = (_G.StrataBoreFloor or 0) + 8
	local from   = math.clamp(hrp.Position.Y - 3.2, floorY, DECK_Y - 20)

	-- Already at the top: a two-stud lift with a cutscene over it is worse
	-- than no cutscene at all.
	if DECK_Y - from < 24 then
		if onTop then onTop() end
		return true
	end

	riding[player] = true

	local ok, err = pcall(function()
		local seconds = StrataConfig.RideSeconds(from, DECK_Y, true)
		local stratum = StrataConfig.GetStratum(from)

		if _G.StrataEnsureRegion then
			_G.StrataEnsureRegion(Vector3.new(0, from, 0), 64)
		end
		terrain:FillCylinder(
			CFrame.new(0, from + 8, 0) * CFrame.Angles(0, 0, math.pi / 2),
			CAGE_H + 18, D.BoreRadius, Enum.Material.Air)

		local cage, _, gates = buildCage(player)
		cage:PivotTo(CFrame.new(0, from - FLOOR_T / 2, 0))

		local hold = D.GateTime + 0.35

		descentStarted:FireClient(player, {
			mode      = "up",
			cage      = cage.Name,
			fromY     = from,
			toY       = DECK_Y,
			seconds   = seconds,
			hold      = hold,
			layerId   = stratum and stratum.id or nil,
			layerName = "Surface",
			colour    = StrataConfig.UI.Ore,
		})

		local place = board(player)
		if place then place(from) end

		moveGates(gates, false)
		task.wait(hold)

		local opened = false
		travel(cage, place, from - FLOOR_T / 2, DECK_Y - FLOOR_T / 2, seconds,
			function(y)
				if not opened and y > DECK_Y - 46 then
					opened = true
					grate(true)
				end
			end)
		if not opened then grate(true) end

		closeGates()

		moveGates(gates, true)
		descentEnded:FireClient(player, { mode = "up", layerName = "Surface" })

		unboard(player)
		if onTop then onTop() end

		task.wait(D.Park)
		stepOut(player, DECK_Y)
		task.wait(0.3)
		grate(false)
		dismiss(cage)
		closeGates()
	end)

	riding[player] = nil

	if not ok then
		warn("[Descent] ride up failed: " .. tostring(err))
		unboard(player)
		grate(false)
		closeGates()
		if onTop then onTop() end
	end
	return ok
end

_G.StrataDescent = Descent

-- ── Keeping the shaft honest ─────────────────────────────────────────────────
-- The bore follows the crew. Somebody breaking into the Magma Vents for the
-- first time lengthens the shaft for everybody on the server, which makes it
-- the one piece of the world that records what has been found.

local function deepestFound()
	local best = LANDINGS[1]
	for _, player in ipairs(Players:GetPlayers()) do
		for _, entry in ipairs(LANDINGS) do
			if entry.y < best.y and PlayerState.Discovered(player, entry.stratum.id) then
				best = entry
			end
		end
	end
	return best
end

-- Leaving mid-ride leaves an anchored root on a cage that is about to be
-- deleted, and the character goes with the player. Nothing to unwind but the
-- flag and the cage.
Players.PlayerRemoving:Connect(function(player)
	riding[player] = nil
	local cage = root:FindFirstChild("Cage_" .. player.UserId)
	if cage then cage:Destroy() end
end)

task.spawn(function()
	repeat task.wait(0.25) until _G.StrataMineReady

	buildGrate()
	furnish(_G.StrataBoreFloor or (LANDINGS[1].y - D.Overrun))

	print(("[DescentService] online, bore to %d")
		:format(math.floor(_G.StrataBoreFloor or 0)))

	while true do
		task.wait(4)
		extendBore(deepestFound().y)
	end
end)
