-- ── Depth chart ──────────────────────────────────────────────────────────────
-- The ladder down the right edge of the camp. Layers you have reached are lit
-- in their own colour; the ones below are sealed and read as ???. Segments are
-- equal height rather than to scale — this is a map, not a graph, and the
-- Topsoil would be a sliver otherwise.
--
-- Lifted out of SurfaceUI, which sits on Luau's ceiling of 200 locals per
-- function and could not afford the thirty-odd this declares. In here they are
-- this module's registers and cost the caller one name.
--
-- Everything it needs from the parent arrives in `ctx`; it hands back the
-- refresh function, which the parent calls whenever player state changes.

return function(ctx)

local gui          = ctx.gui
local S            = ctx.state
local player       = ctx.player
local text         = ctx.text
local corner       = ctx.corner
local StrataConfig = ctx.StrataConfig
local panel        = ctx.panel
local kit          = ctx.kit

local INK, DIM, ORE  = ctx.INK, ctx.DIM, ctx.ORE
local CRIT, GREEN    = ctx.CRIT, ctx.GREEN
local OUTLINE        = ctx.OUTLINE
local SIGNAL         = ctx.SIGNAL

-- Assigned further down; declared here so `function refreshChart()` binds this
-- local rather than quietly creating a global.
local refreshChart

-- ── Depth chart ──────────────────────────────────────────────────────────────
-- The ladder, down the right edge. Layers you have reached are lit in their own
-- colour; the ones below are sealed and read as ???. Segments are equal height
-- rather than to scale — this is a map, not a graph, and Topsoil would be a
-- sliver otherwise. The marker interpolates inside whichever layer you're in.

local RunSvc = game:GetService("RunService")

-- Was 76, which is narrower than the words in it: "Magma Vents" wrapped onto
-- two lines at 11px and every depth was a cramped number underneath, so the
-- one panel whose entire job is telling you where you may go was the least
-- readable thing on screen.
--
-- Then it was a flat 190 with 56-tall segments, which on a smaller window came
-- to better than two fifths of the screen height — a ladder you read before a
-- run and never during one, taking up more room than the game. Share of the
-- window now, clamped, with shorter rungs.
local CH       = StrataConfig.Hud.Chart
local VIEW     = workspace.CurrentCamera
local CHART_W  = math.clamp(
	math.floor(((VIEW and VIEW.ViewportSize.X or 0) > 320
		and VIEW.ViewportSize.X or 1600) * CH.WidthShare),
	CH.WidthMin, CH.WidthMax)
local SEG_H    = CH.SegH
local SEG_GAP  = CH.SegGap
local HEAD_H   = CH.HeadH
local SWATCH   = CH.Swatch
local CHART    = StrataConfig.DepthChart
local CHART_H  = HEAD_H + #CHART * SEG_H + (#CHART - 1) * SEG_GAP

local chart = Instance.new("Frame")
chart.Name                   = "DepthChart"
chart.Size                   = UDim2.new(0, CHART_W, 0, CHART_H)
chart.AnchorPoint            = Vector2.new(1, 0.5)
chart.Position               = UDim2.new(1, -14, 0.5, 20)
chart.BackgroundColor3       = Color3.fromRGB(20, 24, 30)
chart.BorderSizePixel        = 0
chart.Parent                 = gui
corner(chart, 14)

-- The chart answers "where could I go", which is a question you ask at the
-- camp. Underground it is a column of question marks sitting on top of the
-- dig-site map, which is the one thing you actually need down there.
--
-- It also stands down while a screen is open. It hugs the right edge, the
-- screens are centred, and on a laptop viewport the two met — so the chart was
-- showing through the side of the contract board. Nothing is lost by hiding it:
-- if a screen is up, the screen is what you are reading.
task.spawn(function()
	while task.wait(0.4) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		chart.Visible = (root == nil
				or root.Position.Y > StrataConfig.Mine.SurfaceY - 24)
			and not panel.Visible
			and not kit.Visible
	end
end)

local chartEdge = Instance.new("UIStroke", chart)
chartEdge.Color     = OUTLINE
chartEdge.Thickness = 3

