local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local ItemModels   = require(ReplicatedStorage:WaitForChild("ItemModels"))
local GearConfig   = require(ReplicatedStorage:WaitForChild("GearConfig"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes      = ReplicatedStorage:WaitForChild("MineRemotes")
local digRequest   = remotes:WaitForChild("DigRequest")
local digResult    = remotes:WaitForChild("DigResult")
local scanRequest  = remotes:WaitForChild("ScanRequest")
local scanResult   = remotes:WaitForChild("ScanResult")
local oreCollected = remotes:WaitForChild("OreCollected")
local digBlocked   = remotes:WaitForChild("DigBlocked")
local mineNode     = remotes:WaitForChild("MineNode")
local nodeHit      = remotes:WaitForChild("NodeHit")
local stateChanged = remotes:WaitForChild("StateChanged")
local surfaceCall  = remotes:WaitForChild("ReturnToSurface")
local depositHit   = remotes:WaitForChild("DepositHit")

-- ── Palette ──────────────────────────────────────────────────────────────────
local INK    = StrataConfig.UI.Ink
local DIM    = StrataConfig.UI.Dim
local ORE    = StrataConfig.UI.Ore
local SIGNAL = StrataConfig.UI.Crystal
local PANEL  = StrataConfig.UI.StoneDeep

-- ── Mirrored server values ───────────────────────────────────────────────────
-- Declared up here because both the HUD and the dig loop read them, and a local
-- defined further down is invisible to any closure created above it.
local digCooldown   = StrataConfig.Dig.Cooldown
local miningPower   = StrataConfig.Player.StartingStrength
local localStrength = StrataConfig.Player.StartingStrength
-- Best pickaxe owned; decides which model is in your hand
local heldPickId    = nil

-- ── HUD ──────────────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "StrataHUD"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = player:WaitForChild("PlayerGui")

-- Same frame language as the panels and the depth banner: solid, rounded, with
-- the heavy dark outline. The outline colour is a literal on purpose — OUTLINE
-- is declared further down, and a local defined below a function is invisible
-- to it.
local function panel(size, position, anchor)
	local f = Instance.new("Frame")
	f.Size                   = size
	f.Position               = position
	f.AnchorPoint            = anchor or Vector2.new(0, 0)
	f.BackgroundColor3       = StrataConfig.UI.Stone
	f.BackgroundTransparency = 0
	f.BorderSizePixel        = 0
	f.Parent                 = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, StrataConfig.UI.Corner)

	-- Lit along the top like everything else, so a panel reads as a slab with a
	-- light on it rather than as a flat rectangle
	local lit = Instance.new("UIGradient", f)
	lit.Rotation = 90
	lit.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, StrataConfig.UI.StoneLit),
		ColorSequenceKeypoint.new(0.3, StrataConfig.UI.Stone),
		ColorSequenceKeypoint.new(1, StrataConfig.UI.StoneDeep),
	})

	local stroke = Instance.new("UIStroke", f)
	stroke.Color     = StrataConfig.UI.StoneDark
	stroke.Thickness = StrataConfig.UI.Outline
	return f
end

local function label(parent, text, size, position, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.Position               = position
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextColor3             = colour or INK
	l.TextSize               = textSize or 14
	l.Font                   = font or StrataConfig.UI.Number
	l.TextXAlignment         = align or Enum.TextXAlignment.Left

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

-- ── Depth banner, top centre ─────────────────────────────────────────────────
-- The one thing you always want visible: how deep you are and what you're
-- standing in. Its accent takes the stratum's own colour, so the band changes
-- character as you descend and you can feel the Magma Vents coming.

local OUTLINE = StrataConfig.UI.StoneDark

local depthBanner = Instance.new("Frame")
depthBanner.Size             = UDim2.new(0, 300, 0, 62)
depthBanner.AnchorPoint      = Vector2.new(0.5, 0)
depthBanner.Position         = UDim2.new(0.5, 0, 0, 10)
depthBanner.BackgroundColor3 = StrataConfig.UI.Stone
depthBanner.BorderSizePixel  = 0
depthBanner.Parent           = gui
Instance.new("UICorner", depthBanner).CornerRadius = UDim.new(0, 16)

local bannerEdge = Instance.new("UIStroke", depthBanner)
bannerEdge.Color     = OUTLINE
bannerEdge.Thickness = 3

local bannerShadow = Instance.new("Frame")
bannerShadow.Size                   = UDim2.new(1, 14, 1, 12)
bannerShadow.Position               = UDim2.new(0, -7, 0, -3)
bannerShadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
bannerShadow.BackgroundTransparency = 0.65
bannerShadow.BorderSizePixel        = 0
bannerShadow.ZIndex                 = 0
bannerShadow.Parent                 = depthBanner
Instance.new("UICorner", bannerShadow).CornerRadius = UDim.new(0, 20)

-- Colour bar down the left, tinted by the layer you are in
local depthBar = Instance.new("Frame")
depthBar.Size             = UDim2.new(0, 7, 1, -16)
depthBar.Position         = UDim2.new(0, 9, 0, 8)
depthBar.BackgroundColor3 = Color3.fromRGB(122, 106, 79)
depthBar.BorderSizePixel  = 0
depthBar.ZIndex           = 2
depthBar.Parent           = depthBanner
Instance.new("UICorner", depthBar).CornerRadius = UDim.new(0, 4)

local depthValue = label(depthBanner, "0m", UDim2.new(0, 150, 0, 32),
	UDim2.new(0, 26, 0, 6), INK, 30, StrataConfig.UI.Number)
depthValue.ZIndex = 2

local depthName = label(depthBanner, "SURFACE", UDim2.new(1, -36, 0, 18),
	UDim2.new(0, 26, 0, 38), DIM, 14)
depthName.ZIndex = 2

-- Right-hand hint: what is below, and whether it will hurt
local depthAhead = label(depthBanner, "", UDim2.new(0, 132, 0, 36),
	UDim2.new(1, -14, 0, 13), DIM, 11, StrataConfig.UI.Number, Enum.TextXAlignment.Right)
depthAhead.AnchorPoint = Vector2.new(1, 0)
depthAhead.ZIndex      = 2

-- Backpack and cash, second in the left-hand column. The haul is on top, and
-- the credits get their own gold strip underneath. They used to be a dark icon
-- and a 13px number on a dark panel, which is why they were hard to read.
local packPanel = panel(UDim2.new(0, StrataConfig.Hud.Width, 0, StrataConfig.Hud.Pack.H),
	UDim2.new(0, StrataConfig.Hud.Left, 0.5, StrataConfig.Hud.Pack.Y))

label(packPanel, "PACK", UDim2.new(0, 40, 0, 20), UDim2.new(0, 12, 0, 9), DIM, 11)

local packValue = label(packPanel, "0 / " .. StrataConfig.Player.BackpackSlots,
	UDim2.new(0, 80, 0, 22), UDim2.new(0, 50, 0, 8), INK, 18)

-- What the haul would fetch at the Depot, so digging visibly earns something
local haulWorth = label(packPanel, "", UDim2.new(0, 70, 0, 20),
	UDim2.new(1, -12, 0, 9), ORE, 12, nil, Enum.TextXAlignment.Right)
haulWorth.AnchorPoint = Vector2.new(1, 0)

local GOLD      = Color3.fromRGB(255, 204, 92)
local GOLD_DEEP = Color3.fromRGB(150, 102, 28)

local cashStrip = Instance.new("Frame")
cashStrip.Size             = UDim2.new(1, -16, 0, 38)
cashStrip.Position         = UDim2.new(0, 8, 0, 38)
cashStrip.BackgroundColor3 = Color3.fromRGB(56, 42, 18)
cashStrip.BorderSizePixel  = 0
cashStrip.Parent           = packPanel
Instance.new("UICorner", cashStrip).CornerRadius = UDim.new(0, 9)

local stripEdge = Instance.new("UIStroke", cashStrip)
stripEdge.Color     = GOLD_DEEP
stripEdge.Thickness = 1.5

-- A coin drawn from frames: face, rim, inner ring and a glint. Reads on any
-- background, which the icon asset did not.
local coin = Instance.new("Frame")
coin.Size             = UDim2.new(0, 24, 0, 24)
coin.AnchorPoint      = Vector2.new(0, 0.5)
coin.Position         = UDim2.new(0, 8, 0.5, 0)
coin.BackgroundColor3 = GOLD
coin.BorderSizePixel  = 0
coin.Parent           = cashStrip
Instance.new("UICorner", coin).CornerRadius = UDim.new(0.5, 0)

local coinRim = Instance.new("UIStroke", coin)
coinRim.Color     = GOLD_DEEP
coinRim.Thickness = 2

local coinInner = Instance.new("Frame")
coinInner.Size                   = UDim2.new(0, 13, 0, 13)
coinInner.AnchorPoint            = Vector2.new(0.5, 0.5)
coinInner.Position               = UDim2.fromScale(0.5, 0.5)
coinInner.BackgroundTransparency = 1
coinInner.Parent                 = coin
Instance.new("UICorner", coinInner).CornerRadius = UDim.new(0.5, 0)

local innerRing = Instance.new("UIStroke", coinInner)
innerRing.Color     = Color3.fromRGB(214, 150, 44)
innerRing.Thickness = 1.5

local glint = Instance.new("Frame")
glint.Size                   = UDim2.new(0, 6, 0, 4)
glint.Position               = UDim2.new(0, 5, 0, 4)
glint.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
glint.BackgroundTransparency = 0.35
glint.BorderSizePixel        = 0
glint.Parent                 = coin
Instance.new("UICorner", glint).CornerRadius = UDim.new(0.5, 0)

local cashValue = label(cashStrip, "0", UDim2.new(1, -48, 1, 0),
	UDim2.new(0, 40, 0, 0), GOLD, 22, StrataConfig.UI.Head)

-- Thousands separators: 14,250 rather than 14250
local function commas(n)
	local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Credits count up to the new total instead of snapping, and the strip flares
-- when money comes in, so a sale is something you see happen.
local shownCash = 0
local cashTween = nil
local cashNum   = Instance.new("NumberValue")
cashNum.Parent  = packPanel
cashNum.Changed:Connect(function(v)
	cashValue.Text = commas(v)
end)

local function setCash(amount)
	if amount == shownCash then return end
	local gained = amount > shownCash
	shownCash = amount

	if cashTween then cashTween:Cancel() end
	cashTween = TweenService:Create(cashNum,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = amount })
	cashTween:Play()

	if gained then
		stripEdge.Color     = GOLD
		stripEdge.Thickness = 3
		TweenService:Create(stripEdge, TweenInfo.new(0.6),
			{ Color = GOLD_DEEP, Thickness = 1.5 }):Play()
	end
