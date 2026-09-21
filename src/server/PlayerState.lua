-- ── PlayerState ──────────────────────────────────────────────────────────────
-- Every per-player number lives here so the mine, the economy and the hazards
-- all read the same truth. Session-only for now; a DataStore drops in behind
-- Load/Save without any caller changing.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local GearConfig   = require(ReplicatedStorage:WaitForChild("GearConfig"))
local Remotes      = require(script.Parent.Remotes)

local PlayerState = {}

-- Fired whenever a player's state is pushed, so server systems like worn armour
-- can react without polling.
PlayerState.Changed = Instance.new("BindableEvent")

-- Called, synchronously, just before a leaving player's state is thrown away,
-- so it can be written to disk first. A BindableEvent will not do here: those
-- run deferred, and the state would already be gone by the time one fired.
local releaseHandlers = {}

function PlayerState.OnRelease(fn)
	table.insert(releaseHandlers, fn)
end

local BASE_WALK_SPEED = 16

local stateChanged = Remotes.Event("StateChanged")
local states = {}

local function blank()
	return {
		inventory = {},   -- [oreId] = count
		carried   = 0,
		credits   = 0,
		owned     = {},   -- [gearId] = true, everything usable right now
		earned    = {},   -- [gearId] = true, only what was actually bought
		debug     = { credits = 0, ore = {} },  -- handed out by GrantAll, never saved
		equipped  = {},   -- [slot] = gearId, armour only
		strength  = StrataConfig.Player.StartingStrength,
		-- Rises only with prestige, never with mining. See StrataConfig.PackLight.
		lightLevel = 1,
		xp        = 0,
		level     = 1,
		run       = nil,  -- set while on an expedition; see the Expeditions section
		discovered = { Topsoil = true },  -- layers you have stood in
		deepest   = 0,
	}
end

function PlayerState.Get(player)
	local s = states[player]
	if not s then
		s = blank()
		states[player] = s
	end
	return s
end

-- ── Derived values ───────────────────────────────────────────────────────────
-- Gear grants are summed rather than replaced, so tiers stack naturally.

-- Tools count as soon as you own them. Armour only counts while it is worn —
-- that distinction is the whole point of the equip screen.
local function grantsTotal(player, key)
	local s = PlayerState.Get(player)
	local total = 0

	-- Pickaxes are excluded: owning three of them should not stack three
	-- powers. The best one is picked separately in PickaxePower.
	for gearId in pairs(s.owned) do
		local gear = GearConfig.Get(gearId)
		if gear and gear.grants[key]
			and not GearConfig.IsArmorSlot(gear.slot)
			and gear.slot ~= "pickaxe" then
			total += gear.grants[key]
		end
	end

	for _, gearId in pairs(s.equipped) do
		local gear = GearConfig.Get(gearId)
		if gear and gear.grants[key] then
			total += gear.grants[key]
		end
	end

	-- Set bonuses land only when every piece is worn. Resistance lives here and
	-- nowhere else, so a biome is always opened by a complete set.
	for _, progress in ipairs(GearConfig.SetProgress(s.equipped)) do
		if progress.complete and progress.set.bonus[key] then
			total += progress.set.bonus[key]
		end
	end

	return total
end

function PlayerState.Capacity(player)
	return StrataConfig.Player.BackpackSlots + grantsTotal(player, "capacity")
end

function PlayerState.Resistance(player, kind)
	return grantsTotal(player, kind)
end

function PlayerState.ScanRadius(player)
	return StrataConfig.Scanner.Radius + grantsTotal(player, "scanRadius")
end

function PlayerState.ScanCooldown(player)
	return math.max(StrataConfig.Scanner.Cooldown + grantsTotal(player, "scanCooldown"), 0.4)
end

function PlayerState.LightRange(player)
	local spec = StrataConfig.PackLightLevel(PlayerState.Get(player).lightLevel)
	return grantsTotal(player, "light") + (spec.grants.light or 0)
