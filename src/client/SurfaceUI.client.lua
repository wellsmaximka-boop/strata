local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local GearConfig   = require(ReplicatedStorage:WaitForChild("GearConfig"))
local ItemModels   = require(ReplicatedStorage:WaitForChild("ItemModels"))

local player = Players.LocalPlayer

local remotes      = ReplicatedStorage:WaitForChild("MineRemotes")
local stateChanged = remotes:WaitForChild("StateChanged")
local soldEvent    = remotes:WaitForChild("Sold")
local sellRequest  = remotes:WaitForChild("SellRequest")
local craftRequest = remotes:WaitForChild("CraftRequest")
local craftResult  = remotes:WaitForChild("CraftResult")
local equipRequest = remotes:WaitForChild("EquipRequest")
local liftRequest  = remotes:WaitForChild("LiftRequest")
local zoneChanged  = remotes:WaitForChild("ZoneChanged")
local hazardState  = remotes:WaitForChild("HazardState")
local surfaceCall  = remotes:WaitForChild("ReturnToSurface")

-- Fetched up here with the rest of them on purpose. A WaitForChild halfway down
-- the file stalls everything below it if the remote is late, which would take
-- the whole HUD with it rather than just the contract board.
local contractBoardEvent = remotes:WaitForChild("ContractBoard")
local contractRequest    = remotes:WaitForChild("ContractRequest")
local contractAccept     = remotes:WaitForChild("ContractAccept")

-- ── Palette ──────────────────────────────────────────────────────────────────
-- Read from the shared stone palette so the panels, the HUD and the world all
-- agree on what colour the game is.
local UIP    = StrataConfig.UI
local INK    = UIP.Ink
local DIM    = UIP.Dim
local ORE    = UIP.Ore
local SIGNAL = UIP.Crystal
local GREEN  = UIP.Moss
local CRIT   = UIP.Warning
local PANEL  = UIP.StoneDeep
local SLOT   = UIP.Stone

local gui = Instance.new("ScreenGui")
gui.Name           = "StrataUI"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 5
gui.Parent         = player:WaitForChild("PlayerGui")

-- Latest server state; every panel reads from this.
local S = {
	inventory = {}, carried = 0, capacity = 0,
	credits = 0, owned = {}, equipped = {}, resistances = {},
}

-- Forward-declared: the depth chart is built at the bottom of this file, but
-- the state handler above it needs to call this when `deepest` changes.
local refreshChart

-- ── Building blocks ──────────────────────────────────────────────────────────
-- Thousands separators. Up here with the other primitives rather than down
-- in the Depot section where it started: the contract board needs it too,
-- and a local declared below its caller is invisible to it.
local function commas(n)
	local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end


-- The requested radius is a suggestion; the config decides.
--
-- There were 78 places setting a corner by hand across the interface, using
-- nineteen different radii between 2 and 22. That inconsistency is most of what
-- read as unpolished — nothing lined up with anything, and a panel at 18 next to
-- a chip at 9 next to a tile at 12 is three different products on one screen.
-- It is also why setting StrataConfig.UI.Corner to 2 changed nothing: not one of
-- those 78 asked.
--
-- Capped rather than replaced, so a caller that deliberately wanted a tight 3
-- still gets 3 and nothing grows. Anything genuinely circular — a coin, a pip,
-- the end of a bar — calls round() instead, which is scale-based and stays a
-- circle whatever the chrome does.
local function corner(inst, radius)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(0, math.min(radius or UIP.Corner, UIP.Corner))
	return c
end

local function round(inst)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(1, 0)
	return c
end

local function stroked(inst, colour, thickness, transparency)
	local s = Instance.new("UIStroke", inst)
	s.Color        = colour or Color3.fromRGB(64, 74, 88)
	s.Thickness    = thickness or 1.5
	s.Transparency = transparency or 0.25
	return s
end

local function text(parent, str, size, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.BackgroundTransparency = 1
	l.Text                   = str
	l.TextColor3             = colour or INK
	l.TextSize               = textSize or 14
	l.Font                   = StrataConfig.FaceFor(font or StrataConfig.UI.Body, l.TextSize)
	l.TextXAlignment         = align or Enum.TextXAlignment.Left

	-- The black outline every label used to carry. It was hardcoded here and
	-- ignored StrataConfig.UI.TextEdge entirely, which is why turning that down
	-- never did anything: a halo on every word, which is what a sticker looks
	-- like rather than a readout. The panels are dark; light text sits on them
	-- without help.
	--
	-- Driven by the config now, and skipped outright at zero rather than left as
	-- a thousand UIStroke objects doing nothing.
	local thick = StrataConfig.UI.TextEdge or 0
	if thick > 0 then
		local edge = Instance.new("UIStroke")
		edge.Color           = StrataConfig.UI.StoneDark
		edge.Thickness       = thick
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		edge.Parent          = l
	end
	l.Parent                 = parent
	return l
end

-- ── Plate ────────────────────────────────────────────────────────────────────
-- What turns a rounded rectangle into a panel: something behind the content so
-- it is not a flat void, iron brackets bolted over the corners, and rivets. The
-- references all do the same three things — a patterned backing, a frame with
-- weight to it, and hardware.
--
-- Ours is a mining company, so the hardware is riveted plate and the pattern is
-- strata running across the back.

local IRON_UI   = Color3.fromRGB(96, 104, 118)
local IRON_UI_D = Color3.fromRGB(58, 65, 78)
local RIVET     = Color3.fromRGB(140, 150, 166)

-- Granite grains scattered over a panel. Fixed positions from a fixed seed, so
-- the stone never crawls, and cheap: forty frames drawn once when the panel is
-- built. This is what stops a flat rectangle reading as flat.
local function granite(parent, w, h, count, salt)
	local speck = Instance.new("Frame")
	speck.Name                   = "Granite"
	speck.Size                   = UDim2.fromScale(1, 1)
	speck.BackgroundTransparency = 1
	speck.BorderSizePixel        = 0
	speck.ClipsDescendants       = true
	speck.ZIndex                 = 0
	speck.Parent                 = parent

	local seed = (salt or 7) * 104729 + 20261
	for i = 1, count or 60 do
		seed = (seed * 48271) % 2147483647
		local sx = seed % math.max(w, 1)
		seed = (seed * 48271) % 2147483647
		local sy = seed % math.max(h, 1)
		seed = (seed * 48271) % 2147483647
		local big = (seed % 7 == 0)

		local fleck = Instance.new("Frame")
		fleck.Size                   = UDim2.new(0, big and 3 or 2, 0, big and 3 or 2)
		fleck.Position               = UDim2.new(0, sx, 0, sy)
		fleck.BackgroundColor3       = big and UIP.Vein or UIP.Speckle
		fleck.BackgroundTransparency = big and 0.62 or 0.8
		fleck.BorderSizePixel        = 0
		fleck.ZIndex                 = 0
		fleck.Parent                 = speck
	end
	return speck
end

-- Diagonal seams across the back of a panel, very faint. Clipped by the parent,
-- so the parent has to be clipping already.
local function hatch(parent, spacing, alpha, rotation)
	local back = Instance.new("Frame")
	back.Name                   = "Hatch"
	back.Size                   = UDim2.fromScale(1, 1)
	back.BackgroundTransparency = 1
	back.BorderSizePixel        = 0
	back.ClipsDescendants       = true
	back.ZIndex                 = 0
	back.Parent                 = parent

	for i = 0, 44 do
		local seam = Instance.new("Frame")
		seam.Size                   = UDim2.new(0, 2, 2, 0)
		seam.Position               = UDim2.new(0, i * (spacing or 26) - 260, -0.5, 0)
		seam.Rotation               = rotation or 38
		seam.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
		seam.BackgroundTransparency = alpha or 0.965
		seam.BorderSizePixel        = 0
		seam.ZIndex                 = 0
		seam.Parent                 = back
	end
	return back
end

local function rivet(parent, x, y, zindex)
	local r = Instance.new("Frame")
	r.Size             = UDim2.new(0, 7, 0, 7)
	r.AnchorPoint      = Vector2.new(0.5, 0.5)
	r.Position         = UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
	r.BackgroundColor3 = RIVET
	r.BorderSizePixel  = 0
	r.ZIndex           = zindex or 4
	r.Parent           = parent
	corner(r, 4)
	local ring = Instance.new("UIStroke", r)
	ring.Color        = UIP.Stone
	ring.Thickness    = 1.5
	ring.Transparency = 0.2
	return r
end

-- An iron bracket bolted over one corner, with its bolts
local function bracket(parent, sx, sy, accent)
	local arm, thick, inset = 46, 7, 7

	for _, run in ipairs({
		{ w = arm, h = thick },
		{ w = thick, h = arm },
	}) do
		local bar = Instance.new("Frame")
		bar.Size             = UDim2.new(0, run.w, 0, run.h)
		bar.AnchorPoint      = Vector2.new(sx < 0 and 0 or 1, sy < 0 and 0 or 1)
		bar.Position         = UDim2.new(sx < 0 and 0 or 1, sx < 0 and inset or -inset,
			sy < 0 and 0 or 1, sy < 0 and inset or -inset)
		bar.BackgroundColor3 = IRON_UI
		bar.BorderSizePixel  = 0
		bar.ZIndex           = 4
		bar.Parent           = parent
		corner(bar, 3)

		local line = Instance.new("UIStroke", bar)
		line.Color     = UIP.StoneDeep
		line.Thickness = 2

		local sheen = Instance.new("UIGradient", bar)
		sheen.Rotation = 90
		sheen.Color    = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 158, 172)),
		})
	end

	-- A bolt at the elbow, and a stub of the panel accent so each screen is
	-- still its own colour
	rivet(parent, UDim.new(sx < 0 and 0 or 1, sx < 0 and 14 or -14),
		UDim.new(sy < 0 and 0 or 1, sy < 0 and 14 or -14), 5)

	local tab = Instance.new("Frame")
	tab.Size             = UDim2.new(0, 20, 0, 3)
	tab.AnchorPoint      = Vector2.new(sx < 0 and 0 or 1, sy < 0 and 0 or 1)
	tab.Position         = UDim2.new(sx < 0 and 0 or 1, sx < 0 and 56 or -56,
		sy < 0 and 0 or 1, sy < 0 and 9 or -9)
	tab.BackgroundColor3 = accent
	tab.BorderSizePixel  = 0
	tab.ZIndex           = 4
	tab.Parent           = parent
	corner(tab, 2)
	return tab
end

-- Everything a panel gets that is not its content. Returns a function that
-- recolours the accent bits when the panel changes what it is showing.
local function plate(frame, accent)
	frame.ClipsDescendants = false

	-- The backing sits in its own clipped frame, inset so it does not spill
	-- past the panel's rounded corners
	local backing = Instance.new("Frame")
	backing.Name                   = "Backing"
	backing.Size                   = UDim2.new(1, -6, 1, -6)
	backing.Position               = UDim2.new(0, 3, 0, 3)
	backing.BackgroundColor3       = UIP.Stone
	backing.BorderSizePixel        = 0
	backing.ClipsDescendants       = true
	backing.ZIndex                 = 0
	backing.Parent                 = frame
	corner(backing, 15)
	hatch(backing, 34, 0.978)
	granite(backing, 780, 500, 150, 3)

	-- Lit along the top edge like a cut face, dark at the foot
	local face = Instance.new("UIGradient", backing)
	face.Rotation = 90
	face.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIP.StoneLit),
		ColorSequenceKeypoint.new(0.28, UIP.Stone),
		ColorSequenceKeypoint.new(1, UIP.StoneDeep),
	})

	-- A wash of the accent up from the bottom, so the panel is not evenly grey
	local wash = Instance.new("Frame")
	wash.Size             = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = accent
	wash.BorderSizePixel  = 0
	wash.ZIndex           = 0
	wash.Parent           = backing

	local washFade = Instance.new("UIGradient", wash)
	washFade.Rotation     = 90
	washFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.97),
		NumberSequenceKeypoint.new(1, 0.9),
	})

	local tabs = {}

	-- Top corners only. Brackets on the bottom two sat straight on top of the
	-- footer text and the action button — the frame has to stay out of the
	-- way of the panel it is framing.
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(tabs, bracket(frame, sx, -1, accent))
	end

	return function(colour)
		wash.BackgroundColor3 = colour
		for _, tab in ipairs(tabs) do tab.BackgroundColor3 = colour end
	end
end

-- ── Panel chrome ─────────────────────────────────────────────────────────────
-- The look those reference shots share: a heavy dark outline, a coloured header
-- band with a diagonal gloss streak, a round close button hanging off the
-- corner, and a body inset inside the frame. Kept in the mine's palette rather
-- than the usual cartoon blue.

local OUTLINE = UIP.StoneDark
local CLOSE_R = Color3.fromRGB(206, 74, 60)

