local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- Siblings in PlayerScripts are not guaranteed to have replicated when this
-- runs, and a plain index returns nil rather than waiting. That exact mistake
-- cost us a camp screen that would not open, so: WaitForChild, always.
local movement   = script.Parent:WaitForChild("movement")
local GrappleRig = require(movement:WaitForChild("GrappleRig"))
local Momentum   = require(movement:WaitForChild("Momentum"))
local RopeView   = require(movement:WaitForChild("RopeView"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes      = ReplicatedStorage:WaitForChild("MineRemotes")
local grappleFire  = remotes:WaitForChild("GrappleFire")
local grappleLet   = remotes:WaitForChild("GrappleLet")
local grappleState = remotes:WaitForChild("GrappleState")
local grappleRope  = remotes:WaitForChild("GrappleRope")

-- ── Grapple, from the firing end ─────────────────────────────────────────────
-- Aim at rock, press Q, and you are on a rope. W climbs it, S feeds it out,
-- A and D steer the swing, Q or G lets go and you keep every bit of the speed
-- you built.
--
-- Everything that makes this feel like anything is on this side, and the reason
-- is latency. If the hook waited for the server to say yes, every rope would
-- catch a tenth of a second after the button, and no amount of tuning recovers
-- a traversal move that starts late. So the client builds the rig immediately
-- against its own mirror of the cooldown; the server keeps the real one and
-- corrects the mirror whenever the two disagree.
--
-- The rig is local. That is not a shortcut around co-op, it is the right answer
-- to it: Roblox gives a player's own character to their own client, so a rope
-- built here solves where the character is actually simulated. What the other
-- players need is not the constraint but the picture of it, and the picture
-- only needs two things, which are who is swinging and from where. Their
-- character position already replicates on its own. So the server broadcasts
-- an anchor once per hook and every other client draws the cable itself, every
-- frame, for free. See RopeView.

local CFG = StrataConfig.Grapple
local UIP = StrataConfig.UI

-- Where the slot sits along the bottom edge. Shared, because this script used
-- to park itself at -152 and so did the flare's charge gauge.
local BOT  = StrataConfig.HudBottom()
local BOTW = StrataConfig.Hud.Bottom.Width

-- Matches GrappleRig, and only used for other people's cables: for our own we
-- read the attachment's world position straight off the rig, and theirs we do
-- not have. A hand's width of error on a rope across the room is nothing.
local HAND = Vector3.new(0, 0.6, 0)

-- ── Aiming ───────────────────────────────────────────────────────────────────

local rayParams = RaycastParams.new()
rayParams.FilterType  = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshFilter()
	local ignore = {}
	if player.Character then table.insert(ignore, player.Character) end

	-- Driven by the config now. The old list was hardcoded, and the comment
	-- above it claimed deposits were excluded while the filter never mentioned
	-- them, so you could hook the objective you were trying to mine.
	for _, name in ipairs(CFG.Surfaces.Ignore) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			table.insert(ignore, other.Character)
		end
	end

	rayParams.FilterDescendantsInstances = ignore
end
refreshFilter()

-- What the crosshair is looking at, recomputed every frame.
local function aim()
	local hit = workspace:Raycast(camera.CFrame.Position,
		camera.CFrame.LookVector * CFG.Range, rayParams)
	if not hit then return nil end

	if hit.Instance == workspace.Terrain then
		if not CFG.Surfaces.Terrain then return nil end
	elseif not CFG.Surfaces.Parts then
		return nil
	end

	-- Measured from the player, not the camera. The camera sits behind the
	-- shoulder, so a camera-length check quietly hands out free studs.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	if (hit.Position - root.Position).Magnitude > CFG.Range then return nil end

	return hit.Position, hit.Normal
end

-- ── Sound, if anyone ever fills the hooks in ─────────────────────────────────

local function sfx(id)
	if not id or id == "" then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local s   = Instance.new("Sound")
	s.SoundId = id
	s.Parent  = root or workspace
	s:Play()
	Debris:AddItem(s, 5)
end

-- ── State ────────────────────────────────────────────────────────────────────

local rig      = nil   -- the live GrappleRig, or nil
local body     = nil   -- the live Momentum
local selfView = RopeView.new("Self")
local readyAt  = 0     -- the client's mirror of the server's cooldown
local baseFov  = camera.FieldOfView

local function underground()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return (root and root.Position.Y <= StrataConfig.Mine.SurfaceY - CFG.MinDepth) or false
end

local function release(quietly)
	if not rig then return end

	rig:Destroy()
	rig = nil
	selfView:Hide()

	-- The velocity is simply left alone. It is already exactly whatever the
	-- swing earned, which is the entire reason for using a constraint instead
	-- of writing velocities: there is nothing to hand back. ReleaseBoost is
	-- there to tune with and is zero on purpose, because a free kick on every
	-- release is the unearned, magnetic feel we are trying not to have.
	if CFG.ReleaseBoost > 0 then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity += Vector3.new(0, CFG.ReleaseBoost, 0)
		end
	end

	if not quietly then
		grappleLet:FireServer()
		sfx(CFG.Sfx.Release)
	end
end

local function fire()
	local anchor, normal = aim()
	if not anchor then
		sfx(CFG.Sfx.Miss)
		return
	end

	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local fresh = GrappleRig.new(character, anchor)
	if not fresh then return end
	rig = fresh

	-- Once, not every frame. This unsticks you from the floor so the first
	-- moment of the rope is not fighting a standing Humanoid. After this the
	-- controller is left entirely alone, which is the difference between a rope
	-- and a piece of string.
	hum:ChangeState(Enum.HumanoidStateType.Freefall)

	grappleFire:FireServer(anchor, normal or Vector3.yAxis)
	sfx(CFG.Sfx.Fire)
	sfx(CFG.Sfx.Attach)
end

-- ── Input ────────────────────────────────────────────────────────────────────

local function strafe()
	local x = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
	if x == 0 then return Vector3.zero end

	local right = camera.CFrame.RightVector
	local level = Vector3.new(right.X, 0, right.Z)
	if level.Magnitude < 0.05 then return Vector3.zero end

	return level.Unit * x
end

grappleState.OnClientEvent:Connect(function(state)
	readyAt = os.clock() + (state.wait or 0)
end)

-- InputBegan fires once per physical press, so one press cannot start two
-- hooks. The guard that matters is the other one: while a rope is live, the
-- fire key is the release key.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	local isFire    = input.KeyCode == CFG.Key
	local isRelease = input.KeyCode == CFG.Release
	if not isFire and not isRelease then return end

	if rig then
		release(false)
		return
	end
	if isRelease then return end

	if os.clock() < readyAt then return end
	if not underground() then return end

	readyAt = os.clock() + CFG.Cooldown   -- corrected by the server's reply
	fire()
end)

-- ── Other people's ropes ─────────────────────────────────────────────────────

local others = {}   -- [userId] = { anchor = Vector3, view = RopeView }

local function clearOther(id)
	local entry = others[id]
	if not entry then return end
	entry.view:Destroy()
	others[id] = nil
end

grappleRope.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" or not msg.id then return end
	if msg.id == player.UserId then return end   -- we draw our own, frame-exact

	if not msg.anchor then
		clearOther(msg.id)
		return
	end

	local entry = others[msg.id]
	if not entry then
		entry = { view = RopeView.new("P" .. msg.id) }
		others[msg.id] = entry
	end
	entry.anchor = msg.anchor
end)

