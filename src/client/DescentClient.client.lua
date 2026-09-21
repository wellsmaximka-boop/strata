local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes        = ReplicatedStorage:WaitForChild("MineRemotes")
local descentStarted = remotes:WaitForChild("DescentStarted")
local descentEnded   = remotes:WaitForChild("DescentEnded")

-- ── Descent client ───────────────────────────────────────────────────────────
-- The ride down, from inside. The server owns the cage and where it is; this
-- file owns everything you experience while you are in it.
--
-- Two things are worth knowing about how it works:
--
--   The cage is moved here as well as on the server. An anchored part driven
--   from the server replicates as a property change every few frames, which
--   over two hundred studs reads as a stutter. So the client runs the same
--   easing curve on the same numbers and writes the CFrame every frame; the
--   server's updates land on top and are immediately overwritten. Both agree
--   at both ends, which is the only place agreement matters.
--
--   The camera is scriptable for the whole ride rather than handed back after
--   an opening swoop. Half a cutscene is worse than none: the moment control
--   comes back people look at the floor and miss the Stonebed going past.

local UIP = StrataConfig.UI
local D   = StrataConfig.Descent

local gui = Instance.new("ScreenGui")
gui.Name           = "StrataDescent"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 40
gui.Enabled        = false
gui.Parent         = player:WaitForChild("PlayerGui")

local function label(parent, text, size, position, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.Position               = position
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextColor3             = colour or UIP.Ink
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

-- ── Letterbox ────────────────────────────────────────────────────────────────
-- The cheapest possible way of saying "this is not gameplay, stand still".

local bars = {}
for i = 0, 1 do
	local bar = Instance.new("Frame")
	bar.AnchorPoint      = Vector2.new(0, i)
	bar.Position         = UDim2.new(0, 0, i, 0)
	bar.Size             = UDim2.new(1, 0, 0, 0)
	bar.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
	bar.BorderSizePixel  = 0
	bar.ZIndex           = 60
	bar.Parent           = gui
	bars[i + 1] = bar
end

local function letterbox(shown)
	for _, bar in ipairs(bars) do
		TweenService:Create(bar, TweenInfo.new(0.55, Enum.EasingStyle.Quart,
			Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, shown and 62 or 0) }):Play()
	end
end

-- ── Depth ────────────────────────────────────────────────────────────────────
-- Top centre, and deliberately the largest thing on the screen. A number that
-- climbs on its own is the whole of the suspense; everything else is dressing
-- around it.

local head = Instance.new("Frame")
head.AnchorPoint            = Vector2.new(0.5, 0)
head.Position               = UDim2.new(0.5, 0, 0, 74)
head.Size                   = UDim2.new(0, 300, 0, 96)
head.BackgroundTransparency = 1
head.ZIndex                 = 61
head.Parent                 = gui

local depthValue = label(head, "0", UDim2.new(1, 0, 0, 62), UDim2.new(0, 0, 0, 10),
	UIP.Ore, 58, StrataConfig.UI.Number, Enum.TextXAlignment.Center)
depthValue.ZIndex = 62

local depthTag = label(head, "METRES BELOW THE CAMP", UDim2.new(1, 0, 0, 16),
	UDim2.new(0, 0, 0, 70), UIP.Dim, 12, StrataConfig.UI.Head,
	Enum.TextXAlignment.Center)
depthTag.ZIndex = 62

-- A rule under the number that fills as the ride runs, so the number is not
-- the only thing saying how far there is left to go
local runTrack = Instance.new("Frame")
runTrack.AnchorPoint      = Vector2.new(0.5, 0)
runTrack.Position         = UDim2.new(0.5, 0, 0, 4)
runTrack.Size             = UDim2.new(0, 210, 0, 3)
runTrack.BackgroundColor3 = UIP.StoneDeep
runTrack.BorderSizePixel  = 0
runTrack.ZIndex           = 62
runTrack.Parent           = head