local function gloss(parent, width, rotation)
	local streak = Instance.new("Frame")
	streak.Size                   = UDim2.new(0, width, 2, 0)
	streak.Position               = UDim2.new(0, 0, -0.5, 0)
	streak.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	streak.BackgroundTransparency = 0.86
	streak.BorderSizePixel        = 0
	streak.Rotation               = rotation or 20
	streak.ZIndex                 = 2
	streak.Parent                 = parent
	return streak
end

-- Adds the frame, header and close button to an existing panel frame.
-- Returns the header (for a title) and the close button.
local function dress(frame, titleText, accent, headerHeight)
	headerHeight = headerHeight or 46

	frame.BackgroundColor3       = UIP.Stone
	frame.BackgroundTransparency = 0
	corner(frame, 18)

	-- Backing, brackets and bolts, before anything else goes on top
	local setPlate = plate(frame, accent)

	local edge = Instance.new("UIStroke", frame)
	edge.Color        = OUTLINE
	edge.Thickness    = 3.5
	edge.Transparency = 0

	-- Shadow plate behind the whole panel
	local shadow = Instance.new("Frame")
	shadow.Size                   = UDim2.new(1, 16, 1, 16)
	shadow.Position               = UDim2.new(0, -8, 0, -4)
	shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.62
	shadow.BorderSizePixel        = 0
	shadow.ZIndex                 = 0
	shadow.Parent                 = frame
	corner(shadow, 22)

	-- Header band
	-- White background on purpose: UIGradient *multiplies* with BackgroundColor3
	-- rather than replacing it, so tinting both would render accent² — much
	-- darker and duller than intended. White lets the gradient carry the colour
	-- exactly as specified.
	local header = Instance.new("Frame")
	header.Name             = "Header"
	header.Size             = UDim2.new(1, -10, 0, headerHeight)
	header.Position         = UDim2.new(0, 5, 0, 5)
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.BorderSizePixel  = 0
	header.ClipsDescendants = true
	header.ZIndex           = 2
	header.Parent           = frame
	corner(header, 13)

	-- Dark plate, not a coloured band.
	--
	-- The header used to be filled with the screen's accent at full strength —
	-- a saturated cyan slab a thousand pixels wide, which is the loudest thing
	-- in the game and says nothing except "shop". The reference does the
	-- opposite: the plate is the same steel as everything else and the colour
	-- arrives as a thin rule under it. Accent as a line reads as a label on
	-- equipment; accent as a fill reads as a website banner.
	local headerFade = Instance.new("UIGradient", header)
	headerFade.Rotation = 90
	headerFade.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIP.StoneLit),
		ColorSequenceKeypoint.new(1, UIP.Stone),
	})

	-- The rule along the bottom of the header, which is now where the accent
	-- lives. Thick enough to be a decision rather than a hairline.
	local accentRule = Instance.new("Frame")
	accentRule.Name             = "Accent"
	accentRule.Size             = UDim2.new(1, 0, 0, 4)
	accentRule.Position         = UDim2.new(0, 0, 1, -4)
	accentRule.BackgroundColor3 = accent
	accentRule.BorderSizePixel  = 0
	accentRule.ZIndex           = 4
	accentRule.Parent           = header

	local headerEdge = Instance.new("UIStroke", header)
	headerEdge.Color     = OUTLINE
	headerEdge.Thickness = 2.5

	-- Bolts along the header, and a hazard strip under it: the two details that
	-- say this is equipment rather than a website
	-- No bolts down the left of the header: they sat straight through the
	-- title. The plaque below carries the hardware instead.

	local hazard = Instance.new("Frame")
	hazard.Size             = UDim2.new(1, -10, 0, 5)
	hazard.Position         = UDim2.new(0, 5, 0, headerHeight + 6)
	hazard.BackgroundColor3 = Color3.fromRGB(24, 28, 35)
	hazard.BorderSizePixel  = 0
	hazard.ClipsDescendants = true
	hazard.ZIndex           = 2
	hazard.Parent           = frame
	corner(hazard, 3)

	for i = 0, 40 do
		local tick = Instance.new("Frame")
		tick.Size             = UDim2.new(0, 9, 2, 0)
		tick.Position         = UDim2.new(0, i * 22 - 10, -0.5, 0)
		tick.Rotation         = 34
		tick.BackgroundColor3 = Color3.fromRGB(214, 174, 72)
		tick.BackgroundTransparency = 0.55
		tick.BorderSizePixel  = 0
		tick.ZIndex           = 2
		tick.Parent           = hazard
	end

	-- The well: a recessed surface for content to sit in.
	--
	-- Until now a panel was one flat fill with everything floating on it, which
	-- is the flattest thing in the interface and most of why it read as a web
	-- page rather than a box with things in it. A darker inset, a hard inner
	-- border and a lit lip along its top edge give the plate a front and a back.
	-- It is the cheapest thing that makes a panel look built rather than drawn,
	-- and because it lives in dress() every screen gets it at once.
	local well = Instance.new("Frame")
	well.Name             = "Well"
	well.Size             = UDim2.new(1, -22, 1, -(headerHeight + 61))
	well.Position         = UDim2.new(0, 11, 0, headerHeight + 15)
	well.BackgroundColor3 = UIP.StoneDeep
	well.BorderSizePixel  = 0
	well.ZIndex           = 1
	well.Parent           = frame
	corner(well, UIP.CornerSm)

	-- Two rings, dark outside and brass inside. One line is a border; a dark
	-- line with a bright one inside it is a rebate — the thing the references
	-- put round every panel, well and slot, and most of what makes a dark box
	-- read as an object rather than a hole in the page.
	local wellEdge = Instance.new("UIStroke", well)
	wellEdge.Color     = OUTLINE
	wellEdge.Thickness = 3

	local wellBrass = Instance.new("Frame")
	wellBrass.Size                   = UDim2.new(1, -4, 1, -4)
	wellBrass.Position               = UDim2.new(0, 2, 0, 2)
	wellBrass.BackgroundTransparency = 1
	wellBrass.ZIndex                 = 1
	wellBrass.Parent                 = well
	corner(wellBrass, UIP.CornerSm)
	stroked(wellBrass, UIP.Brass, 1.5, 0.45)

	-- A lit line along the inside top edge. Light falls from above, so the upper
	-- lip of something cut into a surface catches it and the lower does not —
	-- that one asymmetry is what reads as depth rather than as a drawn rectangle.
	local wellLip = Instance.new("Frame")
	wellLip.Size                   = UDim2.new(1, -6, 0, 2)
	wellLip.Position               = UDim2.new(0, 3, 0, 1)
	wellLip.BackgroundColor3       = UIP.StoneLit
	wellLip.BackgroundTransparency = 0.4
	wellLip.BorderSizePixel        = 0
	wellLip.ZIndex                 = 1
	wellLip.Parent                 = well

	gloss(header, 26, 22).Position = UDim2.new(0, 40, -0.5, 0)
	gloss(header, 12, 22).Position = UDim2.new(0, 76, -0.5, 0)

	-- Stops short of the credits plate on the right. At 20px a long title merely
	-- got close to it; at 24 it runs underneath, and a title sliding behind the
	-- money is the kind of thing that only shows up on the one screen with the
	-- longest name.
	local title = text(header, titleText, UDim2.new(1, -(52 + 152 + UIP.Gap.lg), 1, 0),
		Color3.fromRGB(255, 255, 255), 24, StrataConfig.UI.Head)
	title.Position     = UDim2.new(0, 52, 0, 0)   -- clear of the corner bracket
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex   = 3

	-- The panel title kept its own hardcoded halo when every other label lost
	-- theirs, so it was the one word on screen still wearing an outline. It sits
	-- on a saturated accent band; it does not need help.

	-- Sat in the header rather than overhanging the corner, and the same steel
	-- as the plate it is set into.
	--
	-- It used to hang off the corner as a bright circle, which is a cartoon
	-- affordance: it drew more attention than anything in the panel, and once
	-- the header stopped being a coloured slab it became the only saturated
	-- object left. Red is still the hover, because a destructive control should
	-- say so when you reach for it — but it says it then, not permanently.
	local close = Instance.new("TextButton")
	close.Size             = UDim2.new(0, 34, 0, 34)
	close.AnchorPoint      = Vector2.new(1, 0.5)
	close.Position         = UDim2.new(1, -UIP.Gap.sm, 0, headerHeight / 2 + 5)
	close.BackgroundColor3 = UIP.StoneDeep
	close.BorderSizePixel  = 0
	close.Text             = "X"
	close.TextColor3       = Color3.fromRGB(255, 255, 255)
	close.TextSize         = 20
	close.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, close.TextSize)
	close.AutoButtonColor  = false
	close.ZIndex           = 5
	close.Parent           = frame
	corner(close, UIP.CornerSm)

	local closeEdge = Instance.new("UIStroke", close)
	closeEdge.Color     = OUTLINE
	closeEdge.Thickness = 2

	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.1),
			{ BackgroundColor3 = CLOSE_R }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.1),
			{ BackgroundColor3 = UIP.StoneDeep }):Play()
	end)

	-- Recolours the header. An explicit function rather than a metatable hook,
	-- which was clever and fragile in equal measure.
	-- The plate and the rule carry the accent now; the header itself stays steel
	-- whatever screen is open, which is what makes six screens look like six
	-- views of one machine rather than six differently painted boxes.
	local function setAccent(colour)
		setPlate(colour)
		accentRule.BackgroundColor3 = colour
	end

	return header, close, title, setAccent
end

-- ── Open / close animation ───────────────────────────────────────────────────
-- Scale rather than fade: fading a panel means fading every descendant, and a
-- CanvasGroup would break the character ViewportFrame inside the armour screen.

local POP_IN  = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function scaler(frame)
	local s = Instance.new("UIScale")
	s.Scale  = 1
	s.Parent = frame
	return s
end

-- Both pops scale relative to whatever the screen has been fitted to, which is
-- 1 on a wide monitor and less on a laptop. Tweening to a flat 1 would throw the
-- fit away the moment a panel opened, which is how the panel came to cover the
-- action bar.
local function popIn(frame, scale)
	local target  = frame:GetAttribute("FitScale") or 1
	scale.Scale   = target * 0.82
	frame.Visible = true
	TweenService:Create(scale, POP_IN, { Scale = target }):Play()
end

-- Squish on press, spring back on release. Applied to every clickable row so
-- the whole interface responds the same way.
local function pressable(button, baseColour, hoverColour)
	local s = Instance.new("UIScale")
	s.Parent = button

	button.MouseButton1Down:Connect(function()
		TweenService:Create(s, TweenInfo.new(0.06), { Scale = 0.97 }):Play()
	end)

	local function release()
		TweenService:Create(s, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)

	if baseColour and hoverColour then
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.1),
				{ BackgroundColor3 = hoverColour }):Play()
		end)
		button.MouseLeave:Connect(function()
			release()
			TweenService:Create(button, TweenInfo.new(0.1),
				{ BackgroundColor3 = baseColour }):Play()
		end)
	else
		button.MouseLeave:Connect(release)
	end
end

-- ── Button states ────────────────────────────────────────────────────────────
-- Normal, hover and disabled, on top of the press squish pressable() already
-- gives. The interface had normal and a squish; a button you cannot use looked
-- exactly like one you can, which is the state that matters most because it is
-- the one that needs explaining.
--
-- Disabled is not the same colour turned down. It drops to steel and loses its
-- lit edge completely, because a dimmed amber still reads as amber and people
-- keep clicking it. Losing the bevel is what says "this is not a thing right
-- now" rather than "this is a thing, quietly".
--
-- The lit edge follows the same rule as the well's lip: light from above, so
-- the top catches it. A raised button lights its top; a cut well lights its
-- inside top. Same light, opposite surfaces, and together they read as one
-- material.
local function states(button, tone)
	local lip = Instance.new("Frame")
	lip.Name                   = "Lip"
	lip.Size                   = UDim2.new(1, -8, 0, 2)
	lip.Position               = UDim2.new(0, 4, 0, 2)
	lip.BackgroundColor3       = Color3.new(1, 1, 1)
	lip.BackgroundTransparency = 0.62
	lip.BorderSizePixel        = 0
	lip.ZIndex                 = (button.ZIndex or 1) + 1
	lip.Parent                 = button

	local handle = { tone = tone, enabled = true, hovering = false }

	local function paint(instant)
		local fill, ink
		if not handle.enabled then
			fill, ink = UIP.Stone, UIP.Dim
		elseif handle.hovering then
			fill, ink = handle.tone:Lerp(Color3.new(1, 1, 1), 0.22), OUTLINE
		else
			fill, ink = handle.tone, OUTLINE
		end

		lip.Visible      = handle.enabled
		button.TextColor3 = ink
		button.Active     = handle.enabled
		button.AutoButtonColor = false

		if instant then
			button.BackgroundColor3 = fill
		else
			TweenService:Create(button, TweenInfo.new(0.1),
				{ BackgroundColor3 = fill }):Play()
		end
	end

	button.MouseEnter:Connect(function()
		handle.hovering = true
		if handle.enabled then paint() end
	end)
	button.MouseLeave:Connect(function()
		handle.hovering = false
		paint()
	end)

	function handle.setTone(colour)
		handle.tone = colour
		paint(true)
	end

	function handle.setEnabled(on)
		handle.enabled = on and true or false
		paint(true)
	end

	paint(true)
	return handle
