local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local StrataConfig    = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local NodeGrid        = require(ReplicatedStorage:WaitForChild("NodeGrid"))
local OreModelBuilder = require(ReplicatedStorage:WaitForChild("OreModelBuilder"))
local Remotes         = require(script.Parent.Remotes)
local PlayerState     = require(script.Parent.PlayerState)

-- ── Mine service ─────────────────────────────────────────────────────────────
-- Server-authoritative digging, scanning, node exposure and collection.
-- The client asks; the server decides. Every request is distance- and
-- rate-checked, because whoever owns the carve owns the economy.

local terrain = workspace.Terrain

-- ── Remotes ──────────────────────────────────────────────────────────────────
local digRequest   = Remotes.Event("DigRequest")      -- client → server: Vector3
local digResult    = Remotes.Event("DigResult")       -- server → client: position, value
local scanRequest  = Remotes.Event("ScanRequest")     -- client → server
local scanResult   = Remotes.Event("ScanResult")      -- server → client: table | nil
local oreCollected = Remotes.Event("OreCollected")    -- server → client: oreId, value, position
local digBlocked   = Remotes.Event("DigBlocked")      -- server → client: stratum, needed, have
local mineNode     = Remotes.Event("MineNode")        -- client → server: the node model
local nodeHit      = Remotes.Event("NodeHit")         -- server → client: model, damage, broke
local packFull     = Remotes.Event("PackFull")        -- server → client: oreId

-- Ore nodes live in their own folder so the dig raycast can include them
-- without also picking up the camp, the character, or the debris.
local oreFolder = Instance.new("Folder")
oreFolder.Name   = "OreNodes"
oreFolder.Parent = workspace

-- Terrain only, for dropping a freshly uncovered node onto the floor
local settleParams = RaycastParams.new()
settleParams.FilterType = Enum.RaycastFilterType.Include
settleParams.FilterDescendantsInstances = { workspace.Terrain }
settleParams.IgnoreWater = true
local surfaceCall  = Remotes.Event("ReturnToSurface") -- client → server

-- ── State ────────────────────────────────────────────────────────────────────
local seed = 0
repeat
	seed = _G.StrataSeed or 0
	if seed == 0 then task.wait(0.1) end
until seed ~= 0

local minedCells  = {}   -- [cellKey] = true, once collected it never comes back
local exposed     = {}   -- [cellKey] = { model = Model, node = node }
local exposedCount = 0

-- Rate-limiting only. Everything the player *owns* lives in PlayerState.
local state = {}

local function getState(player)
	local s = state[player]
	if not s then
		s = { lastDig = 0, lastScan = 0 }
		state[player] = s
	end
	return s
end

-- ── Terrain queries ──────────────────────────────────────────────────────────

-- True when the voxel containing `pos` is solid.
local function isSolidAt(pos)
	local region = Region3.new(
		pos - Vector3.new(2, 2, 2),
		pos + Vector3.new(2, 2, 2)
	):ExpandToGrid(4)

	local ok, _, occupancies = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	if not ok or not occupancies then return false end

	for x = 1, #occupancies do
		for y = 1, #occupancies[x] do
			for z = 1, #occupancies[x][y] do
				if occupancies[x][y][z] > 0.5 then return true end
			end
		end
	end
	return false
end

-- A few studs of rock are left untouchable at the rim and the floor, so nobody
-- can tunnel out through the side of the island or the bottom of the world.
local RIM = 6

local function inMineBounds(pos)
	local m = StrataConfig.Mine
	return pos.X * pos.X + pos.Z * pos.Z <= (m.Radius - RIM) ^ 2
	   and pos.Y <= m.CeilingY
	   and pos.Y >= m.FloorY + RIM
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- ── Digging ──────────────────────────────────────────────────────────────────

local function reject(player, reason)
	if StrataConfig.Debug then
		warn(("[MineService] dig rejected for %s: %s"):format(player.Name, reason))
	end
end

-- A contract is for one layer. While you are on one the seams above and below
-- it will not break, which is the answer to "what stops somebody taking a
-- Topsoil job and digging straight down into the Magma Vents on it".
--
-- It is a rule about the contract, not about the rock: off a contract the whole
-- mine is yours to dig through exactly as it always was.
local function pastTheSeam(player, y)
	local run = PlayerState.Run(player)
	if not run then return false end

	local top, bottom = StrataConfig.LayerBounds(run.contract.layerId)
	local slack = StrataConfig.Site.Seam.Margin
	if y <= top + slack and y >= bottom - slack then return false end

	return true, run.contract.layerName or run.contract.layerId
end