local chartShadow = Instance.new("Frame")
chartShadow.Size                   = UDim2.new(1, 14, 1, 14)
chartShadow.Position               = UDim2.new(0, -7, 0, -4)
chartShadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
chartShadow.BackgroundTransparency = 0.62
chartShadow.BorderSizePixel        = 0
chartShadow.ZIndex                 = 0
chartShadow.Parent                 = chart
corner(chartShadow, 18)

-- ── Header ───────────────────────────────────────────────────────────────────
-- This was a strip of sky with drifting clouds and the word SURFACE on it,
-- which was a nice thing and the wrong thing: it labelled the panel with the
-- name of its first row, so the panel itself had no name, and a lit sky sat at
-- the top of a dark column looking like something you were supposed to click.
-- A title tells you what the thing is, which is all the top of a panel owes.

local head = Instance.new("Frame")
head.Size                   = UDim2.new(1, -8, 0, HEAD_H - 6)
head.Position               = UDim2.new(0, 4, 0, 4)
head.BackgroundTransparency = 1
head.ZIndex                 = 2
head.Parent                 = chart

-- Strata, drawn: three bands offset like a cut bank. Same reasoning as the
-- pickaxe and the clipboard — no asset id to resolve and nothing to go missing.
local strataMark = Instance.new("Frame")
strataMark.AnchorPoint            = Vector2.new(0, 0.5)
strataMark.Position               = UDim2.new(0, 2, 0.5, 0)
strataMark.Size                   = UDim2.new(0, 16, 0, 14)
strataMark.BackgroundTransparency = 1
strataMark.ZIndex                 = 3
strataMark.Parent                 = head

for i, band in ipairs({
	{ Color3.fromRGB(176, 150, 104), 0 },
	{ Color3.fromRGB(132, 138, 148), 5 },
	{ Color3.fromRGB( 96, 100, 110), 10 },
}) do
	local b = Instance.new("Frame")
	b.Size             = UDim2.new(1, -(i - 1) * 3, 0, 3)
	b.Position         = UDim2.new(0, (i - 1) * 2, 0, band[2])
	b.BackgroundColor3 = band[1]
	b.BorderSizePixel  = 0
	b.ZIndex           = 3
	b.Parent           = strataMark
	corner(b, 1)
end

local headLabel = text(head, "GEOLOGY", UDim2.new(1, -24, 1, 0),
	StrataConfig.UI.Ink, 13, StrataConfig.UI.Head)
headLabel.Position       = UDim2.new(0, 24, 0, 0)
headLabel.TextYAlignment = Enum.TextYAlignment.Center
headLabel.ZIndex         = 3

local headRule = Instance.new("Frame")
headRule.Size                   = UDim2.new(1, -8, 0, 1)
headRule.Position               = UDim2.new(0, 4, 0, HEAD_H - 3)
headRule.BackgroundColor3       = StrataConfig.UI.Brass
headRule.BackgroundTransparency = 0.6
headRule.BorderSizePixel        = 0
headRule.ZIndex                 = 3
headRule.Parent                 = chart

-- ── Segments ─────────────────────────────────────────────────────────────────

local segments = {}