local runFill = Instance.new("Frame")
runFill.Size             = UDim2.new(0, 0, 1, 0)
runFill.BackgroundColor3 = UIP.Ore
runFill.BorderSizePixel  = 0
runFill.ZIndex           = 63
runFill.Parent           = runTrack

-- ── The column ───────────────────────────────────────────────────────────────
-- Down the right-hand side: every layer drawn at its true thickness, with the
-- cage sliding through them. It is the depth chart from the lodge turned on its
-- side and made to mean something, and it is how you know the Magma Vents are
-- still a long way off.

local COL_TOP, COL_BOT = 0.16, 0.84

local column = Instance.new("Frame")
column.AnchorPoint      = Vector2.new(1, 0)
column.Position         = UDim2.new(1, -38, COL_TOP, 0)
column.Size             = UDim2.new(0, 16, COL_BOT - COL_TOP, 0)
column.BackgroundColor3 = UIP.StoneDark
column.BorderSizePixel  = 0
column.ZIndex           = 61
column.Parent           = gui

local colEdge = Instance.new("UIStroke", column)
colEdge.Color     = UIP.StoneDeep
colEdge.Thickness = 2

local DEEPEST = StrataConfig.LandingY(StrataConfig.Strata[#StrataConfig.Strata])
	- D.Overrun
local TOP_Y   = StrataConfig.Surface.PlatformY

local function columnAlpha(y)
	return math.clamp((TOP_Y - y) / (TOP_Y - DEEPEST), 0, 1)
end

local marks = {}
for i, stratum in ipairs(StrataConfig.Strata) do
	local a0 = columnAlpha(stratum.top)
	local a1 = i < #StrataConfig.Strata
		and columnAlpha(StrataConfig.Strata[i + 1].top) or 1

	local band = Instance.new("Frame")
	band.Position         = UDim2.new(0, 0, a0, 0)
	band.Size             = UDim2.new(1, 0, a1 - a0, 0)
	band.BackgroundColor3 = stratum.color:Lerp(Color3.fromRGB(0, 0, 0), 0.32)
	band.BorderSizePixel  = 0
	band.ZIndex           = 62
	band.Parent           = column

	local seam = Instance.new("Frame")
	seam.Position         = UDim2.new(0, 0, a0, 0)
	seam.Size             = UDim2.new(1, 0, 0, 2)
	seam.BackgroundColor3 = UIP.StoneDark
	seam.BorderSizePixel  = 0
	seam.ZIndex           = 63
	seam.Parent           = column

	local name = label(column, string.upper(stratum.name), UDim2.new(0, 130, 0, 14),
		UDim2.new(0, -138, a0, 2), UIP.Dim, 11, StrataConfig.UI.Head,
		Enum.TextXAlignment.Right)
	name.ZIndex = 63

	marks[stratum.id] = { band = band, name = name, stratum = stratum }
end

-- Where the job is. Set at the start of the ride and left there, so the gap
-- between the cage and the target is always on screen.
local target = Instance.new("Frame")
target.AnchorPoint      = Vector2.new(0.5, 0.5)
target.Size             = UDim2.new(0, 26, 0, 3)
target.BackgroundColor3 = UIP.Crystal
target.BorderSizePixel  = 0
target.ZIndex           = 66
target.Visible          = false
target.Parent           = column

-- The cage itself
local cageMark = Instance.new("Frame")
cageMark.AnchorPoint      = Vector2.new(0.5, 0.5)
cageMark.Position         = UDim2.new(0.5, 0, 0, 0)
cageMark.Size             = UDim2.new(0, 13, 0, 13)
cageMark.Rotation         = 45
cageMark.BackgroundColor3 = UIP.Ore
cageMark.BorderSizePixel  = 0
cageMark.ZIndex           = 67
cageMark.Parent           = column

local cageEdge = Instance.new("UIStroke", cageMark)
cageEdge.Color     = Color3.fromRGB(10, 9, 12)
cageEdge.Thickness = 2

-- ── Layer flash ──────────────────────────────────────────────────────────────
-- Crossing out of one layer and into the next is the only event in a lift ride.
-- It gets the middle of the screen for a second and a half.

local flash = Instance.new("Frame")
flash.AnchorPoint            = Vector2.new(0.5, 0.5)
flash.Position               = UDim2.new(0.5, 0, 0.44, 0)
flash.Size                   = UDim2.new(0, 460, 0, 78)
flash.BackgroundTransparency = 1
flash.ZIndex                 = 64
flash.Visible                = false
flash.Parent                 = gui

local flashName = label(flash, "", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 0),
	UIP.Ink, 38, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
flashName.ZIndex = 65

local flashTag = label(flash, "", UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 0, 48),
	UIP.Dim, 13, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
flashTag.ZIndex = 65

local flashRule = Instance.new("Frame")
flashRule.AnchorPoint      = Vector2.new(0.5, 0)
flashRule.Position         = UDim2.new(0.5, 0, 0, 70)
flashRule.Size             = UDim2.new(0, 0, 0, 2)
flashRule.BackgroundColor3 = UIP.Ore
flashRule.BorderSizePixel  = 0
flashRule.ZIndex           = 65
flashRule.Parent           = flash

local function showFlash(name, tag, colour)
	flash.Visible          = true
	flashName.Text         = string.upper(name)
	flashName.TextColor3   = colour
	flashName.TextTransparency = 0
	flashTag.Text          = tag
	flashTag.TextTransparency  = 0
	flashRule.BackgroundColor3 = colour
	flashRule.Size         = UDim2.new(0, 0, 0, 2)

	TweenService:Create(flashRule, TweenInfo.new(0.5, Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out), { Size = UDim2.new(0, 330, 0, 2) }):Play()

	task.delay(1.1, function()
		local fade = TweenInfo.new(0.45)
		TweenService:Create(flashName, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(flashTag, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(flashRule, fade, { BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		flash.Visible = false
		flashRule.BackgroundTransparency = 0
	end)
end

-- ── Briefing ─────────────────────────────────────────────────────────────────
-- Bottom left, fading in once the ride is properly under way. The contract is
-- worth reading twice and this is the only time you have nothing else to do.

local brief = Instance.new("Frame")
brief.AnchorPoint      = Vector2.new(0, 1)
brief.Position         = UDim2.new(0, 40, 1, -96)
brief.Size             = UDim2.new(0, 330, 0, 132)
brief.BackgroundColor3 = UIP.Stone
brief.BorderSizePixel  = 0
brief.ZIndex           = 61
brief.Visible          = false
brief.Parent           = gui
Instance.new("UICorner", brief).CornerRadius = UDim.new(0, 12)

local briefEdge = Instance.new("UIStroke", brief)
briefEdge.Color     = UIP.StoneDark
briefEdge.Thickness = 3

local briefFace = Instance.new("UIGradient", brief)
briefFace.Rotation = 90
briefFace.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, UIP.StoneLit),
	ColorSequenceKeypoint.new(0.4, UIP.Stone),
	ColorSequenceKeypoint.new(1, UIP.StoneDeep),
})

local briefStripe = Instance.new("Frame")
briefStripe.Size             = UDim2.new(0, 5, 1, -22)
briefStripe.Position         = UDim2.new(0, 0, 0, 11)
briefStripe.BackgroundColor3 = UIP.Ore
briefStripe.BorderSizePixel  = 0
briefStripe.ZIndex           = 63
briefStripe.Parent           = brief

local briefKind = label(brief, "CONTRACT", UDim2.new(1, -30, 0, 20),
	UDim2.new(0, 18, 0, 12), UIP.Ore, 17, StrataConfig.UI.Head)
briefKind.ZIndex = 62

local briefTier = label(brief, "", UDim2.new(0, 120, 0, 16),
	UDim2.new(1, -14, 0, 14), UIP.Dim, 12, StrataConfig.UI.Head,
	Enum.TextXAlignment.Right)
briefTier.AnchorPoint = Vector2.new(1, 0)
briefTier.ZIndex      = 62

local briefLine = label(brief, "", UDim2.new(1, -32, 0, 34),
	UDim2.new(0, 18, 0, 36), UIP.Ink, 14, StrataConfig.UI.Body)
briefLine.TextWrapped    = true
briefLine.TextYAlignment = Enum.TextYAlignment.Top
briefLine.ZIndex         = 62

local briefFoot = label(brief, "", UDim2.new(1, -32, 0, 44),
	UDim2.new(0, 18, 0, 78), UIP.Dim, 12, StrataConfig.UI.Number)
briefFoot.TextYAlignment = Enum.TextYAlignment.Top
briefFoot.ZIndex         = 62

-- ── The ride ─────────────────────────────────────────────────────────────────

local active   = nil    -- the payload we are riding on
local frameTie = nil    -- the RenderStepped connection
local guard    = nil    -- the "something went wrong" restore

local savedFov  = camera.FieldOfView
local savedType = camera.CameraType

local function otherGuis(visible)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	for _, name in ipairs({ "StrataHUD", "StrataUI", "StrataSiteMap" }) do
		local other = pg:FindFirstChild(name)
		if other then other.Enabled = visible end
	end
end

local function restore()
	if frameTie then frameTie:Disconnect() end
	frameTie = nil
	active   = nil

	camera.CameraType   = savedType
	camera.FieldOfView  = savedFov
	letterbox(false)
	otherGuis(true)
	brief.Visible = false

	task.delay(0.6, function()
		if not active then gui.Enabled = false end
	end)
end

-- The gauge on the cage itself. Written from here rather than replicated from
-- the server: it is a display, only the rider is close enough to read it, and
-- a text property changing sixty times a second is not worth a packet.
local function gauge(cage)
	local board = cage and cage:FindFirstChild("Gauge")
	local face  = board and board:FindFirstChild("GaugeFace")
	if not face then return nil, nil end
	local back = face:FindFirstChildOfClass("Frame")
	if not back then return nil, nil end
	return back:FindFirstChild("Depth"), back:FindFirstChild("Where")
end

local function crossings(fromY, toY)
	-- Every stratum boundary the ride passes, in the order it passes them
	local out = {}
	for _, s in ipairs(StrataConfig.Strata) do
		local crossed = (fromY > s.top and toY <= s.top)
			or (fromY < s.top and toY >= s.top)
		if crossed and s.top < StrataConfig.Mine.SurfaceY + 1 then
			table.insert(out, s)
		end
	end
	return out
end

descentStarted.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	if frameTie then frameTie:Disconnect() end

	active = info
	local rising = info.mode == "up"

	gui.Enabled = true
	otherGuis(false)
	letterbox(true)

	savedType = Enum.CameraType.Custom
	savedFov  = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	-- The layer stripe on the column, coloured for where the job is
	local accent = info.colour or UIP.Ore
	depthValue.TextColor3      = accent
	runFill.BackgroundColor3   = accent
	cageMark.BackgroundColor3  = accent
	briefStripe.BackgroundColor3 = accent

	target.Visible  = not rising
	target.Position = UDim2.new(0.5, 0, columnAlpha(info.toY), 0)

	for _, mark in pairs(marks) do
		local here = mark.stratum.id == info.layerId
		mark.name.TextColor3 = here and accent or UIP.Dim
		mark.name.TextSize   = here and 12 or 11
	end

	-- The briefing, once you have stopped watching the gate come down
	if info.contract then
		local c = info.contract
		briefKind.Text = string.upper(c.title or "CONTRACT")
		briefTier.Text = string.upper(c.difficultyName or "")
		briefLine.Text = c.line or ""
		briefFoot.Text = ("%s   ·   %d credits   ·   %d:%02d on the clock")
			:format(string.upper(info.layerName or ""), c.payout or 0,
				math.floor((c.duration or 0) / 60), (c.duration or 0) % 60)

		task.delay(2.2, function()
			if active == info then brief.Visible = true end
		end)
	else
		briefKind.Text = "COMING UP"
		briefTier.Text = ""
		briefLine.Text = "the haul banks when the gate opens"
		briefFoot.Text = ""
		task.delay(1.4, function()
			if active == info then brief.Visible = true end
		end)
	end

	local ahead = crossings(info.fromY, info.toY)
	local shown = {}

	local cage    = workspace:FindFirstChild("Descent")
	cage = cage and cage:FindFirstChild(info.cage)
	local gDepth, gWhere = gauge(cage)

	local started = os.clock()
	local hold    = info.hold or (D.GateTime + 0.45)
	local span    = info.toY - info.fromY

	frameTie = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local a = math.clamp((t - hold) / info.seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		local y = info.fromY + span * e

		-- The cage, driven locally so two hundred studs of travel are smooth.
		-- The server's own updates arrive between frames and are painted over.
		if cage and cage.Parent then
			cage:PivotTo(CFrame.new(0, y - 0.4, 0))
		end

		-- How fast we are actually moving, for the shake and the field of view
		local speed = math.abs(span) * (6 * a * (1 - a)) / info.seconds

		-- Camera: three-quarters behind the rider at the start, drifting square
		-- on to the gate by the time it opens. Every offset is kept inside ten
		-- studs of the axis, because the bore wall is at eleven and a camera a
		-- stud into the rock sees the inside of the world.
		local swing  = 1 - e
		local jitter = speed * 0.010
		local eye = Vector3.new(
			4.4 * swing + math.sin(t * 23) * jitter,
			y + 6.6 + math.cos(t * 19) * jitter,
			-7.4 - 1.5 * swing)
		local at = Vector3.new(0, y + 4.1, 9)
		camera.CFrame      = CFrame.lookAt(eye, at)
		camera.FieldOfView = 70 + math.min(speed * 0.34, 12)

		-- Depth, on the screen and on the pod
		local metres = math.max(math.floor(-y + 0.5), 0)
		depthValue.Text = tostring(metres)
		if gDepth then gDepth.Text = metres .. " m" end

		local here = StrataConfig.GetStratum(y)
		if gWhere then
			gWhere.Text = y >= StrataConfig.Mine.SurfaceY and "SURFACE"
				or string.upper(here and here.name or "")
		end

		runFill.Size      = UDim2.new(a, 0, 1, 0)
		cageMark.Position = UDim2.new(0.5, 0, columnAlpha(y), 0)

		-- Layer boundaries, announced as they go by
		for _, s in ipairs(ahead) do
			if not shown[s.id] then
				local passed = rising and y >= s.top or (not rising and y <= s.top)
				if passed then
					shown[s.id] = true
					local arriving = s.id == info.layerId
					showFlash(s.name,
						arriving and "the contract is here" or "passing through",
						arriving and accent or s.color:Lerp(Color3.fromRGB(255, 255, 255), 0.45))
				end
			end
		end
	end)

	-- If the server never says the ride ended, the camera still comes back
	if guard then task.cancel(guard) end
	guard = task.delay(hold + info.seconds + 12, function()
		if active == info then restore() end
	end)
end)

descentEnded.OnClientEvent:Connect(function(info)
	if not active then return end

	local rising = active.mode == "up"
	showFlash(info and info.layerName or active.layerName,
		rising and "the haul is banked" or "gate open — clock running",
		rising and UIP.Moss or (active.colour or UIP.Ore))

	-- A beat on the open gate before control comes back, so arriving is a
	-- moment rather than a cut. It has to be well inside the time the cage
	-- stands at the station, or the pod leaves before you can walk out of it.
	task.delay(0.8, restore)
end)

print("[DescentClient] ready")
