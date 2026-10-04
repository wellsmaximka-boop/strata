local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Remotes      = require(script.Parent.Remotes)

-- ── Grapple, the authority half ──────────────────────────────────────────────
-- Deliberately small, and worth saying why.
--
-- Roblox hands a player's own character to their client: the client simulates
-- it and the server takes what it is told. So a server that re-ran the pull, or
-- checked where somebody ended up, would be writing a second opinion it has no
-- means to enforce. Pretending otherwise is how you get a hook that fights the
-- player across half a second of latency and feels like string.
--
-- What the server genuinely owns is the *budget*: whether you have a hook
-- ready, and when the next one is. That cannot live on the client, because then
-- it is a number the client can pick. So it lives here, and the client mirrors
-- it for the UI and gets corrected the moment the two disagree.
--
-- The rope is drawn locally by whoever fired it. In a run you are alone, so
-- replicating a rope nobody is there to see would be cost without a viewer.

local CFG = StrataConfig.Grapple

local grappleFire  = Remotes.Event("GrappleFire")    -- client → server: anchor
local grappleState = Remotes.Event("GrappleState")   -- server → client: ready, wait

-- [player] = { readyAt }
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

grappleFire.OnServerEvent:Connect(function(player, anchor)
	if typeof(anchor) ~= "Vector3" then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Above ground there is nothing worth reaching and a hook that works on the
	-- camp deck is a way out of the claim
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

	local hook = hookFor(player)
	if os.clock() < hook.readyAt then
		push(player)   -- correct a client that thinks it is ready and is not
		return
	end

	hook.readyAt = os.clock() + CFG.Cooldown
	push(player)
end)

-- The client draws its own countdown off `wait` and does not need a tick from
-- here; this is the correction that lands when the cooldown is actually up, so
-- a client whose timer drifted still turns green at the right moment.
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local hook = hooks[player]
			if hook and hook.readyAt ~= 0 and now >= hook.readyAt then
				hook.readyAt = 0
				push(player)
			end
		end
	end
end)

local function greet(player)
	hooks[player] = { readyAt = 0 }
	task.wait(2)
	push(player)
end

Players.PlayerAdded:Connect(greet)
Players.PlayerRemoving:Connect(function(player) hooks[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(greet, player) end

print("[GrappleService] online")