end

-- Unsold value, kept locally between server pushes so each dig ticks it up
local haulTotal = 0
local function setHaul(amount)
	haulTotal = amount
	haulWorth.Text = amount > 0 and ("≈ " .. commas(amount)) or ""
end

-- Strength, under the depth readout. Mining power is what actually breaks
-- rock — strength is the part of it you earn rather than buy.
local STRENGTH_ICON = "rbxassetid://15909461117"

-- Top of the left-hand column. It used to sit in the top-left corner, which is
-- where Roblox draws its own menu and chat buttons — they covered it.
local HUD = StrataConfig.Hud

local strengthPanel = panel(UDim2.new(0, HUD.Width, 0, HUD.Strength.H),
	UDim2.new(0, HUD.Left, 0.5, HUD.Strength.Y))

local strengthIcon = Instance.new("ImageLabel")
strengthIcon.Image                  = STRENGTH_ICON
strengthIcon.ScaleType              = Enum.ScaleType.Fit
strengthIcon.BackgroundTransparency = 1
strengthIcon.Size                   = UDim2.new(0, 32, 0, 32)
strengthIcon.Position               = UDim2.new(0, 10, 0, 11)
strengthIcon.Parent                 = strengthPanel

-- Mining power is the headline, because it is the number that decides what
-- breaks. Strength — the part of it you earn — sits underneath.
local strengthValue = label(strengthPanel, "5", UDim2.new(0, 80, 0, 26),
	UDim2.new(0, 50, 0, 5), ORE, 24)

local powerTag = label(strengthPanel, "POWER", UDim2.new(0, 60, 0, 14),
	UDim2.new(1, -12, 0, 10), DIM, 11, nil, Enum.TextXAlignment.Right)
powerTag.AnchorPoint = Vector2.new(1, 0)

local strengthSub = label(strengthPanel, "STRENGTH 5", UDim2.new(1, -60, 0, 16),
	UDim2.new(0, 50, 0, 31), DIM, 12)

-- Scanner readout, bottom centre
-- Bottom right, out of the way of the pickaxe hotbar in the middle. The sweep
-- is a thing you glance at, not a thing you read, so a corner suits it.
local scanPanel = panel(UDim2.new(0, 300, 0, 96), UDim2.new(1, -16, 1, -18), Vector2.new(1, 1))
scanPanel.BackgroundTransparency = 0.15

local scanArrow = label(scanPanel, "^", UDim2.new(0, 60, 0, 60), UDim2.new(0, 14, 0, 18), SIGNAL, 44, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
scanArrow.TextYAlignment = Enum.TextYAlignment.Center

local scanClass = label(scanPanel, "NO SIGNAL", UDim2.new(1, -90, 0, 24), UDim2.new(0, 84, 0, 18), INK, 18)
local scanBand  = label(scanPanel, "—", UDim2.new(1, -90, 0, 20), UDim2.new(0, 84, 0, 42), DIM, 14)
local scanHint  = label(scanPanel, "[E] SWEEP", UDim2.new(1, -90, 0, 18), UDim2.new(0, 84, 0, 64), SIGNAL, 12)

-- Strength bar under the readout
local barBg = Instance.new("Frame")
barBg.Size              = UDim2.new(1, -28, 0, 3)
barBg.Position          = UDim2.new(0, 14, 1, -10)
barBg.BackgroundColor3  = Color3.fromRGB(50, 58, 68)
barBg.BorderSizePixel   = 0
barBg.Parent            = scanPanel

local barFill = Instance.new("Frame")
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = SIGNAL
barFill.BorderSizePixel  = 0
barFill.Parent           = barBg

-- Return to surface now lives in the action bar (SurfaceUI), not here.
-- Controls hint, bottom left
-- Centred just above the pickaxe hotbar. It used to sit in the bottom-left,
-- which is now the player card.
local hint = label(gui, "HOLD [LMB] DIG   ·   [E] SWEEP   ·   [SHIFT] RUN", UDim2.new(0, 420, 0, 18),
	UDim2.new(0.5, 0, 1, -94), DIM, 12, nil, Enum.TextXAlignment.Center)
hint.AnchorPoint = Vector2.new(0.5, 1)

-- ── Audio hooks ──────────────────────────────────────────────────────────────
-- Drop Creator Store sound ids in here. The scanner ping is the single most
-- important piece of feedback in the game — it carries the whole loop.
local SOUND_IDS = {
	scanPing = "",   -- e.g. "rbxassetid://..."
	digHit   = "",
	oreGet   = "",
}

local function makeSound(id)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume  = 0.5
	s.Parent  = gui
	return s
end

local sounds = {}
for key, id in pairs(SOUND_IDS) do
	if id ~= "" then sounds[key] = makeSound(id) end
end

local function play(key, pitch)
	local s = sounds[key]
	if not s then return end
	s.PlaybackSpeed = pitch or 1
	s:Play()
end

-- ── Depth readout ────────────────────────────────────────────────────────────

-- Which stratum begins next, and how far down it is
local function nextStratum(y)
	local best, bestTop = nil, -math.huge
	for _, s in ipairs(StrataConfig.Strata) do
		if s.top < y and s.top > bestTop then
			best, bestTop = s, s.top
		end
	end
	return best
end

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local y       = root.Position.Y
	local surface = y >= StrataConfig.Mine.SurfaceY - 2
	local stratum = StrataConfig.GetStratum(y)

	-- Zeroed at the shaft mouth and never negative: standing on the camp deck
	-- reads 0m rather than −9m, and every stratum depth in the config lines up
	-- with what the banner shows.
	depthValue.Text = string.format("%dm", math.max(0, math.floor(-y)))
	depthName.Text  = surface and "SURFACE" or string.upper(stratum.name)

	-- Brightened so the band reads on the dark panel
	depthBar.BackgroundColor3 = stratum.color:Lerp(Color3.fromRGB(255, 255, 255), 0.28)

	local ahead = nextStratum(y)
	if not ahead then
		depthAhead.Text = ""
	else
		local metres  = math.floor(y - ahead.top)
		local canMine = miningPower >= (ahead.hardness or 1)
		depthAhead.Text = string.format("%s\n%dm below", string.upper(ahead.name), metres)
		depthAhead.TextColor3 = canMine and DIM or Color3.fromRGB(214, 158, 60)
	end
end)

-- ── Digging ──────────────────────────────────────────────────────────────────

local digging     = false
local lastDigSent = 0

-- Only terrain is a valid dig target. Including *just* the Terrain object means
-- the spawn pad, ore crystals and the character never block the cursor — the
-- old exclude-the-character version let the pad eat every click.
local oreFolder = workspace:WaitForChild("OreNodes")
-- Contract objectives. Their own folder so the ray can tell an objective apart
-- from a lump of ore without inspecting every model it hits.
local depositFolder = workspace:WaitForChild("SiteDeposits")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain, oreFolder, depositFolder }
rayParams.IgnoreWater = true

-- The ray starts at the camera, which in third person sits well behind the
-- character — so it has to be cast long and the *reach* checked separately
-- from the character. Capping the ray at reach length is why zoomed-out
-- aiming found nothing.
local RAY_LENGTH = 512

-- Returns the aim point, whether it is in reach, and the ore node under the
-- cursor if there is one. Nodes take priority: if you are pointing at ore, you
-- swing at the ore rather than the rock behind it.
local function digTarget()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return nil, false, nil end

	-- GetMouseLocation includes the topbar inset, so ScreenPointToRay is the
	-- matching conversion — ViewportPointToRay would aim ~36px high.
	local mousePos = UserInputService:GetMouseLocation()
	local ray      = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
	local hit      = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, rayParams)
	if not hit then return nil, false, nil end

	local deposit = hit.Instance:FindFirstAncestorWhichIsA("Model")
	if deposit and deposit.Parent == depositFolder then
		local pos = deposit:GetPivot().Position
		return pos, (root.Position - pos).Magnitude <= StrataConfig.Dig.MaxDistance,
			deposit, true
	end

	local node = hit.Instance:FindFirstAncestorWhichIsA("Model")
	if node and node.Parent == oreFolder then
		local pos = node:GetPivot().Position
		return pos, (root.Position - pos).Magnitude <= StrataConfig.Dig.MaxDistance, node
	end

	-- Aim slightly *into* the rock so the ball actually removes material
	local target  = hit.Position - hit.Normal * (StrataConfig.Dig.Radius * 0.5)
	local inReach = (root.Position - target).Magnitude <= StrataConfig.Dig.MaxDistance
	return target, inReach, nil
end

-- ── Dig cursor ───────────────────────────────────────────────────────────────
-- Shows exactly where a click would land, and whether it would land at all.

local cursor = Instance.new("Part")
cursor.Name         = "DigCursor"
cursor.Shape        = Enum.PartType.Ball
cursor.Size         = Vector3.new(1, 1, 1) * StrataConfig.Dig.Radius * 2
cursor.Anchored     = true
cursor.CanCollide   = false
cursor.CanQuery     = false
cursor.CanTouch     = false
cursor.CastShadow   = false
cursor.Material     = Enum.Material.Neon
cursor.Color        = SIGNAL
cursor.Transparency = 0.82
cursor.Parent       = workspace

local OUT_OF_REACH = StrataConfig.UI.Warning
local TOO_HARD     = Color3.fromRGB(214, 158, 60)

local CURSOR_ROCK = Vector3.new(1, 1, 1) * StrataConfig.Dig.Radius * 2
local CURSOR_NODE = Vector3.new(1, 1, 1) * 4.5

RunService.RenderStepped:Connect(function()
	local target, inReach, node, isDeposit = digTarget()
	if not target then
		cursor.Transparency = 1
		return
	end

	cursor.Position = target

	-- Over a node the cursor tightens and takes the ore's colour, so it is
	-- obvious you are about to swing at ore rather than at the wall. A contract
	-- deposit gets the same treatment in its own colour, because missing one of
	-- those costs you the run rather than a lump of rock.
	if isDeposit then
		cursor.Size         = CURSOR_NODE
		cursor.Transparency = inReach and 0.62 or 0.9
		cursor.Color        = inReach and Color3.fromRGB(255, 208, 120) or OUT_OF_REACH
		return
	elseif node then
		cursor.Size         = CURSOR_NODE
		cursor.Transparency = inReach and 0.7 or 0.92
		local ore = StrataConfig.GetOre(node:GetAttribute("OreId"))
		cursor.Color = inReach and (ore and ore.color or SIGNAL) or OUT_OF_REACH
		return
	end

	cursor.Size = CURSOR_ROCK

	local hardEnough = miningPower >= (StrataConfig.GetStratum(target.Y).hardness or 1)

	if not inReach then
		cursor.Transparency = 0.93
		cursor.Color        = OUT_OF_REACH
	elseif not hardEnough then
		-- Amber rather than red: you can get here, you just can't break it yet
		cursor.Transparency = 0.88
		cursor.Color        = TOO_HARD
	else
		cursor.Transparency = 0.82
		cursor.Color        = SIGNAL
	end
end)