for i, layer in ipairs(CHART) do
	local y = HEAD_H + (i - 1) * (SEG_H + SEG_GAP)

	local seg = Instance.new("TextButton")
	seg.Text            = ""
	seg.AutoButtonColor = false
	seg.Name             = layer.id
	seg.Size             = UDim2.new(1, -8, 0, SEG_H)
	seg.Position         = UDim2.new(0, 4, 0, y)
	seg.BackgroundColor3 = Color3.new(1, 1, 1)
	seg.BorderSizePixel  = 0
	seg.ClipsDescendants = true
	seg.ZIndex           = 2
	seg.Parent           = chart
	corner(seg, 9)

	local fade = Instance.new("UIGradient", seg)
	fade.Rotation = 90

	local edge = Instance.new("UIStroke", seg)
	edge.Color        = OUTLINE
	edge.Thickness    = 2
	edge.Transparency = 0.2

	-- ── The swatch ───────────────────────────────────────────────────────────
	-- A real piece of the rock, not a coloured square: a part wearing the
	-- layer's own terrain material, rendered live in a ViewportFrame. The same
	-- trick ItemModels uses for the kit, and for the same reason — there is no
	-- image to upload, so the picture cannot go stale when the material does.
	--
	-- Only the built layers have a stratum to read a material off. The rest
	-- get a padlock where this would be, which is what the concept does too.
	local stratum = StrataConfig.GetStratumById
		and StrataConfig.GetStratumById(layer.id) or nil

	local swatch = Instance.new("ViewportFrame")
	swatch.AnchorPoint            = Vector2.new(0, 0.5)
	swatch.Position               = UDim2.new(0, 7, 0.5, 0)
	swatch.Size                   = UDim2.new(0, SWATCH, 0, SWATCH)
	swatch.BackgroundColor3       = Color3.fromRGB(16, 18, 22)
	swatch.BorderSizePixel        = 0
	swatch.Ambient                = Color3.fromRGB(150, 150, 158)
	swatch.LightColor             = Color3.fromRGB(255, 244, 226)
	swatch.LightDirection         = Vector3.new(-0.6, -1, -0.4)
	swatch.ZIndex                 = 3
	swatch.Parent                 = seg
	corner(swatch, 5)

	local swatchEdge = Instance.new("UIStroke", swatch)
	swatchEdge.Color        = StrataConfig.UI.StoneDark
	swatchEdge.Thickness    = 1.5
	swatchEdge.Transparency = 0.2

	do
		-- Turned off-axis so the light catches two faces. Flat on, a rock
		-- material is one even tone and reads as paint.
		local rock = Instance.new("Part")
		rock.Size     = Vector3.new(2, 2, 2)
		rock.Material = (stratum and stratum.material) or Enum.Material.Rock
		rock.Color    = layer.color
		rock.CFrame   = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-18), math.rad(32), 0)
		rock.Parent   = swatch

		local cam = Instance.new("Camera")
		cam.FieldOfView = 28
		cam.CFrame      = CFrame.lookAt(Vector3.new(0, 0, 7), Vector3.zero)
		cam.Parent      = swatch
		swatch.CurrentCamera = cam
	end

	-- Colour rail, now a thin stripe down the very edge rather than a bar in
	-- the middle of the row: the swatch carries the layer's identity and two
	-- things doing that competed.
	local rail = Instance.new("Frame")
	rail.Size             = UDim2.new(0, 3, 1, -14)
	rail.Position         = UDim2.new(0, 1, 0, 7)
	rail.BackgroundColor3 = layer.color
	rail.BorderSizePixel  = 0
	rail.ZIndex           = 3
	rail.Parent           = seg
	corner(rail, 2)

	local TEXT_X = 7 + SWATCH + 8

	local name = text(seg, layer.name, UDim2.new(1, -(TEXT_X + 8), 0, 17),
		Color3.fromRGB(255, 255, 255), 13, StrataConfig.UI.Head)
	name.Position       = UDim2.new(0, TEXT_X, 0, 7)
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.TextTruncate   = Enum.TextTruncate.AtEnd
	name.ZIndex         = 3

	-- The band, not just its top edge. "260m" told you where a layer starts
	-- and nothing about how far it runs, which is the question the panel is
	-- being asked.
	local nextLayer = CHART[i + 1]
	local band = nextLayer
		and ("%d - %dm"):format(math.abs(layer.top), math.abs(nextLayer.top))
		or  ("%dm+"):format(math.abs(layer.top))

	local depth = text(seg, band, UDim2.new(1, -(TEXT_X + 8), 0, 14),
		Color3.fromRGB(206, 214, 224), 11, StrataConfig.UI.Number)
	depth.Position     = UDim2.new(0, TEXT_X, 1, -20)
	depth.TextTruncate = Enum.TextTruncate.AtEnd
	depth.ZIndex       = 3

	-- Where you are, as a chip. Shown instead of the padlock, since the two
	-- can never both be true.
	local chip = Instance.new("Frame")
	chip.Name             = "Current"
	chip.AnchorPoint      = Vector2.new(1, 0.5)
	chip.Position         = UDim2.new(1, -6, 0.5, 0)
	chip.Size             = UDim2.new(0, 10, 0, 10)
	chip.BackgroundColor3 = StrataConfig.UI.Brass
	chip.BorderSizePixel  = 0
	chip.Visible          = false
	chip.ZIndex           = 4
	chip.Parent           = seg
	corner(chip, 5)

	-- ── The padlock ──────────────────────────────────────────────────────────
	-- Two frames: a body, and a shackle that is a ring with its lower half
	-- hidden behind the body. Drawn rather than an asset id, because an asset
	-- id that does not resolve fails silently and leaves an empty square, and
	-- a padlock is six lines.
	local lock = Instance.new("Frame")
	lock.Name                   = "Lock"
	lock.AnchorPoint            = Vector2.new(0.5, 0.5)
	lock.Position               = UDim2.new(0, 7 + SWATCH / 2, 0.5, 0)
	lock.Size                   = UDim2.new(0, 15, 0, 19)
	lock.BackgroundTransparency = 1
	lock.ZIndex                 = 3
	-- Off until the refresh says otherwise, so an unlocked layer never shows a
	-- padlock for the frame between being built and being told what it is.
	lock.Visible                = false
	lock.Parent                 = seg

	local shackle = Instance.new("Frame")
	shackle.Size                   = UDim2.new(0, 9, 0, 10)
	shackle.Position               = UDim2.new(0.5, -4.5, 0, 0)
	shackle.BackgroundTransparency = 1
	shackle.ZIndex                 = 3
	shackle.Parent                 = lock
	corner(shackle, 5)
	local shackleEdge = Instance.new("UIStroke", shackle)
	shackleEdge.Color     = Color3.fromRGB(150, 160, 174)
	shackleEdge.Thickness = 2

	local body = Instance.new("Frame")
	body.Size             = UDim2.new(1, 0, 0, 11)
	body.Position         = UDim2.new(0, 0, 1, -11)
	body.BackgroundColor3 = Color3.fromRGB(150, 160, 174)
	body.BorderSizePixel  = 0
	body.ZIndex           = 4
	body.Parent           = lock
	corner(body, 3)

	segments[i] = {
		layer = layer, frame = seg, fade = fade, edge = edge,
		rail = rail, name = name, depth = depth, y = y, lit = nil,
		lock = lock, lockParts = { shackleEdge, body },
		swatch = swatch, chip = chip, band = band,
	}