Players.PlayerRemoving:Connect(function(gone)
	clearOther(gone.UserId)
	refreshFilter()
end)
Players.PlayerAdded:Connect(refreshFilter)

-- ── The frame ────────────────────────────────────────────────────────────────

local function bind(character)
	release(true)
	if body then body:Destroy() end
	body = nil

	character:WaitForChild("HumanoidRootPart", 10)
	local hum = character:WaitForChild("Humanoid", 10)

	body = Momentum.new(character)
	refreshFilter()

	if hum then
		hum.Died:Connect(function() release(false) end)
	end
end

player.CharacterAdded:Connect(bind)
if player.Character then task.spawn(bind, player.Character) end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum  = character and character:FindFirstChildOfClass("Humanoid")

	if rig then
		if not root or not hum or hum.Health <= 0 then
			release(false)
		elseif os.clock() - rig.bornAt > CFG.HangLimit then
			-- A safety net and not a mechanic. Hanging still to look around is
			-- fine; being stuck on a bad anchor until you reset is not.
			release(false)
		elseif not rig:Step(dt, UserInputService:IsKeyDown(CFG.ReelIn),
			UserInputService:IsKeyDown(CFG.ReelOut)) then
			release(false)
		else
			selfView:Draw(rig.hand.WorldPosition, rig.anchor)
		end
	end

	if body then
		body:Step(dt, rig, strafe(), UserInputService:IsKeyDown(CFG.ReelIn))
	end

	for id, entry in pairs(others) do
		local them = Players:GetPlayerByUserId(id)
		local far  = them and them.Character
			and them.Character:FindFirstChild("HumanoidRootPart")
		if far then
			entry.view:Draw(far.Position + HAND, entry.anchor)
		else
			entry.view:Hide()
		end
	end

	-- Speed widens the lens a little and nothing else moves. Only while the
	-- camera is Custom: DescentClient takes it Scriptable for the lift ride and
	-- restores the field of view it saved, so this stays out of its way.
	if camera.CameraType == Enum.CameraType.Custom then
		local speed = root and root.AssemblyLinearVelocity.Magnitude or 0
		local want  = baseFov
			+ math.min(speed / CFG.Camera.FovSpeed, 1) * CFG.Camera.FovGain
		camera.FieldOfView += (want - camera.FieldOfView)
			* math.min(dt * CFG.Camera.Smooth, 1)
	end
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
	t.Font                   = StrataConfig.FaceFor(font, textSize)
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
slot.Position         = UDim2.new(0.5, 0, 1, -BOT.GrappleSlot.y)
slot.Size             = UDim2.new(0, BOTW, 0, BOT.GrappleSlot.h)
slot.BackgroundColor3 = UIP.StoneDeep
slot.BorderSizePixel  = 0
slot.Visible          = false
slot.Parent           = gui
Instance.new("UICorner", slot).CornerRadius = UDim.new(0, math.min(10, UIP.Corner))