local function digBurst(position, colour)
	local p = Instance.new("Part")
	p.Size         = Vector3.new(1, 1, 1)
	p.CFrame       = CFrame.new(position)
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false
	p.Transparency = 1
	p.Parent       = workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Texture      = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color        = ColorSequence.new(colour)
	pe.Size         = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime     = NumberRange.new(0.3, 0.6)
	pe.Speed        = NumberRange.new(6)
	pe.SpreadAngle  = Vector2.new(180, 180)
	pe.Rate         = 0
	pe.Parent       = p
	pe:Emit(14)

	task.delay(1, function() p:Destroy() end)
end

-- ── Feel ─────────────────────────────────────────────────────────────────────
-- The terrain carve itself is instant — voxels flip from solid to air and there
-- is no tweening that. Everything below exists to hide that instant behind a
-- physical cause: debris, a swing, and a camera punch.

local Debris = game:GetService("Debris")

-- Rock chunks thrown out of the hole.
local function spawnDebris(position, colour, material)
	for _ = 1, math.random(StrataConfig.Feel.DebrisMin, StrataConfig.Feel.DebrisMax) do
		local chunk = Instance.new("Part")
		local s     = 0.4 + math.random() * 0.55
		chunk.Size         = Vector3.new(s, s, s * (0.7 + math.random() * 0.6))
		chunk.CFrame       = CFrame.new(position + Vector3.new(
			math.random(-2, 2), math.random(-1, 2), math.random(-2, 2)
		)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Color        = colour
		chunk.Material     = material or Enum.Material.Slate
		chunk.CanCollide   = false
		chunk.CanQuery     = false
		chunk.CanTouch     = false
		chunk.CastShadow   = false
		chunk.Parent       = workspace

		chunk.AssemblyLinearVelocity = Vector3.new(
			math.random(-14, 14), math.random(8, 20), math.random(-14, 14)
		)
		chunk.AssemblyAngularVelocity = Vector3.new(
			math.random(-12, 12), math.random(-12, 12), math.random(-12, 12)
		)

		TweenService:Create(chunk, TweenInfo.new(0.9, Enum.EasingStyle.Linear), {
			Transparency = 1,
			Size         = chunk.Size * 0.3,
		}):Play()
		Debris:AddItem(chunk, 1.0)
	end
end

-- ── Pickaxe and swing ────────────────────────────────────────────────────────
-- Built from parts and welded to the hand. The swing drives the shoulder
-- Motor6D's Transform directly, which overrides the animator for that frame —
-- so no published animation asset is involved.

-- Every joint here is a Weld with an explicit C0, which drives the offset every
-- frame. A WeldConstraint only captures the offset once, so anything that moves
-- afterwards gets left behind — that was the detached pickaxe head.
local function rigidPart(parent, name, size, colour, material)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.Color         = colour
	p.Material      = material or Enum.Material.SmoothPlastic
	p.CanCollide    = false
	p.CanQuery      = false
	p.CanTouch      = false
	p.Massless      = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent        = parent
	return p
end

local function boltTo(base, part, c0)
	part.CFrame = base.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Part0  = base
	weld.Part1  = part
	weld.C0     = c0
	weld.Parent = base
	return weld
end

local function buildPickaxe()
	local model = Instance.new("Model")
	model.Name = "StrataPickaxe"

	-- Shaft runs along its own Y, head sits at the top
	local handle = rigidPart(model, "Handle", Vector3.new(0.16, 2.5, 0.16),
		Color3.fromRGB(96, 66, 45), Enum.Material.Wood)
	model.PrimaryPart = handle

	-- Rotated a quarter turn about the shaft so the head lies in the swing
	-- plane — front-to-back — instead of sticking out sideways like a crossbar.
	local head = rigidPart(model, "Head", Vector3.new(0.26, 0.3, 1.7),
		Color3.fromRGB(126, 132, 141), Enum.Material.Metal)
	boltTo(handle, head, CFrame.new(0, 1.12, 0))

	local tip = rigidPart(model, "Tip", Vector3.new(0.2, 0.2, 0.45),
		Color3.fromRGB(168, 172, 178), Enum.Material.Metal)
	boltTo(handle, tip, CFrame.new(0, 1.12, -0.95))

	local butt = rigidPart(model, "Butt", Vector3.new(0.22, 0.2, 0.5),
		Color3.fromRGB(104, 110, 118), Enum.Material.Metal)
	boltTo(handle, butt, CFrame.new(0, 1.12, 0.92))

	local grip = rigidPart(model, "Grip", Vector3.new(0.21, 0.7, 0.21),
		Color3.fromRGB(48, 44, 42), Enum.Material.Fabric)
	boltTo(handle, grip, CFrame.new(0, -0.55, 0))

	return model, handle
end


local pickaxe
-- The weld the swing actually drives. Keeping the rest pose lets the animation
-- be expressed as an offset from it rather than as absolute CFrames.
local pickWeld, pickRest

local function attachPickaxe(char)
	if pickaxe then pickaxe:Destroy(); pickaxe = nil end
	pickWeld, pickRest = nil, nil

	local r15  = char:FindFirstChild("RightHand")
	local hand = r15 or char:FindFirstChild("Right Arm")
	if not hand then
		if StrataConfig.Debug then
			warn("[MineClient] no right hand found; pickaxe not attached")
		end
		return
	end

	-- The best pick you own is the one in your hand. Picks without a model yet
	-- fall back to the plain starter pick.
	local model, handle = ItemModels.BuildHeld(heldPickId)
	if not model then model, handle = buildPickaxe() end
	model.Parent = char

	pickRest = r15 and StrataConfig.Grip.PickaxeR15 or StrataConfig.Grip.PickaxeR6
	pickWeld = boltTo(hand, handle, pickRest)
	pickaxe  = model

	if StrataConfig.Debug then
		print("[MineClient] pickaxe attached to " .. hand.Name)
	end
end



-- ── Swing ────────────────────────────────────────────────────────────────────
-- Written straight onto the joints one render step after the animator, so it
-- overrides the idle pose for that frame only. This is why no published
-- animation asset is needed — nothing is uploaded, it is just arithmetic on
-- Motor6D.Transform every frame.

-- Motor6D joints hang off the *child* limb in R15 (RightShoulder lives inside
-- RightUpperArm, RightElbow inside RightLowerArm) but off the Torso in R6.
-- Guessing at the parent is how this silently did nothing; find them by name
-- instead and the rig layout stops mattering.
-- Arm joints are a bonus, not the mechanism. Some rigs expose no Motor6D at
-- all, so the swing must not depend on finding one — the pickaxe weld below is
-- what actually carries the animation. Cached unconditionally so a miss cannot
-- turn into a per-frame rescan.
local jointCache, jointChar = nil, nil
local rigReported = false

local function resolveJoints(char)
	-- JointInstance, not Motor6D: rigs vary, and a Motor6D-only search finds
	-- nothing on a rig whose joints are a sibling class. The names are stable
	-- even when the class is not.
	local motors, names = {}, {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("JointInstance") and d.Name ~= "Weld" then
			motors[d.Name] = d
			table.insert(names, d.ClassName .. ":" .. d.Name)
		end
	end

	local found = {
		shoulder = motors["RightShoulder"] or motors["Right Shoulder"],
		elbow    = motors["RightElbow"],
		waist    = motors["Waist"],
	}

	-- Only lock the result in once something turned up. Caching a miss is how
	-- a slow-assembling rig gets permanently written off.
	if found.shoulder then
		jointChar  = char
		jointCache = found
		if StrataConfig.Debug then
			table.sort(names)
			print("[MineClient] arm joints found: " .. table.concat(names, ", "))
		end
	end

	return found
end

-- Runs once per character when no joints turn up, so the rig can be identified
-- instead of guessed at. Only rig joints are listed: armour and the pickaxe
-- attach with plain Welds, and a full set of those buried the actual answer.
local function dumpRig(char)
	if not StrataConfig.Debug then return end

	local lines = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Bone") then
			table.insert(lines, d.ClassName .. ":" .. d.Name .. " in " .. d.Parent.Name)
		end
	end
	warn("[MineClient] no arm joints. Rig joints found: " ..
		(#lines > 0 and table.concat(lines, " | ") or "absolutely none"))

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		warn(("[MineClient] Humanoid RigType=%s, parts=%d")
			:format(tostring(humanoid.RigType), #char:GetChildren()))
	else
		warn("[MineClient] no Humanoid on character at all")
	end
end

local function swingJoints()
	local char = player.Character
	if not char then return nil end
	if jointChar == char and jointCache then return jointCache end
	return resolveJoints(char)
end

local SW       = StrataConfig.Swing
local swingSpan = SW.Windup + SW.Chop + SW.Recover
local swingAt  = math.huge   -- seconds since this swing began
local impactFired = true

-- Fired the instant the head lands, so debris and kick line up with contact
-- rather than with the button press.
local onImpact = nil

local swingCount = 0
-- Where the arc currently sits, so a new swing can pick up from the live pose
-- instead of snapping to zero. Digs repeat every 0.28s and the swing lasts
-- 0.28s, so swings always overlap — without this the tool visibly jumps.
local liveAngle, liveElbow, liveLean = 0, 0, 0
local fromAngle, fromElbow, fromLean = 0, 0, 0

local function startSwing()
	fromAngle, fromElbow, fromLean = liveAngle, liveElbow, liveLean
	swingAt     = 0
	impactFired = false
	swingCount += 1
	if StrataConfig.Debug and swingCount == 1 then
		print("[MineClient] swinging (tool weld: " .. (pickWeld and "yes" or "MISSING") .. ")")
	end
end

-- Smoothstep: zero velocity at both ends, so phases join without a kink.
local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- Returns shoulder angle, elbow angle, torso lean for a point in the swing.
local function swingPose(t)
	local raise = math.rad(SW.RaiseDeg)
	local chop  = math.rad(SW.ChopDeg)
	local elbow = math.rad(SW.ElbowDeg)
	local lean  = math.rad(SW.LeanDeg)

	if t < SW.Windup then
		-- Blend out of wherever the previous swing left the arc
		local a = smooth(t / SW.Windup)
		return fromAngle + (raise - fromAngle) * a,
		       fromElbow + (elbow - fromElbow) * a,
		       fromLean + (-lean * 0.4 - fromLean) * a

	elseif t < SW.Windup + SW.Chop then
		-- Accelerate into the rock: this phase should *not* be symmetric
		local a = (t - SW.Windup) / SW.Chop
		local e = a * a
		return raise + (chop - raise) * e,
		       elbow * (1 - e),
		       -lean * 0.4 + lean * 1.4 * e

	else
		local a = smooth((t - SW.Windup - SW.Chop) / SW.Recover)
		return chop * (1 - a), 0, lean * (1 - a)
	end
end

RunService:BindToRenderStep("StrataSwing", Enum.RenderPriority.Character.Value + 1, function(dt)
	if swingAt > swingSpan then return end
	swingAt += dt

	local shoulder, elbow, lean = swingPose(math.min(swingAt, swingSpan))
	liveAngle, liveElbow, liveLean = shoulder, elbow, lean
	local dir = SW.Direction

	-- Primary: swing the tool around the hand. This works on any rig, because
	-- the weld is ours — nothing about the character has to cooperate.
	if pickWeld and pickRest then
		pickWeld.C0 = CFrame.Angles(shoulder * dir * SW.ToolGain, 0, 0) * pickRest
	end

	-- Bonus: if the rig does expose joints, move the arm along with it.
	local joints = swingJoints()
	if joints and joints.shoulder then
		joints.shoulder.Transform = joints.shoulder.Transform * CFrame.Angles(shoulder * dir, 0, 0)
		if joints.elbow then
			joints.elbow.Transform = joints.elbow.Transform * CFrame.Angles(elbow * dir, 0, 0)
		end
		if joints.waist then
			joints.waist.Transform = joints.waist.Transform * CFrame.Angles(lean * dir, 0, 0)
		end
	end

	-- Contact is the end of the chop, not the start of the animation
	if not impactFired and swingAt >= SW.Windup + SW.Chop then
		impactFired = true
		if onImpact then
			local fire = onImpact
			onImpact = nil
			fire()
		end
	end
end)

-- ── Camera kick ──────────────────────────────────────────────────────────────

-- One punch per dig: the direction is chosen once at trigger time and then
-- eased out. Re-randomising per frame is what turns a kick into a rattle.
local kick, kickYaw = 0, 0

local function addKick()
	kick    = 1
	kickYaw = (math.random() - 0.5) * 0.5
end

RunService:BindToRenderStep("StrataKick", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if kick <= 0.001 then return end
	kick = math.max(kick - dt * StrataConfig.Feel.KickDecay, 0)

	local amp = StrataConfig.Feel.CameraKick
	if amp <= 0 then return end

	local eased = kick * kick  -- lands hard, settles fast
	camera.CFrame = camera.CFrame * CFrame.Angles(
		math.rad(amp * eased),
		math.rad(amp * kickYaw * eased),
		0
	)
end)

-- ── Scanner pulse ────────────────────────────────────────────────────────────

local function scanPulse(colour)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local ring = Instance.new("Part")
	ring.Shape        = Enum.PartType.Ball
	ring.Size         = Vector3.new(2, 2, 2)
	ring.Position     = root.Position
	ring.Anchored     = true
	ring.CanCollide   = false
	ring.CanQuery     = false
	ring.CanTouch     = false
	ring.CastShadow   = false
	ring.Material     = Enum.Material.Neon
	ring.Color        = colour
	ring.Transparency = 0.6
	ring.Parent       = workspace

	TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size         = Vector3.new(1, 1, 1) * StrataConfig.Scanner.Radius * 1.4,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.95)
end

-- Ghost crystal that flies to the player when one is picked up.
local function collectFlight(position, colour)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local ghost = Instance.new("Part")
	ghost.Shape        = Enum.PartType.Ball
	ghost.Size         = Vector3.new(1.4, 1.4, 1.4)
	ghost.Position     = position
	ghost.Anchored     = true
	ghost.CanCollide   = false
	ghost.CanQuery     = false
	ghost.CanTouch     = false
	ghost.CastShadow   = false
	ghost.Material     = Enum.Material.Neon
	ghost.Color        = colour
	ghost.Transparency = 0.15
	ghost.Parent       = workspace

	local t0   = os.clock()
	local from = position
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not ghost.Parent then conn:Disconnect(); return end
		local a = math.min((os.clock() - t0) / 0.42, 1)
		local to = root.Position + Vector3.new(0, 1, 0)
		ghost.Position     = from:Lerp(to, a * a)
		ghost.Size         = Vector3.new(1, 1, 1) * (1.4 * (1 - a) + 0.2)
		ghost.Transparency = 0.15 + a * 0.85
		if a >= 1 then
			conn:Disconnect()
			ghost:Destroy()
		end
	end)
	Debris:AddItem(ghost, 0.8)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		digging = true
	elseif input.KeyCode == Enum.KeyCode.E then
		scanRequest:FireServer()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		digging = false
	end
end)

RunService.Heartbeat:Connect(function()
	if not digging then return end
	local now = os.clock()
	if now - lastDigSent < (digCooldown or StrataConfig.Dig.Cooldown) then return end

	local target, inReach, node, isDeposit = digTarget()
	if not target or not inReach then return end

	lastDigSent = now
	-- Swing immediately rather than waiting for the server to confirm. The
	-- round trip is what made the old swing feel detached from the click.
	startSwing()

	if isDeposit then
		depositHit:FireServer(node)
	elseif node then
		mineNode:FireServer(node)
	else
		digRequest:FireServer(target)
	end
end)

digResult.OnClientEvent:Connect(function(position, value, stratumId, strengthGained)
	-- Each dig breaks off saleable rock, so the haul value ticks up with it
	setHaul(haulTotal + (value or 0))
	-- Applied locally so the readout keeps up with the swing rate; the server
	-- holds the real number and resyncs on any economy action.
	if strengthGained then
		localStrength = localStrength + strengthGained
		miningPower   = miningPower + strengthGained
		strengthValue.Text = tostring(miningPower)
		strengthSub.Text   = "STRENGTH " .. tostring(localStrength)
	end

	local stratum = nil
	for _, s in ipairs(StrataConfig.Strata) do
		if s.id == stratumId then stratum = s end
	end
	local colour = stratum and stratum.color or Color3.fromRGB(120, 120, 120)

	-- Everything that reads as impact waits for the head to actually land.
	local function impact()
		digBurst(position, colour)
		-- Slate rather than the stratum's own material: several terrain
		-- materials are terrain-only and error when assigned to a Part.
		spawnDebris(position, colour, Enum.Material.Slate)
		addKick()
		play("digHit", 0.9 + math.random() * 0.2)
	end

	if impactFired then
		impact()          -- the swing already landed; don't hold the feedback
	else
		onImpact = impact -- land it exactly on contact
	end
end)

-- ── Scanner ──────────────────────────────────────────────────────────────────

local currentSignal = nil   -- { direction, band, class, strength, expires }

scanResult.OnClientEvent:Connect(function(result)
	scanPulse(result and (result.class == "ANOMALOUS" and ORE or SIGNAL) or DIM)

	if not result then
		currentSignal   = nil
		scanClass.Text  = "NO SIGNAL"
		scanClass.TextColor3 = DIM
		scanBand.Text   = "nothing in range"
		scanArrow.TextTransparency = 0.75
		barFill:TweenSize(UDim2.new(0, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.25, true)
		play("scanPing", 0.7)
		return
	end

	currentSignal = {
		direction = result.direction,
		strength  = result.strength,
		expires   = os.clock() + StrataConfig.Scanner.Cooldown + 1.5,
	}

	scanClass.Text = result.class
	scanClass.TextColor3 = result.class == "ANOMALOUS" and ORE
		or result.class == "STRONG" and SIGNAL
		or INK
	scanBand.Text  = result.band
	scanArrow.TextTransparency = 0

	barFill:TweenSize(UDim2.new(result.strength, 0, 1, 0),
		Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)

	-- Pitch rises as you close on it — the metal-detector cue
	play("scanPing", 0.85 + result.strength * 0.7)
end)

-- Arrow points toward the signal, relative to where the camera is facing.
RunService.RenderStepped:Connect(function()
	if not currentSignal then return end
	if os.clock() > currentSignal.expires then
		currentSignal = nil
		scanArrow.TextTransparency = 0.75
		scanClass.Text = "NO SIGNAL"
		scanClass.TextColor3 = DIM
		scanBand.Text = "sweep again"
		return
	end

	local dir  = currentSignal.direction
	local look = camera.CFrame.LookVector

	local flatDir  = Vector3.new(dir.X, 0, dir.Z)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatDir.Magnitude < 0.01 or flatLook.Magnitude < 0.01 then return end
	flatDir  = flatDir.Unit
	flatLook = flatLook.Unit

	local right   = Vector3.new(flatLook.Z, 0, -flatLook.X)
	local angle   = math.deg(math.atan2(flatDir:Dot(right), flatDir:Dot(flatLook)))
	scanArrow.Rotation = angle

	local vertical = dir.Y > 0.4 and "ABOVE"
		or dir.Y < -0.4 and "BELOW"
		or "LEVEL"
	scanHint.Text = vertical .. "  ·  [E] SWEEP"
end)

-- ── Stats and pickups ────────────────────────────────────────────────────────

stateChanged.OnClientEvent:Connect(function(s)
	packValue.Text = s.carried .. " / " .. s.capacity
	setCash(s.credits or 0)
	setHaul(s.worth or 0)

	if s.pickaxe ~= heldPickId then
		heldPickId = s.pickaxe
		if player.Character then attachPickaxe(player.Character) end
	end
	packValue.TextColor3 = s.carried >= s.capacity and ORE or INK
	digCooldown = s.digCooldown or digCooldown

	if s.strength then
		localStrength      = s.strength
		miningPower        = s.miningPower or s.strength
		strengthValue.Text = tostring(miningPower)
		strengthSub.Text   = "STRENGTH " .. tostring(localStrength)
	end
end)

oreCollected.OnClientEvent:Connect(function(oreId, value, position)
	local ore = StrataConfig.GetOre(oreId)
	play("oreGet", 1)

	if position then
		collectFlight(position, ore and ore.color or ORE)
	end

	local pop = Instance.new("TextLabel")
	pop.Size                   = UDim2.new(0, 260, 0, 34)
	pop.AnchorPoint            = Vector2.new(0.5, 0.5)
	pop.Position               = UDim2.new(0.5, math.random(-70, 70), 0.80, 0)
	pop.BackgroundTransparency = 1
	-- Count first, value second. Showing "+25" alone read as if the pack had
	-- gained 25 of something, when 25 is what the single stone is worth.
	pop.Text                   = "+1  " .. (ore and ore.name or oreId) .. "   ·   " .. value .. "cr"
	pop.TextColor3             = ore and ore.color or ORE
	pop.TextSize               = 20
	pop.Font                   = StrataConfig.UI.Number
	pop.Parent                 = gui

	local stroke = Instance.new("UIStroke", pop)
	stroke.Color     = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2

	TweenService:Create(pop, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position         = UDim2.new(0.5, math.random(-70, 70), 0.68, 0),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(1.1), { Transparency = 1 }):Play()
	task.delay(1.2, function() pop:Destroy() end)
end)

-- ── Ore nodes ────────────────────────────────────────────────────────────────
-- HP is an attribute the server owns, so it replicates on its own and every
-- client sees the same bar without a per-hit remote.

local function watchNode(model)
	if not model:IsA("Model") or not model:GetAttribute("MaxHP") then return end

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local bar  = root and root:FindFirstChild("OreBar")
	local fill = bar and bar:FindFirstChild("Fill", true)
	if not (root and fill) then return end

	local basePivot = model:GetPivot()

	model:GetAttributeChangedSignal("HP"):Connect(function()
		local hp  = model:GetAttribute("HP") or 0
		local max = model:GetAttribute("MaxHP") or 1
		local pct = math.clamp(hp / max, 0, 1)

		TweenService:Create(fill, TweenInfo.new(0.12), {
			Size = UDim2.new(pct, 0, 1, 0),
		}):Play()

		-- Rock jolts on the strike, then settles
		if model.Parent then
			local jolt = basePivot * CFrame.new(
				(math.random() - 0.5) * 0.45, -0.16, (math.random() - 0.5) * 0.45)
			model:PivotTo(jolt)
			task.delay(0.07, function()
				if model.Parent then model:PivotTo(basePivot) end
			end)
		end
	end)
end

for _, child in ipairs(oreFolder:GetChildren()) do watchNode(child) end
oreFolder.ChildAdded:Connect(function(child)
	task.wait()   -- let the attributes and parts finish replicating
	watchNode(child)
end)

-- Chips fly off the node on every strike, and it bursts when it gives way
nodeHit.OnClientEvent:Connect(function(model, damage, broke)
	if not model or not model.Parent then return end

	local ore    = StrataConfig.GetOre(model:GetAttribute("OreId"))
	local colour = ore and ore.color or Color3.fromRGB(200, 200, 200)
	local at     = model:GetPivot().Position

	spawnDebris(at, colour, Enum.Material.Slate)
	addKick()
	play("digHit", 0.9 + math.random() * 0.2)

	if broke then
		digBurst(at, colour)
		spawnDebris(at, colour, Enum.Material.Slate)
	end
end)

-- ── Too-hard feedback ────────────────────────────────────────────────────────
-- Throttled, because the dig loop fires continuously while the button is held
-- and a message per attempt would be a strobe.

local lastBlockShown = 0

-- A line of text that rises and fades in the middle of the screen, for anything
-- that stops a swing doing what it should. Rate-limited, because the thing that
-- blocks a swing usually blocks the next one too.
local function floatingWarning(text, colour)
	local now = os.clock()
	if now - lastBlockShown < 1.4 then return end
	lastBlockShown = now

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(0, 520, 0, 28)
	lbl.AnchorPoint            = Vector2.new(0.5, 0)
	lbl.Position               = UDim2.new(0.5, 0, 0.34, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = text
	lbl.TextColor3             = colour or Color3.fromRGB(214, 158, 60)
	lbl.TextSize               = 16
	lbl.Font                   = StrataConfig.UI.Number
	lbl.Parent                 = gui

	local stroke = Instance.new("UIStroke", lbl)
	stroke.Color     = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2

	TweenService:Create(lbl, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position         = UDim2.new(0.5, 0, 0.30, 0),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(1.3), { Transparency = 1 }):Play()
	task.delay(1.4, function() lbl:Destroy() end)
end

digBlocked.OnClientEvent:Connect(function(stratumName, needed, have)
	-- No power number means it was not the rock that refused: it was the
	-- contract. A job is for one layer and the seams either side of it hold.
	if not needed then
		floatingWarning(("THE CONTRACT DOES NOT REACH PAST THE %s SEAM")
			:format(string.upper(stratumName)), Color3.fromRGB(224, 106, 84))
		return
	end

	floatingWarning(("%s IS TOO HARD — POWER %d NEEDED, YOU HAVE %d")
		:format(string.upper(stratumName), needed, have))
end)

-- A broken node with nowhere to go stays in the ground. Without this the ore
-- just refuses to break, with no reason given.
local packFull = remotes:WaitForChild("PackFull")

packFull.OnClientEvent:Connect(function()
	floatingWarning("PACK FULL — SELL AT THE DEPOT", Color3.fromRGB(226, 137, 74))
end)

-- Wrapped in a function so its locals belong to it rather than to this file,
-- which has its own ceiling of 200 to stay under.
;(function()
-- ── Player card ──────────────────────────────────────────────────────────────
-- Top left, under the Roblox topbar. A hexagonal portrait with your level cut
-- into the bottom of it, and beside it your name, your rank stars, your health
-- and your experience.
--
-- Roblox has no polygon, so the hexagon is three rectangles rotated sixty
-- degrees apart. That gives a real six-sided silhouette; the portrait itself is
-- the round headshot Roblox serves, sitting inside it.

local UIP = StrataConfig.UI
local CARD = HUD.Card

local card = Instance.new("Frame")
card.Name             = "PlayerCard"
card.Size             = UDim2.new(0, CARD.W, 0, CARD.H)
card.AnchorPoint      = Vector2.new(0, 1)
card.Position         = UDim2.new(0, CARD.X, 1, -CARD.Bottom)
card.BackgroundColor3 = UIP.Stone
card.BorderSizePixel  = 0
card.Parent           = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

local cardEdge = Instance.new("UIStroke", card)
cardEdge.Color     = UIP.StoneDark
cardEdge.Thickness = 3

-- Lit along the top like a slab catching the light
local cardFace = Instance.new("UIGradient", card)
cardFace.Rotation = 90
cardFace.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, UIP.StoneLit),
	ColorSequenceKeypoint.new(0.35, UIP.Stone),
	ColorSequenceKeypoint.new(1, UIP.StoneDeep),
})

-- Granite: a scatter of pale grains, fixed so it never crawls
local grain = Instance.new("Frame")
grain.Size             = UDim2.fromScale(1, 1)
grain.BackgroundTransparency = 1
grain.ClipsDescendants = true
grain.Parent           = card
Instance.new("UICorner", grain).CornerRadius = UDim.new(0, 14)

local seed = 20261
for i = 1, 46 do
	seed = (seed * 48271) % 2147483647
	local sx = seed % CARD.W
	seed = (seed * 48271) % 2147483647
	local sy = seed % CARD.H
	local fleck = Instance.new("Frame")
	fleck.Size                   = UDim2.new(0, 2, 0, 2)
	fleck.Position               = UDim2.new(0, sx, 0, sy)
	fleck.BackgroundColor3       = UIP.Speckle
	fleck.BackgroundTransparency = 0.72
	fleck.BorderSizePixel        = 0
	fleck.Parent                 = grain
end

-- ── The hexagon ──────────────────────────────────────────────────────────────

local HEX = 74

local function hexPlate(parent, size, colour, z)
	local hub = Instance.new("Frame")
	hub.Size                   = UDim2.new(0, size, 0, size)
	hub.BackgroundTransparency = 1
	hub.ZIndex                 = z
	hub.Parent                 = parent

	-- Three bars at sixty degrees. A hexagon is exactly the union of them.
	for i = 0, 2 do
		local bar = Instance.new("Frame")
		bar.Size             = UDim2.new(0, size, 0, size * 0.578)
		bar.AnchorPoint      = Vector2.new(0.5, 0.5)
		bar.Position         = UDim2.new(0.5, 0, 0.5, 0)
		bar.Rotation         = i * 60
		bar.BackgroundColor3 = colour
		bar.BorderSizePixel  = 0
		bar.ZIndex           = z
		bar.Parent           = hub
	end
	return hub
end

local hexHolder = Instance.new("Frame")
hexHolder.Size                   = UDim2.new(0, HEX, 0, HEX)
hexHolder.Position               = UDim2.new(0, 10, 0, 8)
hexHolder.BackgroundTransparency = 1
hexHolder.ZIndex                 = 2
hexHolder.Parent                 = card

hexPlate(hexHolder, HEX, UIP.Ore, 2)
hexPlate(hexHolder, HEX - 7, UIP.StoneDark, 3).Position = UDim2.new(0, 3.5, 0, 3.5)

-- The portrait, round, sitting in the middle of the hex
local portrait = Instance.new("ImageLabel")
portrait.Size                   = UDim2.new(0, HEX - 22, 0, HEX - 22)
portrait.Position               = UDim2.new(0, 11, 0, 11)
portrait.BackgroundColor3       = UIP.StoneDeep
portrait.BorderSizePixel        = 0
portrait.ScaleType              = Enum.ScaleType.Fit
portrait.ZIndex                 = 4
portrait.Parent                 = hexHolder
Instance.new("UICorner", portrait).CornerRadius = UDim.new(1, 0)

task.spawn(function()
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and image then portrait.Image = image end
end)

-- Level, cut into the bottom of the hexagon
local levelPlate = Instance.new("Frame")
levelPlate.Size             = UDim2.new(0, 46, 0, 20)
levelPlate.AnchorPoint      = Vector2.new(0.5, 0)
levelPlate.Position         = UDim2.new(0, 10 + HEX / 2, 0, 8 + HEX - 11)
levelPlate.BackgroundColor3 = UIP.StoneDark
levelPlate.BorderSizePixel  = 0
levelPlate.ZIndex           = 6
levelPlate.Parent           = card
Instance.new("UICorner", levelPlate).CornerRadius = UDim.new(0, 7)

local levelEdge = Instance.new("UIStroke", levelPlate)
levelEdge.Color     = UIP.Ore
levelEdge.Thickness = 2

local levelValue = label(levelPlate, "1", UDim2.new(1, 0, 1, 0), UDim2.new(),
	UIP.Ore, 14, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
levelValue.ZIndex = 7

-- ── Name, stars, bars ────────────────────────────────────────────────────────

local COL = 10 + HEX + 12

local nameLabel = label(card, player.DisplayName or player.Name,
	UDim2.new(0, CARD.W - COL - 12, 0, 18), UDim2.new(0, COL, 0, 9),
	UIP.Ink, 16, StrataConfig.UI.Head)
nameLabel.ZIndex       = 3
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Rank stars. Driven off level for now; when the star system proper arrives it
-- reads S.stars instead and nothing else here changes.
local stars = {}
for i = 1, 5 do
	local s = label(card, "*", UDim2.new(0, 13, 0, 16),
		UDim2.new(0, COL + (i - 1) * 14, 0, 28), UIP.StoneLit, 20,
		StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	s.ZIndex = 3
	stars[i] = s
end

local function bar(y, height, trackColour, fillColour)
	local track = Instance.new("Frame")
	track.Size             = UDim2.new(0, CARD.W - COL - 14, 0, height)
	track.Position         = UDim2.new(0, COL, 0, y)
	track.BackgroundColor3 = trackColour
	track.BorderSizePixel  = 0
	track.ZIndex           = 3
	track.Parent           = card
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, math.floor(height / 2))

	local edge = Instance.new("UIStroke", track)
	edge.Color        = UIP.StoneDark
	edge.Thickness    = 1.5
	edge.Transparency = 0.35

	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColour
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 4
	fill.Parent           = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, math.floor(height / 2))

	local shine = Instance.new("UIGradient", fill)
	shine.Rotation = 90
	shine.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)),
	})
	return track, fill