end

local function popOut(frame, scale, onDone)
	local target = frame:GetAttribute("FitScale") or 1
	local t = TweenService:Create(scale, POP_OUT, { Scale = target * 0.86 })
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		scale.Scale   = target
		if onDone then onDone() end
	end)
end

-- ── Action bar ───────────────────────────────────────────────────────────────
-- Left edge, vertically centred and lifted clear of the mobile joystick.
-- Everything the player needs is reachable from here, at any depth.

-- 3×2 grid, three wide so it lines up exactly with the power and pack panels
-- above it (3 × 58 + 2 × 8 = 190, the column width). Position comes from
-- StrataConfig.Hud, shared with MineClient, so the column is one object even
-- though two scripts build it.
local HUD = StrataConfig.Hud

-- Measured off the window, the same way MineClient does it, so the buttons
-- come out the width of the panels stacked above them.
local function viewport()
	local cam = workspace.CurrentCamera
	local v   = cam and cam.ViewportSize or Vector2.new(0, 0)
	if v.X < 320 or v.Y < 240 then return 1600, 900 end
	return v.X, v.Y
end

local STACK = StrataConfig.HudMetrics(viewport())

local NAV  = STACK.Nav
local TILE = NAV.Tile
local ICON = NAV.Icon

local bar = Instance.new("Frame")
bar.Name                   = "ActionBar"
bar.Size                   = UDim2.new(0, NAV.W_total, 0, NAV.H_total)
bar.Position               = UDim2.new(0, HUD.Left, 0, STACK.NavY)
bar.BackgroundTransparency = 1
-- Above the screens. They are fitted to clear the bar, but on a viewport too
-- narrow to have room for both the fit gives up and takes the full width — and
-- navigation you cannot click is worse than navigation that overlaps.
bar.ZIndex                 = 8
bar.Parent                 = gui

local barLayout = Instance.new("UIGridLayout", bar)
barLayout.CellSize              = UDim2.new(0, TILE, 0, TILE)
barLayout.CellPadding           = UDim2.new(0, NAV.Gap, 0, NAV.Gap)
barLayout.FillDirectionMaxCells = NAV.Cols
barLayout.SortOrder             = Enum.SortOrder.LayoutOrder

-- ── The name, on request ─────────────────────────────────────────────────────
-- One plate, moved to whichever tile the mouse is over, rather than six labels
-- permanently taking up the width of the word CAMP. This is the whole reason
-- the nav could shrink: the names were never needed at rest, only findable.
local tip = Instance.new("Frame")
tip.Name                   = "NavTip"
tip.AnchorPoint            = Vector2.new(0, 0.5)
tip.Size                   = UDim2.new(0, 0, 0, 26)
tip.AutomaticSize          = Enum.AutomaticSize.X
tip.BackgroundColor3       = UIP.StoneDeep
tip.BackgroundTransparency = 0.08
tip.BorderSizePixel        = 0
tip.Visible                = false
tip.ZIndex                 = 20
tip.Parent                 = gui
corner(tip, 6)

local tipEdge = stroked(tip, UIP.Brass, 1, 0.45)

local tipPad = Instance.new("UIPadding", tip)
tipPad.PaddingLeft  = UDim.new(0, 10)
tipPad.PaddingRight = UDim.new(0, 10)

local tipText = text(tip, "", UDim2.new(0, 0, 1, 0), UIP.Ink, 13,
	StrataConfig.UI.Head)
tipText.AutomaticSize = Enum.AutomaticSize.X
tipText.ZIndex        = 21

local function showTip(tile, label, accent)
	tipText.Text      = label
	tipText.TextColor3 = accent
	tipEdge.Color     = accent
	tip.Visible       = true
	tip.Position      = UDim2.new(
		0, tile.AbsolutePosition.X + tile.AbsoluteSize.X + 10,
		0, tile.AbsolutePosition.Y + tile.AbsoluteSize.Y / 2)
end

local function hideTip()
	tip.Visible = false
end

-- Paste Creator Store icon asset ids here and they replace the emoji glyphs
-- automatically — nothing else has to change. Free UI packs work fine; the ids
-- look like "rbxassetid://1234567890".
local ICONS = {
	SHOP  = "rbxassetid://13429538917",
	KIT   = "rbxassetid://16181381646",
	LIFT  = "rbxassetid://12338897538",
	CAMP  = "rbxassetid://13060262529",
}

-- The two with no asset behind them. Filled in further down, once the drawing
-- functions exist; an entry here beats an emoji, which is what the fallback
-- gives you and which does not sit with five flat white icons.
local DRAWN = {}

-- [label] = setActive. Collected as the rows are built, so the code that knows
-- which screen is open can light the right one without holding a reference to
-- six buttons.
local NAV_ROWS = {}

