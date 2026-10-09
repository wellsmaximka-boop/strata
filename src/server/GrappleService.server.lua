local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Remotes      = require(script.Parent.Remotes)

-- ── Grapple, the authority half ──────────────────────────────────────────────
-- Deliberately small, and worth saying why.
--
-- Roblox hands a player's own character to their client: the client simulates
-- it and the server takes what it is told. So a server that re-ran the swing,
-- or checked where somebody ended up, would be writing a second opinion it has
-- no means to enforce. Pretending otherwise is how you get a hook that fights
-- the player across half a second of latency and feels like string.
--
-- What the server genuinely owns is three things:
--
--   The budget. Whether you have a hook ready and when the next one is. That
--   cannot live on the client, because then it is a number the client picks.
--
--   The claim. Whether there is actually rock where the client says there is,
--   and whether it is close enough to be reachable. The client's raycast is
--   the one that decides how aiming feels, so it has to happen there; this is
--   the second opinion that stops a hand-written remote anchoring to open air
--   on the far side of a wall.
--
--   The broadcast. Every other player needs to see the cable, and this is the
--   only place that knows who is on one. It sends an anchor once per hook and
--   once more when the hook is dropped. The swinging player's character
--   position already replicates by itself, so each client redraws the cable
--   locally every frame off those two facts and the rope costs no per-frame
--   network traffic at all.

local CFG = StrataConfig.Grapple

local grappleFire  = Remotes.Event("GrappleFire")    -- client → server: anchor, normal
local grappleLet   = Remotes.Event("GrappleLet")     -- client → server: released
local grappleState = Remotes.Event("GrappleState")   -- server → client: ready, wait
local grappleRope  = Remotes.Event("GrappleRope")    -- server → everyone: who, where

-- [player] = { readyAt, anchor, firedAt }
local hooks = {}

local function hookFor(player)
	local hook = hooks[player]
	if not hook then
		hook = { readyAt = 0 }
		hooks[player] = hook
	end
	return hook
end

local function push(player)
	local hook = hookFor(player)
	grappleState:FireClient(player, {
		-- Seconds remaining rather than a timestamp: the client's clock is not
		-- the server's, and a countdown is the only thing it has to draw.
		wait  = math.max(hook.readyAt - os.clock(), 0),
		total = CFG.Cooldown,
	})
end

-- Dropping a rope, from wherever the news came from: the player let go, they
-- died, they left, or they have been hanging long enough that something is
-- wrong. Everyone who can see them needs to stop drawing the cable.
local function drop(player)
	local hook = hooks[player]
	if not hook or not hook.anchor then return end
	hook.anchor = nil
	grappleRope:FireAllClients({ id = player.UserId })
end

-- ── Validation ───────────────────────────────────────────────────────────────

local probe = RaycastParams.new()
probe.FilterType  = Enum.RaycastFilterType.Exclude
probe.IgnoreWater = true

local function refreshProbe()
	local ignore = {}
	for _, name in ipairs(CFG.Surfaces.Ignore) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	-- You cannot hook a person, so nobody's character counts as rock.
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	probe.FilterDescendantsInstances = ignore
end

-- Vector3 arrives off the wire and can be anything, including a NaN that would
-- poison every comparison it touches and quietly pass every bound below.
local function sane(v)
	if typeof(v) ~= "Vector3" then return false end
	local m = v.Magnitude
	return m == m and m < 1e6
end

-- Is there actually something solid where the hook claims to be? Probed along
-- the surface normal the client reported, because anchors land on ceilings and
-- walls as often as floors and a downward check would reject most of them.
local function solidAt(position, normal)
	refreshProbe()
	local hit = workspace:Raycast(position + normal * 3, -normal * 6, probe)
	return hit ~= nil
end

-- ── Firing ───────────────────────────────────────────────────────────────────

grappleFire.OnServerEvent:Connect(function(player, anchor, normal)
	if not sane(anchor) or not sane(normal) then return end
	if normal.Magnitude < 0.1 then return end
	normal = normal.Unit

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Above ground there is nothing worth reaching, and a hook that works on
	-- the camp deck is a way out of the claim.
	if root.Position.Y > StrataConfig.Mine.SurfaceY - CFG.MinDepth then
		push(player)
		return
	end

	-- Range is checked against the position the server last heard, which lags
	-- the client's by whatever the ping is. The slack is deliberate: a hook
	-- refused for being four studs long is a bug report, and the worst a
	-- generous bound allows is a slightly longer hook than the UI promised.
	if (anchor - root.Position).Magnitude > CFG.Range * 1.25 then
		push(player)
		return
	end

	if not solidAt(anchor, normal) then
		push(player)
		return
	end

	local hook = hookFor(player)
	if os.clock() < hook.readyAt then
		push(player)   -- correct a client that thinks it is ready and is not
		return
	end

	-- A new hook supersedes an old one rather than stacking with it, so a
	-- client that never sent its release cannot leave a cable on screen.
	drop(player)

	hook.readyAt = os.clock() + CFG.Cooldown
	hook.anchor  = anchor
	hook.firedAt = os.clock()
	push(player)

	grappleRope:FireAllClients({ id = player.UserId, anchor = anchor })
end)

grappleLet.OnServerEvent:Connect(function(player)
	drop(player)
end)

-- ── Housekeeping ─────────────────────────────────────────────────────────────

-- The client draws its own countdown off `wait` and does not need a tick from
-- here; this is the correction that lands when the cooldown is actually up, so
-- a client whose timer drifted still turns green at the right moment. The same
-- pass clears ropes whose release never arrived.
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local hook = hooks[player]
			if hook then
				if hook.readyAt ~= 0 and now >= hook.readyAt then
					hook.readyAt = 0
					push(player)
				end
				-- Two seconds past the client's own limit, so this only ever
				-- fires for a client that stopped talking.
				if hook.anchor and now - (hook.firedAt or now) > CFG.HangLimit + 2 then
					drop(player)
				end
			end
		end
	end
end)

local function greet(player)
	hooks[player] = { readyAt = 0 }

	player.CharacterRemoving:Connect(function() drop(player) end)

	task.wait(2)
	push(player)

	-- So somebody who joins mid-run sees the ropes that are already in the air
	-- rather than a set of players flying with nothing attached to them.
	for other, hook in pairs(hooks) do
		if other ~= player and hook.anchor then
			grappleRope:FireClient(player, { id = other.UserId, anchor = hook.anchor })
		end
	end
end

Players.PlayerAdded:Connect(greet)
Players.PlayerRemoving:Connect(function(player)
	drop(player)
	hooks[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(greet, player) end

print("[GrappleService] online")