end

-- ── Layer detail card ────────────────────────────────────────────────────────
-- Hovering a layer opens a card beside the strip: what the rock is, how hard it
-- is, and what comes out of it. Layers you have never reached give away nothing
-- except what they will want from you.

local card = Instance.new("Frame")
card.Name             = "LayerCard"
card.Size             = UDim2.new(0, 238, 0, 156)
card.AnchorPoint      = Vector2.new(1, 0.5)
card.Position         = UDim2.new(0, -10, 0, 0)
card.BackgroundColor3 = Color3.fromRGB(24, 28, 35)
card.BorderSizePixel  = 0
card.Visible          = false
card.ZIndex           = 8
card.Parent           = chart
corner(card, 12)

local cardEdge = Instance.new("UIStroke", card)
cardEdge.Color     = OUTLINE
cardEdge.Thickness = 3

local cardBar = Instance.new("Frame")
cardBar.Size             = UDim2.new(1, -20, 0, 4)
cardBar.Position         = UDim2.new(0, 10, 0, 10)
cardBar.BackgroundColor3 = ORE
cardBar.BorderSizePixel  = 0
cardBar.ZIndex           = 9
cardBar.Parent           = card
corner(cardBar, 2)

local function cardText(str, y, colour, size, font, height)
	local l = text(card, str, UDim2.new(1, -24, 0, height or 16), colour, size, font)
	l.Position       = UDim2.new(0, 12, 0, y)
	l.ZIndex         = 9
	l.TextWrapped    = true
	l.TextYAlignment = Enum.TextYAlignment.Top
	return l