end

local healthTrack, healthFill = bar(50, 15, UIP.StoneDeep, UIP.Moss)
local healthText = label(healthTrack, "100", UDim2.new(1, -8, 1, 0), UDim2.new(0, 4, 0, 0),
	Color3.fromRGB(22, 30, 22), 11, StrataConfig.UI.Head, Enum.TextXAlignment.Right)
healthText.ZIndex = 5

local xpTrack, xpFill = bar(72, 12, UIP.StoneDeep, UIP.Ore)
local xpText = label(xpTrack, "0 / 120", UDim2.new(1, -8, 1, 0), UDim2.new(0, 4, 0, 0),
	Color3.fromRGB(34, 26, 12), 10, StrataConfig.UI.Head, Enum.TextXAlignment.Right)
xpText.ZIndex = 5

-- ── Keeping it current ───────────────────────────────────────────────────────

local shownLevel = 1

local function setStars(n)
	for i, s in ipairs(stars) do
		s.TextColor3 = i <= n and UIP.Ore or UIP.StoneLit
	end
end

stateChanged.OnClientEvent:Connect(function(s)
	local level  = s.level or 1
	local xp     = s.xp or 0
	local needed = math.max(s.xpNeeded or 1, 1)

	levelValue.Text = tostring(level)
	xpText.Text     = ("%d / %d"):format(xp, needed)

	TweenService:Create(xpFill, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(math.clamp(xp / needed, 0, 1), 0, 1, 0) }):Play()

	-- Placeholder until the star system exists: one star per twelve levels
	setStars(s.stars or math.min(math.floor(level / 12), 5))

	if level > shownLevel then
		shownLevel = level
		local pop = Instance.new("UIScale")
		pop.Scale  = 1.45
		pop.Parent = levelPlate
		TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		task.delay(0.6, function() pop:Destroy() end)
		floatingWarning("LEVEL " .. level, UIP.Ore)
	end