end

function PlayerState.WalkSpeed(player)
	local spec = StrataConfig.PackLightLevel(PlayerState.Get(player).lightLevel)
	return BASE_WALK_SPEED + grantsTotal(player, "walkSpeed") + (spec.grants.walkSpeed or 0)
end

-- ── Mining ───────────────────────────────────────────────────────────────────
-- The best pickaxe owned, never a sum. Buying a better one retires the old.
function PlayerState.BestPickaxe(player)
	local s = PlayerState.Get(player)
	local best, bestPower = nil, 0

	for gearId in pairs(s.owned) do
		local gear = GearConfig.Get(gearId)
		if gear and gear.slot == "pickaxe" then
			local power = gear.grants.power or 0
			if power > bestPower then
				best, bestPower = gear, power
			end
		end
	end
	return best, bestPower
end

-- What decides whether rock breaks: what you have earned, what you are
-- holding, and what your armour set adds on top.
function PlayerState.MiningPower(player)
	local s = PlayerState.Get(player)
	local _, pickPower = PlayerState.BestPickaxe(player)
	return s.strength + pickPower + grantsTotal(player, "power")
end

function PlayerState.DigCooldown(player)
	local pick = select(1, PlayerState.BestPickaxe(player))
	local pickBonus = (pick and pick.grants.digCooldown) or 0
	return math.max(
		StrataConfig.Dig.Cooldown + grantsTotal(player, "digCooldown") + pickBonus,
		0.08
	)
end

function PlayerState.AddStrength(player, amount)
	local s = PlayerState.Get(player)
	s.strength += amount
	return s.strength
end

function PlayerState.Owns(player, gearId)
	return PlayerState.Get(player).owned[gearId] == true
end

-- ── Mutations ────────────────────────────────────────────────────────────────

-- On a run, ore is raw: it goes to the manifest and only becomes yours when you
-- extract. Off a run it lands in the pack as it always did.
function PlayerState.AddOre(player, oreId)
	local s   = PlayerState.Get(player)
	local run = s.run

	if run then
		if run.carried >= PlayerState.Capacity(player) then return false end
		run.manifest[oreId] = (run.manifest[oreId] or 0) + 1
		run.carried += 1
		return true
	end

	if s.carried >= PlayerState.Capacity(player) then return false end
	s.inventory[oreId] = (s.inventory[oreId] or 0) + 1
	s.carried += 1
	return true
end

-- Loose rock goes in the inventory but not in `carried`. It sells, but it never
-- uses a pack slot.
function PlayerState.AddRock(player, rockId, amount)
	local s   = PlayerState.Get(player)
	local run = s.run
	local bag = run and run.manifest or s.inventory
	bag[rockId] = (bag[rockId] or 0) + (amount or 1)
end

-- What the whole pack would fetch at the Depot right now
function PlayerState.PackWorth(player)
	local s   = PlayerState.Get(player)
	local bag = s.run and s.run.manifest or s.inventory
	local total = 0
	for id, count in pairs(bag) do
		local m = StrataConfig.GetMaterial(id)
		total += (m and m.value or 0) * count
	end
	return total
end
-- Empties the pack into credits. Returns the amount earned and the manifest.
function PlayerState.SellAll(player)
	local s = PlayerState.Get(player)
	-- Rock doesn't count toward `carried`, so zero slots used no longer means
	-- an empty pack
	if s.run then return 0, nil end   -- raw ore is not yours to sell yet
	if next(s.inventory) == nil then return 0, nil end

	local earned   = 0
	local manifest = {}
	for id, count in pairs(s.inventory) do
		local m = StrataConfig.GetMaterial(id)
		earned += (m and m.value or 0) * count
		manifest[id] = count
	end

	s.inventory = {}
	-- The handed-out ore went with it, so the tally of what was handed out is
	-- settled too. Without this, ore mined after a sale would be cancelled out
	-- by a debt that was already paid.
	s.debug.ore = {}
	s.carried   = 0
	s.credits  += earned

	if StrataConfig.Debug then
		print(("[Economy] %s sold for %d, credits now %d"):format(player.Name, earned, s.credits))
	end

	PlayerState.Push(player)
	return earned, manifest