end

local cardName  = cardText("", 18, Color3.fromRGB(255, 255, 255), 16, StrataConfig.UI.Head, 22)
local cardRange = cardText("", 40, DIM, 11, StrataConfig.UI.Number)
local cardHard  = cardText("", 56, Color3.fromRGB(214, 158, 60), 11, StrataConfig.UI.Number)
local cardBlurb = cardText("", 76, Color3.fromRGB(186, 194, 204), 11, StrataConfig.UI.Body, 30)
local cardHead  = cardText("FOUND HERE", 110, SIGNAL, 10, StrataConfig.UI.Head, 14)
local cardFinds = cardText("", 124, ORE, 11, StrataConfig.UI.Body, 28)

local function showCard(i)
	local s     = segments[i]
	local layer = s.layer
	local found = (S.deepest or 0) >= math.floor(math.abs(layer.top))
	local below = CHART[i + 1] and math.floor(math.abs(CHART[i + 1].top)) or nil

	cardBar.BackgroundColor3 = found and layer.color or Color3.fromRGB(80, 88, 100)
	cardName.Text  = found and layer.name or "UNCHARTED"
	cardRange.Text = below
		and ("%dm – %dm"):format(math.floor(math.abs(layer.top)), below)
		or  ("%dm and below"):format(math.floor(math.abs(layer.top)))

	if found then
		-- Hardness alone answered "can I break it". The ladder is two locks, so
		-- the chart states both, and states them in the same words the contract
		-- board refuses you in.
		local stratum = StrataConfig.GetStratumById and StrataConfig.GetStratumById(layer.id)
		local gate = stratum and StrataConfig.LayerLock(stratum, S.level, S.miningPower)
		cardHard.Text = gate and gate.why
			or ("hardness %d  ·  open"):format(layer.hardness or 1)
		cardHard.TextColor3 = gate and CRIT or GREEN
		cardBlurb.Text = layer.blurb or ""

		local names = {}
		for _, id in ipairs(layer.finds or {}) do
			local ore = StrataConfig.GetOre(id)
			table.insert(names, ore and ore.name or id)
		end
		cardFinds.Text      = table.concat(names, ", ")
		cardFinds.TextColor3 = ORE
	else
		cardHard.Text  = layer.requires and ("requires " .. layer.requires) or ""
		cardBlurb.Text = "You have never been this deep. Nothing is known about the rock down here."
		cardFinds.Text = "???"
		cardFinds.TextColor3 = Color3.fromRGB(110, 118, 130)
	end

	card.Position = UDim2.new(0, -10, 0, s.y + SEG_H / 2)
	card.Visible  = true
end

for i, s in ipairs(segments) do
	s.frame.MouseEnter:Connect(function() showCard(i) end)
	s.frame.MouseLeave:Connect(function() card.Visible = false end)
end

-- ── Position marker ──────────────────────────────────────────────────────────

local markerLine = Instance.new("Frame")
markerLine.Size             = UDim2.new(1, -8, 0, 2)
markerLine.Position         = UDim2.new(0, 4, 0, HEAD_H)
markerLine.AnchorPoint      = Vector2.new(0, 0.5)
markerLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
markerLine.BorderSizePixel  = 0
markerLine.ZIndex           = 6
markerLine.Parent           = chart