end)

-- Health follows the humanoid directly rather than the server state, so it is
-- as immediate as the damage is
local function watchHealth(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if not humanoid then return end

	local function draw()
		local share = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		TweenService:Create(healthFill, TweenInfo.new(0.2), { Size = UDim2.new(share, 0, 1, 0) }):Play()
		healthText.Text = tostring(math.ceil(humanoid.Health))
		healthFill.BackgroundColor3 = share < 0.3 and UIP.Warning
			or (share < 0.6 and UIP.Ore or UIP.Moss)
	end

	humanoid.HealthChanged:Connect(draw)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(draw)
	draw()
end

if player.Character then task.spawn(watchHealth, player.Character) end
player.CharacterAdded:Connect(watchHealth)
end)()   -- player card

-- Wrapped for the same reason as the card above: its locals stay its own.
;(function()
-- ── Hotbar ───────────────────────────────────────────────────────────────────
-- Only what you actually carry. One slot for the pick in your hand — the best
-- one you own is always equipped, so a row of the picks you have *not* got is
-- four slots saying nothing — plus a slot for each tool you have bought.
--
-- It grows as you buy things, which is the progression it is there to show. An
-- empty slot shows nothing, because an empty slot is a promise the UI has no
-- business making.

local UIP = StrataConfig.UI

local hotbar = Instance.new("Frame")
hotbar.Name                   = "Hotbar"
hotbar.AnchorPoint            = Vector2.new(0.5, 1)
hotbar.Position               = UDim2.new(0.5, 0, 1, -18)
hotbar.Size                   = UDim2.new(0, 0, 0, 68)
hotbar.AutomaticSize          = Enum.AutomaticSize.X
hotbar.BackgroundTransparency = 1
hotbar.Parent                 = gui

local hotLayout = Instance.new("UIListLayout", hotbar)
hotLayout.FillDirection       = Enum.FillDirection.Horizontal
hotLayout.Padding             = UDim.new(0, 8)
hotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hotLayout.SortOrder           = Enum.SortOrder.LayoutOrder

-- Tools worth a slot, in the order they should appear. Armour is not here: you
-- wear it, you do not carry it.
local TOOL_SLOTS = { "lamp", "scanner", "pack" }
local TOOL_KEY   = { scanner = "E" }

local hotSignature = nil

local function slotFor(order, spec)
	local slot = Instance.new("Frame")
	slot.Size             = UDim2.new(0, 68, 0, 68)
	slot.BackgroundColor3 = spec.active and Color3.fromRGB(58, 48, 32) or UIP.StoneDeep
	slot.BorderSizePixel  = 0
	slot.LayoutOrder      = order
	slot.ClipsDescendants = true
	slot.Parent           = hotbar
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 10)

	local edge = Instance.new("UIStroke", slot)
	edge.Color     = spec.active and UIP.Ore or UIP.StoneDark
	edge.Thickness = spec.active and 3 or 2.5

	local face = Instance.new("UIGradient", slot)
	face.Rotation = 90
	face.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 168, 172)),
	})

	local art = Instance.new("Frame")
	art.Size                   = UDim2.new(0, 52, 0, 44)
	art.Position               = UDim2.new(0, 8, 0, 4)
	art.BackgroundTransparency = 1
	art.Parent                 = slot

	local drawn = spec.id and ItemModels.Icon(spec.id, art, 44, UDim2.new(0, 4, 0, 0)) or nil
	if not drawn then
		local glyph = label(slot, spec.glyph or "T", UDim2.new(1, 0, 0, 40),
			UDim2.new(0, 0, 0, 8), UIP.Iron, 22, StrataConfig.UI.Head,
			Enum.TextXAlignment.Center)
		glyph.ZIndex = 2
	end

	local name = label(slot, string.upper(spec.name), UDim2.new(1, -6, 0, 12),
		UDim2.new(0, 3, 1, -16), spec.active and UIP.Ore or UIP.Dim, 9,
		StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	name.ZIndex = 2

	if spec.key then
		local keyPlate = Instance.new("Frame")
		keyPlate.Size             = UDim2.new(0, 15, 0, 15)
		keyPlate.Position         = UDim2.new(0, 4, 0, 4)
		keyPlate.BackgroundColor3 = UIP.StoneDark
		keyPlate.BorderSizePixel  = 0
		keyPlate.ZIndex           = 3
		keyPlate.Parent           = slot
		Instance.new("UICorner", keyPlate).CornerRadius = UDim.new(0, 4)

		local k = label(keyPlate, spec.key, UDim2.new(1, 0, 1, 0), UDim2.new(),
			UIP.Crystal, 10, StrataConfig.UI.Number, Enum.TextXAlignment.Center)
		k.ZIndex = 4
	end
end

local function refreshHotbar(state)
	local owned = state.owned or {}

	-- The pick in your hand, whatever it is
	local held = state.pickaxe and GearConfig.Get(state.pickaxe) or nil
	local list = { {
		id     = held and held.id or nil,
		name   = held and (held.name:gsub(" Pick", "")) or "Starter",
		active = true,
		glyph  = "T",
	} }

	-- Then everything else you have bought that you carry
	for _, slotId in ipairs(TOOL_SLOTS) do
		for _, gear in ipairs(GearConfig.Gear) do
			if gear.slot == slotId and owned[gear.id] then
				table.insert(list, {
					id    = gear.id,
					name  = gear.name,
					key   = TOOL_KEY[slotId],
					glyph = "o",
				})
			end
		end
	end

	-- Rebuilding means rebuilding a 3D render per slot, so only when the set
	-- actually changed
	local parts = {}
	for _, s in ipairs(list) do table.insert(parts, tostring(s.id)) end
	local signature = table.concat(parts, "|")
	if signature == hotSignature then return end
	hotSignature = signature

	for _, c in ipairs(hotbar:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for i, spec in ipairs(list) do slotFor(i, spec) end
end

stateChanged.OnClientEvent:Connect(refreshHotbar)

-- Wrapped so its locals stay its own.
;(function()
-- ── Sprint ───────────────────────────────────────────────────────────────────
-- Shift to run. The bar only shows itself while it matters: it fades in when
-- you start spending stamina and fades out again once it is full, so it is not
-- one more thing sitting on screen while you mine.

local UIP = StrataConfig.UI
local SP  = StrataConfig.Sprint

local stamina   = SP.Max
local sprinting = false
local baseSpeed = 16
local restedAt  = 0

local bar = Instance.new("Frame")
bar.Name             = "Stamina"
bar.AnchorPoint      = Vector2.new(0.5, 1)
bar.Position         = UDim2.new(0.5, 0, 1, -112)
bar.Size             = UDim2.new(0, 220, 0, 9)
bar.BackgroundColor3 = UIP.StoneDeep
bar.BorderSizePixel  = 0
bar.BackgroundTransparency = 1
bar.Parent           = gui
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 5)

local barEdge = Instance.new("UIStroke", bar)
barEdge.Color        = UIP.StoneDark
barEdge.Thickness    = 1.5
barEdge.Transparency = 1

local fill = Instance.new("Frame")
fill.Size             = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = UIP.Crystal
fill.BorderSizePixel  = 0
fill.BackgroundTransparency = 1
fill.Parent           = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

local function humanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function applySpeed()
	local h = humanoid()
	if not h then return end
	h.WalkSpeed = baseSpeed * (sprinting and SP.Multiplier or 1)
end

-- The server sets WalkSpeed whenever it pushes state, which happens on every
-- pickup. Re-applying here means a sprint is not cancelled by picking up ore.
stateChanged.OnClientEvent:Connect(function(s)
	baseSpeed = s.walkSpeed or baseSpeed
	applySpeed()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.LeftShift and input.KeyCode ~= Enum.KeyCode.RightShift then
		return
	end
	if stamina < SP.MinToStart then return end
	sprinting = true
	applySpeed()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.LeftShift and input.KeyCode ~= Enum.KeyCode.RightShift then
		return
	end
	sprinting = false
	restedAt  = os.clock()
	applySpeed()
end)

RunService.Heartbeat:Connect(function(dt)
	local h = humanoid()
	local moving = h and h.MoveDirection.Magnitude > 0.1

	if sprinting and moving then
		stamina -= SP.Drain * dt
		if stamina <= 0 then
			stamina   = 0
			sprinting = false
			restedAt  = os.clock()
			applySpeed()
		end
	elseif os.clock() - restedAt > SP.Delay then
		stamina = math.min(stamina + SP.Recover * dt, SP.Max)
	end

	local share = stamina / SP.Max
	fill.Size = UDim2.new(share, 0, 1, 0)
	fill.BackgroundColor3 = share < 0.25 and UIP.Warning or UIP.Crystal

	-- Only on screen while it is not full
	local hide = share >= 0.999
	local want = hide and 1 or 0
	bar.BackgroundTransparency  = bar.BackgroundTransparency + (want - bar.BackgroundTransparency) * math.min(dt * 6, 1)
	fill.BackgroundTransparency = bar.BackgroundTransparency
	barEdge.Transparency        = bar.BackgroundTransparency
end)

player.CharacterAdded:Connect(function()
	sprinting = false
	stamina   = SP.Max
	task.wait(0.4)
	applySpeed()
end)
end)()   -- sprint

-- ── Run manifest ─────────────────────────────────────────────────────────────
-- Bottom left, only while a contract is running. What you have pulled out so
-- far and what it is worth — the thing you weigh against the clock every time
-- you decide to take one more chamber.

local manifest = Instance.new("Frame")
manifest.Name             = "RunManifest"
manifest.AnchorPoint      = Vector2.new(0, 1)
-- Stacked directly on top of the player card, so the whole bottom-left corner
-- is you and what you are carrying
manifest.Position         = UDim2.new(0, HUD.Card.X, 1, -(HUD.Card.Bottom + HUD.Card.H + 10))
manifest.Size             = UDim2.new(0, 240, 0, 56)
manifest.BackgroundColor3 = UIP.Stone
manifest.BorderSizePixel  = 0
manifest.Visible          = false
manifest.Parent           = gui
Instance.new("UICorner", manifest).CornerRadius = UDim.new(0, 12)

local manEdge = Instance.new("UIStroke", manifest)
manEdge.Color     = UIP.StoneDark
manEdge.Thickness = 3

local manFace = Instance.new("UIGradient", manifest)
manFace.Rotation = 90
manFace.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, UIP.StoneLit),
	ColorSequenceKeypoint.new(0.4, UIP.Stone),
	ColorSequenceKeypoint.new(1, UIP.StoneDeep),
})