end

-- Buys gear if it is affordable, consuming credits and ore. Returns ok, reason.
function PlayerState.Craft(player, gearId)
	local gear = GearConfig.Get(gearId)
	if not gear then return false, "no such gear" end

	local s = PlayerState.Get(player)
	if s.owned[gearId] then return false, "already owned" end
	if s.credits < (gear.cost.credits or 0) then return false, "not enough credits" end

	for oreId, needed in pairs(gear.cost.ore or {}) do
		if (s.inventory[oreId] or 0) < needed then
			local ore = StrataConfig.GetOre(oreId)
			return false, ("need %d %s"):format(needed, ore and ore.name or oreId)
		end
	end

	local spent = gear.cost.credits or 0
	s.credits -= spent
	-- Same for handed-out money: once it is spent it is no longer owed back, so
	-- what you earn afterwards saves in full.
	s.debug.credits = math.max(s.debug.credits - spent, 0)
	for oreId, needed in pairs(gear.cost.ore or {}) do
		s.inventory[oreId] -= needed
		-- Spent handed-out ore stops counting as handed out
		local given = s.debug.ore[oreId]
		if given then s.debug.ore[oreId] = math.max(given - needed, 0) end
		s.carried = math.max(s.carried - needed, 0)
		if s.inventory[oreId] <= 0 then s.inventory[oreId] = nil end
	end
	s.owned[gearId]  = true
	s.earned[gearId] = true  -- bought, so it survives a restart

	-- Buying armour for an empty slot equips it straight away. Nobody wants to
	-- buy a helmet and then wonder why nothing changed.
	if GearConfig.IsArmorSlot(gear.slot) and not s.equipped[gear.slot] then
		s.equipped[gear.slot] = gearId
	end

	PlayerState.Push(player)
	return true, gear.name
end

-- ── Equipping ────────────────────────────────────────────────────────────────

function PlayerState.Equip(player, gearId)
	local gear = GearConfig.Get(gearId)
	if not gear then return false, "no such gear" end
	if not GearConfig.IsArmorSlot(gear.slot) then return false, "that is not armour" end

	local s = PlayerState.Get(player)
	if not s.owned[gearId] then return false, "you do not own that" end

	s.equipped[gear.slot] = gearId
	PlayerState.Push(player)
	return true, gear.name
end

function PlayerState.Unequip(player, slot)
	if not GearConfig.IsArmorSlot(slot) then return false end

	local s = PlayerState.Get(player)
	if not s.equipped[slot] then return false end

	s.equipped[slot] = nil
	PlayerState.Push(player)
	return true
end

function PlayerState.RecordDepth(player, worldY)
	local s = PlayerState.Get(player)
	local depth = math.floor(-worldY)
	if depth > s.deepest then
		s.deepest = depth
		return true
	end
	return false
end

-- ── Saving and loading ───────────────────────────────────────────────────────
-- What goes to disk is deliberately narrow: what you own, what you are wearing,
-- your money, your pack and how far you have got. Everything else is derived.

-- Debug grants are stripped here rather than at grant time, so a test bench can
-- be switched off without leaving anything behind in a save file.
function PlayerState.Serialize(player)
	local s = PlayerState.Get(player)

	local inventory = {}
	for id, count in pairs(s.inventory) do
		local real = count - (s.debug.ore[id] or 0)
		if real > 0 then inventory[id] = real end
	end

	local owned = {}
	for id in pairs(s.earned) do owned[id] = true end

	-- Never save a slot filled by something the player does not really own
	local equipped = {}
	for slot, id in pairs(s.equipped) do
		if owned[id] then equipped[slot] = id end
	end

	return {
		v         = 1,
		inventory = inventory,
		credits   = math.max(s.credits - s.debug.credits, 0),
		owned     = owned,
		equipped  = equipped,
		strength  = s.strength,
		xp        = s.xp,
		level     = s.level,
		lightLevel = s.lightLevel or 1,
		deepest   = s.deepest,
		discovered = s.discovered,
	}