local slotEdge = Instance.new("UIStroke", slot)
slotEdge.Color     = UIP.StoneDark
slotEdge.Thickness = 2.5

local keyPlate = Instance.new("Frame")
keyPlate.Size             = UDim2.new(0, 20, 0, 20)
keyPlate.Position         = UDim2.new(0, 9, 0, 8)
keyPlate.BackgroundColor3 = UIP.Stone
keyPlate.BorderSizePixel  = 0
keyPlate.Parent           = slot
Instance.new("UICorner", keyPlate).CornerRadius = UDim.new(0, math.min(5, UIP.Corner))

label(keyPlate, "Q", UDim2.new(1, 0, 1, 0), UDim2.new(), UIP.Ink, 12,
	UIP.Head, Enum.TextXAlignment.Center)

label(slot, "GRAPPLE", UDim2.new(0, 96, 0, 14), UDim2.new(0, 36, 0, 7),
	UIP.Dim, 11, UIP.Body)

local statusText = label(slot, "READY", UDim2.new(0, 60, 0, 14),
	UDim2.new(1, -9, 0, 7), UIP.Crystal, 11, UIP.Number, Enum.TextXAlignment.Right)
statusText.AnchorPoint = Vector2.new(1, 0)

-- The cooldown, as a bar rather than only a number, because a bar is readable
-- without being looked at. At six tenths of a second it is more of a flicker
-- than a wait, which is the point: the cable length takes the readout over
-- while you are actually on a rope, where it is the number that matters.
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
reticle.Name                   = "Reticle"
reticle.AnchorPoint            = Vector2.new(0.5, 0.5)
reticle.Position               = UDim2.new(0.5, 0, 0.5, 0)
reticle.Size                   = UDim2.new(0, CFG.Reticle.Size, 0, CFG.Reticle.Size)
reticle.BackgroundTransparency = 1
reticle.Visible                = false
reticle.Parent                 = gui

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
	local under = underground()

	slot.Visible    = under
	reticle.Visible = under and not rig
	if not under then return end

	local left  = math.max(readyAt - os.clock(), 0)
	local ready = left <= 0

	if rig then
		statusText.Text          = ("%dm"):format(rig.length)
		statusText.TextColor3    = UIP.Brass
		fillBar.Size             = UDim2.new(
			math.clamp(rig.length / CFG.MaxLength, 0, 1), 0, 1, 0)
		fillBar.BackgroundColor3 = UIP.Brass
	else
		statusText.Text          = ready and "READY" or ("%.1fs"):format(left)
		statusText.TextColor3    = ready and UIP.Crystal or UIP.Dim
		fillBar.Size             = UDim2.new(
			ready and 1 or math.clamp(1 - left / CFG.Cooldown, 0, 1), 0, 1, 0)
		fillBar.BackgroundColor3 = ready and UIP.Crystal or UIP.Iron

		local colour = (ready and aim()) and CFG.Reticle.Good or CFG.Reticle.Bad
		for _, t in ipairs(ticks) do t.BackgroundColor3 = colour end
	end
end)

print("[GrappleClient] ready")