local manTitle = label(manifest, "EXTRACTING", UDim2.new(0, 140, 0, 14),
	UDim2.new(0, 12, 0, 8), UIP.Ore, 11, StrataConfig.UI.Head)
manTitle.ZIndex = 2

local manWorth = label(manifest, "0", UDim2.new(0, 84, 0, 14),
	UDim2.new(1, -12, 0, 8), UIP.Ink, 12, StrataConfig.UI.Head, Enum.TextXAlignment.Right)
manWorth.AnchorPoint = Vector2.new(1, 0)
manWorth.ZIndex      = 2

local manList = Instance.new("Frame")
manList.Size                   = UDim2.new(1, -22, 1, -34)
manList.Position               = UDim2.new(0, 11, 0, 27)
manList.BackgroundTransparency = 1
manList.ZIndex                 = 2
manList.Parent                 = manifest

local manLayout = Instance.new("UIListLayout", manList)
manLayout.Padding   = UDim.new(0, 3)
manLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function refreshManifest(state)
	local running = state.run ~= nil
	manifest.Visible = running
	if not running then return end

	for _, c in ipairs(manList:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	-- Best first: what you would be sorriest to lose is what you want to see
	local rows = {}
	for id, count in pairs(state.inventory or {}) do
		local m = StrataConfig.GetMaterial(id)
		if m and count > 0 then
			table.insert(rows, { name = m.name, count = count,
				worth = (m.value or 0) * count, colour = m.color })
		end
	end
	table.sort(rows, function(a, b) return a.worth > b.worth end)

	local shown = math.min(#rows, 5)
	for i = 1, shown do
		local r = rows[i]

		local line = Instance.new("Frame")
		line.Size                   = UDim2.new(1, 0, 0, 15)
		line.BackgroundTransparency = 1
		line.LayoutOrder            = i
		line.ZIndex                 = 2
		line.Parent                 = manList

		local chip = Instance.new("Frame")
		chip.Size             = UDim2.new(0, 8, 0, 8)
		chip.Position         = UDim2.new(0, 0, 0, 4)
		chip.Rotation         = 45
		chip.BackgroundColor3 = r.colour or UIP.Iron
		chip.BorderSizePixel  = 0
		chip.ZIndex           = 3
		chip.Parent           = line

		local nm = label(line, ("%s  x%d"):format(r.name, r.count),
			UDim2.new(1, -70, 1, 0), UDim2.new(0, 16, 0, 0), UIP.Dim, 11)
		nm.ZIndex       = 3
		nm.TextTruncate = Enum.TextTruncate.AtEnd

		local wv = label(line, tostring(r.worth), UDim2.new(0, 60, 1, 0),
			UDim2.new(1, 0, 0, 0), UIP.Ore, 11, StrataConfig.UI.Number, Enum.TextXAlignment.Right)
		wv.AnchorPoint = Vector2.new(1, 0)
		wv.ZIndex      = 3
	end

	if #rows == 0 then
		local nothing = label(manList, "nothing yet", UDim2.new(1, 0, 0, 14), UDim2.new(),
			UIP.StoneLit, 11)
		nothing.LayoutOrder = 1
		nothing.ZIndex      = 3
	end

	if #rows > shown then
		local more = label(manList, ("and %d more"):format(#rows - shown),
			UDim2.new(1, 0, 0, 14), UDim2.new(), UIP.StoneLit, 10)
		more.LayoutOrder = 99
		more.ZIndex      = 3
	end

	manTitle.Text = ("EXTRACTING  ·  %d/%d"):format(state.carried or 0, state.capacity or 0)
	manWorth.Text = tostring(state.worth or 0)
	manifest.Size = UDim2.new(0, 240, 0,
		34 + math.max(shown, 1) * 18 + (#rows > shown and 16 or 0))
end

stateChanged.OnClientEvent:Connect(refreshManifest)
end)()   -- hotbar and manifest


-- ── Caverns ──────────────────────────────────────────────────────────────────
-- Breaking into a room should land. The name of the place arrives on screen,
-- the fog takes its colour while you are inside, and a rare room is announced
-- to everyone on the server the first time anybody walks into it.

local Lighting = game:GetService("Lighting")

local cavernEntered = remotes:WaitForChild("CavernEntered")
local cavernFound   = remotes:WaitForChild("CavernFound")

local cavernCard = Instance.new("Frame")
cavernCard.Size             = UDim2.new(0, 340, 0, 74)
cavernCard.AnchorPoint      = Vector2.new(0.5, 0)
cavernCard.Position         = UDim2.new(0.5, 0, 0, 78)
cavernCard.BackgroundColor3 = StrataConfig.UI.Stone
cavernCard.BorderSizePixel  = 0
cavernCard.Visible          = false
cavernCard.Parent           = gui
Instance.new("UICorner", cavernCard).CornerRadius = UDim.new(0, 14)

local cavernEdge = Instance.new("UIStroke", cavernCard)
cavernEdge.Color     = Color3.fromRGB(8, 10, 14)
cavernEdge.Thickness = 3

local cavernStripe = Instance.new("Frame")
cavernStripe.Size             = UDim2.new(0, 6, 1, -20)
cavernStripe.Position         = UDim2.new(0, 12, 0, 10)
cavernStripe.BackgroundColor3 = SIGNAL
cavernStripe.BorderSizePixel  = 0
cavernStripe.Parent           = cavernCard
Instance.new("UICorner", cavernStripe).CornerRadius = UDim.new(0, 3)

local cavernName = label(cavernCard, "", UDim2.new(1, -40, 0, 22),
	UDim2.new(0, 30, 0, 12), INK, 18, StrataConfig.UI.Head)
local cavernBlurb = label(cavernCard, "", UDim2.new(1, -44, 0, 32),
	UDim2.new(0, 30, 0, 34), DIM, 13)
cavernBlurb.TextWrapped = true
cavernBlurb.TextYAlignment = Enum.TextYAlignment.Top

local currentRoom = nil
local cavernHide  = nil

local function showCavern(info)
	cavernName.Text  = string.upper(info.name or "CAVERN")
	cavernBlurb.Text = info.blurb or ""
	cavernStripe.BackgroundColor3 = info.light or SIGNAL

	cavernCard.Visible = true
	cavernCard.BackgroundTransparency = 1
	cavernCard.Position = UDim2.new(0.5, 0, 0, 64)
	TweenService:Create(cavernCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 78),
		BackgroundTransparency = 0,
	}):Play()

	-- The card is a greeting, not a permanent readout: it gets out of the way
	-- again once you have read it.
	if cavernHide then task.cancel(cavernHide) end
	cavernHide = task.delay(5, function()
		TweenService:Create(cavernCard, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cavernName, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(cavernBlurb, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		cavernCard.Visible = false
		cavernName.TextTransparency  = 0
		cavernBlurb.TextTransparency = 0
	end)
end

cavernEntered.OnClientEvent:Connect(function(info)
	currentRoom = info
	if info then showCavern(info) end
end)

-- ── Fog ──────────────────────────────────────────────────────────────────────
-- Each stratum already carries a fog colour and a view distance. Standing in a
-- room overrides both, which is what makes a Crystal Vault feel blue and a Lava
-- Chamber feel like standing next to a furnace.

local SKY_FOG = Color3.fromRGB(176, 188, 204)
local lastFog = nil

local function fogTarget()
	if currentRoom and currentRoom.fog then
		return currentRoom.fog, 10, 120
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local y    = root and root.Position.Y or 50
	if y > StrataConfig.Mine.SurfaceY + 3 then
		return SKY_FOG, 180, 3000
	end

	local f = StrataConfig.GetStratum(y).fog
	return f.color, f.start, f.ending
end

task.spawn(function()
	while true do
		local colour, start, ending = fogTarget()
		local key = tostring(colour) .. start .. ending
		if key ~= lastFog then
			lastFog = key
			TweenService:Create(Lighting, TweenInfo.new(1.1), {
				FogColor = colour,
				FogStart = start,
				FogEnd   = ending,
			}):Play()
		end
		task.wait(0.5)
	end
end)

-- ── Server-wide finds ────────────────────────────────────────────────────────

cavernFound.OnClientEvent:Connect(function(find)
	if type(find) ~= "table" then return end

	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 420, 0, 62)
	card.AnchorPoint      = Vector2.new(0.5, 0)
	card.Position         = UDim2.new(0.5, 0, 0, -70)
	card.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	card.BorderSizePixel  = 0
	card.ZIndex           = 20
	card.Parent           = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	local edge = Instance.new("UIStroke", card)
	edge.Color     = find.light or ORE
	edge.Thickness = 3

	local glow = Instance.new("Frame")
	glow.Size             = UDim2.new(1, 0, 0, 4)
	glow.Position         = UDim2.new(0, 0, 1, -4)
	glow.BackgroundColor3 = find.light or ORE
	glow.BorderSizePixel  = 0
	glow.ZIndex           = 21
	glow.Parent           = card

	local title = label(card, "RARE FIND  ·  " .. string.upper(find.name or ""),
		UDim2.new(1, -28, 0, 22), UDim2.new(0, 16, 0, 10),
		find.light or ORE, 16, StrataConfig.UI.Head)
	title.ZIndex = 21

	local line = label(card,
		("%s broke into it at %dm down"):format(find.finder or "someone", find.depth or 0),
		UDim2.new(1, -28, 0, 20), UDim2.new(0, 16, 0, 32), DIM, 13)
	line.ZIndex = 21

	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 80),
	}):Play()

	task.delay(6, function()
		TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -80),
		}):Play()
		task.wait(0.55)
		card:Destroy()
	end)