digRequest.OnServerEvent:Connect(function(player, target)
	if typeof(target) ~= "Vector3" then return end

	-- Nothing gets mined out of a moving cage. The camera is scripted during a
	-- descent, so a held mouse button would otherwise chew a stripe out of the
	-- shaft wall all the way down.
	if _G.StrataDescent and _G.StrataDescent.Riding(player) then return end

	local s   = getState(player)
	local now = os.clock()
	if now - s.lastDig < PlayerState.DigCooldown(player) then return end

	local root = rootOf(player)
	if not root then return end

	local dist = (root.Position - target).Magnitude
	if dist > StrataConfig.Dig.MaxDistance then
		return reject(player, ("out of range (%.1f > %d)"):format(dist, StrataConfig.Dig.MaxDistance))
	end
	if not inMineBounds(target) then
		return reject(player, "outside mine bounds " .. tostring(target))
	end
	if not isSolidAt(target) then
		return reject(player, "no solid terrain at " .. tostring(target))
	end

	local blocked, layerName = pastTheSeam(player, target.Y)
	if blocked then
		digBlocked:FireClient(player, layerName)
		return reject(player, "past the seam of the " .. layerName)
	end


	-- Strength gate: rock you are not strong enough for simply does not break.
	-- This is the mining half of progression, separate from surviving the heat.
	local stratum = StrataConfig.GetStratum(target.Y)
	local power   = PlayerState.MiningPower(player)
	if power < stratum.hardness then
		digBlocked:FireClient(player, stratum.name, stratum.hardness, power)
		return reject(player, ("too hard: %s needs %d, have %d")
			:format(stratum.name, stratum.hardness, power))
	end

	s.lastDig = now
	terrain:FillBall(target, StrataConfig.Dig.Radius, Enum.Material.Air)

	-- Strength is earned by mining, so the activity is the progression.
	-- The gain rides along on digResult rather than triggering a full state
	-- push: digs fire several times a second, and replicating the whole
	-- inventory that often is pure waste. The client adds it locally, and any
	-- economy action resyncs from the authoritative value.
	local gained = stratum.strengthGain or 1
	PlayerState.AddStrength(player, gained)

	-- The rock you broke goes in the pack as saleable loose rock
	local rock = StrataConfig.Rocks[stratum.id]
	if rock then PlayerState.AddRock(player, rock.id) end

	digResult:FireClient(player, target, stratum.valuePerDig, stratum.id, gained)
end)

-- ── Scanning ─────────────────────────────────────────────────────────────────
-- Returns a direction and a distance *band*. Never coordinates — the hunt is
-- the gameplay, and a waypoint marker would delete it.

local function classify(ore)
	if ore.value >= 200 then return "ANOMALOUS" end
	if ore.value >= 50  then return "STRONG"    end
	return "ORDINARY"
end

scanRequest.OnServerEvent:Connect(function(player)
	local s   = getState(player)
	local now = os.clock()
	if now - s.lastScan < PlayerState.ScanCooldown(player) then return end
	s.lastScan = now

	local root = rootOf(player)
	if not root then return end
	local origin = root.Position
	local radius = PlayerState.ScanRadius(player)

	local best, bestScore, bestDist = nil, -1, 0
	NodeGrid.ForEachNear(origin, radius, seed, function(node)
		if minedCells[node.key] then return end
		local dist  = (node.position - origin).Magnitude
		local score = node.ore.value / math.max(dist, 4)
		if score > bestScore then
			best, bestScore, bestDist = node, score, dist
		end
	end)

	if not best then
		scanResult:FireClient(player, nil)
		return
	end

	local flat = (best.position - origin)
	scanResult:FireClient(player, {
		direction = flat.Unit,
		band      = StrataConfig.DistanceBand(bestDist),
		class     = classify(best.ore),
		strength  = math.clamp(1 - bestDist / radius, 0, 1),
	})
end)

-- ── Node exposure ────────────────────────────────────────────────────────────
-- A node materialises when the rock around it is gone — whether the player dug
-- it out or wandered into a natural cave. One ReadVoxels per player per tick
-- covers the whole neighbourhood.

