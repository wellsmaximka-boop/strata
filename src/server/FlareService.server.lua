local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local Remotes      = require(script.Parent.Remotes)

-- ── Flares ───────────────────────────────────────────────────────────────────
-- Three of them, one back every half minute, thrown by hand.
--
-- They exist because the halls got big. A pack light follows you around and
-- lights whatever you are already looking at, which is exactly the wrong tool
-- for a two-hundred-stud room with pits in the floor and alcoves round the
-- walls. A flare is light you *place*, and placing it is a decision: into the
-- pit, across the hall, or back down the gallery you came in by so you can find
-- it again with a full pack and forty seconds left.
--
-- The server owns the charges and the physics. The client owns the aiming, and
-- the aiming is most of what makes it feel like anything.

local CFG = StrataConfig.Flare

local flareThrow = Remotes.Event("FlareThrow")   -- client → server: direction, power
local flareState = Remotes.Event("FlareState")   -- server → client: charges left, timer

local folder = Instance.new("Folder")
folder.Name   = "Flares"
folder.Parent = workspace

-- [player] = { count, nextAt }
local packs = {}

local function packFor(player)
	local pack = packs[player]
	if not pack then
		pack = { count = CFG.Charges, nextAt = 0 }
		packs[player] = pack
	end
	return pack
end

local function push(player)
	local pack = packFor(player)
	flareState:FireClient(player, {
		count = pack.count,
		max   = CFG.Charges,
		-- Seconds, not a timestamp: the client's clock is not the server's, and
		-- a countdown is the only thing it needs to draw.
		wait  = pack.count >= CFG.Charges and 0
			or math.max(pack.nextAt - os.clock(), 0),
	})
end

-- ── The flare itself ─────────────────────────────────────────────────────────

local function light(part, brightness, range)
	local l = Instance.new("PointLight")
	l.Color      = CFG.Colour
	l.Brightness = brightness
	l.Range      = range
	l.Shadows    = false
	l.Parent     = part
	return l
end

local function spawnFlare(player, origin, velocity)
	local flare = Instance.new("Part")
	flare.Name         = "Flare"
	flare.Shape        = Enum.PartType.Ball
	flare.Size         = Vector3.new(1.7, 1.7, 1.7)
	flare.Color        = CFG.Colour
	flare.Material     = Enum.Material.Neon
	flare.CanCollide   = true
	flare.CastShadow   = false
	flare.CFrame       = CFrame.new(origin)

	-- Heavy, grippy and almost dead. A flare that bounces off down a gallery is
	-- a flare you threw somewhere you did not choose, which is the one thing it
	-- must not do.
	flare.CustomPhysicalProperties = PhysicalProperties.new(4.2, 0.9, 0.08, 1, 1)
	flare.Parent = folder

	flare.AssemblyLinearVelocity = velocity

	local glow = light(flare, CFG.Brightness, CFG.Range)

	-- A halo, so it reads as burning rather than as a painted ball
	local halo = Instance.new("Part")
	halo.Name         = "Halo"
	halo.Shape        = Enum.PartType.Ball
	halo.Size         = Vector3.new(5.4, 5.4, 5.4)
	halo.Color        = CFG.Colour
	halo.Material     = Enum.Material.Neon
	halo.Transparency = 0.78
	halo.CanCollide   = false
	halo.CanQuery     = false
	halo.CanTouch     = false
	halo.CastShadow   = false
	halo.Massless     = true
	halo.CFrame       = flare.CFrame
	halo.Parent       = flare

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = flare
	weld.Part1  = halo
	weld.Parent = flare

	-- Handed to the thrower, so the arc they watched is the arc they get rather
	-- than a server-side approximation of it arriving three frames late
	pcall(function() flare:SetNetworkOwner(player) end)

	-- Burns, then goes out rather than blinking off
	task.delay(CFG.Life, function()
		if not flare.Parent then return end
		local fade = TweenInfo.new(CFG.Fade)
		TweenService:Create(glow, fade, { Brightness = 0, Range = 4 }):Play()
		TweenService:Create(flare, fade, { Transparency = 1 }):Play()
		TweenService:Create(halo, fade, { Transparency = 1 }):Play()
		Debris:AddItem(flare, CFG.Fade + 0.4)
	end)

	return flare
end

-- ── Throwing ─────────────────────────────────────────────────────────────────

flareThrow.OnServerEvent:Connect(function(player, direction, power)
	if typeof(direction) ~= "Vector3" or typeof(power) ~= "number" then return end
	if direction.Magnitude < 0.01 then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Above ground there is nothing to light and a thrown flare is litter on
	-- the camp deck
	if root.Position.Y > StrataConfig.Mine.SurfaceY - CFG.MinDepth then return end

	local pack = packFor(player)
	if pack.count <= 0 then return end

	-- Spending the last of a full pack is what starts the timer
	if pack.count >= CFG.Charges then
		pack.nextAt = os.clock() + CFG.Recharge
	end
	pack.count -= 1
	push(player)

	power = math.clamp(power, 0, 1)
	local speed = CFG.MinSpeed + (CFG.MaxSpeed - CFG.MinSpeed) * power

	-- The lift is added here as well as on the client, so the arc the client
	-- drew and the throw the server makes are the same throw
	local aim = (direction.Unit + Vector3.new(0, CFG.Lift, 0)).Unit
	spawnFlare(player, root.Position + aim * 3 + Vector3.new(0, 1.6, 0), aim * speed)
end)

-- ── Coming back ──────────────────────────────────────────────────────────────
-- One charge at a time rather than the whole set at once. Getting all three
-- back together would make the pack a thing you empty and then wait on; one at
-- a time makes it a thing you spend.

task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()

		for _, player in ipairs(Players:GetPlayers()) do
			local pack = packs[player]
			if pack and pack.count < CFG.Charges and now >= pack.nextAt then
				pack.count += 1
				if pack.count < CFG.Charges then
					pack.nextAt = now + CFG.Recharge
				end
				push(player)
			end
		end
	end
end)

local function greet(player)
	packs[player] = { count = CFG.Charges, nextAt = 0 }
	task.wait(2)
	push(player)
end

Players.PlayerAdded:Connect(greet)
Players.PlayerRemoving:Connect(function(player) packs[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(greet, player) end

print("[FlareService] online")