end)

-- ── Expedition HUD ───────────────────────────────────────────────────────────
-- While a contract is running: the clock, what it wants, and what the haul is
-- worth so far. Top right, clear of the depth banner and the left-hand column.
--
-- The clock counts down locally between server pushes. The server owns when the
-- run actually ends; this is only the readout.

local extractRequest = remotes:WaitForChild("ExtractRequest")
local runEnded       = remotes:WaitForChild("RunEnded")

local runState   = nil    -- the `run` field from the last state push
local runClock   = 0      -- seconds left, ticked down locally
local packWorth  = 0

local runCard = Instance.new("Frame")
runCard.Size             = UDim2.new(0, 264, 0, 96)
runCard.AnchorPoint      = Vector2.new(1, 0)
runCard.Position         = UDim2.new(1, -16, 0, 12)
runCard.BackgroundColor3 = StrataConfig.UI.Stone
runCard.BorderSizePixel  = 0
runCard.Visible          = false
runCard.Parent           = gui
Instance.new("UICorner", runCard).CornerRadius = UDim.new(0, 14)

local runEdge = Instance.new("UIStroke", runCard)
runEdge.Color     = StrataConfig.UI.StoneDark
runEdge.Thickness = 3

local runStripe = Instance.new("Frame")
runStripe.Size             = UDim2.new(1, 0, 0, 4)
runStripe.Position         = UDim2.new(0, 0, 0, 0)
runStripe.BackgroundColor3 = ORE
runStripe.BorderSizePixel  = 0
runStripe.Parent           = runCard

