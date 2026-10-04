local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes      = ReplicatedStorage:WaitForChild("MineRemotes")
local grappleFire  = remotes:WaitForChild("GrappleFire")
local grappleState = remotes:WaitForChild("GrappleState")

-- ── Grapple, from the firing end ─────────────────────────────────────────────
-- Aim at rock, press Q, get pulled there.
--
-- Everything that makes this feel like anything is on this side, and the reason
-- is latency. If the pull waited for the server to say yes, every hook would
-- begin a tenth of a second after the button, and no amount of tuning recovers
-- a traversal move that starts late. So the client fires immediately against
-- its own mirror of the cooldown; the server keeps the real one and corrects
-- the mirror whenever the two disagree. The worst case is a hook that starts
-- and a UI that snaps back, which is better than one that always feels slow.
--
-- The pull is a reel along a straight line, not a swing. See the note in
-- StrataConfig.Grapple for why.

local CFG = StrataConfig.Grapple
local UIP = StrataConfig.UI

-- ── Aiming ───────────────────────────────────────────────────────────────────

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshFilter()
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end
	for _, name in ipairs({ "FlareArc", "GrappleRope" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	rayParams.FilterDescendantsInstances = ignore
end
refreshFilter()
player.CharacterAdded:Connect(function() task.wait(0.2); refreshFilter() end)

-- What the crosshair is looking at, recomputed every frame. Terrain counts;
-- so does anything solid. A deposit does not, because reeling into the
-- objective you are trying to mine is not a move anyone meant to make.
local function aim()
	local origin    = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * CFG.Range
	local hit = workspace:Raycast(origin, direction, rayParams)
	if not hit then return nil end

	-- Measured from the player, not the camera. The camera sits behind the
	-- shoulder, so a camera-length check quietly hands out free studs.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	if (hit.Position - root.Position).Magnitude > CFG.Range then return nil end

	return hit.Position, hit.Normal
end

-- ── The rope ─────────────────────────────────────────────────────────────────

local ropeFolder = Instance.new("Folder")
ropeFolder.Name   = "GrappleRope"
ropeFolder.Parent = workspace

local function visual(name, size, colour, material)
	local p = Instance.new("Part")
	p.Name         = name
	p.Size         = size
	p.Color        = colour
	p.Material     = material
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false
	p.CanTouch     = false
	p.CastShadow   = false
	p.Transparency = 1
	p.Parent       = ropeFolder
	return p
end

local rope = visual("Line", Vector3.new(CFG.Rope.Thickness, CFG.Rope.Thickness, 1),
	CFG.Rope.Colour, Enum.Material.SmoothPlastic)
local hook = visual("Hook", Vector3.new(0.9, 0.9, 0.9),
	CFG.Rope.Hook, Enum.Material.Neon)

local function drawRope(from, to)
	local span = (to - from).Magnitude
	rope.Size         = Vector3.new(CFG.Rope.Thickness, CFG.Rope.Thickness, span)
	rope.CFrame       = CFrame.lookAt(from:Lerp(to, 0.5), to)
	rope.Transparency = 0
	hook.CFrame       = CFrame.new(to)
	hook.Transparency = 0
end

local function hideRope()
	rope.Transparency = 1
	hook.Transparency = 1
end

-- ── The pull ─────────────────────────────────────────────────────────────────

local flight = nil   -- { anchor, startedAt }

local function stop(arrived)
	if not flight then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum  = character and character:FindFirstChildOfClass("Humanoid")

	if arrived and root and hum then
		-- The kick. Without it you reel into the rock under the ledge you were
		-- aiming at and slide back down it, which reads as the hook failing
		-- even though it did exactly what it was told.
		local carried = root.AssemblyLinearVelocity * CFG.Carry
		root.AssemblyLinearVelocity =
			Vector3.new(carried.X, 0, carried.Z) + Vector3.new(0, CFG.Launch, 0)
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	flight = nil
	hideRope()
end

local function fire()
	local anchor = aim()
	if not anchor then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum  = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end

	flight = { anchor = anchor, startedAt = os.clock() }
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	grappleFire:FireServer(anchor)
end

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum  = character and character:FindFirstChildOfClass("Humanoid")

	if not flight then return end

	if not root or not hum or hum.Health <= 0 then
		stop(false)
		return
	end

	-- The hard stop. An anchor buried in geometry, or a player wedged on a lip,
	-- would otherwise hold someone in the air until they reset.
	if os.clock() - flight.startedAt > CFG.MaxTime then
		stop(false)
		return
	end

	local toward = flight.anchor - root.Position
	if toward.Magnitude <= CFG.Arrive then
		stop(true)
		return
	end

	-- Re-asserted every frame. Touching the floor mid-flight puts the humanoid
	-- into Running, and Running applies ground friction that eats the pull —
	-- so the hook would die the moment it dragged you across a shelf.
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = toward.Unit * CFG.Speed

	drawRope(root.Position, flight.anchor)
end)

-- ── Input ────────────────────────────────────────────────────────────────────

local readyAt = 0   -- the client's mirror of the server's cooldown

grappleState.OnClientEvent:Connect(function(state)
	readyAt = os.clock() + (state.wait or 0)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= CFG.Key then return end

	-- Pressing it again mid-flight is the release, and releasing early with
	-- speed in hand is the whole point of having momentum at all.
	if flight then
		stop(true)
		return
	end

	if os.clock() < readyAt then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if root.Position.Y > StrataConfig.Mine.SurfaceY - CFG.MinDepth then return end

	readyAt = os.clock() + CFG.Cooldown   -- corrected by the server's reply
	fire()
end)

-- ── The slot and the crosshair ───────────────────────────────────────────────
-- Same chrome as the flare slot, sitting directly above it, because two tools
-- on two different plates is two interfaces.

local gui = Instance.new("ScreenGui")
gui.Name           = "GrappleUI"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 6
gui.Parent         = player:WaitForChild("PlayerGui")

local function label(parent, text, size, position, colour, textSize, font, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size                   = size
	t.Position               = position
	t.Text                   = text
	t.TextColor3             = colour
	t.TextSize               = textSize
	t.Font                   = font
	t.TextXAlignment         = align or Enum.TextXAlignment.Left
	t.Parent                 = parent

	local edge = Instance.new("UIStroke", t)
	edge.Color     = UIP.StoneDark
	edge.Thickness = UIP.TextEdge
	return t
end

local slot = Instance.new("Frame")
slot.Name             = "GrappleSlot"
slot.AnchorPoint      = Vector2.new(0.5, 1)
slot.Position         = UDim2.new(0.5, 0, 1, -152)
slot.Size             = UDim2.new(0, 158, 0, 44)
slot.BackgroundColor3 = UIP.StoneDeep
slot.BorderSizePixel  = 0
slot.Visible          = false
slot.Parent           = gui
Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 10)

local slotEdge = Instance.new("UIStroke", slot)
slotEdge.Color     = UIP.StoneDark
slotEdge.Thickness = 2.5

local keyPlate = Instance.new("Frame")
keyPlate.Size             = UDim2.new(0, 20, 0, 20)
keyPlate.Position         = UDim2.new(0, 9, 0, 8)
keyPlate.BackgroundColor3 = UIP.Stone
keyPlate.BorderSizePixel  = 0
keyPlate.Parent           = slot
Instance.new("UICorner", keyPlate).CornerRadius = UDim.new(0, 5)

label(keyPlate, "Q", UDim2.new(1, 0, 1, 0), UDim2.new(), UIP.Ink, 12,
	UIP.Head, Enum.TextXAlignment.Center)

label(slot, "GRAPPLE", UDim2.new(0, 96, 0, 14), UDim2.new(0, 36, 0, 7),
	UIP.Dim, 11, UIP.Body)

local statusText = label(slot, "READY", UDim2.new(0, 60, 0, 14),
	UDim2.new(1, -9, 0, 7), UIP.Crystal, 11, UIP.Number, Enum.TextXAlignment.Right)
statusText.AnchorPoint = Vector2.new(1, 0)

-- The cooldown, as a bar rather than only a number, because a bar is readable
-- without being looked at.
local track = Instance.new("Frame")
track.Size             = UDim2.new(1, -18, 0, 5)
track.Position         = UDim2.new(0, 9, 1, -11)
track.BackgroundColor3 = UIP.StoneDark
track.BorderSizePixel  = 0
track.Parent           = slot
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local fillBar = Instance.new("Frame")
fillBar.Size             = UDim2.new(1, 0, 1, 0)
fillBar.BackgroundColor3 = UIP.Crystal
fillBar.BorderSizePixel  = 0
fillBar.Parent           = track
Instance.new("UICorner", fillBar).CornerRadius = UDim.new(1, 0)

-- The crosshair. This is the entirety of "grapple point detection": lit means
-- the rock under the cursor is reachable, unlit means it is not.
local reticle = Instance.new("Frame")
reticle.Name             = "Reticle"
reticle.AnchorPoint      = Vector2.new(0.5, 0.5)
reticle.Position         = UDim2.new(0.5, 0, 0.5, 0)
reticle.Size             = UDim2.new(0, CFG.Reticle.Size, 0, CFG.Reticle.Size)
reticle.BackgroundTransparency = 1
reticle.Visible          = false
reticle.Parent           = gui

local ticks = {}
for i, spec in ipairs({
	{ UDim2.new(0, 2, 0, 7), UDim2.new(0.5, -1, 0, 0) },
	{ UDim2.new(0, 2, 0, 7), UDim2.new(0.5, -1, 1, -7) },
	{ UDim2.new(0, 7, 0, 2), UDim2.new(0, 0, 0.5, -1) },
	{ UDim2.new(0, 7, 0, 2), UDim2.new(1, -7, 0.5, -1) },
}) do
	local t = Instance.new("Frame")
	t.Size             = spec[1]
	t.Position         = spec[2]
	t.BackgroundColor3 = CFG.Reticle.Bad
	t.BorderSizePixel  = 0
	t.Parent           = reticle
	ticks[i] = t
end

RunService.RenderStepped:Connect(function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local under = root
		and root.Position.Y <= StrataConfig.Mine.SurfaceY - CFG.MinDepth

	slot.Visible    = under or false
	reticle.Visible = (under and not flight) or false
	if not under then return end

	local left  = math.max(readyAt - os.clock(), 0)
	local ready = left <= 0

	statusText.Text       = ready and "READY" or ("%.1fs"):format(left)
	statusText.TextColor3 = ready and UIP.Crystal or UIP.Dim
	fillBar.Size          = UDim2.new(ready and 1 or 1 - left / CFG.Cooldown, 0, 1, 0)
	fillBar.BackgroundColor3 = ready and UIP.Crystal or UIP.Iron

	if reticle.Visible then
		local colour = (ready and aim()) and CFG.Reticle.Good or CFG.Reticle.Bad
		for _, t in ipairs(ticks) do t.BackgroundColor3 = colour end
	end
end)

print("[GrappleClient] ready")
