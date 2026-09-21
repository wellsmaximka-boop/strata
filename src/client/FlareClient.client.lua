local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes    = ReplicatedStorage:WaitForChild("MineRemotes")
local flareThrow = remotes:WaitForChild("FlareThrow")
local flareState = remotes:WaitForChild("FlareState")

-- ── Flares, from the throwing end ────────────────────────────────────────────
-- Hold F, the arc appears; the longer you hold the further it goes; let go and
-- it flies.
--
-- The arc is the feature. Without it this is a button that makes a light happen
-- somewhere, and the whole point of a flare over a lamp is that *you* chose the
-- somewhere. So the dotted line is simulated forward under the same gravity the
-- flare will actually fall under, and raycast segment by segment so it stops at
-- the first thing it would hit — which means the ring at the end of it is where
-- the flare lands, not where it would land in a vacuum.

local CFG = StrataConfig.Flare
local UIP = StrataConfig.UI

-- ── The arc ──────────────────────────────────────────────────────────────────

local arc = Instance.new("Folder")
arc.Name   = "FlareArc"
arc.Parent = workspace

local dots = {}
for i = 1, CFG.Arc.Dots do
	local dot = Instance.new("Part")
	dot.Name         = "Dot"
	dot.Shape        = Enum.PartType.Ball
	dot.Size         = Vector3.new(CFG.Arc.Size, CFG.Arc.Size, CFG.Arc.Size)
	dot.Color        = CFG.Colour
	dot.Material     = Enum.Material.Neon
	dot.Anchored     = true
	dot.CanCollide   = false
	dot.CanQuery     = false
	dot.CanTouch     = false
	dot.CastShadow   = false
	dot.Transparency = 1
	dot.Parent       = arc
	dots[i] = dot
end

-- Where it lands, drawn flat against whatever it lands on
local ring = Instance.new("Part")
ring.Name         = "Landing"
ring.Shape        = Enum.PartType.Cylinder
ring.Size         = Vector3.new(0.25, 7, 7)
ring.Color        = CFG.Colour
ring.Material     = Enum.Material.Neon
ring.Anchored     = true
ring.CanCollide   = false
ring.CanQuery     = false
ring.CanTouch     = false
ring.CastShadow   = false
ring.Transparency = 1
ring.Parent       = arc

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function hideArc()
	for _, dot in ipairs(dots) do dot.Transparency = 1 end
	ring.Transparency = 1
end

-- Steps the throw forward under real gravity, stopping at the first thing in
-- the way. Returns how many dots were used.
local function drawArc(origin, velocity)
	local g    = Vector3.new(0, -workspace.Gravity, 0)
	local step = CFG.Arc.Step
	local at   = origin
	local v    = velocity
	local used = 0

	for i = 1, CFG.Arc.Dots do
		local next = at + v * step + g * (step * step * 0.5)
		v = v + g * step

		local hit = workspace:Raycast(at, next - at, rayParams)
		if hit then
			ring.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.2,
				hit.Position + hit.Normal * 2) * CFrame.Angles(0, math.rad(90), 0)
			ring.Transparency = 0.35
			used = i
			break
		end

		at = next
		dots[i].Position     = at
		-- Fading along its length, so the near end reads as "now" and the far
		-- end as "maybe"
		dots[i].Transparency = 0.1 + (i / CFG.Arc.Dots) * 0.55
		dots[i].Size         = Vector3.new(1, 1, 1)
			* (CFG.Arc.Size * (1 - (i / CFG.Arc.Dots) * 0.45))
		used = i
	end

	for i = used + 1, CFG.Arc.Dots do dots[i].Transparency = 1 end
	if used < CFG.Arc.Dots and ring.Transparency > 0.9 then
		ring.Transparency = 1
	end
	return used
end

-- ── The slot ─────────────────────────────────────────────────────────────────
-- Sits directly above the hotbar in the same chrome, so it reads as part of it
-- without either script having to know about the other's layout.

local gui = Instance.new("ScreenGui")
gui.Name           = "StrataFlares"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 11
gui.Enabled        = false
gui.Parent         = player:WaitForChild("PlayerGui")