local runWhere = label(runCard, "", UDim2.new(1, -110, 0, 16), UDim2.new(0, 14, 0, 12),
	DIM, 11, StrataConfig.UI.Head)

local runTimer = label(runCard, "0:00", UDim2.new(0, 92, 0, 30), UDim2.new(1, -14, 0, 10),
	INK, 26, StrataConfig.UI.Head, Enum.TextXAlignment.Right)
runTimer.AnchorPoint = Vector2.new(1, 0)

-- Kept, but never shown. The objective banner across the top says exactly
-- this in much bigger type, and having "0 / 34 Coalbit" in two places on
-- one screen made both of them easier to ignore.
local runGoal = label(runCard, "", UDim2.new(1, -28, 0, 18), UDim2.new(0, 14, 0, 40),
	ORE, 13, StrataConfig.UI.Body)
runGoal.Visible = false

local runHaul = label(runCard, "", UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, 40),
	DIM, 11, StrataConfig.UI.Body)

-- The button only appears once you are close enough for it to work, which makes
-- the walk back the thing you are doing rather than a menu you could have used
-- at any point.
local extractBtn = Instance.new("TextButton")
extractBtn.Size             = UDim2.new(0, 264, 0, 46)
extractBtn.AnchorPoint      = Vector2.new(1, 0)
extractBtn.Position         = UDim2.new(1, -16, 0, 116)
extractBtn.BackgroundColor3 = Color3.fromRGB(142, 192, 142)
extractBtn.BorderSizePixel  = 0
extractBtn.Text             = "EXTRACT"
extractBtn.TextColor3       = Color3.fromRGB(14, 24, 14)
extractBtn.TextSize         = 18
extractBtn.Font             = StrataConfig.UI.Head
extractBtn.Visible          = false
extractBtn.Parent           = gui
Instance.new("UICorner", extractBtn).CornerRadius = UDim.new(0, 12)

local extractEdge = Instance.new("UIStroke", extractBtn)
extractEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
extractEdge.Color           = Color3.fromRGB(8, 10, 14)
extractEdge.Thickness       = 3

extractBtn.Activated:Connect(function()
	extractRequest:FireServer()
end)

local function runClockText(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Distance to the shaft, which is the bore straight down the middle of the mine
local function atShaft()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local p = root.Position
	return p.X * p.X + p.Z * p.Z <= StrataConfig.Expedition.ExtractRange ^ 2
end

RunService.Heartbeat:Connect(function(dt)
	if not runState then return end

	runClock = math.max(runClock - dt, 0)
	runTimer.Text = runClockText(runClock)

	-- The last half minute is the one that matters
	runTimer.TextColor3 = runClock <= 30 and StrataConfig.UI.Warning or StrataConfig.UI.Ink
	runStripe.BackgroundColor3 = runClock <= 30 and StrataConfig.UI.Warning or ORE

	local close = atShaft()
	extractBtn.Visible = close
	extractBtn.Text = runState.met and "EXTRACT  ·  CONTRACT MET" or "EXTRACT"
end)

local function showRun(run, worth)
	runState  = run
	packWorth = worth or 0

	if not run then
		runCard.Visible    = false
		extractBtn.Visible = false
		return
	end

	runClock = run.remaining or 0
	runCard.Visible = true

	runWhere.Text = string.upper(run.contract.layerName or "")
	runGoal.Text  = run.progress or ""
	runGoal.TextColor3 = run.met and Color3.fromRGB(142, 192, 142) or ORE
	runHaul.Text  = ("raw haul worth %d — banks when you extract"):format(packWorth)
end

-- Its own connection rather than a call from the handler further up the file:
-- that one runs before any of this exists.
stateChanged.OnClientEvent:Connect(function(s)
	showRun(s.run, s.worth or 0)
end)

-- ── The summary ──────────────────────────────────────────────────────────────

runEnded.OnClientEvent:Connect(function(summary)
	if type(summary) ~= "table" then return end

	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 420, 0, 172)
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.Position         = UDim2.new(0.5, 0, 0.42, 0)
	card.BackgroundColor3 = StrataConfig.UI.Stone
	card.BorderSizePixel  = 0
	card.ZIndex           = 30
	card.Parent           = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)

	local tone = summary.success and Color3.fromRGB(142, 192, 142) or Color3.fromRGB(224, 112, 92)

	local edge = Instance.new("UIStroke", card)
	edge.Color     = tone
	edge.Thickness = 3

	local head = label(card, summary.success and "EXTRACTED" or "THE MINE CLOSED",
		UDim2.new(1, -28, 0, 26), UDim2.new(0, 18, 0, 14), tone, 20, StrataConfig.UI.Head)
	head.ZIndex = 31

	local lines = {}
	table.insert(lines, ("haul banked: %d credits worth"):format(summary.worth or 0))
	if summary.paid and summary.paid > 0 then
		table.insert(lines, ("contract paid: %d"):format(summary.paid))
	end
	if summary.objective then
		table.insert(lines, "objective met — bonus included")
	elseif summary.success then
		table.insert(lines, "objective not met — no bonus")
	end
	if summary.xp and summary.xp > 0 then
		table.insert(lines, ("experience: +%d%s"):format(summary.xp,
			(summary.levels or 0) > 0
				and ("   ·   LEVEL " .. summary.level) or ""))
	end
	if not summary.success then
		table.insert(lines, ("you kept %d%% of what you were carrying")
			:format(math.floor((summary.kept or 0) * 100)))
	end

	local body = label(card, table.concat(lines, "\n"), UDim2.new(1, -36, 0, 84),
		UDim2.new(0, 18, 0, 48), INK, 14, StrataConfig.UI.Body)
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 31

	task.delay(6, function()
		TweenService:Create(card, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(edge, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(head, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(body, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.55)
		card:Destroy()
	end)
end)

-- ── Character lifecycle ──────────────────────────────────────────────────────

local function onCharacter(char)
	jointCache, jointChar = nil, nil  -- rig is new; re-find the motors
	char:WaitForChild("HumanoidRootPart", 10)
	-- Wait for the actual limb rather than guessing at a delay
	local hand = char:WaitForChild("RightHand", 5) or char:WaitForChild("Right Arm", 5)
	if not hand then return end
	task.wait(0.2)
	attachPickaxe(char)

	-- Joints can appear after the limbs do, so retry before giving up. This rig
	-- exposes none, so the tool swing carries the animation on its own.
	for _ = 1, 6 do
		if resolveJoints(char).shoulder then return end
		task.wait(0.5)
	end
	if StrataConfig.Debug and not rigReported then
		rigReported = true  -- once a session, not once a respawn
		dumpRig(char)
	end
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

print("[MineClient] ready")
