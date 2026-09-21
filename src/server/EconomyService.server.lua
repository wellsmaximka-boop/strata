local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local GearConfig   = require(ReplicatedStorage:WaitForChild("GearConfig"))
local Remotes      = require(script.Parent.Remotes)
local PlayerState  = require(script.Parent.PlayerState)

-- ── Economy service ──────────────────────────────────────────────────────────
-- The surface half of the loop: sell what you hauled, forge what you need,
-- ride the lift back down. Everything here is server-authoritative; the client
-- only ever asks.

local terrain = workspace.Terrain

local soldEvent    = Remotes.Event("Sold")
local sellRequest  = Remotes.Event("SellRequest")
local craftRequest = Remotes.Event("CraftRequest")
local craftResult  = Remotes.Event("CraftResult")
local equipRequest = Remotes.Event("EquipRequest")
local liftRequest  = Remotes.Event("LiftRequest")
local zoneChanged  = Remotes.Event("ZoneChanged")

-- ── Surface structures ───────────────────────────────────────────────────────

local SELL_POS   = StrataConfig.Surface.SellPos
local CRAFT_POS  = StrataConfig.Surface.CraftPos
local LIFT_POS   = StrataConfig.Surface.LiftPos
local PICK_POS   = StrataConfig.Surface.PickPos
local RUNS_POS   = StrataConfig.Surface.RunsPos
local ZONE_RANGE = StrataConfig.Surface.ZoneRange

-- Horizontal distance, with a generous vertical band. A plain 3D distance
-- shrank the zone for taller avatars, whose root part sits higher off the
-- floor, until standing inside the ring no longer counted as being in it.
local function near(a, b, range)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz <= range * range and math.abs(a.Y - b.Y) <= 10
end

-- ── Station rings ────────────────────────────────────────────────────────────
-- A ring on the ground in front of each station marks where to stand, the way
-- simulator hubs do it, instead of square slabs that read as loose floor tiles.
-- The ring is painted by a SurfaceGui on an invisible plate: a circular frame
-- with a stroke gives a crisp edge with no geometry at all. Pads still take
-- their colour from the zone table, so each ring matches its building.
local RING_D = StrataConfig.Surface.RingSize   -- ZoneRange is half of this

