local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Remotes      = require(script.Parent.Remotes)
local PlayerState  = require(script.Parent.PlayerState)

-- ── Expedition service ───────────────────────────────────────────────────────
-- A contract, a drop, a clock, and a walk back to the shaft.
--
-- The run itself lives in PlayerState, because the mine already asks that file
-- where mined ore should go. This service owns the things around it: what is on
-- the board, dropping you in, the clock running out, and getting you home.
--
-- Nothing here knows how ore is found. It only decides when the pack you are
-- carrying stops being raw.

local CFG      = StrataConfig.Expedition
local terrain  = workspace.Terrain

local contractBoard   = Remotes.Event("ContractBoard")    -- server → client: the board
local contractRequest = Remotes.Event("ContractRequest")  -- client → server: send me the board
local contractAccept  = Remotes.Event("ContractAccept")   -- client → server: contract id
local extractRequest  = Remotes.Event("ExtractRequest")   -- client → server
local runEnded        = Remotes.Event("RunEnded")         -- server → client: summary
local craftResult     = Remotes.Event("CraftResult")      -- reused for refusals

local seed = 0
task.spawn(function()
	repeat
		seed = _G.StrataSeed or 0
		if seed == 0 then task.wait(0.1) end
	until seed ~= 0
end)

-- ── The board ────────────────────────────────────────────────────────────────
-- Server-wide, so everyone is looking at the same work. Contracts for layers a
-- player has not reached are shown but locked — you can see that the deep work
-- exists, which is half the reason to go looking for it.

local sendBoard   -- forward declaration: refreshBoard calls it
local board       = {}
local nextId      = 1
local refreshedAt = 0

local function pickKind()
	local total = 0
	for _, k in ipairs(CFG.Kinds) do total += k.weight end

	local roll, run = math.random() * total, 0
	for _, k in ipairs(CFG.Kinds) do
		run += k.weight
		if roll <= run then return k.id end
	end
	return CFG.Kinds[1].id
end

-- Ore common enough in a layer to be worth asking for. Asking for a Cinderheart
-- would be asking for a miracle.
local function haulTargets(layerId)
	local out = {}
	for _, ore in ipairs(StrataConfig.Ores) do
		if not ore.archetype and (ore.strata[layerId] or 0) >= 12 then
			table.insert(out, ore)
		end
	end
	return out
end