local markerArrow = text(chart, "<", UDim2.new(0, 18, 0, 18),
	Color3.fromRGB(255, 255, 255), 16, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
markerArrow.AnchorPoint = Vector2.new(0, 0.5)
markerArrow.Position    = UDim2.new(1, 2, 0, HEAD_H)
markerArrow.ZIndex      = 6

-- ── Refresh ──────────────────────────────────────────────────────────────────

local function isDiscovered(layer)
	return (S.deepest or 0) >= math.floor(math.abs(layer.top))
end

-- First sealed layer is your objective, so it shows what it wants from you
function refreshChart()
	local firstSealed = nil
	for i, s in ipairs(segments) do
		if not isDiscovered(s.layer) then firstSealed = firstSealed or i end
	end

	for i, s in ipairs(segments) do
		local found = isDiscovered(s.layer)
		local goal  = (i == firstSealed)

		if found ~= s.lit or goal then
			s.lit = found

			if found then
				local base = s.layer.color
				s.fade.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, base:Lerp(Color3.new(0, 0, 0), 0.32)),
					ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(0, 0, 0), 0.62)),
				})
				s.name.Text        = s.layer.name
				s.name.TextColor3  = Color3.fromRGB(255, 255, 255)
				s.depth.Text       = s.band
				s.depth.TextColor3 = Color3.fromRGB(206, 214, 224)
				s.rail.BackgroundColor3       = s.layer.color
				s.rail.BackgroundTransparency = 0
				s.lock.Visible   = false
				s.swatch.Visible = true
			else
				s.fade.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 38, 46)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 25, 31)),
				})
				s.name.Text       = goal and s.layer.name or "???"
				s.name.TextColor3 = goal and Color3.fromRGB(210, 216, 224)
					or Color3.fromRGB(96, 104, 116)
				-- The goal layer says what it wants from you; the ones past it
				-- still give away their depth, because how far down a thing is
				-- is not a secret and "?" told you nothing twice.
				s.depth.Text       = goal and (s.layer.requires or s.band) or s.band
				s.depth.TextColor3 = goal and ORE or Color3.fromRGB(104, 112, 124)
				s.rail.BackgroundColor3       = Color3.fromRGB(70, 78, 90)
				s.rail.BackgroundTransparency = 0.3

				-- The padlock takes the swatch's place rather than sitting
				-- beside it. You have not seen this rock, so there is no
				-- picture of it to show — which is the honest version of the
				-- concept's locked row, and leaves the right side clear.
				s.swatch.Visible = false
				s.lock.Visible   = true
				local tone = goal and ORE or Color3.fromRGB(104, 112, 124)
				s.lockParts[1].Color           = tone
				s.lockParts[2].BackgroundColor3 = tone
			end
		end
	end
end

-- ── Live marker + idle animation ─────────────────────────────────────────────

local markerY = HEAD_H
local pulse   = 0

RunSvc.RenderStepped:Connect(function(dt)
	pulse += dt

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local y = math.min(root.Position.Y, 0)

	-- Which layer contains this depth, and how far through it we are
	local index, frac = 1, 0
	for i, layer in ipairs(CHART) do
		local nextTop = CHART[i + 1] and CHART[i + 1].top or StrataConfig.ChartFloor
		if y <= layer.top and y > nextTop then
			index = i
			frac  = (layer.top - y) / math.max(layer.top - nextTop, 1)
			break
		elseif y <= nextTop and i == #CHART then
			index, frac = i, 1
		end
	end

	local targetY = HEAD_H + (index - 1) * (SEG_H + SEG_GAP) + math.clamp(frac, 0, 1) * SEG_H
	markerY = markerY + (targetY - markerY) * math.min(dt * 9, 1)

	markerLine.Position  = UDim2.new(0, 4, 0, markerY)
	markerArrow.Position = UDim2.new(1, 2, 0, markerY)

	-- The layer you're standing in breathes so it reads as "you are here", and
	-- carries the chip. This loop is the only thing that knows which layer
	-- that is, so it is the right place to set it — the refresh runs on state
	-- changes and would be a frame behind the arrow beside it.
	for i, s in ipairs(segments) do
		-- Compared rather than just anded: lit is nil until the first refresh,
		-- and assigning nil to Visible is an error rather than a false.
		local here = (i == index) and s.lit == true
		if here then
			s.edge.Color        = s.layer.color
			s.edge.Transparency = 0.15 + math.sin(pulse * 3) * 0.15
			s.edge.Thickness    = 2.6
		else
			s.edge.Color        = OUTLINE
			s.edge.Transparency = 0.2
			s.edge.Thickness    = 2
		end
		if s.chip.Visible ~= here then s.chip.Visible = here end
	end
end)


return refreshChart
end
