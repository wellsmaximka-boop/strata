-- ── SaveService ──────────────────────────────────────────────────────────────
-- Progress that outlives the session. PlayerState stays the single source of
-- truth in memory; this only carries it to a DataStore and back.
--
-- Three moments write a save: joining reads one, an autosave runs on a timer,
-- and leaving or a server shutdown flushes the last of it. Nothing else in the
-- game needs to know saving exists.
--
-- In Studio a DataStore only works with "Allow Studio Access to API Services"
-- ticked under Game Settings > Security. Without it every call throws, so the
-- first failure disables saving for the session and says why once, rather than
-- filling the output with the same error every two minutes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService      = game:GetService("HttpService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local PlayerState  = require(script.Parent.PlayerState)

local CFG = StrataConfig.Save

local store   = nil
local enabled = CFG.Enabled == true

-- [player] = the JSON of the last thing written, so an unchanged state is not
-- written again. DataStore budgets are small and a quiet player costs nothing.
local lastWritten = {}

if enabled then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(("%s_v%d"):format(CFG.StoreName, CFG.Version))
	end)
	if ok then
		store = result
	else
		enabled = false
		warn("[SaveService] no DataStore available, progress will not be saved: " .. tostring(result))
	end
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- DataStore calls fail for reasons that pass on their own — throttling, a
-- hiccup between servers — so a few attempts with a pause between them turns
-- most failures into a slightly slower success.
local function attempt(label, fn)
	local lastErr
	for i = 1, (CFG.Retries or 3) do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		task.wait(0.6 * i)
	end
	warn(("[SaveService] %s failed: %s"):format(label, tostring(lastErr)))

	-- API access being switched off is not a hiccup, it is the answer for the
	-- whole session. Stop trying, and say what to tick.
	local message = tostring(lastErr):lower()
	if message:find("not allowed") or message:find("403") or message:find("publish") then
		enabled = false
		warn("[SaveService] saving switched off for this session. In Studio, tick "
			.. "Game Settings > Security > Allow Studio Access to API Services, and "
			.. "make sure the place has been published.")
	end

	return false, nil
end

-- ── Loading ──────────────────────────────────────────────────────────────────

local function load(player)
	PlayerState.Get(player)  -- make sure a blank state exists either way

	if enabled and store then
		local ok, data = attempt("load " .. player.Name, function()
			return store:GetAsync(keyFor(player))
		end)
		if ok and data then
			PlayerState.Restore(player, data)
			if StrataConfig.Debug then
				print(("[SaveService] loaded %s (%d credits, strength %d)")
					:format(player.Name, data.credits or 0, data.strength or 0))
			end
		elseif ok then
			if StrataConfig.Debug then
				print("[SaveService] no save for " .. player.Name .. ", starting fresh")
			end
		end
	end

	-- Debug grants go on top of whatever was loaded, and are stripped again
	-- when the state is serialised, so they never end up in the save file.
	PlayerState.GrantAll(player)
	lastWritten[player] = HttpService:JSONEncode(PlayerState.Serialize(player))
	PlayerState.Push(player)
end

-- ── Saving ───────────────────────────────────────────────────────────────────

-- `force` writes even if nothing changed, which is what a shutdown wants.
local function save(player, force)
	if not (enabled and store) then return end

	local okState, data = pcall(PlayerState.Serialize, player)
	if not okState then return end

	local encoded = HttpService:JSONEncode(data)
	if not force and lastWritten[player] == encoded then return end

	local ok = attempt("save " .. player.Name, function()
		store:SetAsync(keyFor(player), data)
	end)
	if ok then
		lastWritten[player] = encoded
		if StrataConfig.Debug then
			print(("[SaveService] saved %s (%d credits)"):format(player.Name, data.credits or 0))
		end
	end
end

-- ── Wiring ───────────────────────────────────────────────────────────────────

Players.PlayerAdded:Connect(load)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(load, player)  -- a script reload in Studio joins nobody
end

-- Synchronous, because PlayerState discards the state immediately afterwards
PlayerState.OnRelease(function(player)
	save(player, true)
	lastWritten[player] = nil
end)

task.spawn(function()
	local interval = math.max(CFG.AutosaveSec or 120, 30)
	while true do
		task.wait(interval)
		for _, player in ipairs(Players:GetPlayers()) do
			save(player, false)
		end
	end
end)

-- A shutdown gives about 30 seconds. Saving everyone in parallel fits easily.
game:BindToClose(function()
	if not (enabled and store) then return end

	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			save(player, true)
			pending -= 1
		end)
	end
	while pending > 0 do task.wait(0.1) end
end)

print(("[SaveService] online, saving %s"):format(enabled and "enabled" or "DISABLED"))