local slot = Instance.new("Frame")
slot.Name             = "FlareSlot"
slot.AnchorPoint      = Vector2.new(0.5, 1)
slot.Position         = UDim2.new(0.5, 0, 1, -94)
slot.Size             = UDim2.new(0, 158, 0, 52)
slot.BackgroundColor3 = UIP.StoneDeep
slot.BorderSizePixel  = 0
slot.Parent           = gui
Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 10)

local slotEdge = Instance.new("UIStroke", slot)
slotEdge.Color     = UIP.StoneDark
slotEdge.Thickness = 2.5

local slotFace = Instance.new("UIGradient", slot)
slotFace.Rotation = 90
slotFace.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(162, 162, 168)),
})

local keyPlate = Instance.new("Frame")
keyPlate.Size             = UDim2.new(0, 22, 0, 18)
keyPlate.Position         = UDim2.new(0, 7, 0, 7)
keyPlate.BackgroundColor3 = UIP.StoneDark
keyPlate.BorderSizePixel  = 0
keyPlate.ZIndex           = 3
keyPlate.Parent           = slot
Instance.new("UICorner", keyPlate).CornerRadius = UDim.new(0, 5)

local function label(parent, text, size, position, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.Position               = position
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextColor3             = colour
	l.TextSize               = textSize
	l.Font                   = font or StrataConfig.UI.Head
	l.TextXAlignment         = align or Enum.TextXAlignment.Center
	l.ZIndex                 = 4

	-- A heavy black outline on every label. It is the single change that makes
	-- text on a dark panel read as a label rather than a smear, and putting it
	-- in the helper means it happens everywhere without a line at each call.
	local edge = Instance.new("UIStroke")
	edge.Color           = StrataConfig.UI.StoneDark
	edge.Thickness       = math.clamp((l.TextSize or 14) * 0.15, 1.1, 3.2)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	edge.Parent          = l
	l.Parent                 = parent
	return l
end

label(keyPlate, "F", UDim2.fromScale(1, 1), UDim2.new(), UIP.Crystal, 12, StrataConfig.UI.Number)

local name = label(slot, "FLARES", UDim2.new(0, 96, 0, 14), UDim2.new(0, 34, 0, 8),
	UIP.Dim, 10, StrataConfig.UI.Head, Enum.TextXAlignment.Left)

local timer = label(slot, "", UDim2.new(0, 46, 0, 14), UDim2.new(1, -9, 0, 8),
	UIP.Dim, 10, StrataConfig.UI.Number, Enum.TextXAlignment.Right)
timer.AnchorPoint = Vector2.new(1, 0)

-- One pip per charge. Three pips is a number you read without reading.
local pips = {}
for i = 1, CFG.Charges do
	local pip = Instance.new("Frame")
	pip.Size             = UDim2.new(0, 38, 0, 12)
	pip.Position         = UDim2.new(0, 7 + (i - 1) * 44, 0, 28)
	pip.BackgroundColor3 = CFG.Colour
	pip.BorderSizePixel  = 0
	pip.ZIndex           = 3
	pip.Parent           = slot
	Instance.new("UICorner", pip).CornerRadius = UDim.new(0, 4)
	pips[i] = pip
end

-- The one filling back up, drawn over its own pip
local refill = Instance.new("Frame")
refill.Size             = UDim2.new(0, 0, 0, 12)
refill.Position         = UDim2.new(0, 7, 0, 28)
refill.BackgroundColor3 = CFG.Colour
refill.BackgroundTransparency = 0.55
refill.BorderSizePixel  = 0
refill.ZIndex           = 4
refill.Parent           = slot
Instance.new("UICorner", refill).CornerRadius = UDim.new(0, 4)

-- ── Power ────────────────────────────────────────────────────────────────────

local power = Instance.new("Frame")
power.AnchorPoint      = Vector2.new(0.5, 1)
power.Position         = UDim2.new(0.5, 0, 1, -152)
power.Size             = UDim2.new(0, 158, 0, 8)
power.BackgroundColor3 = UIP.StoneDeep
power.BorderSizePixel  = 0
power.Visible          = false
power.Parent           = gui
Instance.new("UICorner", power).CornerRadius = UDim.new(0, 4)

local powerEdge = Instance.new("UIStroke", power)
powerEdge.Color     = UIP.StoneDark
powerEdge.Thickness = 2

local powerFill = Instance.new("Frame")
powerFill.Size             = UDim2.new(0, 0, 1, 0)
powerFill.BackgroundColor3 = CFG.Colour
powerFill.BorderSizePixel  = 0
powerFill.Parent           = power
Instance.new("UICorner", powerFill).CornerRadius = UDim.new(0, 4)

-- ── State ────────────────────────────────────────────────────────────────────

local charges  = CFG.Charges
local waitLeft = 0
local charging = nil    -- os.clock() at the moment the key went down

local function underground()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil
		and root.Position.Y <= StrataConfig.Mine.SurfaceY - CFG.MinDepth
end

local function paint()
	for i, pip in ipairs(pips) do
		pip.BackgroundTransparency = i <= charges and 0 or 0.82
	end
	name.TextColor3 = charges > 0 and UIP.Ink or UIP.StoneLit
	slotEdge.Color  = charging and CFG.Colour or UIP.StoneDark
end

flareState.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	charges  = info.count or 0
	waitLeft = info.wait or 0
	paint()
end)