local function makePad(name, position, zone, text)
	local at = Vector3.new(position.X, StrataConfig.Surface.PlatformY + 0.22, position.Z)

	local plate = Instance.new("Part")
	plate.Name         = name
	plate.Size         = Vector3.new(RING_D, 0.1, RING_D)
	plate.Transparency = 1
	plate.Anchored     = true
	plate.CanCollide   = false
	plate.CanQuery     = false
	plate.CanTouch     = false
	plate.CastShadow   = false

	-- Face the plate away from the shaft, then turn it a quarter. A Top-face
	-- SurfaceGui runs its text along the part's front axis rather than across
	-- it, so without the turn the word read sideways to someone walking out.
	local outward = Vector3.new(at.X, 0, at.Z)
	plate.CFrame = outward.Magnitude > 0.1
		and CFrame.lookAt(at, at + outward.Unit) * CFrame.Angles(0, -math.pi / 2, 0)
		or  CFrame.new(at)
	plate.Parent = workspace

	local gui = Instance.new("SurfaceGui")
	gui.Name           = "RingGui"
	gui.Face           = Enum.NormalId.Top
	gui.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud  = 50
	gui.LightInfluence = 0
	gui.Parent         = plate

	-- A faint fill so the whole circle reads as a zone, not just its edge.
	-- Scaled to 0.9 because a UIStroke draws outside its frame, and anything
	-- past the plate's edge gets clipped.
	local fill = Instance.new("Frame")
	fill.Name                   = "Fill"
	fill.Size                   = UDim2.fromScale(0.86, 0.86)
	fill.AnchorPoint            = Vector2.new(0.5, 0.5)
	fill.Position               = UDim2.fromScale(0.5, 0.5)
	fill.BackgroundColor3       = zone.accent
	fill.BackgroundTransparency = 0.74
	fill.BorderSizePixel        = 0
	fill.Parent                 = gui
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

	local ring = Instance.new("UIStroke")
	ring.Name         = "Ring"
	ring.Color        = zone.accent
	ring.Thickness    = 26
	ring.Transparency = 0.06
	ring.Parent       = fill

	-- A wider, fainter halo outside it. Two rings read as a target and catch
	-- the eye from across the hall; one thick ring just reads as a stain.
	local halo = Instance.new("Frame")
	halo.Name                   = "Halo"
	halo.Size                   = UDim2.fromScale(0.99, 0.99)
	halo.AnchorPoint            = Vector2.new(0.5, 0.5)
	halo.Position               = UDim2.fromScale(0.5, 0.5)
	halo.BackgroundTransparency = 1
	halo.BorderSizePixel        = 0
	halo.ZIndex                 = 0
	halo.Parent                 = gui
	Instance.new("UICorner", halo).CornerRadius = UDim.new(0.5, 0)

	local haloRing = Instance.new("UIStroke")
	haloRing.Name         = "Ring"
	haloRing.Color        = zone.accent
	haloRing.Thickness    = 9
	haloRing.Transparency = 0.55
	haloRing.Parent       = halo

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(0.62, 0.2)
	label.AnchorPoint            = Vector2.new(0.5, 0.5)
	label.Position               = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text                   = text
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextTransparency       = 0
	label.TextScaled             = true
	label.Font                   = StrataConfig.UI.Head
	label.ZIndex                 = 3
	label.Parent                 = gui

	-- Painted on a wooden floor, white text needs an outline or it disappears
	-- into the boards
	local outline = Instance.new("UIStroke", label)
	outline.Color     = Color3.fromRGB(16, 12, 10)
	outline.Thickness = 7
	outline.Transparency = 0.25

	local shade = Instance.new("UIStroke", label)
	shade.Color     = zone.accent:Lerp(Color3.new(0, 0, 0), 0.65)
	shade.Thickness = 3

	-- A soft wash of the zone's colour, far dimmer than the old pad light
	local light = Instance.new("PointLight")
	light.Color      = zone.accent
	light.Brightness = 0.5
	light.Range      = 16
	light.Shadows    = false
	light.Parent     = plate

	return plate
end

local Z = StrataConfig.Zones
makePad("SellPad",  SELL_POS,  Z.sell,  "SELL")
makePad("CraftPad", CRAFT_POS, Z.craft, "FORGE")
makePad("LiftPad",  LIFT_POS,  Z.lift,  "LIFT")
makePad("PickPad",  PICK_POS,  Z.pickaxe, "PICKS")
makePad("RunsPad",  RUNS_POS,  Z.runs,    "CONTRACTS")