local function makeContract(stratum)
	local spec = CFG.Layers[stratum.id]
	if not spec then return nil end

	local kind = pickKind()
	local c = {
		id        = nextId,
		layerId   = stratum.id,
		layerName = stratum.name,
		kind      = kind,
		duration  = spec.duration,
		payout    = spec.payout,
		bonus     = spec.bonus,
	}
	nextId += 1

	if kind == "haul" then
		local targets = haulTargets(stratum.id)
		if #targets == 0 then return nil end

		local ore = targets[math.random(1, #targets)]
		c.oreId = ore.id
		c.count = math.random(spec.haul[1], spec.haul[2])
		c.title = "HAUL"
		c.line  = ("bring back %d %s"):format(c.count, ore.name)

	elseif kind == "extract" then
		-- The deposits are placed in the dig site itself, one per hall and the
		-- far ones first, so this is really an instruction to walk the map.
		local band = StrataConfig.Site.Deposit.Count
		c.count = math.random(band[1], band[2])
		c.title = "EXTRACT"
		c.line  = ("break %d deposits and get out"):format(c.count)

	else
		local list = stratum.archetypes
		if not list or #list == 0 then return nil end

		local pick = list[math.random(1, #list)]
		local arch = StrataConfig.GetArchetype(pick.id)
		c.archetypeId = pick.id
		c.title = "SURVEY"
		c.line  = ("find a %s and mine it"):format(arch and arch.name or pick.id)
	end

	return c
end

local function refreshBoard()
	board = {}

	-- One contract per layer, so the board always shows the ladder rather than
	-- three jobs in the same place
	for _, stratum in ipairs(StrataConfig.Strata) do
		if CFG.Layers[stratum.id] then
			local c = makeContract(stratum)
			if c then table.insert(board, c) end
		end
	end

	refreshedAt = os.clock()

	for _, player in ipairs(Players:GetPlayers()) do
		sendBoard(player)
	end
end

-- Forward declared above, because refreshBoard calls it: a local defined here
-- and nowhere else would be invisible to the function above.
function sendBoard(player)
	local out = {}
	for i, c in ipairs(board) do
		local copy = table.clone(c)
		copy.locked = not PlayerState.Discovered(player, c.layerId)
		copy.index  = i
		table.insert(out, copy)
	end
	contractBoard:FireClient(player, out, math.max(
		CFG.RefreshSec - (os.clock() - refreshedAt), 0))
end

contractRequest.OnServerEvent:Connect(sendBoard)

-- ── Taking one ───────────────────────────────────────────────────────────────

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function refuse(player, why)
	craftResult:FireClient(player, false, why)
end

-- Where the pod puts you down when there is no pod. DescentService owns the
-- real journey; this is the fallback for a server where that file failed to
-- start, and it is deliberately the old behaviour rather than a refusal — a
-- contract that begins without its cutscene is a worse game, not a broken one.
local function dropInto(player, stratum, contract)
	local dest = Vector3.new(0, StrataConfig.LandingY(stratum), 0)

	if _G.StrataEnsureRegion then _G.StrataEnsureRegion(dest, 96) end
	terrain:FillBall(dest, 13, Enum.Material.Air)
	task.wait(0.1)

	PlayerState.StartRun(player, contract)

	local root = rootOf(player)
	if root then root.CFrame = CFrame.new(dest + Vector3.new(0, 3, 0)) end
end

contractAccept.OnServerEvent:Connect(function(player, index, tier)
	if typeof(index) ~= "number" then return end

	local base = board[index]
	if not base then return refuse(player, "that contract is gone") end
	if PlayerState.Run(player) then return refuse(player, "you are already out on one") end
	if _G.StrataDescent and _G.StrataDescent.Riding(player) then
		return refuse(player, "you are already in the shaft")
	end
	if not PlayerState.Discovered(player, base.layerId) then
		return refuse(player, "you have never been to the " .. base.layerName)
	end

	local root = rootOf(player)
	if not root then return end
	if root.Position.Y < StrataConfig.Mine.SurfaceY - 8 then
		return refuse(player, "sign for it at the camp")
	end

	local stratum
	for _, s in ipairs(StrataConfig.Strata) do
		if s.id == base.layerId then stratum = s end
	end
	if not stratum then return end

	-- The contract you signed for is the template scaled by the tier you picked.
	-- Scaled here rather than on the board, because the board is shared and the
	-- tier is yours.
	local diff     = StrataConfig.Difficulty(tier)
	local contract = table.clone(base)
	contract.difficulty     = diff.id
	contract.difficultyName = diff.name
	contract.duration = math.floor(base.duration * diff.time)
	contract.payout   = math.floor(base.payout * diff.pay)
	contract.bonus    = math.floor(base.bonus * diff.pay)
	if base.kind == "haul" and base.count then
		contract.count = math.max(math.floor(base.count * diff.quota), 1)
		local ore = StrataConfig.GetOre(base.oreId)
		contract.line = ("bring back %d %s"):format(contract.count, ore and ore.name or base.oreId)
	elseif base.kind == "extract" and base.count then
		-- Deposits scale far more gently than an ore quota. One more of them is
		-- another hall to walk to, not another minute of mining, so the tiers
		-- bite through the clock rather than through the count.
		contract.count = math.clamp(
			math.floor(base.count + (diff.quota - 1) * 2 + 0.5), 2, 6)
		contract.line = ("break %d deposits and get out"):format(contract.count)
	end

	if StrataConfig.Debug then
		print(("[Expedition] %s took %s in the %s on %s")
			:format(player.Name, contract.kind, contract.layerName, diff.name))
	end

	-- The map is cut while you are in the cage. A sixteen-second ride down to
	-- the Magma Vents is the loading screen for the dig site waiting at the
	-- bottom of it, which is the second reason the descent exists.
	if _G.StrataSiteBuilder then
		_G.StrataSiteBuilder.Open(player, contract, stratum, tier)
	end

	-- The clock starts when the gates open at the bottom, not when you sign.
	-- The ride is the game telling you how far down this is; charging you for
	-- it would make the deepest contract the one you are least able to finish.
	local descent = _G.StrataDescent
	if descent then
		task.spawn(descent.Descend, player, stratum, contract, function()
			PlayerState.StartRun(player, contract)
		end)
	else
		task.spawn(dropInto, player, stratum, contract)
	end
end)

-- ── Getting home ─────────────────────────────────────────────────────────────

local function atShaft(position)
	return position.X * position.X + position.Z * position.Z
		<= CFG.ExtractRange * CFG.ExtractRange
end

-- Only for people who are still underground. Extracting by cage puts you on
-- the lodge floor already, and teleporting someone who just walked out of the
-- lift is the one thing that would undo the ride they just sat through.
local function sendHome(player)
	local root = rootOf(player)
	if root and root.Position.Y < StrataConfig.Mine.SurfaceY then
		root.CFrame = CFrame.new(StrataConfig.Player.SpawnPosition)
	end
end

local function finish(player, success)
	-- Experience before the run is cleared, so the contract is still readable
	local run  = PlayerState.Run(player)
	local tier = 1
	if run then
		for i, d in ipairs(StrataConfig.Expedition.Difficulties) do
			if d.id == run.contract.difficulty then tier = i end
		end
	end
	local layerId = run and run.contract.layerId or nil
	local met     = run and PlayerState.ContractMet(player) or false

	local summary = PlayerState.EndRun(player, success)
	if not summary then return end

	local L = StrataConfig.Levels
	local earned = layerId and StrataConfig.RunXp(layerId, tier) or 0
	if not success then earned = math.floor(earned * L.FailShare) end
	if met then earned = math.floor(earned * (1 + L.ObjectiveBonus)) end

	local levels = PlayerState.AddXp(player, earned)
	summary.xp     = earned
	summary.levels = levels
	summary.level  = PlayerState.Get(player).level

	-- The lamps, the signs and the deposits go with the contract. The rock they
	-- were standing in stays: a worked-out dig site is a place you can come
	-- back to and mine on your own time, and the layer accumulating them is the
	-- mine having a history.
	if _G.StrataSiteBuilder then _G.StrataSiteBuilder.Close(player) end

	sendHome(player)
	runEnded:FireClient(player, summary)

	if StrataConfig.Debug then
		print(("[Expedition] %s %s, banked %d worth, paid %d")
			:format(player.Name, success and "extracted" or "ran out of time",
				summary.worth, summary.paid))
	end
end

extractRequest.OnServerEvent:Connect(function(player)
	local run = PlayerState.Run(player)
	if not run then return end
	if run.extracting then return end

	local root = rootOf(player)
	if not root then return end
	if not atShaft(root.Position) then
		return refuse(player, "get back to the shaft")
	end

	local descent = _G.StrataDescent
	if not descent then return finish(player, true) end

	-- The clock stops the moment the cage takes you, or a ride that is a
	-- quarter of a minute long would be able to fail a run you had already won.
	run.extracting = true

	task.spawn(descent.Ascend, player, function()
		finish(player, true)
	end)
end)

-- ── The clock ────────────────────────────────────────────────────────────────
-- Running out is not a death. The mine closes, you are pushed back to the
-- surface, and you keep a fraction of what you were carrying.

task.spawn(function()
	while true do
		task.wait(0.5)

		for _, player in ipairs(Players:GetPlayers()) do
			local run = PlayerState.Run(player)
			if run and not run.extracting and os.clock() >= run.endsAt then
				finish(player, false)
			end
		end

		if os.clock() - refreshedAt >= CFG.RefreshSec then
			refreshBoard()
		end
	end
end)

-- A run does not survive leaving, and nothing of it is banked: see
-- PlayerState.AbandonRun for why.
Players.PlayerRemoving:Connect(function(player)
	local run = PlayerState.Run(player)
	if run then PlayerState.AbandonRun(player) end
	if _G.StrataSiteBuilder then _G.StrataSiteBuilder.Close(player) end
end)

-- In Studio the player is already in the game before this script finishes,
-- so PlayerAdded never fires for them and the board never arrives. Anyone
-- already here gets one too.
local function greet(player)
	task.wait(1)
	sendBoard(player)
end

Players.PlayerAdded:Connect(greet)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(greet, player) end

refreshBoard()
print("[ExpeditionService] online, " .. #board .. " contracts")