-- ── Aiming ───────────────────────────────────────────────────────────────────

local function throwFrom()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	-- Excludes you, so the arc does not stop dead on your own shoulder
	rayParams.FilterDescendantsInstances = { char, arc }

	local aim = (camera.CFrame.LookVector + Vector3.new(0, CFG.Lift, 0)).Unit
	return root.Position + aim * 3 + Vector3.new(0, 1.6, 0), aim
end

UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if input.KeyCode ~= Enum.KeyCode.F then return end
	if charges <= 0 or not underground() then return end

	charging      = os.clock()
	power.Visible = true
	paint()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.F then return end
	if not charging then return end

	local held = math.clamp((os.clock() - charging) / CFG.ChargeTime, 0, 1)
	charging      = nil
	power.Visible = false
	hideArc()
	paint()

	local _, aim = throwFrom()
	if not aim then return end

	flareThrow:FireServer(aim, held)

	-- Spent locally the moment it is thrown. Waiting for the server to say so
	-- makes a thrown flare feel like a request rather than an action; the next
	-- push corrects it either way.
	charges = math.max(charges - 1, 0)
	paint()

	TweenService:Create(slotEdge, TweenInfo.new(0.25), { Color = UIP.StoneDark }):Play()
end)

RunService.RenderStepped:Connect(function(dt)
	local ok = underground()
	gui.Enabled = ok

	if not ok then
		if charging then
			charging      = nil
			power.Visible = false
			hideArc()
		end
		return
	end

	-- The countdown runs locally between pushes, so it ticks rather than jumps
	if charges < CFG.Charges then
		waitLeft = math.max(waitLeft - dt, 0)
		timer.Text = ("%ds"):format(math.ceil(waitLeft))
		refill.Size = UDim2.new(0,
			38 * (1 - math.clamp(waitLeft / CFG.Recharge, 0, 1)), 0, 12)
		refill.Position = UDim2.new(0, 7 + charges * 44, 0, 28)
		refill.Visible  = true
	else
		timer.Text     = "READY"
		refill.Visible = false
	end

	if not charging then return end

	local held = math.clamp((os.clock() - charging) / CFG.ChargeTime, 0, 1)
	powerFill.Size = UDim2.new(held, 0, 1, 0)
	powerFill.BackgroundColor3 = held >= 0.99 and UIP.Warning or CFG.Colour

	local origin, aim = throwFrom()
	if not origin then return end

	local speed = CFG.MinSpeed + (CFG.MaxSpeed - CFG.MinSpeed) * held
	drawArc(origin, aim * speed)
end)

print("[FlareClient] ready")