local function exposeNear(player)
	local root = rootOf(player)
	if not root then return end

	local s = getState(player)
	if exposedCount >= StrataConfig.Nodes.MaxExposedPerPlayer * math.max(#Players:GetPlayers(), 1) then
		return
	end

	local r      = StrataConfig.Nodes.ExposeRadius
	local origin = root.Position
	local region = Region3.new(
		origin - Vector3.new(r, r, r),
		origin + Vector3.new(r, r, r)
	):ExpandToGrid(4)

	local ok, _, occupancies = pcall(function()
		return terrain:ReadVoxels(region, 4)
	end)
	if not ok or not occupancies then return end

	local regionOrigin = region.CFrame.Position - region.Size / 2

	NodeGrid.ForEachNear(origin, r, seed, function(node)
		if minedCells[node.key] or exposed[node.key] then return end

		local rel = node.position - regionOrigin
		local ix  = math.floor(rel.X / 4) + 1
		local iy  = math.floor(rel.Y / 4) + 1
		local iz  = math.floor(rel.Z / 4) + 1

		local col = occupancies[ix]
		local row = col and col[iy]
		local occ = row and row[iz]
		if not occ or occ > 0.5 then return end  -- still buried

		-- Drop it onto whatever rock is under it. A node uncovered by a dig sits
		-- in the middle of the hole otherwise, which reads as floating.
		local settled = node.position
		local down = workspace:Raycast(
			node.position + Vector3.new(0, 3, 0),
			Vector3.new(0, -11, 0),
			settleParams
		)
		if down then
			settled = down.Position + Vector3.new(0, 1.0, 0)
			node.position = settled   -- keep range checks and the pickup in sync
		end

		local model = OreModelBuilder.Build(node.ore, math.floor(node.position.X + node.position.Z))
		model:SetAttribute("CellKey", node.key)
		model:PivotTo(CFrame.new(settled))
		model.Parent = oreFolder

		exposed[node.key] = { model = model, node = node }
		exposedCount += 1

		if StrataConfig.Debug then
			print(("[MineService] exposed %s at %s (%d showing)")
				:format(node.ore.id, tostring(node.position), exposedCount))
		end
	end)
end

-- ── Collection ───────────────────────────────────────────────────────────────

local function collect(player, key, entry)
	-- A full pack leaves the ore in the ground for the walk back
	if not PlayerState.AddOre(player, entry.node.ore.id) then return false end

	minedCells[key] = true
	exposed[key]    = nil
	exposedCount   -= 1
	entry.model:Destroy()

	oreCollected:FireClient(player, entry.node.ore.id, entry.node.ore.value, entry.node.position)
	PlayerState.Push(player)
	return true
end

-- ── Breaking a node ──────────────────────────────────────────────────────────
-- Ore is mined, not walked into. Each swing removes mining power from the
-- node's health, so a stronger player clears a vein in fewer hits and a weak
-- one still gets there eventually — a soft gate rather than a wall.

mineNode.OnServerEvent:Connect(function(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if model.Parent ~= oreFolder then return end

	local key   = model:GetAttribute("CellKey")
	local entry = key and exposed[key]
	if not entry or entry.model ~= model then return end

	local s   = getState(player)
	local now = os.clock()
	if now - s.lastDig < PlayerState.DigCooldown(player) then return end

	local root = rootOf(player)
	if not root then return end
	if (root.Position - entry.node.position).Magnitude > StrataConfig.Dig.MaxDistance then
		return reject(player, "node out of range")
	end
	s.lastDig = now

	local damage = math.max(PlayerState.MiningPower(player), 1)
	local hp     = (model:GetAttribute("HP") or 0) - damage

	-- The bar stays hidden until the node has actually been struck
	local bar = model.PrimaryPart and model.PrimaryPart:FindFirstChild("OreBar")
	if bar then bar.Enabled = true end

	if hp > 0 then
		model:SetAttribute("HP", hp)
		nodeHit:FireClient(player, model, damage, false)
		return
	end

	-- Broken, but it only leaves the ground if there is room for it. A silent
	-- failure here reads as ore that cannot be broken at all, so the node is
	-- left standing on its last point of health and the player is told why.
	if not collect(player, key, entry) then
		model:SetAttribute("HP", 1)
		packFull:FireClient(player, entry.node.ore.id)
		return reject(player, "pack full")
	end

	nodeHit:FireClient(player, model, damage, true)
end)

local function despawnFar()
	local players = Players:GetPlayers()
	local limit   = StrataConfig.Nodes.ExposeRadius * 1.8

	for key, entry in pairs(exposed) do
		local keep = false
		for _, p in ipairs(players) do
			local root = rootOf(p)
			if root and (root.Position - entry.node.position).Magnitude <= limit then
				keep = true
				break
			end
		end
		if not keep then
			entry.model:Destroy()
			exposed[key] = nil
			exposedCount -= 1
		end
	end
end

-- ── Loops ────────────────────────────────────────────────────────────────────

task.spawn(function()
	while task.wait(0.45) do
		for _, player in ipairs(Players:GetPlayers()) do
			exposeNear(player)
		end
		despawnFar()
	end
end)

-- Nodes are no longer picked up by walking near them; they are broken with the
-- pickaxe. The proximity collector that used to live here is gone deliberately.

-- ── Safety: never let a player be trapped in their own hole ──────────────────

surfaceCall.OnServerEvent:Connect(function(player)
	local root = rootOf(player)
	if not root then return end
	root.CFrame = CFrame.new(StrataConfig.Player.SpawnPosition)
end)

-- ── Lifecycle ────────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
end)

print("[MineService] online, seed " .. seed)