end

-- Applies a loaded save. Written defensively: a save from an older build is
-- missing fields, and gear that has since been renamed simply no longer exists.
function PlayerState.Restore(player, data)
	if type(data) ~= "table" then return false end
	local s = blank()

	s.credits  = tonumber(data.credits) or 0
	s.strength = tonumber(data.strength) or StrataConfig.Player.StartingStrength
	s.deepest  = tonumber(data.deepest) or 0
	s.lightLevel = math.max(tonumber(data.lightLevel) or 1, 1)
	s.xp    = math.max(tonumber(data.xp) or 0, 0)
	s.level = math.clamp(tonumber(data.level) or 1, 1, StrataConfig.Levels.Max)

	for id in pairs(type(data.discovered) == "table" and data.discovered or {}) do
		s.discovered[id] = true
	end

	for id, count in pairs(type(data.inventory) == "table" and data.inventory or {}) do
		if StrataConfig.GetMaterial(id) and tonumber(count) then
			s.inventory[id] = count
			if StrataConfig.GetOre(id) then s.carried += count end
		end
	end

	for id in pairs(type(data.owned) == "table" and data.owned or {}) do
		if GearConfig.Get(id) then
			s.owned[id]  = true
			s.earned[id] = true
		end
	end

	for slot, id in pairs(type(data.equipped) == "table" and data.equipped or {}) do
		if s.owned[id] and GearConfig.IsArmorSlot(slot) then
			s.equipped[slot] = id
		end
	end

	states[player] = s
	return true
end