-- A pickaxe built from two rotated frames. Not as crisp as real icon art, but
-- it costs no asset and sits in the same visual language as everything else.
local function drawPickaxe(parent)
	-- Drawn in a fixed 28-unit space and then scaled, because the four pieces
	-- below are placed by hand and a pick that is one pixel out at this size
	-- stops looking like a pick. UIScale takes the whole drawing with it.
	local holder = Instance.new("Frame")
	holder.Size                   = UDim2.new(0, 28, 0, 28)
	holder.AnchorPoint            = Vector2.new(0.5, 0.5)
	holder.Position               = UDim2.new(0.5, 0, 0.5, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex                 = 4
	holder.Parent                 = parent

	Instance.new("UIScale", holder).Scale = (ICON - 7) / 28

	local function piece(w, h, x, y, rot, colour, z)
		local p = Instance.new("Frame")
		p.Size             = UDim2.new(0, w, 0, h)
		p.Position         = UDim2.new(0, x, 0, y)
		p.Rotation         = rot
		p.BackgroundColor3 = colour
		p.BorderSizePixel  = 0
		p.ZIndex           = z
		p.Parent           = holder
		corner(p, 2)
		return p
	end

	-- Upright: straight shaft, head across the top, and two angled ends that
	-- give it the swept pick shape. Reads clearest at this size.
	local WOOD  = Color3.fromRGB(156, 111, 69)
	local STEEL = Color3.fromRGB(201, 207, 215)

	piece(4, 24, 12, 4, 0, WOOD, 4)      -- shaft
	piece(24, 6,  2, 3, 0, STEEL, 5)     -- head
	piece(8, 6,   1, 7,  34, STEEL, 5)   -- left point, angled down
	piece(8, 6,  19, 7, -34, STEEL, 5)   -- right point, angled down

	return holder
end

-- RUNS was the one button with no asset behind it, so it fell through to the
-- glyph branch and rendered a full-colour emoji clipboard next to five flat
-- white icons. Drawn in the same 28-unit space as the pick, for the same
-- reason: no asset id to resolve, nothing to 404.
local function drawClipboard(parent)
	local holder = Instance.new("Frame")
	holder.Size                   = UDim2.new(0, 28, 0, 28)
	holder.AnchorPoint            = Vector2.new(0.5, 0.5)
	holder.Position               = UDim2.new(0.5, 0, 0.5, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex                 = 4
	holder.Parent                 = parent

	Instance.new("UIScale", holder).Scale = (ICON - 7) / 28

	local function piece(w, h, x, y, colour, z, radius)
		local p = Instance.new("Frame")
		p.Size             = UDim2.new(0, w, 0, h)
		p.Position         = UDim2.new(0, x, 0, y)
		p.BackgroundColor3 = colour
		p.BorderSizePixel  = 0
		p.ZIndex           = z
		p.Parent           = holder
		corner(p, radius or 2)
		return p
	end

	local BOARD = Color3.fromRGB(198, 204, 212)
	local CLIP  = Color3.fromRGB(150, 158, 168)
	local LINE  = Color3.fromRGB(96, 102, 112)

	piece(20, 25, 4, 3, BOARD, 4, 3)     -- the board
	piece(10,  4, 9, 1, CLIP,  6, 2)     -- the clip across the top
	for i = 0, 2 do
		piece(12, 2, 8, 11 + i * 5, LINE, 5, 1)   -- three ruled lines
	end

	return holder
end

DRAWN.PICKS = drawPickaxe
DRAWN.RUNS  = drawClipboard

-- A button built the way a designed one is built: a shadow beneath, a gradient
-- body, a highlight bevel across the top, a coloured rim, and a press that
-- actually moves. No image required, though one drops straight in.
local function barButton(order, icon, label, accent, onClick)
	-- The grid layout owns both position and size, so the holder sets neither.
	local holder = Instance.new("Frame")
	holder.Name                   = label
	holder.BackgroundTransparency = 1
	holder.LayoutOrder            = order
	holder.Parent                 = bar

	-- Drop shadow: Roblox has no box-shadow, so it is a darker plate behind
	local shadow = Instance.new("Frame")
	shadow.Size                   = UDim2.new(1, 4, 1, 4)
	shadow.Position               = UDim2.new(0, -2, 0, 3)
	shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel        = 0
	shadow.ZIndex                 = 1
	shadow.Parent                 = holder
	corner(shadow, 17)

	-- White background, colour in the gradient — see the note in dress(): a
	-- UIGradient multiplies with BackgroundColor3, so tinting both darkens the
	-- result badly.
	local b = Instance.new("TextButton")
	b.Size             = UDim2.new(1, 0, 1, 0)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel  = 0
	b.Text             = ""
	b.AutoButtonColor  = false
	b.ZIndex           = 2
	b.Parent           = holder
	corner(b, 16)

	-- Warm steel, matching the panels. These were cold blue-grey (56, 66, 80),
	-- which was the only place in the interface still on the old palette — six
	-- grey boxes stacked beside a warm one, which is exactly the look being
	-- chased out.
	local FILL_TOP, FILL_BOTTOM = UIP.Stone, UIP.StoneDeep

	local fill = Instance.new("UIGradient", b)
	fill.Rotation = 90

	local function setFill(top, bottom)
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(1, bottom),
		})
	end
	setFill(FILL_TOP, FILL_BOTTOM)

	local rim = stroked(b, accent, 2, 0.3)

	-- Glossy bevel across the top half
	local bevel = Instance.new("Frame")
	bevel.Size                   = UDim2.new(1, -10, 0, math.floor(TILE * 0.38))
	bevel.Position               = UDim2.new(0, 5, 0, 4)
	bevel.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	bevel.BorderSizePixel        = 0
	bevel.ZIndex                 = 3
	bevel.Parent                 = b
	corner(bevel, 11)
	local bevelFade = Instance.new("UIGradient", bevel)
	bevelFade.Rotation     = 90
	bevelFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- The icon is the whole tile now. A plate behind it stops six icons at six
	-- different weights from reading as six different sizes.
	local plate = Instance.new("Frame")
	plate.AnchorPoint            = Vector2.new(0.5, 0.5)
	plate.Position               = UDim2.new(0.5, 0, 0.5, 0)
	plate.Size                   = UDim2.new(0, ICON + 8, 0, ICON + 8)
	plate.BackgroundColor3       = UIP.StoneDark
	plate.BackgroundTransparency = 0.4
	plate.BorderSizePixel        = 0
	plate.ZIndex                 = 3
	plate.Parent                 = b
	corner(plate, 8)

	local iconId = ICONS[label]
	local art
	if DRAWN[label] then
		art = DRAWN[label](plate)
	elseif iconId and iconId ~= "" then
		art = Instance.new("ImageLabel")
		art.Image                  = iconId
		art.ScaleType              = Enum.ScaleType.Fit
		art.BackgroundTransparency = 1
		art.AnchorPoint            = Vector2.new(0.5, 0.5)
		art.Size                   = UDim2.new(0, ICON, 0, ICON)
		art.Position               = UDim2.new(0.5, 0, 0.5, 0)
		art.ZIndex                 = 4
		art.Parent                 = plate
	else
		art = text(plate, icon, UDim2.new(1, 0, 1, 0), INK,
			math.floor(ICON * 0.66), StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		art.ZIndex = 4
	end


	local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- ── Open, hovered, resting ───────────────────────────────────────────────
	-- The open tile fills with its own accent, which is the one piece of this
	-- that tells you where you are without being read. It matters more now
	-- than it did as a list: with the names gone, this is the only thing left
	-- saying which screen you are looking at.
	local WHITE  = Color3.new(1, 1, 1)
	local active = false

	local function paint(hovered)
		if active then
			setFill(accent:Lerp(WHITE, 0.2), accent)
			plate.BackgroundTransparency = 0.7
			TweenService:Create(rim, QUICK, { Transparency = 0, Thickness = 2.5 }):Play()
			return
		end

		local lift = hovered and 0.18 or 0
		setFill(FILL_TOP:Lerp(WHITE, lift), FILL_BOTTOM:Lerp(WHITE, lift))
		plate.BackgroundTransparency = hovered and 0.25 or 0.4
		TweenService:Create(rim, QUICK, {
			Transparency = hovered and 0 or 0.45,
			Thickness    = hovered and 2.5 or 1.5,
		}):Play()
	end

	paint(false)

	local function setActive(on)
		if active == on then return end
		active = on
		paint(false)
	end

	b.MouseEnter:Connect(function()
		paint(true)
		showTip(holder, label, accent)
	end)
	b.MouseLeave:Connect(function()
		paint(false)
		hideTip()
	end)

	-- Press: sink into the shadow, then spring back
	b.MouseButton1Down:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.07), { Position = UDim2.new(0, 0, 0, 3) }):Play()
		TweenService:Create(shadow, TweenInfo.new(0.07), { BackgroundTransparency = 0.8 }):Play()
	end)
	local function release()
		TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0, 0, 0, 0) }):Play()
		TweenService:Create(shadow, TweenInfo.new(0.12), { BackgroundTransparency = 0.55 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)

	b.Activated:Connect(onClick)

	NAV_ROWS[label] = setActive
	return b, rim
end

-- ── Panel shell ──────────────────────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name                   = "Panel"
panel.Size                   = UDim2.new(0, 900, 0, 546)
panel.AnchorPoint            = Vector2.new(0.5, 0.5)
panel.Position               = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3       = PANEL
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.Parent                 = gui

local panelHeader, closeBtn, panelTitle, setPanelAccent = dress(panel, "SHOP", SIGNAL)
local panelScale = scaler(panel)

-- ── The credits readout ──────────────────────────────────────────────────────
-- A number and a coin used to sit loose on the header gradient, which makes
-- money a caption. It is the one figure on the screen that every decision in the
-- shop is measured against, so it gets a housing: a recessed plate cut into the
-- header, the coin on the left, the figure in amber monospace on the right.
--
-- Monospace matters here more than anywhere. Credits tick up and down by
-- thousands, and a proportional face makes the whole number jump sideways every
-- time a digit changes.
local cashPlate = Instance.new("Frame")
cashPlate.Name             = "Credits"
cashPlate.AnchorPoint      = Vector2.new(1, 0.5)
cashPlate.Size             = UDim2.new(0, 152, 0, 28)
cashPlate.Position         = UDim2.new(1, -UIP.Gap.md, 0.5, 0)
cashPlate.BackgroundColor3 = UIP.StoneDark
cashPlate.BackgroundTransparency = 0.12
cashPlate.BorderSizePixel  = 0
cashPlate.ZIndex           = 3
cashPlate.Parent           = panelHeader
corner(cashPlate, UIP.CornerSm)

local cashEdge = Instance.new("UIStroke", cashPlate)
cashEdge.Color     = OUTLINE
cashEdge.Thickness = 2

-- A drawn gold coin instead of the icon asset, which rendered almost black and
-- disappeared against the dark end of the header gradient.
local panelCash = Instance.new("Frame")
panelCash.Size             = UDim2.new(0, 18, 0, 18)
panelCash.AnchorPoint      = Vector2.new(0, 0.5)
panelCash.Position         = UDim2.new(0, UIP.Gap.sm, 0.5, 0)
panelCash.BackgroundColor3 = Color3.fromRGB(255, 204, 92)
panelCash.BorderSizePixel  = 0
panelCash.ZIndex           = 4
panelCash.Parent           = cashPlate
round(panelCash)   -- a coin is a circle, not a rounded square

local panelCashRim = Instance.new("UIStroke", panelCash)
panelCashRim.Color     = Color3.fromRGB(150, 102, 28)
panelCashRim.Thickness = 2

local panelCredits = text(cashPlate, "0", UDim2.new(1, -34, 1, 0),
	UIP.Ore, 17, StrataConfig.UI.Number, Enum.TextXAlignment.Right)
panelCredits.Position    = UDim2.new(1, -UIP.Gap.sm, 0, 0)
panelCredits.AnchorPoint = Vector2.new(1, 0)
panelCredits.ZIndex      = 4

local panelBody = Instance.new("ScrollingFrame")
panelBody.Size                   = UDim2.new(1, -36, 1, -116)
panelBody.Position               = UDim2.new(0, 18, 0, 60)
panelBody.BackgroundTransparency = 1
panelBody.BorderSizePixel        = 0
panelBody.ScrollBarThickness     = 4
panelBody.ScrollBarImageColor3   = Color3.fromRGB(90, 100, 114)
panelBody.CanvasSize             = UDim2.new()
panelBody.AutomaticCanvasSize    = Enum.AutomaticSize.Y
panelBody.Parent                 = panel

-- Two cards to a row. A single tall column of full-width rows was the thing
-- that made every panel feel like a wall of text.
local bodyLayout = Instance.new("UIGridLayout", panelBody)
bodyLayout.CellSize    = UDim2.new(0, StrataConfig.UI.TileW, 0, StrataConfig.UI.TileH)
bodyLayout.CellPadding = UDim2.new(0, StrataConfig.UI.Gap.md, 0, StrataConfig.UI.Gap.md)
bodyLayout.SortOrder   = Enum.SortOrder.LayoutOrder

-- Centred, which is the cheap half of the "huge empty space on tile screens"
-- note. A grid pinned left puts six tiles against one wall of a 900px panel and
-- leaves a void on the other side; centred, a short row reads as a short row
-- rather than as a panel that failed to fill. The expensive half — the panel
-- sizing itself to its contents — is a separate job.
bodyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- A strip along the bottom for the footer line to sit on, rather than text
-- floating on the backing. It also stops the panel ending in nothing, which is
-- what made the whole thing feel unfinished.
local panelRail = Instance.new("Frame")
panelRail.Size                   = UDim2.new(1, -22, 0, 30)
panelRail.Position               = UDim2.new(0, 11, 1, -38)
panelRail.BackgroundColor3       = Color3.fromRGB(16, 19, 25)
panelRail.BackgroundTransparency = 0.15
panelRail.BorderSizePixel        = 0
panelRail.ClipsDescendants       = true
panelRail.Parent                 = panel
corner(panelRail, 8)
hatch(panelRail, 18, 0.955, 34)

local railEdge = Instance.new("UIStroke", panelRail)
railEdge.Color        = Color3.fromRGB(70, 78, 92)
railEdge.Thickness    = 1.5
railEdge.Transparency = 0.4

-- A stamped plate at the left end of the rail, the way a bit of kit carries its
-- part number
local panelStamp = Instance.new("Frame")
panelStamp.Size             = UDim2.new(0, 92, 0, 18)
panelStamp.Position         = UDim2.new(0, 8, 0.5, -9)
panelStamp.BackgroundColor3 = Color3.fromRGB(30, 35, 44)
panelStamp.BorderSizePixel  = 0
panelStamp.ZIndex           = 2
panelStamp.Parent           = panelRail
corner(panelStamp, 5)

local stampEdge = Instance.new("UIStroke", panelStamp)
stampEdge.Color        = Color3.fromRGB(96, 106, 122)
stampEdge.Thickness    = 1.5
stampEdge.Transparency = 0.3

local stampText = text(panelStamp, "STRATA CO.", UDim2.new(1, 0, 1, 0),
	Color3.fromRGB(126, 138, 156), 10, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
stampText.ZIndex = 3

rivet(panelRail, UDim.new(1, -12), UDim.new(0.5, 0), 2)
rivet(panelRail, UDim.new(1, -26), UDim.new(0.5, 0), 2)

local panelFoot = text(panelRail, "", UDim2.new(1, -150, 0, 18), DIM, 12, StrataConfig.UI.Body)
panelFoot.Position = UDim2.new(0, 108, 0.5, -9)
panelFoot.ZIndex   = 2

local openTab = nil   -- "shop" | "bag" | "lift" | nil


-- ── Panel action ─────────────────────────────────────────────────────────────
-- One big button along the bottom for the panels that have a single obvious
-- thing to do. It lives outside the scrolling body so it cannot be scrolled
-- past, which is what used to happen to SELL ALL once the pack was full.

local panelAction = Instance.new("TextButton")
panelAction.Size             = UDim2.new(1, -36, 0, 48)
panelAction.Position         = UDim2.new(0, 18, 1, -92)
panelAction.BackgroundColor3 = Color3.fromRGB(214, 164, 64)
panelAction.BorderSizePixel  = 0
panelAction.Text             = ""
panelAction.TextColor3       = Color3.fromRGB(40, 28, 10)
panelAction.TextSize         = 20
	panelAction.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, panelAction.TextSize)
panelAction.AutoButtonColor  = false
panelAction.Visible          = false
panelAction.Parent           = panel
corner(panelAction, 12)

local actionEdge = Instance.new("UIStroke", panelAction)
actionEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
actionEdge.Color           = Color3.fromRGB(12, 14, 18)
actionEdge.Thickness       = 3

local actionState = states(panelAction, Color3.fromRGB(214, 164, 64))
pressable(panelAction)

local actionHandler = nil
panelAction.Activated:Connect(function()
	-- Checked here as well as painted. A disabled button that still fires is
	-- worse than one that never looked disabled, because now the interface has
	-- lied about it.
	if actionState.enabled and actionHandler then actionHandler() end
end)

-- `enabled` is optional and defaults to true, so every existing caller keeps
-- working and the ones that have a reason to refuse can say so.
local function showAction(label, colour, onClick, enabled)
	panelAction.Text    = label
	panelAction.Visible = true
	actionState.setTone(colour)
	actionState.setEnabled(enabled ~= false)
	actionHandler       = onClick
	panelBody.Size      = UDim2.new(1, -36, 1, -178)
end


-- ── Choice strip ─────────────────────────────────────────────────────────────
-- A row of buttons along the bottom instead of one, for when the panel is
-- asking which of several rather than yes or no. The contract board uses it for
-- difficulty; anything else can.

local panelPicker = Instance.new("Frame")
panelPicker.Size                   = UDim2.new(1, -36, 0, 64)
panelPicker.Position               = UDim2.new(0, 18, 1, -108)
panelPicker.BackgroundTransparency = 1
panelPicker.Visible                = false
panelPicker.Parent                 = panel

local pickerLayout = Instance.new("UIListLayout", panelPicker)
pickerLayout.FillDirection       = Enum.FillDirection.Horizontal
pickerLayout.Padding             = UDim.new(0, 8)
pickerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pickerLayout.SortOrder           = Enum.SortOrder.LayoutOrder

-- Solid dark fill with a bright border and bright text, not a wash of colour
-- over the panel. At eighty percent transparency every tier came out the same
-- grey — the colour has to be in the edge and the letters to read at all.
local function showPicker(options)
	for _, c in ipairs(panelPicker:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	local width = math.floor((panel.AbsoluteSize.X - 36 - (#options - 1) * 8) / #options)
	if width <= 0 then width = 168 end

	for i, o in ipairs(options) do
		local b = Instance.new("TextButton")
		b.Size             = UDim2.new(0, width, 1, 0)
		b.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
		b.BorderSizePixel  = 0
		b.Text             = ""
		b.AutoButtonColor  = false
		b.LayoutOrder      = i
		b.Parent           = panelPicker
		corner(b, 9)

		local rim = Instance.new("UIStroke", b)
		rim.Color     = o.colour
		rim.Thickness = 2.5

		-- A bar of the tier colour down the left, and a wash of it from the
		-- bottom, so the button is unmistakably that colour without the text
		-- sitting on top of it
		local wash = Instance.new("Frame")
		wash.Size             = UDim2.new(1, 0, 1, 0)
		wash.BackgroundColor3 = o.colour
		wash.BorderSizePixel  = 0
		wash.Parent           = b
		corner(wash, 9)

		local washFade = Instance.new("UIGradient", wash)
		washFade.Rotation     = 90
		washFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.94),
			NumberSequenceKeypoint.new(1, 0.72),
		})

		local label = text(b, o.label, UDim2.new(1, -10, 0, 19), o.colour, 15,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		label.Position = UDim2.new(0, 5, 0, 7)
		label.ZIndex   = 2

		local sub = text(b, o.sub, UDim2.new(1, -10, 0, 14), Color3.fromRGB(206, 214, 224), 11,
			StrataConfig.UI.Body, Enum.TextXAlignment.Center)
		sub.Position = UDim2.new(0, 5, 0, 27)
		sub.ZIndex   = 2

		if o.note then
			local note = text(b, o.note, UDim2.new(1, -10, 0, 13),
				o.noteColour or DIM, 10, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
			note.Position = UDim2.new(0, 5, 0, 44)
			note.ZIndex   = 2
		end

		b.MouseEnter:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.1),
				{ BackgroundColor3 = Color3.fromRGB(28, 34, 44) }):Play()
			TweenService:Create(rim, TweenInfo.new(0.1), { Thickness = 3.5 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.12),
				{ BackgroundColor3 = Color3.fromRGB(15, 18, 24) }):Play()
			TweenService:Create(rim, TweenInfo.new(0.12), { Thickness = 2.5 }):Play()
		end)
		b.Activated:Connect(o.pick)
	end

	panelPicker.Visible = true
	panelBody.Size      = UDim2.new(1, -36, 1, -196)
end


-- ── The detail pane ──────────────────────────────────────────────────────────
-- The right-hand column every inventory screen in the references has: whatever
-- you clicked, big, with its rarity named in its own colour and the button that
-- acts on it underneath.
--
-- The grid makes room for it with padding rather than by resizing, so the two
-- screens that want full-width rows — the contract board and the depth chart —
-- go on working without knowing this exists.

-- One handle for everything the panel wears around its grid: the category
-- chips above it, the detail pane beside it, and the padding that makes
-- room for both. One local rather than five, which matters here — this
-- file runs a handful of locals under Luau's limit of two hundred.
local screen
;(function()
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local detail = UIKit.Detail(panel, 240)
detail.frame.Visible = false

local bodyPad = Instance.new("UIPadding", panelBody)

-- The chip row lives above the grid and pushes it down with the same
-- padding the detail pane uses to pull it in, so nothing has to resize.
local chips = UIKit.Chips(panel, UDim2.new(0, 20, 0, 62))

local function useDetail(on)
	detail.frame.Visible  = on
	bodyPad.PaddingRight  = UDim.new(0, on and 256 or 0)
	if not on then detail.Clear() end
end

-- Called by every screen that wants neither, which is every screen that
-- has not asked for them
local function clearChrome()
	chips.Hide()
	useDetail(false)
	bodyPad.PaddingTop = UDim.new(0, 0)
end

local function showChips(options, accent, onPick)
	chips.Set(options, accent, onPick)
	bodyPad.PaddingTop = UDim.new(0, 36)
end

screen = {
	chips  = chips,
	detail = detail,
	Use    = useDetail,
	Show   = showChips,
	Reset  = clearChrome,
}

end)()
-- Cells are set per screen: the contract board wants one wide row each, the
-- shop wants two to a line.
local function setCells(w, h)
	bodyLayout.CellSize = UDim2.new(0, w, 0, h)
end

local function clearBody()
	panelAction.Visible = false
	panelPicker.Visible = false
	setCells(StrataConfig.UI.TileW, StrataConfig.UI.TileH)
	screen.Reset()
	actionHandler       = nil
	panelBody.Size      = UDim2.new(1, -36, 1, -116)
	for _, c in ipairs(panelBody:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

local function closePanel()
	if not panel.Visible then return end
	openTab = nil
	popOut(panel, panelScale)
end
closeBtn.Activated:Connect(closePanel)

-- ── Ribbon and close ─────────────────────────────────────────────────────────
-- The title on a plate hanging off the top-left corner and a red X hanging off
-- the top-right. A title inside a panel is a caption; a title overhanging it is
-- a label on an object, which is the difference these screens live or die on.
--
-- Both follow the header rather than replacing it: every screen goes on setting
-- panelTitle.Text as it always did, and the ribbon listens.

;(function()
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local ribbon = UIKit.Ribbon(panel, "SHOP", SIGNAL)
-- Hidden outright, not faded. TextTransparency only hides the fill, and every
-- label in this game now carries a UIStroke with its own transparency — so the
-- old title kept drawing as a black outline behind the ribbon.
panelTitle.Visible = false

panelTitle:GetPropertyChangedSignal("Text"):Connect(function()
	ribbon.Set(panelTitle.Text)
end)
-- Wrapping the function rather than watching the header. `setPanelAccent` puts
-- the colour into a UIGradient — which multiplies, so the header's own
-- BackgroundColor3 stays pure white and a GetPropertyChangedSignal on it never
-- fires. That is why the ribbon stayed cyan while the header went gold.
local applyAccent = setPanelAccent
setPanelAccent = function(colour)
	applyAccent(colour)
	ribbon.Set(panelTitle.Text, colour)
end

closeBtn.Visible = false
UIKit.Close(panel, closePanel)
end)()

-- ── Cards ────────────────────────────────────────────────────────────────────
-- Two to a row, wide and short. The old rows were a single tall column of three
-- full-width lines of prose each, which turned into a wall of text you had to
-- scroll through. A card gets a picture, a name, one line of what it does and
-- one line of what it costs — and nothing else.
--
-- Every card has a picture, even when the item has no model yet: an empty well
-- looks like a bug, and a drawn glyph looks like a placeholder on purpose.

-- What to draw in the well when there is nothing to render
local SLOT_GLYPH = {
	helmet = "▲", chest = "■", legs = "▼", pickaxe = "T",
	lamp = "*", pack = "B", scanner = "O",
}

local function iconWell(parent, x, y, size)
	local well = Instance.new("Frame")
	well.Size             = UDim2.new(0, size, 0, size)
	well.Position         = UDim2.new(0, x, 0, y)
	well.BackgroundColor3 = Color3.fromRGB(13, 16, 21)
	well.BorderSizePixel  = 0
	well.ZIndex           = 2
	well.Parent           = parent
	corner(well, 9)

	local rim = Instance.new("UIStroke", well)
	rim.Color        = Color3.fromRGB(74, 84, 98)
	rim.Thickness    = 2
	rim.Transparency = 0.15

	-- A corner tick, so the well reads as a socket rather than a hole
	local tick = Instance.new("Frame")
	tick.Size             = UDim2.new(0, 10, 0, 2)
	tick.Position         = UDim2.new(0, 5, 0, 5)
	tick.BackgroundColor3 = Color3.fromRGB(110, 122, 140)
	tick.BorderSizePixel  = 0
	tick.ZIndex           = 4
	tick.Parent           = well

	return well, rim
end

-- A square rarity tile, the way every inventory in this genre draws one: the
-- whole body is the rarity colour, the level is in one corner, a mark in the
-- other, and the name runs along a dark plate at the bottom.
--
-- Every screen still calls this with the same table it always did. The keys are
-- mapped onto a tile here rather than at five call sites, which is why the shop,
-- the pick works, the depot and the forge all changed shape at once.
--
-- Clicking no longer buys. It selects, and the detail pane on the right grows
-- the button — which is both what the references do and the end of misclicking
-- a purchase you meant to read first.
-- Wrapped in a function on purpose: SurfaceUI sits a handful of locals under
-- Luau's limit of two hundred per chunk, and the helpers below belong to the
-- card rather than to the file. A `do` block would not do — a block's locals
-- still coexist with the outer ones and the peak is unchanged.
local card
;(function()
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local function rarityFor(o)
	if o.rarity then return o.rarity end
	if o.ore then return StrataConfig.OreRarity(o.ore) end

	local gear = o.iconId and GearConfig.Get(o.iconId) or nil
	if gear then return StrataConfig.GearRarity(gear) end

	return StrataConfig.RarityAt(1)
end

local function drawArt(o, into)
	if o.locked then
		local q = text(into, "?", UDim2.new(1, 0, 1, 0), Color3.fromRGB(150, 150, 178),
			38, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		q.ZIndex = 8
		return
	end
	if o.iconId and ItemModels.Icon(o.iconId, into, 66, UDim2.new(0, 6, 0, 2)) then return end
	if o.ore and ItemModels.OreIcon(o.ore, into, 66, UDim2.new(0, 6, 0, 2)) then return end
	if o.glyph then
		local g = text(into, o.glyph, UDim2.new(1, 0, 1, 0), o.accent or SIGNAL, 34,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		g.ZIndex = 8
	end
end

-- What the right-hand pane says about the thing you picked
local function selectCard(o)
	local rarity = rarityFor(o)

	local stats = o.stats
	if not stats then
		stats = {}
		if o.perk and o.perk ~= "" then
			table.insert(stats, { label = "EFFECT", value = o.perk, colour = INK })
		end
		if o.cost and o.cost ~= "" then
			table.insert(stats, { label = "COST", value = o.cost,
				colour = o.costColour or ORE })
		end
		if o.pill and o.pill ~= "" then
			table.insert(stats, { label = "STATE", value = o.pill,
				colour = o.pillColour or GREEN })
		end
	end

	screen.detail.Show({ title = o.title, rarity = rarity, stats = stats })
	drawArt(o, screen.detail.art)

	if o.onClick and o.enabled then
		UIKit.Chunky(screen.detail.foot, {
			text     = o.action or "TAKE IT",
			colour   = o.actionColour or GREEN,
			size     = UDim2.new(1, 0, 1, 0),
			onClick  = o.onClick,
		})
	elseif o.pill and o.pill ~= "" then
		UIKit.Chunky(screen.detail.foot, {
			text    = o.pill,
			colour  = o.pillColour or UIP.Iron,
			size    = UDim2.new(1, 0, 1, 0),
		})
	end
end

function card(order, o)
	screen.Use(true)

	local rarity = rarityFor(o)

	-- The line under the name: what it costs where that is the question, and
	-- what it is otherwise
	local line, lineColour = rarity.name, rarity.colour
	if o.cost and o.cost ~= "" then
		line, lineColour = o.cost, o.costColour or ORE
	elseif o.perk and o.perk ~= "" then
		line, lineColour = o.perk, UIP.Dim
	end

	local mark, markColour
	if o.pill == "OWNED" or o.pill == "EQUIPPED" or o.pill == "WORN" then
		mark, markColour = "◆", GREEN
	elseif o.locked or o.pill == "LOCKED" then
		mark, markColour = "!", CRIT
	end

	return UIKit.Tile(panelBody, {
		order      = order,
		rarity     = rarity,
		title      = o.title,
		line       = line,
		lineColour = lineColour,
		count      = o.count,
		level      = o.level,
		mark       = mark,
		markColour = markColour,
		enabled    = o.enabled ~= false,
		-- Locked is a different thing from unavailable: the item is real and is
		-- being withheld, which is worth saying out loud rather than greying out
		locked     = o.locked or o.pill == "LOCKED" or nil,
		art        = function(into) drawArt(o, into) end,
		onClick    = function() selectCard(o) end,
	})
end
end)()
-- ── Mystery ──────────────────────────────────────────────────────────────────
-- The shop used to list every item in the game whether or not it could ever be
-- reached yet, which both spoiled it and buried what you could actually buy.
-- One tier past what you own is visible; the rest is a count of unknowns.

-- The lowest tier that exists in each slot. The gate used to count up from
-- zero, which meant a slot whose cheapest item is tier 2 — every pickaxe in the
-- game — showed nothing at all, and nothing was buyable because nothing was
-- visible. You cannot own your way out of that.
local FLOOR_TIER = {}
for _, gear in ipairs(GearConfig.Gear) do
	local t = gear.tier or 1
	if not FLOOR_TIER[gear.slot] or t < FLOOR_TIER[gear.slot] then
		FLOOR_TIER[gear.slot] = t
	end
end

local function revealedTiers()
	local best = {}
	for slot, floor in pairs(FLOOR_TIER) do best[slot] = floor - 1 end

	for _, gear in ipairs(GearConfig.Gear) do
		if S.owned[gear.id] then
			best[gear.slot] = math.max(best[gear.slot] or 0, gear.tier or 1)
		end
	end
	return best
end

local function mysteryCard(order, count, what)
	card(order, {
		title   = "???",
		perk    = count == 1 and ("one more " .. what .. " exists")
			or ("%d more %ss exist"):format(count, what),
		cost    = "buy what you can and it will show itself",
		accent  = Color3.fromRGB(120, 130, 148),
		enabled = false,
		locked  = true,
	})
end

-- ── Shop ─────────────────────────────────────────────────────────────────────

local function costText(gear)
	local parts = {}
	if (gear.cost.credits or 0) > 0 then
		table.insert(parts, gear.cost.credits .. "c")
	end
	for oreId, n in pairs(gear.cost.ore or {}) do
		local ore = StrataConfig.GetOre(oreId)
		table.insert(parts, n .. " " .. (ore and ore.name or oreId))
	end
	return table.concat(parts, "  ·  ")
end

local function affordable(gear)
	if S.credits < (gear.cost.credits or 0) then return false end
	for oreId, n in pairs(gear.cost.ore or {}) do
		if (S.inventory[oreId] or 0) < n then return false end
	end
	return true
end

-- One short line of what a thing does, not a sentence about it
local function perkText(gear)
	local parts = {}
	for key, value in pairs(gear.grants) do
		table.insert(parts, key .. " +" .. value)
	end
	table.sort(parts)
	return table.concat(parts, "  ·  ")
end

local function buildShop()
	clearBody()
	panelTitle.Text = "SHOP"
	setPanelAccent(SIGNAL)
	panelFoot.Text = "ore is spent from your pack"

	-- Categories, which is what the icon rails in the references are for. Laid
	-- across the top rather than down the side: the side is the detail pane,
	-- and a rail would be a second navigation arguing with the button bar that
	-- already switches screens.
	screen.Show({
		{ id = "all",    text = "All" },
		{ id = "helmet", text = "Head" },
		{ id = "chest",  text = "Body" },
		{ id = "legs",   text = "Legs" },
		{ id = "tool",   text = "Tools" },
	}, SIGNAL, buildShop)

	local want  = screen.chips.Active()
	local ARMOUR = { helmet = true, chest = true, legs = true }

	local reveal = revealedTiers()
	local order, hidden = 1, 0

	-- Picks are sold at the pick works, not here
	for _, gear in ipairs(GearConfig.Gear) do
		local kind = ARMOUR[gear.slot] and gear.slot or "tool"
		if gear.slot ~= "pickaxe" and (want == "all" or want == kind) then
			if (gear.tier or 1) <= (reveal[gear.slot] or 0) + 1 then
				local owned = S.owned[gear.id] == true
				local can   = not owned and affordable(gear)

				card(order, {
					title      = gear.name,
					perk       = perkText(gear),
					cost       = owned and "" or costText(gear),
					costColour = can and ORE or CRIT,
					pill       = owned and "OWNED" or (can and "BUY" or "SHORT"),
					pillColour = owned and GREEN or (can and SIGNAL or CRIT),
					accent     = SIGNAL,
					enabled    = can or owned,
					iconId     = gear.id,
					glyph      = SLOT_GLYPH[gear.slot],
					onClick    = can and function() craftRequest:FireServer(gear.id) end or nil,
				})
				order += 1
			else
				hidden += 1
			end
		end
	end

	if hidden > 0 then mysteryCard(order, hidden, "piece of kit") end
end

-- ── Pick works ───────────────────────────────────────────────────────────────
-- Strength is earned; pick power is bought. Both feed the same number, and the
-- footer is where that sum lives — it does not need a card each.

local function buildPicks()
	clearBody()
	panelTitle.Text = "PICK WORKS"
	setPanelAccent(StrataConfig.Zones.pickaxe.accent)

	local power = S.miningPower or 0
	local breaks = {}
	for _, stratum in ipairs(StrataConfig.Strata) do
		table.insert(breaks, ("%s %s"):format(stratum.name,
			power >= (stratum.hardness or 1) and "OK" or ("NEEDS " .. (stratum.hardness or 1))))
	end

	panelFoot.Text = ("power %d  (strength %d + pick %d)      %s")
		:format(power, S.strength or 0, power - (S.strength or 0), table.concat(breaks, "   "))

	local reveal = revealedTiers()
	local best   = S.pickaxe
	local order, hidden = 1, 0

	for _, gear in ipairs(GearConfig.Gear) do
		if gear.slot == "pickaxe" then
			if (gear.tier or 1) <= (reveal.pickaxe or 0) + 1 then
				local owned  = S.owned[gear.id] == true
				local inHand = best == gear.id
				local can    = not owned and affordable(gear)

				card(order, {
					title      = gear.name,
					perk       = "power +" .. (gear.grants.power or 0)
						.. (gear.grants.digCooldown and ("  ·  faster swing") or ""),
					cost       = owned and "" or costText(gear),
					costColour = can and ORE or CRIT,
					pill       = inHand and "IN HAND" or (owned and "OWNED" or (can and "FORGE" or "SHORT")),
					pillColour = inHand and GREEN or (can and SIGNAL or (owned and GREEN or CRIT)),
					accent     = inHand and GREEN or SIGNAL,
					enabled    = can or owned,
					iconId     = gear.id,
					glyph      = SLOT_GLYPH[gear.slot],
					onClick    = can and function() craftRequest:FireServer(gear.id) end or nil,
				})
				order += 1
			else
				hidden += 1
			end
		end
	end

	if hidden > 0 then mysteryCard(order, hidden, "pick") end
end

-- ── Lift ─────────────────────────────────────────────────────────────────────

local function buildLift()
	clearBody()
	panelTitle.Text = "LIFT"
	setPanelAccent(GREEN)
	panelFoot.Text = "the lift bores a pocket before it drops you"

	for i, stop in ipairs(GearConfig.LiftStops) do
		local locked, need = false, nil

		-- Dig to discover, lift to return: an unvisited layer is not a stop
		if stop.layerId and not (S.discovered or {})[stop.layerId] then
			locked, need = true, "finding it on foot first"
		end
		for kind, level in pairs(stop.requires or {}) do
			if (S.resistances[kind] or 0) < level then
				locked = true
				need   = string.upper(kind) .. " " .. level
			end
		end

		card(i, {
			title      = stop.name,
			perk       = stop.y >= 0 and "surface level" or (math.floor(-stop.y) .. "m down"),
			cost       = locked and ("needs " .. need) or "",
			costColour = CRIT,
			pill       = locked and "LOCKED" or "GO",
			pillColour = locked and CRIT or GREEN,
			accent     = GREEN,
			glyph      = stop.y >= 0 and "▲" or "▼",
			enabled    = not locked,
			onClick    = function()
				liftRequest:FireServer(i)
				closePanel()
			end,
		})
	end
end

-- ── Contracts ────────────────────────────────────────────────────────────────
-- The board at the camp. One job per layer, and a layer you have never stood in
-- shows as locked rather than hidden — seeing that deep work exists is half the
-- reason to go looking for it.
--
-- Taking one is two decisions, not one: which job, then how hard. The tier is
-- where the money is, and it is bought with clock rather than with anything you
-- own, so it is a bet on how fast you are.


local contracts = {}
local boardIn   = 0
local picked    = nil    -- index of the contract being looked at

local function clockText(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return ("%d:%02d"):format(m, s)
end

-- ── Biome preview ────────────────────────────────────────────────────────────
-- A cross-section, not a swatch. Sky at the top, then a band for every layer
-- down to the one the contract is in, and a cavern cut into that bottom band
-- with spikes and ore in it. Reading it top to bottom tells you how far down
-- the job is, which a flat colour never could.
--
-- Every value comes from the config, so a new layer draws itself.

local function stratumIndex(layerId)
	for i, s in ipairs(StrataConfig.Strata) do
		if s.id == layerId then return i, s end
	end
	return nil, nil
end

local function biomePreview(parent, layerId, w, h, x, y, known)
	local index, stratum = stratumIndex(layerId)

	local box = Instance.new("Frame")
	box.Size             = UDim2.new(0, w, 0, h)
	box.Position         = UDim2.new(0, x, 0, y)
	box.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	box.BorderSizePixel  = 0
	box.ClipsDescendants = true
	box.ZIndex           = 2
	box.Parent           = parent
	corner(box, 8)

	local rim = Instance.new("UIStroke", box)
	rim.Color     = Color3.fromRGB(92, 104, 122)
	rim.Thickness = 2

	if not (stratum and known) then
		local q = text(box, "?", UDim2.new(1, 0, 1, 0), Color3.fromRGB(104, 116, 134), 34,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		q.ZIndex = 4
		return box
	end

	local function slab(name, top, height, colour, z)
		local f = Instance.new("Frame")
		f.Size             = UDim2.new(1, 0, 0, math.ceil(height))
		f.Position         = UDim2.new(0, 0, 0, math.floor(top))
		f.BackgroundColor3 = colour
		f.BorderSizePixel  = 0
		f.ZIndex           = z or 3
		f.Parent           = box
		return f
	end

	-- Sky, and the light of the surface far above
	local sky = math.max(16 - index * 2, 8)
	slab("Sky", 0, sky, index == 1 and Color3.fromRGB(126, 168, 196)
		or Color3.fromRGB(24, 30, 40), 2)

	-- One band per layer down to this one. The one the job is in takes half the
	-- remaining height, so it is plainly the subject.
	local room    = h - sky
	local mine    = room * 0.55
	local aboveEach = index > 1 and (room - mine) / (index - 1) or 0
	local top     = sky

	for i = 1, index - 1 do
		local s = StrataConfig.Strata[i]
		slab("Above", top, aboveEach, s.color:Lerp(Color3.fromRGB(0, 0, 0), 0.45), 3)
		-- A seam line between layers
		slab("Seam", top, 1.5, Color3.fromRGB(8, 10, 14), 4)
		top += aboveEach
	end

	local band = slab("Band", top, h - top, stratum.color, 3)
	slab("Seam", top, 2, Color3.fromRGB(8, 10, 14), 4)

	-- Grain in the rock: a few darker streaks so it is not a flat rectangle
	for i = 0, 4 do
		local streak = Instance.new("Frame")
		streak.Size                   = UDim2.new(0, w, 0, 2)
		streak.Position               = UDim2.new(0, 0, 0, math.floor(top + 8 + i * 9))
		streak.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
		streak.BackgroundTransparency = 0.82
		streak.BorderSizePixel        = 0
		streak.ZIndex                 = 4
		streak.Parent                 = box
	end

	-- The cavern: a dark opening cut into the layer, with a lit floor
	local caveH = math.min(h - top - 10, 34)
	local caveY = top + 8
	local cave = Instance.new("Frame")
	cave.Size             = UDim2.new(0, w - 26, 0, caveH)
	cave.Position         = UDim2.new(0, 13, 0, math.floor(caveY))
	cave.BackgroundColor3 = Color3.fromRGB(9, 10, 14)
	cave.BorderSizePixel  = 0
	cave.ClipsDescendants = true
	cave.ZIndex           = 5
	cave.Parent           = box
	corner(cave, 10)

	-- Spikes from the roof, and a couple standing up off the floor. Rotated
	-- squares, half of each hidden by the clip, which reads as a spike.
	for i = 0, 4 do
		local spike = Instance.new("Frame")
		spike.Size             = UDim2.new(0, 9, 0, 9)
		spike.Position         = UDim2.new(0, 8 + i * 20, 0, -4)
		spike.Rotation         = 45
		spike.BackgroundColor3 = stratum.color:Lerp(Color3.fromRGB(255, 255, 255), 0.12)
		spike.BorderSizePixel  = 0
		spike.ZIndex           = 6
		spike.Parent           = cave
	end
	for _, sx in ipairs({ 24, 66 }) do
		local stub = Instance.new("Frame")
		stub.Size             = UDim2.new(0, 8, 0, 8)
		stub.Position         = UDim2.new(0, sx, 1, -5)
		stub.Rotation         = 45
		stub.BackgroundColor3 = stratum.color
		stub.BorderSizePixel  = 0
		stub.ZIndex           = 6
		stub.Parent           = cave
	end

	-- Floor of the cavern, lit by whatever is glowing in it
	local floor = Instance.new("Frame")
	floor.Size             = UDim2.new(1, 0, 0, 6)
	floor.Position         = UDim2.new(0, 0, 1, -6)
	floor.BackgroundColor3 = stratum.color:Lerp(Color3.fromRGB(0, 0, 0), 0.3)
	floor.BorderSizePixel  = 0
	floor.ZIndex           = 6
	floor.Parent           = cave

	-- The layer's three best ores, glowing, each with a halo behind it
	local best = {}
	for _, ore in ipairs(StrataConfig.Ores) do
		if not ore.archetype and (ore.strata[layerId] or 0) > 0 then
			table.insert(best, ore)
		end
	end
	table.sort(best, function(a, b) return a.value > b.value end)

	for i = 1, math.min(3, #best) do
		local ox = 18 + (i - 1) * 34
		local oy = caveH - 14 - (i % 2) * 7

		local halo = Instance.new("Frame")
		halo.Size                   = UDim2.new(0, 18, 0, 18)
		halo.Position               = UDim2.new(0, ox - 5, 0, oy - 5)
		halo.BackgroundColor3       = best[i].color
		halo.BackgroundTransparency = 0.72
		halo.BorderSizePixel        = 0
		halo.ZIndex                 = 6
		halo.Parent                 = cave
		corner(halo, 9)

		local gem = Instance.new("Frame")
		gem.Size             = UDim2.new(0, 8, 0, 8)
		gem.Position         = UDim2.new(0, ox, 0, oy)
		gem.Rotation         = 45
		gem.BackgroundColor3 = best[i].color
		gem.BorderSizePixel  = 0
		gem.ZIndex           = 7
		gem.Parent           = cave
	end

	-- Name plate along the bottom
	local plateBar = Instance.new("Frame")
	plateBar.Size                   = UDim2.new(1, 0, 0, 15)
	plateBar.Position               = UDim2.new(0, 0, 1, -15)
	plateBar.BackgroundColor3       = Color3.fromRGB(8, 10, 14)
	plateBar.BackgroundTransparency = 0.18
	plateBar.BorderSizePixel        = 0
	plateBar.ZIndex                 = 8
	plateBar.Parent                 = box

	local tag = text(plateBar, string.upper(stratum.name), UDim2.new(1, 0, 1, 0),
		Color3.fromRGB(240, 244, 250), 10, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	tag.ZIndex = 9

	return box
end

-- ── The board ────────────────────────────────────────────────────────────────

local buildRuns   -- forward declared: the difficulty buttons rebuild the panel

local function contractCard(order, c)
	local onRun  = S.run ~= nil
	local can    = not c.locked and not onRun
	local chosen = picked == order

	local card = Instance.new(can and "TextButton" or "Frame")
	card.BackgroundColor3       = chosen and Color3.fromRGB(42, 50, 62) or SLOT
	card.BackgroundTransparency = can and 0 or 0.45
	card.BorderSizePixel        = 0
	card.LayoutOrder            = order
	card.ClipsDescendants       = true
	card.Parent                 = panelBody
	if card:IsA("TextButton") then
		card.Text            = ""
		card.AutoButtonColor = false
	end
	corner(card, 10)

	local accent = c.locked and Color3.fromRGB(120, 130, 148) or ORE
	stroked(card, chosen and accent or (can and accent or Color3.fromRGB(52, 60, 72)), 2,
		chosen and 0 or 0.35)

	-- A lit top edge, so a row reads as a plate laid on the panel rather than a
	-- rectangle drawn on it. Same light rule as the wells, the button lips and
	-- the tile slots — it is the repetition that makes them one material.
	local cardLip = Instance.new("Frame")
	cardLip.Size                   = UDim2.new(1, -8, 0, 2)
	cardLip.Position               = UDim2.new(0, 4, 0, 1)
	cardLip.BackgroundColor3       = UIP.StoneLit
	cardLip.BackgroundTransparency = can and 0.45 or 0.78
	cardLip.BorderSizePixel        = 0
	cardLip.ZIndex                 = 2
	cardLip.Parent                 = card

	-- A locked layer gets a narrow bar in its accent down the leading edge
	-- instead of a 132-wide thumbnail of a question mark. A big empty box is the
	-- most space on screen spent saying the least, and it gave a layer you
	-- cannot enter exactly the same visual weight as the one you can.
	if c.locked then
		local bar = Instance.new("Frame")
		bar.Size             = UDim2.new(0, 6, 1, -24)
		bar.Position         = UDim2.new(0, 12, 0, 12)
		bar.BackgroundColor3 = accent
		bar.BackgroundTransparency = 0.25
		bar.BorderSizePixel  = 0
		bar.ZIndex           = 3
		bar.Parent           = card
	else
		biomePreview(card, c.layerId, 132, 88, 12, 12, true)
	end

	-- Text starts where the art ends, and a locked row has no art
	local tx = c.locked and 32 or 156
	local name = text(card, c.layerName, UDim2.new(1, -tx - 130, 0, 22),
		can and INK or DIM, 17, StrataConfig.UI.Head)
	name.Position = UDim2.new(0, tx, 0, 14)

	-- The server says why it is shut: never been here, or the level and the pick
	local line = text(card, c.locked and (c.lockWhy or "you have never been here") or c.line,
		UDim2.new(1, -tx - 20, 0, 18), DIM, 12, StrataConfig.UI.Body)
	line.Position = UDim2.new(0, tx, 0, 38)

	local reward = text(card, ("%s  ·  %d credits  ·  +%d on the objective")
		:format(clockText(c.duration), c.payout, c.bonus),
		UDim2.new(1, -tx - 20, 0, 16), ORE, 11, StrataConfig.UI.Body)
	reward.Position = UDim2.new(0, tx, 0, 62)

	-- State chip
	local tone = c.locked and CRIT or (onRun and DIM or GREEN)
	local chip = Instance.new("Frame")
	chip.Size                   = UDim2.new(0, 96, 0, 24)
	chip.AnchorPoint            = Vector2.new(1, 0)
	chip.Position               = UDim2.new(1, -12, 0, 13)
	chip.BackgroundColor3       = tone
	chip.BackgroundTransparency = 0.82
	chip.BorderSizePixel        = 0
	chip.ZIndex                 = 3
	chip.Parent                 = card
	corner(chip, 7)
	local chipEdge = Instance.new("UIStroke", chip)
	chipEdge.Color        = tone
	chipEdge.Thickness    = 1.5
	chipEdge.Transparency = 0.25

	local pill = text(chip, c.locked and "LOCKED" or (onRun and "OUT" or (chosen and "PICKED" or c.title)),
		UDim2.new(1, 0, 1, 0), tone, 10, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	pill.ZIndex = 4

	if can then
		pressable(card, chosen and Color3.fromRGB(42, 50, 62) or SLOT, Color3.fromRGB(45, 54, 67))
		card.Activated:Connect(function()
			picked = (picked == order) and nil or order
			buildRuns()
		end)
	end
	return card
end

function buildRuns()
	clearBody()
	panelTitle.Text = "CONTRACTS"
	setPanelAccent(ORE)
	setCells(716, 112)

	-- Deliberately does NOT ask the server for the board. Asking here fed the
	-- reply straight back into this function, which rebuilt the panel several
	-- times a second — and a card destroyed between your mouse-down and your
	-- mouse-up never fires. openTabNamed asks once, when the tab opens.



	if S.run then
		panelFoot.Text = "you are out on one — get back to the shaft"
	elseif picked and contracts[picked] then
		panelFoot.Text = "pick how hard you want it"
	else
		panelFoot.Text = "the board turns over in " .. clockText(boardIn)
	end

	if #contracts == 0 then
		local empty = text(panelBody, "No work posted.",
			UDim2.new(1, -8, 0, 60), DIM, 14, StrataConfig.UI.Body, Enum.TextXAlignment.Center)
		empty.LayoutOrder = 1
		return
	end

	for i, c in ipairs(contracts) do
		contractCard(i, c)
	end

	-- The tier row, once a job is chosen. Each button shows what that tier does
	-- to the clock and the pay, because those are the two numbers you are
	-- trading against each other.
	local chosen = picked and contracts[picked]
	if chosen and not chosen.locked and not S.run then
		local stratum
		for _, s in ipairs(StrataConfig.Strata) do
			if s.id == chosen.layerId then stratum = s end
		end

		local yours = S.miningPower or 0
		local tiers = {}

		for i, d in ipairs(StrataConfig.Expedition.Difficulties) do
			local want = StrataConfig.RecommendedPower(stratum, i)
			local up   = yours >= want

			table.insert(tiers, {
				label  = d.name,
				sub    = ("%s   %s c"):format(clockText(chosen.duration * d.time),
					commas(math.floor(chosen.payout * d.pay))),
				-- The one number that says whether to press it. Red when you are
				-- short, which is the whole worth / not worth call.
				note   = ("POWER %d%s"):format(want, up and "" or ("  ·  you have " .. yours)),
				noteColour = up and GREEN or CRIT,
				colour = d.colour,
				pick   = function()
					contractAccept:FireServer(chosen.index, i)
					picked = nil
					closePanel()
				end,
			})
		end
		showPicker(tiers)
	end
end

contractBoardEvent.OnClientEvent:Connect(function(list, refreshIn)
	contracts = list or {}
	boardIn   = refreshIn or 0
	if picked and not contracts[picked] then picked = nil end
	if openTab == "runs" then buildRuns() end
end)

-- ── Kit screen ───────────────────────────────────────────────────────────────
-- Its own module: the largest single screen in the game at nearly eight hundred
-- lines, and the locals it needs were the bulk of what pushed this file onto
-- Luau's 200-per-function ceiling. Over there they are its own; here it costs
-- six names.
local Kit = require(
	script.Parent:WaitForChild("ui"):WaitForChild("KitScreen"))({
	gui = gui, state = S, player = player,
	UIKit = UIKit, StrataConfig = StrataConfig,
	text = text, corner = corner, stroked = stroked,
	pressable = pressable, popIn = popIn, popOut = popOut, scaler = scaler,
	panel = panel, closePanel = closePanel, equipRequest = equipRequest,
	dress = dress,
	INK = INK, DIM = DIM, ORE = ORE, CRIT = CRIT, GREEN = GREEN,
	SIGNAL = SIGNAL, PANEL = PANEL, SLOT = SLOT,
})

local kit        = Kit.frame
local kitScale   = Kit.scale
local openKit    = Kit.open
local closeKit   = Kit.close
local refreshKit = Kit.refresh



-- ── Depot ────────────────────────────────────────────────────────────────────
-- What the Depot's ring opens: everything in the pack, what each lot fetches,
-- and one button to sell the lot.


local function buildSell()
	clearBody()
	panelTitle.Text = "DEPOT"
	setPanelAccent(StrataConfig.Zones.sell.accent)

	-- Sorting is the one place a chip row earns its keep. With a pack of
	-- sixteen kinds of rock and a capacity you are always up against, "what do
	-- I dump first" is a real question, and value-per-unit answers it.
	screen.Show({
		{ id = "worth", text = "Worth" },
		{ id = "each",  text = "Each" },
		{ id = "count", text = "Count" },
		{ id = "name",  text = "Name" },
	}, StrataConfig.Zones.sell.accent, buildSell)

	-- Gathered before it is drawn, because a sort needs the whole list and the
	-- old version rendered straight out of the config in config order
	local rows, total = {}, 0

	for _, ore in ipairs(StrataConfig.Ores) do
		local count = S.inventory[ore.id]
		if count and count > 0 then
			table.insert(rows, { material = ore, count = count, each = ore.value,
				worth = count * ore.value, note = "" })
			total += count * ore.value
		end
	end

	for _, stratum in ipairs(StrataConfig.Strata) do
		local rock  = StrataConfig.Rocks[stratum.id]
		local count = rock and S.inventory[rock.id]
		if count and count > 0 then
			table.insert(rows, { material = rock, count = count,
				each = stratum.valuePerDig, worth = count * stratum.valuePerDig,
				note = "no pack slot" })
			total += count * stratum.valuePerDig
		end
	end

	local by = screen.chips.Active()
	table.sort(rows, function(a, b)
		if by == "each"  then return a.each > b.each end
		if by == "count" then return a.count > b.count end
		if by == "name"  then return a.material.name < b.material.name end
		return a.worth > b.worth
	end)

	for order, row in ipairs(rows) do
		card(order, {
			title      = row.material.name,
			count      = "x" .. row.count,
			perk       = row.note ~= "" and row.note
				or ("%d each"):format(row.each),
			cost       = "+" .. commas(row.worth),
			costColour = ORE,
			accent     = row.material.color,
			ore        = row.material,
			glyph      = "◆",
			enabled    = true,
			action     = "SELL ALL",
			onClick    = function() sellRequest:FireServer() end,
		})
	end

	panelFoot.Text = "your credits: " .. commas(S.credits or 0)

	if total <= 0 then
		screen.Reset()
		local empty = text(panelBody, "Nothing to sell yet.",
			UDim2.new(1, -8, 0, 60), DIM, 14, StrataConfig.UI.Body, Enum.TextXAlignment.Center)
		empty.TextWrapped = true
		empty.LayoutOrder = 1
		return
	end

	-- Worth nothing means the button refuses rather than firing a sale of zero.
	-- The pack can hold things the depot will not buy, so "has items" and "is
	-- worth selling" are different questions and only the second one matters
	-- here.
	showAction("SELL ALL    +" .. commas(total), Color3.fromRGB(214, 164, 64), function()
		sellRequest:FireServer()
	end, total > 0)
end

local builders = {
	shop    = buildShop,
	lift    = buildLift,
	pickaxe = buildPicks,
	runs    = buildRuns,
	sell    = buildSell,
}

local function openTabNamed(name)
	if openTab == name then closePanel(); return end
	if kit.Visible then closeKit() end   -- the kit screen is its own thing
	openTab = name

	-- The board is pushed when it turns over, but a fresh one on open costs
	-- nothing and means you are never looking at something stale
	if name == "runs" then contractRequest:FireServer() end
	-- Builders are called through pcall. A builder that throws used to leave the
	-- panel empty or unopened with nothing said about it, which is impossible to
	-- diagnose from the outside — now the panel opens and tells you what broke.
	local built, why = pcall(builders[name])
	if not built then
		warn("[SurfaceUI] " .. name .. " panel failed: " .. tostring(why))
		clearBody()
		panelTitle.Text = string.upper(name)
		local oops = text(panelBody, "This panel hit an error:\n\n" .. tostring(why),
			UDim2.new(1, -8, 0, 120), CRIT, 12, StrataConfig.UI.Number)
		oops.TextWrapped    = true
		oops.TextYAlignment = Enum.TextYAlignment.Top
		oops.LayoutOrder    = 1
	end
	if panel.Visible then
		panel.Visible = true      -- already up: just swap contents, no re-pop
	else
		popIn(panel, panelScale)
	end
end

local function refreshOpen()
	if openTab and builders[openTab] then
		local ok, why = pcall(builders[openTab])
		if not ok then warn("[SurfaceUI] refresh of " .. openTab .. " failed: " .. tostring(why)) end
	end
end

-- ── Bar buttons ──────────────────────────────────────────────────────────────

barButton(1, "🛒", "SHOP",  SIGNAL, function() openTabNamed("shop") end)
barButton(2, "🧰", "KIT",   ORE,    function() openKit("all", "body") end)

barButton(3, "T", "PICKS", Color3.fromRGB(196, 168, 178), function()
	openTabNamed("pickaxe")
end)
barButton(4, "🛗", "LIFT",  GREEN,  function() openTabNamed("lift") end)
barButton(5, "📋", "RUNS",  ORE,    function() openTabNamed("runs") end)
barButton(6, "⬆",  "CAMP",  INK,    function() surfaceCall:FireServer() end)

-- ── Which row is lit ─────────────────────────────────────────────────────────
-- Driven off what is actually on screen rather than off what was last clicked,
-- so closing with Escape, or a panel closing itself, puts the light out too.
-- CAMP is in the list and never lights, which is correct: it is not a screen,
-- it is a button that sends you somewhere.
do
	local SCREEN_ROW = {
		shop    = "SHOP",
		pickaxe = "PICKS",
		lift    = "LIFT",
		runs    = "RUNS",
	}

	local function syncNav()
		local lit = nil
		if kit.Visible then
			lit = "KIT"
		elseif panel.Visible and openTab then
			lit = SCREEN_ROW[openTab]
		end
		for label, setActive in pairs(NAV_ROWS) do
			setActive(label == lit)
		end
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(syncNav)
	kit:GetPropertyChangedSignal("Visible"):Connect(syncNav)

	-- openTab changes without Visible changing when one screen swaps straight
	-- to another, and there is no signal for a plain local.
	task.spawn(function()
		local was = nil
		while task.wait(0.15) do
			if openTab ~= was then
				was = openTab
				syncNav()
			end
		end
	end)
end

-- Escape closes whatever is open
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.Escape then return end
	if kit.Visible then
		closeKit()
	elseif panel.Visible then
		closePanel()
	end
end)

-- ── Hazard banner ────────────────────────────────────────────────────────────

local hazardBanner = Instance.new("TextLabel")
hazardBanner.Size                   = UDim2.new(0, 470, 0, 36)
hazardBanner.AnchorPoint            = Vector2.new(0.5, 0)
hazardBanner.Position               = UDim2.new(0.5, 0, 0, 106)
hazardBanner.BackgroundColor3       = Color3.fromRGB(62, 20, 16)
hazardBanner.BackgroundTransparency = 0.15
hazardBanner.BorderSizePixel        = 0
hazardBanner.Text                   = ""
hazardBanner.TextColor3             = CRIT
hazardBanner.TextSize               = 15
	hazardBanner.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, hazardBanner.TextSize)
hazardBanner.Visible                = false
hazardBanner.Parent                 = gui
corner(hazardBanner, 10)
stroked(hazardBanner, CRIT, 2, 0.4)

local pulse = 0
game:GetService("RunService").RenderStepped:Connect(function(dt)
	if not hazardBanner.Visible then return end
	pulse += dt * 4
	hazardBanner.BackgroundTransparency = 0.15 + math.sin(pulse) * 0.12
end)

hazardState.OnClientEvent:Connect(function(hazard)
	hazardBanner.Text    = hazard and hazard.warning or ""
	hazardBanner.Visible = hazard ~= nil
end)

-- ── Gate approach warning ────────────────────────────────────────────────────

local approach = text(gui, "", UDim2.new(0, 470, 0, 22), ORE, 13,
	StrataConfig.UI.Body, Enum.TextXAlignment.Center)
approach.AnchorPoint = Vector2.new(0.5, 0)
approach.Position    = UDim2.new(0.5, 0, 0, 80)
approach.Visible     = false

local APPROACH_MARGIN = 55

task.spawn(function()
	while task.wait(0.3) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			approach.Visible = false
		else
			local y, upcoming = root.Position.Y, nil
			for _, gate in ipairs(GearConfig.DepthGates) do
				if y > gate.belowY and y - gate.belowY <= APPROACH_MARGIN then
					upcoming = gate
				end
			end

			if upcoming then
				local have = (S.resistances[upcoming.resistance] or 0) >= upcoming.level
				approach.Text = have
					and ("%s BOUNDARY %dm BELOW — protected"):format(upcoming.label, math.floor(y - upcoming.belowY))
					or ("%s BOUNDARY %dm BELOW — unprotected"):format(upcoming.label, math.floor(y - upcoming.belowY))
				approach.TextColor3 = have and SIGNAL or ORE
				approach.Visible = true
			else
				approach.Visible = false
			end
		end
	end
end)


-- ── Zone rings ───────────────────────────────────────────────────────────────
-- The rings breathe, slowly. A static circle on a wooden floor gets read as
-- part of the floor; one that moves is obviously something to stand on. Done on
-- the client because it is a look, not a fact — the server has no business
-- replicating a sine wave.

task.spawn(function()
	local pads = {}
	for _, name in ipairs({ "SellPad", "CraftPad", "LiftPad", "PickPad", "RunsPad" }) do
		local pad = workspace:WaitForChild(name, 20)
		local pane = pad and pad:FindFirstChild("RingGui")
		if pane then
			local fill = pane:FindFirstChild("Fill")
			local halo = pane:FindFirstChild("Halo")
			table.insert(pads, {
				ring = fill and fill:FindFirstChildOfClass("UIStroke"),
				halo = halo and halo:FindFirstChildOfClass("UIStroke"),
				frame = halo,
				phase = #pads * 0.7,
			})
		end
	end

	while true do
		local t = os.clock()
		for _, pad in ipairs(pads) do
			local wave = (math.sin(t * 1.6 + pad.phase) + 1) / 2
			if pad.ring then pad.ring.Transparency = 0.04 + wave * 0.16 end
			if pad.halo then pad.halo.Transparency = 0.42 + wave * 0.34 end
			if pad.frame then
				local s = 0.95 + wave * 0.05
				pad.frame.Size = UDim2.fromScale(s, s)
			end
		end
		task.wait(0.05)
	end
end)

-- ── Zone hints ───────────────────────────────────────────────────────────────
-- Walking onto a pad still opens its panel, but it is now a shortcut rather
-- than the only way in.

-- Stepping into a station's ring opens its panel, and stepping back out closes
-- it again, unless you've switched to something else from the buttons since.
local ZONE_TABS = {
	sell = "sell", craft = "shop", lift = "lift", pickaxe = "pickaxe", runs = "runs",
}
local zoneTab   = nil

zoneChanged.OnClientEvent:Connect(function(zone)
	local tab = zone and ZONE_TABS[zone]
	if tab then
		zoneTab = tab
		openTab = nil   -- force it open; openTabNamed toggles an already-open tab shut
		openTabNamed(tab)
	elseif zoneTab then
		if openTab == zoneTab then closePanel() end
		zoneTab = nil
	end
end)

-- ── Server responses ─────────────────────────────────────────────────────────

stateChanged.OnClientEvent:Connect(function(s)
	-- Filled in place rather than reassigned. `S = s` swapped the table for a
	-- new one, so anything that had captured the old reference — every screen
	-- moved out into its own module — would quietly keep reading a snapshot
	-- from whenever it was built. Same contents, one identity, forever.
	for k in pairs(S) do S[k] = nil end
	for k, v in pairs(s) do S[k] = v end

	S.inventory   = s.inventory or {}
	S.owned       = s.owned or {}
	S.equipped    = s.equipped or {}
	S.resistances = s.resistances or {}

	panelCredits.Text = tostring(S.credits)
	refreshOpen()
	if kit.Visible then refreshKit() end
	if refreshChart then refreshChart() end

	-- Lamp follows whatever gear grants it
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local light = root:FindFirstChild("StrataLamp")
		if (S.lightRange or 0) > 0 then
			if not light then
				light = Instance.new("PointLight")
				light.Name   = "StrataLamp"
				light.Color  = Color3.fromRGB(255, 226, 178)
				light.Parent = root
			end
			light.Range      = S.lightRange
			light.Brightness = 1.8
		elseif light then
			light:Destroy()
		end
	end
end)

-- ── Toasts ───────────────────────────────────────────────────────────────────

local function toast(message, colour)
	local card = Instance.new("Frame")
	card.Size                   = UDim2.new(0, 340, 0, 42)
	card.AnchorPoint            = Vector2.new(0.5, 0)
	card.Position               = UDim2.new(0.5, 0, 0, 96)
	card.BackgroundColor3       = PANEL
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel        = 0
	card.Parent                 = gui
	corner(card, 10)
	local edge = stroked(card, colour, 2, 0.2)

	local label = text(card, message, UDim2.new(1, -20, 1, 0), colour, 16,
		StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	label.Position = UDim2.new(0, 10, 0, 0)

	TweenService:Create(card, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 62),
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(label, TweenInfo.new(1.8), { TextTransparency = 1 }):Play()
	TweenService:Create(edge, TweenInfo.new(1.8), { Transparency = 1 }):Play()
	task.delay(1.9, function() card:Destroy() end)
end

soldEvent.OnClientEvent:Connect(function(earned)
	toast("SOLD  +" .. earned .. " credits", ORE)
end)

craftResult.OnClientEvent:Connect(function(ok, detail)
	toast(ok and ("PURCHASED  " .. detail) or string.upper(tostring(detail)), ok and SIGNAL or CRIT)
end)
-- Wrapped in a function on purpose. This file sits right on Luau's ceiling of
-- 200 locals per function, and the chart alone declares thirty-two of them.
-- Inside a function body those registers belong to that function rather than to
-- this one. A `do` block would NOT help: a block's locals still coexist with
-- everything outside it, so the peak is unchanged. The one name anyone outside
-- needs — refreshChart — is declared at the top of the file and assigned here.
-- ── Depth chart ──────────────────────────────────────────────────────────────
-- Lives in its own module now. It declared thirty-odd locals and this file sits
-- on Luau's ceiling of 200 per function, so those registers were the most
-- expensive in the project. Over there they are free; here it costs one name.
--
-- WaitForChild, not a dot. A LocalScript in PlayerScripts can start running
-- before its siblings have finished replicating, so indexing the folder
-- directly threw "ui is not a valid member of PlayerScripts" — and because that
-- error killed the script at this line, every panel defined below it never got
-- built. The camp simply did not open. Every other require in this project
-- already waits; this one did not.
refreshChart = require(
	script.Parent:WaitForChild("ui"):WaitForChild("DepthChart"))({
	gui = gui, state = S, player = player,
	text = text, corner = corner,
	StrataConfig = StrataConfig,
	panel = panel, kit = kit,
	INK = INK, DIM = DIM, ORE = ORE,
	CRIT = CRIT, GREEN = GREEN,
	OUTLINE = OUTLINE, SIGNAL = SIGNAL,
})

refreshChart()

-- ── Fitting the screen ───────────────────────────────────────────────────────
-- None of this was responsive, which is the single cause behind three separate
-- playtest notes. The shop, contracts and kit screens are 900 wide and sit dead
-- centre; the action bar sits at x=16 and is the only way to switch screens. So
-- on any viewport narrower than about 1310 the panel simply covered the
-- navigation, and the depth chart poked out from behind its other edge. On a
-- desktop monitor you never see it. In Studio on a laptop, where the play
-- viewport is a fraction of the screen, you cannot miss it.
--
-- The fix is a band rather than a centre: the screens live in the space to the
-- right of the action bar, centred in that space, scaled down to fit it instead
-- of spilling over it. The bar is never covered and never moves, because it is
-- navigation and navigation has to stay put.
;(function()

local MARGIN    = 16
-- First pixel clear of the action bar. Off the measured column, not a fixed
-- Hud.Width — that field is gone, and reading it here returned nil into an
-- addition, which is a hard error on the line that positions every screen.
local BAND_L    = HUD.Left + STACK.Width + MARGIN
local MIN_SCALE = 0.55                            -- below this, text stops being text

local function fit(frame, scale, w, h)
	local vp = gui.AbsoluteSize
	if vp.X < 2 or vp.Y < 2 then return end        -- not laid out yet

	local left, right = BAND_L, vp.X - MARGIN

	-- On a viewport too narrow to have a band at all, take the whole width back
	-- and let the scale deal with it. A readable screen that slightly overlaps
	-- the bar beats an unreadable one that clears it.
	if right - left < w * MIN_SCALE then left = MARGIN end

	local s = math.min(1, (right - left) / w, (vp.Y - MARGIN * 2) / h)
	s = math.max(MIN_SCALE, s)

	-- popIn and popOut read this so they tween to the fitted size, not to 1
	frame:SetAttribute("FitScale", s)
	scale.Scale    = s
	frame.Position = UDim2.new(0, (left + right) * 0.5, 0.5, 0)
end

local function fitAll()
	fit(panel, panelScale, 900, 546)
	fit(kit,   kitScale,   Kit.width, Kit.height)
end

fitAll()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitAll)

end)()

-- Roblox's own player list lives in the top-right corner and draws above every
-- ScreenGui, so no amount of moving our own UI gets out from under it. Nothing
-- here needs a player list — a run is yours alone — so it goes.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

print("[SurfaceUI] ready")