-- ── Selling ──────────────────────────────────────────────────────────────────
-- Selling happens from the Depot menu, which the ring opens. It used to be
-- automatic on stepping in, which emptied the pack before you could see it.
-- The Depot is still the only place selling works: the walk back with a full
-- pack is the loop, and selling from anywhere would delete it.
sellRequest.OnServerEvent:Connect(function(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not near(root.Position, SELL_POS, ZONE_RANGE * 1.5) then
		craftResult:FireClient(player, false, "return to the depot to sell")
		return
	end

	local earned = PlayerState.SellAll(player)
	if earned <= 0 then
		craftResult:FireClient(player, false, "nothing to sell")
		return
	end
	soldEvent:FireClient(player, earned)
end)

-- ── Crafting ─────────────────────────────────────────────────────────────────

craftRequest.OnServerEvent:Connect(function(player, gearId)
	if typeof(gearId) ~= "string" then return end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Picks are bought at the pick works, everything else at the forge
	local gear    = GearConfig.Get(gearId)
	local station = (gear and gear.slot == "pickaxe") and PICK_POS or CRAFT_POS
	local where   = (gear and gear.slot == "pickaxe") and "pick works" or "forge"

	if not near(root.Position, station, ZONE_RANGE * 1.5) then
		craftResult:FireClient(player, false, "go to the " .. where)
		return
	end

	local ok, detail = PlayerState.Craft(player, gearId)
	craftResult:FireClient(player, ok, detail)
end)

-- ── Equipping ────────────────────────────────────────────────────────────────
-- Unlike buying, this works anywhere. Swapping armour at depth is part of the
-- point: you change what you can survive without walking home.
equipRequest.OnServerEvent:Connect(function(player, gearId, slot)
	if gearId == nil and typeof(slot) == "string" then
		PlayerState.Unequip(player, slot)
		return
	end
	if typeof(gearId) ~= "string" then return end

	local ok, detail = PlayerState.Equip(player, gearId)
	if not ok then
		craftResult:FireClient(player, false, detail)
	end
end)

-- ── Lift ─────────────────────────────────────────────────────────────────────
-- Bores a pocket at the destination before dropping you in, so the lift can
-- never deposit a player inside solid rock.

liftRequest.OnServerEvent:Connect(function(player, stopIndex)
	if typeof(stopIndex) ~= "number" then return end

	local stop = GearConfig.LiftStops[stopIndex]
	if not stop then return end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if not near(root.Position, LIFT_POS, ZONE_RANGE * 1.5) then return end

	-- You cannot ride to somewhere you have never stood
	if not PlayerState.Discovered(player, stop.layerId or "") and stop.y < StrataConfig.Mine.SurfaceY then
		craftResult:FireClient(player, false, stop.name .. " has not been found yet — dig to it first")
		return
	end

	if stop.requires then
		for kind, level in pairs(stop.requires) do
			if PlayerState.Resistance(player, kind) < level then
				craftResult:FireClient(player, false, stop.name .. " needs " .. string.upper(kind) .. " gear")
				return
			end
		end
	end

	-- Surface goes to the camp, not to the middle of the open shaft
	if stop.y >= StrataConfig.Mine.SurfaceY then
		root.CFrame = CFrame.new(StrataConfig.Player.SpawnPosition)
		return
	end

	local dest = Vector3.new(0, stop.y, 0)

	-- Deep rock is written as players walk towards it, and the lift skips the
	-- walk. Build the destination before anyone is standing in it, or they
	-- arrive inside a world that has not been made yet.
	if _G.StrataEnsureRegion then _G.StrataEnsureRegion(dest, 96) end

	terrain:FillBall(dest, 11, Enum.Material.Air)
	task.wait(0.1)
	root.CFrame = CFrame.new(dest + Vector3.new(0, 3, 0))
end)

-- ── Zone tracking ────────────────────────────────────────────────────────────
-- Tells the client which pad it is standing on so the UI can open itself.

local currentZone = {}
local depthDirty  = {}   -- [player] = true when they have gone deeper than before

local function zoneFor(position)
	if near(position, SELL_POS, ZONE_RANGE) then return "sell"  end
	if near(position, CRAFT_POS, ZONE_RANGE) then return "craft" end
	if near(position, LIFT_POS, ZONE_RANGE) then return "lift"  end
	if near(position, PICK_POS, ZONE_RANGE) then return "pickaxe" end
	if near(position, RUNS_POS, ZONE_RANGE) then return "runs" end
	return nil
end

task.spawn(function()
	while task.wait(0.2) do
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then

				local zone = zoneFor(root.Position)
				if zone ~= currentZone[player] then
					currentZone[player] = zone
					zoneChanged:FireClient(player, zone)
				end

				-- Standing in a layer is what unlocks it as a lift destination
				-- and as a place contracts can send you. Dig to discover.
				local layer = StrataConfig.GetStratum(root.Position.Y)
				if root.Position.Y <= layer.top then
					PlayerState.Discover(player, layer.id)
				end

				-- A new personal best has to reach the client, or the depth
				-- chart never lights up the layer you just walked into. Marked
				-- here and pushed on a slower loop, so a descent is not one
				-- push per tick.
				if PlayerState.RecordDepth(player, root.Position.Y) then
					depthDirty[player] = true
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	PlayerState.Get(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		PlayerState.Push(player)
	end)
end)


-- ── Depth replication ────────────────────────────────────────────────────────
-- Going deeper changes what the chart knows, and the chart lives on the client.
-- Batched to once a second: descending changes the number constantly, and the
-- whole state goes down the wire on every push.

task.spawn(function()
	while true do
		task.wait(1)
		for player in pairs(depthDirty) do
			depthDirty[player] = nil
			if player.Parent then PlayerState.Push(player) end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	currentZone[player] = nil
	depthDirty[player]  = nil
end)

print("[EconomyService] online")