-- ── Test bench ───────────────────────────────────────────────────────────────
-- One of everything, so a newly built item can be worn and swung immediately.
-- Tracked in s.debug so none of it reaches the save file.
function PlayerState.GrantAll(player)
	local cfg = StrataConfig.GrantAll
	if not (cfg and cfg.Enabled) then return end

	local s = PlayerState.Get(player)

	if cfg.Own then
		for _, gear in ipairs(GearConfig.Gear) do
			s.owned[gear.id] = true
		end
	end

	-- Wear the highest tier owned in each armour slot, so the newest set is what
	-- shows up on the character without visiting the armour screen first. This
	-- happens before the ore is handed out, because worn armour is what decides
	-- how big the pack is.
	if cfg.Equip then
		for _, slot in ipairs(GearConfig.ArmorSlots) do
			local best
			for _, gear in ipairs(GearConfig.ForSlot(slot.id)) do
				if s.owned[gear.id] then best = gear end
			end
			if best then s.equipped[slot.id] = best.id end
		end
	end

	-- A sample of every ore, sized to leave most of the pack empty. Handing out
	-- a flat count per ore overfilled it the moment the ore table grew, and a
	-- pack over capacity cannot take what you mine — which looks from the inside
	-- like ore that refuses to break.
	local share = math.floor(PlayerState.Capacity(player) * 0.4 / #StrataConfig.Ores)
	local each  = math.min(cfg.OreEach or 0, math.max(share, 0))

	for _, ore in ipairs(StrataConfig.Ores) do
		local have  = s.inventory[ore.id] or 0
		local topUp = math.max(each - have, 0)
		if topUp > 0 and s.carried + topUp <= PlayerState.Capacity(player) then
			s.inventory[ore.id] = have + topUp
			s.carried += topUp
			s.debug.ore[ore.id] = (s.debug.ore[ore.id] or 0) + topUp
		end
	end

	local topUp = math.max((cfg.Credits or 0) - s.credits, 0)
	s.credits += topUp
	s.debug.credits += topUp
end

-- ── Experience ───────────────────────────────────────────────────────────────
-- Levels come from finishing runs. Nothing hangs off them mechanically yet —
-- they are the record of how many times you have gone down and come back, and
-- what prestige will read when it arrives.

-- Returns the levels gained, so a caller can announce them.
function PlayerState.AddXp(player, amount)
	if not amount or amount <= 0 then return 0 end

	local s = PlayerState.Get(player)
	s.xp += math.floor(amount)

	local gained = 0
	while s.level < StrataConfig.Levels.Max do
		local need = StrataConfig.XpForLevel(s.level)
		if s.xp < need then break end
		s.xp -= need
		s.level += 1
		gained += 1
	end

	-- At the cap experience stops accumulating rather than piling up invisibly
	if s.level >= StrataConfig.Levels.Max then s.xp = 0 end

	PlayerState.Push(player)
	return gained
end

-- ── Expeditions ──────────────────────────────────────────────────────────────
-- A run is the only time ore is not immediately yours. Everything mined goes to
-- a manifest instead of the pack, and the manifest banks when you extract. Fail
-- and a fraction of it survives.
--
-- It lives here rather than in its own service because the mine already asks
-- PlayerState where ore should go, and one source of truth is the whole point
-- of this file.

function PlayerState.Run(player)
	return PlayerState.Get(player).run
end

function PlayerState.StartRun(player, contract)
	local s = PlayerState.Get(player)
	if s.run then return false, "already on a run" end

	s.run = {
		contract = contract,
		startedAt = os.clock(),
		endsAt   = os.clock() + contract.duration,
		manifest = {},
		carried  = 0,
		found    = {},   -- [archetypeId] = true, for survey contracts
	}

	PlayerState.Push(player)
	return true
end

-- Banks the manifest and clears the run. Returns a summary for the client.
function PlayerState.EndRun(player, success)
	local s   = PlayerState.Get(player)
	local run = s.run
	if not run then return nil end

	local keep = success and 1 or StrataConfig.Expedition.FailKeep
	local banked, worth = {}, 0

	for id, count in pairs(run.manifest) do
		local take = success and count or math.floor(count * keep)
		if take > 0 then
			s.inventory[id] = (s.inventory[id] or 0) + take
			banked[id] = take

			local material = StrataConfig.GetMaterial(id)
			worth += (material and material.value or 0) * take
			-- Only ore takes a pack slot; rock never has
			if StrataConfig.GetOre(id) then s.carried += take end
		end
	end

	local paid = 0
	if success then
		paid = (run.contract.payout or 0)
		if PlayerState.ContractMet(player) then paid += (run.contract.bonus or 0) end
		s.credits += paid
	end

	local summary = {
		success   = success,
		contract  = run.contract,
		banked    = banked,
		worth     = worth,
		paid      = paid,
		objective = PlayerState.ContractMet(player),
		kept      = keep,
	}

	s.run = nil
	PlayerState.Push(player)
	return summary
end

-- Has the contract's objective been satisfied by what is in the manifest?
function PlayerState.ContractMet(player)
	local run = PlayerState.Get(player).run
	if not run then return false end

	local c = run.contract
	if c.kind == "haul" then
		return (run.manifest[c.oreId] or 0) >= c.count
	elseif c.kind == "survey" then
		return run.found[c.archetypeId] == true
	elseif c.kind == "extract" then
		return (run.deposits or 0) >= (c.count or 1)
	end
	return false
end

-- How far along the objective is, as text the client can show without knowing
-- anything about contract types.
function PlayerState.ContractProgress(player)
	local run = PlayerState.Get(player).run
	if not run then return nil end

	local c = run.contract
	if c.kind == "haul" then
		local ore = StrataConfig.GetOre(c.oreId)
		return ("%d / %d %s"):format(run.manifest[c.oreId] or 0, c.count,
			ore and ore.name or c.oreId)
	elseif c.kind == "survey" then
		local arch = StrataConfig.GetArchetype(c.archetypeId)
		return (run.found[c.archetypeId] and "found " or "find ")
			.. (arch and arch.name or c.archetypeId)
	elseif c.kind == "extract" then
		return ("%d / %d deposits cleared"):format(run.deposits or 0, c.count or 1)
	end
	return ""
end

-- Walking into a room is what a survey contract is asking for
function PlayerState.NoteRoom(player, archetypeId)
	local run = PlayerState.Get(player).run
	if run and archetypeId then run.found[archetypeId] = true end
end


-- Breaking one of a contract's deposits. Counted rather than listed: which one
-- you took is not interesting, only how many are left.
function PlayerState.NoteDeposit(player)
	local run = PlayerState.Get(player).run
	if not run then return end
	run.deposits = (run.deposits or 0) + 1
	PlayerState.Push(player)
end

-- Leaving mid-run loses the manifest outright. Banking a fraction here would
-- depend on whether this handler happens to run before the save does, and a
-- rule that depends on connection order is not a rule. Logging out is also the
-- one failure a player fully controls, so it should not pay.
function PlayerState.AbandonRun(player)
	local s = PlayerState.Get(player)
	s.run = nil
end

-- ── Discovery ────────────────────────────────────────────────────────────────
-- A layer becomes a lift destination once you have stood in it, never before.
-- Dig to discover, lift to return.

function PlayerState.Discovered(player, layerId)
	return PlayerState.Get(player).discovered[layerId] == true
end

function PlayerState.Discover(player, layerId)
	local s = PlayerState.Get(player)
	if s.discovered[layerId] then return false end
	s.discovered[layerId] = true

	-- Standing somewhere new for the first time is worth something on its own
	PlayerState.AddXp(player, StrataConfig.Levels.Discovery)
	PlayerState.Push(player)
	return true
end

-- ── Replication ──────────────────────────────────────────────────────────────

function PlayerState.Push(player)
	local s = PlayerState.Get(player)

	-- Walk speed is a gear grant, so it is applied wherever gear changes
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = PlayerState.WalkSpeed(player)
	end

	local bestPick = PlayerState.BestPickaxe(player)
	PlayerState.Changed:Fire(player)

	stateChanged:FireClient(player, {
		-- On a run the pack shows the manifest, so every screen that reads the
		-- inventory keeps working without knowing runs exist
		inventory  = s.run and s.run.manifest or s.inventory,
		carried    = s.run and s.run.carried or s.carried,
		capacity   = PlayerState.Capacity(player),
		credits    = s.credits,
		owned      = s.owned,
		equipped   = s.equipped,
		deepest    = s.deepest,
		discovered = s.discovered,
		run        = s.run and {
			contract  = s.run.contract,
			remaining = math.max(s.run.endsAt - os.clock(), 0),
			progress  = PlayerState.ContractProgress(player),
			met       = PlayerState.ContractMet(player),
		} or nil,
		lightRange  = PlayerState.LightRange(player),
		walkSpeed   = PlayerState.WalkSpeed(player),
		digCooldown = PlayerState.DigCooldown(player),
		strength    = s.strength,
		xp          = s.xp,
		level       = s.level,
		xpNeeded    = StrataConfig.XpForLevel(s.level),
		lightLevel  = s.lightLevel or 1,
		miningPower = PlayerState.MiningPower(player),
		pickaxe     = bestPick and bestPick.id or nil,
		worth       = PlayerState.PackWorth(player),
		resistances = { heat = PlayerState.Resistance(player, "heat") },
	})
end

Players.PlayerRemoving:Connect(function(player)
	-- Give anything holding on to this state a chance to save it first
	for _, fn in ipairs(releaseHandlers) do
		local ok, err = pcall(fn, player)
		if not ok then warn("[PlayerState] release handler failed: " .. tostring(err)) end
	end
	states[player] = nil
end)

return PlayerState
