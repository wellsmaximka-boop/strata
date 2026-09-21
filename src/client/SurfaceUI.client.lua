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


local function corner(inst, radius)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(0, radius or 8)
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
	l.Font                   = font or StrataConfig.UI.Body
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

	local headerFade = Instance.new("UIGradient", header)
	headerFade.Rotation = 90
	headerFade.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accent),
		ColorSequenceKeypoint.new(1, accent:Lerp(OUTLINE, 0.45)),
	})

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

	gloss(header, 26, 22).Position = UDim2.new(0, 40, -0.5, 0)
	gloss(header, 12, 22).Position = UDim2.new(0, 76, -0.5, 0)

	local title = text(header, titleText, UDim2.new(1, -40, 1, 0),
		Color3.fromRGB(255, 255, 255), 20, StrataConfig.UI.Head)
	title.Position = UDim2.new(0, 52, 0, 0)   -- clear of the corner bracket
	title.ZIndex   = 3
	local titleShade = Instance.new("UIStroke", title)
	titleShade.Color     = OUTLINE
	titleShade.Thickness = 2
	titleShade.Transparency = 0.35

	-- Round close button, overhanging the corner like the references
	local close = Instance.new("TextButton")
	close.Size             = UDim2.new(0, 40, 0, 40)
	close.AnchorPoint      = Vector2.new(0.5, 0.5)
	close.Position         = UDim2.new(1, -6, 0, 6)
	close.BackgroundColor3 = CLOSE_R
	close.BorderSizePixel  = 0
	close.Text             = "X"
	close.TextColor3       = Color3.fromRGB(255, 255, 255)
	close.TextSize         = 20
	close.Font             = StrataConfig.UI.Head
	close.AutoButtonColor  = false
	close.ZIndex           = 5
	close.Parent           = frame
	corner(close, 20)

	local closeEdge = Instance.new("UIStroke", close)
	closeEdge.Color     = OUTLINE
	closeEdge.Thickness = 3

	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.1),
			{ BackgroundColor3 = Color3.fromRGB(232, 96, 80) }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.1), { BackgroundColor3 = CLOSE_R }):Play()
	end)

	-- Recolours the header. An explicit function rather than a metatable hook,
	-- which was clever and fragile in equal measure.
	local function setAccent(colour)
		setPlate(colour)
		headerFade.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colour),
			ColorSequenceKeypoint.new(1, colour:Lerp(OUTLINE, 0.45)),
		})
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

local function popIn(frame, scale)
	scale.Scale   = 0.82
	frame.Visible = true
	TweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
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

local function popOut(frame, scale, onDone)
	local t = TweenService:Create(scale, POP_OUT, { Scale = 0.86 })
	t:Play()
	t.Completed:Connect(function()
		frame.Visible = false
		scale.Scale   = 1
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
local BTN = 58
local GAP = 8

local bar = Instance.new("Frame")
bar.Name                   = "ActionBar"
bar.Size                   = UDim2.new(0, BTN * 3 + GAP * 2, 0, BTN * 2 + GAP)
bar.Position               = UDim2.new(0, HUD.Left, 0.5, HUD.Grid.Y)
bar.BackgroundTransparency = 1
bar.Parent                 = gui

local barLayout = Instance.new("UIGridLayout", bar)
barLayout.CellSize    = UDim2.new(0, BTN, 0, BTN)
barLayout.CellPadding = UDim2.new(0, GAP, 0, GAP)
barLayout.SortOrder   = Enum.SortOrder.LayoutOrder
barLayout.FillDirectionMaxCells = 3

-- Paste Creator Store icon asset ids here and they replace the emoji glyphs
-- automatically — nothing else has to change. Free UI packs work fine; the ids
-- look like "rbxassetid://1234567890".
local ICONS = {
	SHOP  = "rbxassetid://13429538917",
	KIT   = "rbxassetid://16181381646",
	LIFT  = "rbxassetid://12338897538",
	PICKS = "draw",   -- no asset for this one; drawn from frames below
	CAMP  = "rbxassetid://13060262529",
}

-- A pickaxe built from two rotated frames. Not as crisp as real icon art, but
-- it costs no asset and sits in the same visual language as everything else.
local function drawPickaxe(parent)
	local holder = Instance.new("Frame")
	holder.Size                   = UDim2.new(0, 28, 0, 28)
	holder.Position               = UDim2.new(0.5, -14, 0, 10)
	holder.BackgroundTransparency = 1
	holder.ZIndex                 = 4
	holder.Parent                 = parent

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

-- A button built the way a designed one is built: a shadow beneath, a gradient
-- body, a highlight bevel across the top, a coloured rim, and a press that
-- actually moves. No image required, though one drops straight in.
local function barButton(order, icon, label, accent, onClick)
	-- The grid layout owns position and size, so the holder must not set either
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

	local FILL_TOP, FILL_BOTTOM = Color3.fromRGB(56, 66, 80), Color3.fromRGB(24, 29, 37)

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
	bevel.Size                   = UDim2.new(1, -10, 0, 22)
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

	-- Icon: an uploaded image when one is configured, the glyph otherwise
	local iconId = ICONS[label]
	local art
	if iconId == "draw" then
		art = drawPickaxe(b)
	elseif iconId and iconId ~= "" then
		art = Instance.new("ImageLabel")
		art.Image                  = iconId
		art.ScaleType              = Enum.ScaleType.Fit
		art.BackgroundTransparency = 1
		art.Size                   = UDim2.new(0, 27, 0, 27)
		art.Position               = UDim2.new(0.5, -13.5, 0, 7)
		art.ZIndex                 = 4
		art.Parent                 = b
	else
		art = text(b, icon, UDim2.new(1, 0, 0, 27), INK, 21,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		art.Position = UDim2.new(0, 0, 0, 7)
		art.ZIndex   = 4
	end

	local name = text(b, label, UDim2.new(1, 0, 0, 12), DIM, 10,
		StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	name.Position = UDim2.new(0, 0, 1, -17)
	name.ZIndex   = 4

	local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Hover brightens rather than grows: resizing a cell inside a grid layout
	-- would shove its neighbours around.
	-- Hover lifts the gradient rather than the background, since the background
	-- has to stay white for the gradient to read true.
	local WHITE = Color3.new(1, 1, 1)
	b.MouseEnter:Connect(function()
		TweenService:Create(rim, QUICK, { Transparency = 0, Thickness = 2.5 }):Play()
		setFill(FILL_TOP:Lerp(WHITE, 0.16), FILL_BOTTOM:Lerp(WHITE, 0.16))
		name.TextColor3 = accent
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(rim, QUICK, { Transparency = 0.3, Thickness = 2 }):Play()
		setFill(FILL_TOP, FILL_BOTTOM)
		name.TextColor3 = DIM
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

local panelCredits = text(panelHeader, "0", UDim2.new(0, 140, 1, 0),
	Color3.fromRGB(255, 255, 255), 16, StrataConfig.UI.Head, Enum.TextXAlignment.Right)
panelCredits.Position    = UDim2.new(1, -54, 0, 0)
panelCredits.AnchorPoint = Vector2.new(1, 0)
panelCredits.ZIndex      = 3

-- A drawn gold coin instead of the icon asset, which rendered almost black and
-- disappeared against the dark end of the header gradient.
local panelCash = Instance.new("Frame")
panelCash.Size             = UDim2.new(0, 20, 0, 20)
panelCash.AnchorPoint      = Vector2.new(0, 0.5)
panelCash.Position         = UDim2.new(1, -50, 0.5, 0)
panelCash.BackgroundColor3 = Color3.fromRGB(255, 204, 92)
panelCash.BorderSizePixel  = 0
panelCash.ZIndex           = 3
panelCash.Parent           = panelHeader
corner(panelCash, 10)

local panelCashRim = Instance.new("UIStroke", panelCash)
panelCashRim.Color     = Color3.fromRGB(150, 102, 28)
panelCashRim.Thickness = 2

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
bodyLayout.CellPadding = UDim2.new(0, 12, 0, 12)

bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder

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
panelAction.Font             = StrataConfig.UI.Head
panelAction.AutoButtonColor  = false
panelAction.Visible          = false
panelAction.Parent           = panel
corner(panelAction, 12)

local actionEdge = Instance.new("UIStroke", panelAction)
actionEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
actionEdge.Color           = Color3.fromRGB(12, 14, 18)
actionEdge.Thickness       = 3

local actionHandler = nil
panelAction.Activated:Connect(function()
	if actionHandler then actionHandler() end
end)

local function showAction(label, colour, onClick)
	panelAction.Text             = label
	panelAction.BackgroundColor3 = colour
	panelAction.Visible          = true
	actionHandler                = onClick
	panelBody.Size               = UDim2.new(1, -36, 1, -178)
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

	biomePreview(card, c.layerId, 132, 88, 12, 12, not c.locked)

	local tx = 156
	local name = text(card, c.layerName, UDim2.new(1, -tx - 130, 0, 22),
		can and INK or DIM, 17, StrataConfig.UI.Head)
	name.Position = UDim2.new(0, tx, 0, 14)

	local line = text(card, c.locked and "you have never been here" or c.line,
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
-- One screen for everything you carry and everything you wear. Your body and
-- its slots on the left, every item you own as a grid of tiles on the right,
-- categories along the bottom.
--
-- Wide rather than tall on purpose: a tall list makes you scroll past ore to
-- reach armour, and the two belong side by side.

local KIT_W, KIT_H = 900, 486

local kit = Instance.new("Frame")
kit.Name                   = "KitScreen"
kit.Size                   = UDim2.new(0, KIT_W, 0, KIT_H)
kit.AnchorPoint            = Vector2.new(0.5, 0.5)
kit.Position               = UDim2.new(0.5, 0, 0.5, 0)
kit.BackgroundColor3       = PANEL
kit.BackgroundTransparency = 0.04
kit.BorderSizePixel        = 0
kit.Visible                = false
kit.Parent                 = gui

-- ── Backdrop ─────────────────────────────────────────────────────────────────
-- Rock behind the panel rather than flat colour: a wash of light from the top
-- left and faint strata lines running across it.

local function backdrop(parent)
	local back = Instance.new("Frame")
	back.Name             = "Backdrop"
	back.Size             = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(17, 21, 27)
	back.BorderSizePixel  = 0
	back.ZIndex           = 0
	back.ClipsDescendants = true
	back.Parent           = parent
	corner(back, 16)

	local wash = Instance.new("Frame")
	wash.Size             = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = Color3.fromRGB(52, 64, 80)
	wash.BorderSizePixel  = 0
	wash.ZIndex           = 0
	wash.Parent           = back

	local fade = Instance.new("UIGradient", wash)
	fade.Rotation     = 122
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.55, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})

	for i = 0, 19 do
		local seam = Instance.new("Frame")
		seam.Size                   = UDim2.new(0, 2, 2, 0)
		seam.Position               = UDim2.new(0, i * 54 - 140, -0.5, 0)
		seam.Rotation               = 38
		seam.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
		seam.BackgroundTransparency = 0.965
		seam.BorderSizePixel        = 0
		seam.ZIndex                 = 0
		seam.Parent                 = back
	end

	return back
end

backdrop(kit)

local _, kitClose = dress(kit, "KIT", ORE)
;(function()
	local K = require(ReplicatedStorage:WaitForChild("UIKit"))
	K.Ribbon(kit, "KIT", ORE)
end)()
local kitScale = scaler(kit)

-- ── Slabs ────────────────────────────────────────────────────────────────────

local function slab(x, y, w, h, title, accent)
	local s = Instance.new("Frame")
	s.Size                   = UDim2.new(0, w, 0, h)
	s.Position               = UDim2.new(0, x, 0, y)
	s.BackgroundColor3       = Color3.fromRGB(25, 31, 39)
	s.BackgroundTransparency = 0.12
	s.BorderSizePixel        = 0
	s.Parent                 = kit
	corner(s, 12)
	stroked(s, Color3.fromRGB(57, 65, 78), 1.5, 0.35)

	if title then
		local head = text(s, title, UDim2.new(1, -28, 0, 16), accent or DIM, 11, StrataConfig.UI.Head)
		head.Position = UDim2.new(0, 14, 0, 12)
	end
	return s
end

local bodySlab = slab(16, 58, 240, 368)   -- titled by its own tabs, below
local gridSlab = slab(272, 58, 612, 368, "EVERYTHING YOU HAVE", ORE)
local capSlab  = slab(16, 436, 240, 34)

local kitCount = text(gridSlab, "", UDim2.new(0, 160, 0, 16), ORE, 11,
	StrataConfig.UI.Head, Enum.TextXAlignment.Right)
kitCount.Position    = UDim2.new(1, -14, 0, 12)
kitCount.AnchorPoint = Vector2.new(1, 0)

-- ── Capacity ─────────────────────────────────────────────────────────────────

local capLabel = text(capSlab, "PACK", UDim2.new(0, 80, 0, 12), DIM, 10, StrataConfig.UI.Head)
capLabel.Position = UDim2.new(0, 10, 0, 5)

local capValue = text(capSlab, "0 / 0", UDim2.new(0, 120, 0, 12), INK, 10,
	StrataConfig.UI.Head, Enum.TextXAlignment.Right)
capValue.Position    = UDim2.new(1, -10, 0, 5)
capValue.AnchorPoint = Vector2.new(1, 0)

local capTrack = Instance.new("Frame")
capTrack.Size             = UDim2.new(1, -20, 0, 7)
capTrack.Position         = UDim2.new(0, 10, 0, 21)
capTrack.BackgroundColor3 = Color3.fromRGB(14, 18, 24)
capTrack.BorderSizePixel  = 0
capTrack.Parent           = capSlab
corner(capTrack, 4)

local capFill = Instance.new("Frame")
capFill.Size             = UDim2.new(0, 0, 1, 0)
capFill.BackgroundColor3 = ORE
capFill.BorderSizePixel  = 0
capFill.Parent           = capTrack
corner(capFill, 4)


-- ── What the left panel is showing ───────────────────────────────────────────
-- Your body, or your backpack. Two tabs rather than two screens, because the
-- pack and the gear are the same inventory seen from different sides.

local refreshKit              -- forward declaration: the tabs and slots call it
local previewMode = "body"
local modeTabs    = {}
local rebuildPreview          -- forward declaration, set below

for i, mode in ipairs({ { id = "body", name = "BODY" }, { id = "pack", name = "BACKPACK" } }) do
	local b = Instance.new("TextButton")
	b.Size             = UDim2.new(0, 104, 0, 22)
	b.Position         = UDim2.new(0, 16 + (i - 1) * 112, 0, 9)
	b.BackgroundColor3 = Color3.fromRGB(27, 33, 42)
	b.BorderSizePixel  = 0
	b.Text             = mode.name
	b.TextColor3       = DIM
	b.TextSize         = 10
	b.Font             = StrataConfig.UI.Head
	b.AutoButtonColor  = false
	b.Parent           = bodySlab
	corner(b, 7)
	local edge = stroked(b, Color3.fromRGB(57, 65, 78), 1.5, 0.35)

	modeTabs[mode.id] = { button = b, edge = edge }

	pressable(b, Color3.fromRGB(27, 33, 42), Color3.fromRGB(38, 46, 58))
	b.Activated:Connect(function()
		if previewMode == mode.id then return end
		previewMode = mode.id
		rebuildPreview()
		refreshKit()
	end)
end

-- ── Character preview ────────────────────────────────────────────────────────
-- A clone of the actual player, rotating. Characters are Archivable = false by
-- default, so cloning one needs the flag flipped for the duration of the copy.

local viewport = Instance.new("ViewportFrame")
viewport.Size             = UDim2.new(0, 208, 0, 176)
viewport.Position         = UDim2.new(0, 16, 0, 40)
viewport.BackgroundColor3 = Color3.fromRGB(16, 20, 26)
viewport.BorderSizePixel  = 0
viewport.Ambient          = Color3.fromRGB(160, 165, 175)
viewport.LightColor       = Color3.fromRGB(255, 250, 240)
viewport.Parent           = bodySlab
corner(viewport, 10)
stroked(viewport, Color3.fromRGB(57, 65, 78), 1.5, 0.4)

local world = Instance.new("WorldModel")
world.Parent = viewport

local vpCamera = Instance.new("Camera")
vpCamera.FieldOfView   = 40
vpCamera.Parent        = viewport
viewport.CurrentCamera = vpCamera

local previewModel = nil

function rebuildPreview()
	if previewModel then previewModel:Destroy(); previewModel = nil end

	-- The backpack, with whatever its mast is carrying
	if previewMode == "pack" then
		local model = ItemModels.BackpackDisplay(
			(S.owned and S.owned.PackI) and 2 or 1, S.lightLevel or 1)
		model:PivotTo(CFrame.new(0, 0, 0))
		model.Parent = world
		previewModel = model
		vpCamera.CFrame = CFrame.new(Vector3.new(0, 0.9, 5.6), Vector3.new(0, 0.1, 0))
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = false
	if not ok or not clone then return end

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end

	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = world
	previewModel = clone

	local _, size = clone:GetBoundingBox()
	local dist = math.max(size.Y * 1.65, 8)   -- a little headroom in a shorter frame
	vpCamera.CFrame = CFrame.new(Vector3.new(0, size.Y * 0.1, dist), Vector3.new(0, 0, 0))
end

local spin = 0
game:GetService("RunService").RenderStepped:Connect(function(dt)
	if not kit.Visible or not previewModel then return end
	spin += dt * 26
	previewModel:PivotTo(CFrame.Angles(0, math.rad(spin), 0))
end)

-- ── Equip slots ──────────────────────────────────────────────────────────────
-- Under the body, one per armour slot. Tapping a filled slot takes the piece
-- off; tapping an empty one jumps the grid to what would fit it.

local selectedCat  = "all"
local selectedKey  = nil
local slotButtons  = {}

-- Each slot is a picture of what is in it, with the piece named underneath.
-- An empty one falls back to the slot glyph and the slot name, so the row still
-- reads as three places for three things.
for i, slot in ipairs(GearConfig.ArmorSlots) do
	local b = Instance.new("TextButton")
	b.Name             = slot.id
	b.Size             = UDim2.new(0, 68, 0, 86)
	b.Position         = UDim2.new(0, 16 + (i - 1) * 70, 0, 224)
	b.BackgroundColor3 = SLOT
	b.BorderSizePixel  = 0
	b.Text             = ""
	b.AutoButtonColor  = false
	b.ClipsDescendants = true
	b.Parent           = bodySlab
	corner(b, 10)
	local edge = stroked(b, Color3.fromRGB(70, 80, 95), 2, 0.25)

	-- Where the picture goes. Kept as its own frame so the icon can be swapped
	-- without disturbing anything else on the button.
	local art = Instance.new("Frame")
	art.Size             = UDim2.new(0, 52, 0, 52)
	art.Position         = UDim2.new(0, 8, 0, 6)
	art.BackgroundColor3 = Color3.fromRGB(16, 20, 26)
	art.BorderSizePixel  = 0
	art.Parent           = b
	corner(art, 8)

	local glyph = text(art, slot.glyph, UDim2.new(1, 0, 1, 0), DIM, 20,
		StrataConfig.UI.Head, Enum.TextXAlignment.Center)

	local label = text(b, string.upper(slot.name), UDim2.new(1, -6, 0, 24),
		DIM, 9, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
	label.Position    = UDim2.new(0, 3, 0, 60)
	label.TextWrapped = true

	slotButtons[slot.id] = {
		button = b, edge = edge, art = art, glyph = glyph, label = label,
		shownId = nil, icon = nil,
	}

	pressable(b)
	b.Activated:Connect(function()
		if S.equipped[slot.id] then
			equipRequest:FireServer(nil, slot.id)
		else
			selectedCat = "armour"
			previewMode = "body"
			refreshKit()
		end
	end)
end


-- ── What the set is doing for you ────────────────────────────────────────────
-- The one number that gates a biome, and how close each set is to being whole.
-- Without it the screen tells you what you own but not what it buys you.

local gateLine = text(bodySlab, "", UDim2.new(1, -28, 0, 14), GREEN, 11, StrataConfig.UI.Head)
gateLine.Position = UDim2.new(0, 16, 0, 316)

local setLine = text(bodySlab, "", UDim2.new(1, -28, 0, 32), DIM, 10, StrataConfig.UI.Body)
setLine.Position      = UDim2.new(0, 16, 0, 332)
setLine.TextWrapped   = true
setLine.TextYAlignment = Enum.TextYAlignment.Top


-- ── The mast, in words ───────────────────────────────────────────────────────
-- Shown where the armour slots sit when the panel is turned round to the pack.

local lightLine = text(bodySlab, "", UDim2.new(1, -28, 0, 16), ORE, 12, StrataConfig.UI.Head)
lightLine.Position = UDim2.new(0, 16, 0, 228)

local lightNote = text(bodySlab, "", UDim2.new(1, -28, 0, 64), DIM, 10, StrataConfig.UI.Body)
lightNote.Position       = UDim2.new(0, 16, 0, 250)
lightNote.TextWrapped    = true
lightNote.TextYAlignment = Enum.TextYAlignment.Top

-- ── The grid ─────────────────────────────────────────────────────────────────

local TIER_EDGE = {
	Color3.fromRGB(87, 97, 111),
	Color3.fromRGB(111, 163, 184),
	Color3.fromRGB(142, 134, 216),
	Color3.fromRGB(217, 154, 78),
	Color3.fromRGB(224, 112, 92),
}

local function tierColour(tier)
	return TIER_EDGE[math.clamp(tier or 1, 1, #TIER_EDGE)]
end

local gridList = Instance.new("ScrollingFrame")
gridList.Size                   = UDim2.new(1, -26, 0, 250)
gridList.Position               = UDim2.new(0, 13, 0, 34)
gridList.BackgroundTransparency = 1
gridList.BorderSizePixel        = 0
gridList.ScrollBarThickness     = 4
gridList.ScrollBarImageColor3   = Color3.fromRGB(90, 100, 114)
gridList.CanvasSize             = UDim2.new()
gridList.AutomaticCanvasSize    = Enum.AutomaticSize.Y
gridList.Parent                 = gridSlab

local gridLayout = Instance.new("UIGridLayout", gridList)
gridLayout.CellSize    = UDim2.new(0, 90, 0, 90)
gridLayout.CellPadding = UDim2.new(0, 9, 0, 9)
gridLayout.SortOrder   = Enum.SortOrder.LayoutOrder

-- ── Detail strip ─────────────────────────────────────────────────────────────

local detail = Instance.new("Frame")
detail.Size                   = UDim2.new(1, -26, 0, 62)
detail.Position               = UDim2.new(0, 13, 0, 294)
detail.BackgroundColor3       = Color3.fromRGB(17, 21, 27)
detail.BackgroundTransparency = 0.25
detail.BorderSizePixel        = 0
detail.Parent                 = gridSlab
corner(detail, 10)

local detailName = text(detail, "Nothing selected", UDim2.new(1, -160, 0, 18), INK, 14, StrataConfig.UI.Head)
detailName.Position = UDim2.new(0, 14, 0, 9)

local detailLine = text(detail, "Tap anything to look at it.", UDim2.new(1, -160, 0, 30), DIM, 11, StrataConfig.UI.Body)
detailLine.Position    = UDim2.new(0, 14, 0, 28)
detailLine.TextWrapped = true

local detailAct = Instance.new("TextButton")
detailAct.Size             = UDim2.new(0, 128, 0, 32)
detailAct.Position         = UDim2.new(1, -14, 0.5, 0)
detailAct.AnchorPoint      = Vector2.new(1, 0.5)
detailAct.BackgroundColor3 = SIGNAL
detailAct.BorderSizePixel  = 0
detailAct.Text             = "EQUIP"
detailAct.TextColor3       = Color3.fromRGB(14, 18, 24)
detailAct.TextSize         = 12
detailAct.Font             = StrataConfig.UI.Head
detailAct.Visible          = false
detailAct.Parent           = detail
corner(detailAct, 8)
pressable(detailAct, SIGNAL, Color3.fromRGB(160, 210, 224))

local detailAction = nil   -- what the button does for the selected item

detailAct.Activated:Connect(function()
	if detailAction then detailAction() end
end)

-- ── Categories ───────────────────────────────────────────────────────────────

local CATS = {
	{ id = "all",     name = "ALL"     },
	{ id = "ore",     name = "ORE"     },
	{ id = "rock",    name = "ROCK"    },
	{ id = "armour",  name = "ARMOUR"  },
	{ id = "pickaxe", name = "PICKS"   },
	{ id = "tool",    name = "TOOLS"   },
}

local catButtons = {}

for i, cat in ipairs(CATS) do
	local w = 96
	local b = Instance.new("TextButton")
	b.Size             = UDim2.new(0, w, 0, 34)
	b.Position         = UDim2.new(0, 272 + (i - 1) * (w + 7), 0, 436)
	b.BackgroundColor3 = Color3.fromRGB(27, 33, 42)
	b.BorderSizePixel  = 0
	b.Text             = cat.name
	b.TextColor3       = DIM
	b.TextSize         = 11
	b.Font             = StrataConfig.UI.Head
	b.AutoButtonColor  = false
	b.Parent           = kit
	corner(b, 9)
	local edge = stroked(b, Color3.fromRGB(57, 65, 78), 1.5, 0.35)

	catButtons[cat.id] = { button = b, edge = edge }

	pressable(b, Color3.fromRGB(27, 33, 42), Color3.fromRGB(38, 46, 58))
	b.Activated:Connect(function()
		selectedCat = cat.id
		selectedKey = nil
		refreshKit()
	end)
end

-- ── What you have ────────────────────────────────────────────────────────────
-- One flat list of entries, whatever the thing is, so the grid does not care
-- whether it is drawing ore or a helmet.

local function grantText(gear)
	local parts = {}
	for key, value in pairs(gear.grants) do
		table.insert(parts, key .. " +" .. value)
	end
	table.sort(parts)
	return table.concat(parts, "  ·  ")
end

local function gearKind(gear)
	if GearConfig.IsArmorSlot(gear.slot) then return "armour" end
	if gear.slot == "pickaxe" then return "pickaxe" end
	return "tool"
end

local function gatherItems()
	local items = {}

	for _, ore in ipairs(StrataConfig.Ores) do
		local count = S.inventory[ore.id]
		if count and count > 0 then
			table.insert(items, {
				kind = "ore", id = ore.id, name = ore.name, count = count,
				tier = ore.tier, colour = ore.color, ore = ore,
				line = ("%s  ·  tier %d  ·  %d credits each, %d for the lot")
					:format(ore.family, ore.tier, ore.value, ore.value * count),
			})
		end
	end

	for _, stratum in ipairs(StrataConfig.Strata) do
		local rock  = StrataConfig.Rocks[stratum.id]
		local count = rock and S.inventory[rock.id]
		if count and count > 0 then
			table.insert(items, {
				kind = "rock", id = rock.id, name = rock.name, count = count,
				ore  = rock,   -- close enough for OreIcon: it wants a name and a colour
				tier = 1, colour = rock.color,
				line = ("broken off every dig  ·  takes no pack slot  ·  %d credits for the lot")
					:format(stratum.valuePerDig * count),
			})
		end
	end

	for _, gear in ipairs(GearConfig.Gear) do
		if S.owned[gear.id] then
			local kind = gearKind(gear)
			local worn = GearConfig.IsArmorSlot(gear.slot) and S.equipped[gear.slot] == gear.id
			table.insert(items, {
				kind = kind, id = gear.id, name = gear.name, count = nil,
				tier = gear.tier, colour = tierColour(gear.tier), gear = gear, worn = worn,
				line = grantText(gear) .. "  ·  " .. (gear.blurb or ""),
			})
		end
	end

	table.sort(items, function(a, b)
		if a.kind ~= b.kind then return a.kind < b.kind end
		if (a.tier or 1) ~= (b.tier or 1) then return (a.tier or 1) < (b.tier or 1) end
		return a.name < b.name
	end)

	return items
end

-- ── Tiles ────────────────────────────────────────────────────────────────────
-- Each tile carries a live 3D render of the thing it stands for, which is not
-- cheap to build. So tiles are rebuilt only when what you own actually changes,
-- and selecting one repaints two tiles rather than the whole grid.

local tiles       = {}     -- [itemKey] = { button, edge, item }
local shownItems  = {}     -- [itemKey] = item, whatever is currently on screen
local lastSig     = nil
local updateDetail         -- forward declaration: tiles call it when clicked

local function paintTile(entry, chosen)
	if not entry then return end
	entry.button.BackgroundColor3 = chosen and Color3.fromRGB(42, 50, 62) or SLOT
	entry.edge.Transparency       = chosen and 0 or 0.15
	entry.edge.Thickness          = chosen and 3 or (entry.item.worn and 2.5 or 2)
end

local function tile(order, item)
	local key = item.kind .. ":" .. item.id

	local b = Instance.new("TextButton")
	b.Size             = UDim2.new(0, 90, 0, 90)
	b.BackgroundColor3 = SLOT
	b.BorderSizePixel  = 0
	b.Text             = ""
	b.AutoButtonColor  = false
	b.LayoutOrder      = order
	b.ClipsDescendants = true
	b.Parent           = gridList
	corner(b, 10)
	local edge = stroked(b, item.worn and GREEN or tierColour(item.tier),
		item.worn and 2.5 or 2, 0.15)

	-- A live render of the thing itself, so nothing needs an uploaded picture
	local drawn
	if item.ore then
		drawn = ItemModels.OreIcon(item.ore, b, 54, UDim2.new(0, 18, 0, 7))
	elseif item.gear then
		drawn = ItemModels.Icon(item.gear.id, b, 54, UDim2.new(0, 18, 0, 7))
	end

	-- Anything without a model yet still needs to look like something
	if not drawn then
		local chip = Instance.new("Frame")
		chip.Size             = UDim2.new(0, 34, 0, 38)
		chip.Position         = UDim2.new(0, 28, 0, 15)
		chip.Rotation         = 8
		chip.BackgroundColor3 = item.colour or DIM
		chip.BorderSizePixel  = 0
		chip.Parent           = b
		corner(chip, 6)
	end

	local name = text(b, item.name, UDim2.new(1, -8, 0, 12), INK, 9.5,
		StrataConfig.UI.Body, Enum.TextXAlignment.Center)
	name.Position     = UDim2.new(0, 4, 1, -16)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	if item.count then
		local badge = Instance.new("Frame")
		badge.Size                   = UDim2.new(0, 30, 0, 16)
		badge.Position               = UDim2.new(1, -34, 0, 5)
		badge.BackgroundColor3       = Color3.fromRGB(13, 17, 23)
		badge.BackgroundTransparency = 0.12
		badge.BorderSizePixel        = 0
		badge.ZIndex                 = 3
		badge.Parent                 = b
		corner(badge, 8)
		stroked(badge, Color3.fromRGB(75, 86, 102), 1, 0.3)

		local qty = text(badge, "x" .. item.count, UDim2.new(1, 0, 1, 0), INK, 10,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		qty.ZIndex = 4
	end

	if item.worn then
		local wornTag = text(b, "WORN", UDim2.new(1, 0, 0, 10), GREEN, 8,
			StrataConfig.UI.Head, Enum.TextXAlignment.Center)
		wornTag.Position = UDim2.new(0, 0, 0, 62)
		wornTag.ZIndex   = 3
	end

	local entry = { button = b, edge = edge, item = item }
	tiles[key] = entry

	b.MouseEnter:Connect(function()
		if selectedKey ~= key then b.BackgroundColor3 = Color3.fromRGB(45, 54, 67) end
	end)
	b.MouseLeave:Connect(function()
		if selectedKey ~= key then b.BackgroundColor3 = SLOT end
	end)

	b.Activated:Connect(function()
		local previous = selectedKey
		selectedKey = key
		if previous and tiles[previous] then paintTile(tiles[previous], false) end
		paintTile(entry, true)
		updateDetail()
	end)

	return b
end

-- ── Detail strip ─────────────────────────────────────────────────────────────

function updateDetail()
	local selected = selectedKey and shownItems[selectedKey] or nil
	detailAction = nil

	if not selected then
		detailName.Text       = "Nothing selected"
		detailName.TextColor3 = INK
		detailLine.Text       = "Tap anything to look at it."
		detailAct.Visible     = false
		return
	end

	detailName.Text = selected.count
		and ("%s  x%d"):format(selected.name, selected.count)
		or selected.name
	detailName.TextColor3 = tierColour(selected.tier)
	detailLine.Text       = selected.line or ""

	if selected.kind == "armour" then
		detailAct.Visible = true
		detailAct.Text    = selected.worn and "TAKE OFF" or "EQUIP"
		local gear, worn = selected.gear, selected.worn
		detailAction = function()
			equipRequest:FireServer(worn and nil or gear.id, gear.slot)
		end
	else
		detailAct.Visible = false
		if selected.kind == "pickaxe" then
			detailLine.Text = detailLine.Text ..
				"  ·  the best pick you own is always the one in your hand"
		end
	end
end

-- ── Refresh ──────────────────────────────────────────────────────────────────

function refreshKit()
	-- Slots under the body. The picture is rebuilt only when the piece in the
	-- slot actually changes, because each one is a live 3D render.
	for _, slot in ipairs(GearConfig.ArmorSlots) do
		local ui   = slotButtons[slot.id]
		local id   = S.equipped[slot.id]
		local gear = id and GearConfig.Get(id)

		if ui.shownId ~= id then
			ui.shownId = id
			if ui.icon then ui.icon:Destroy(); ui.icon = nil end
			if gear then
				ui.icon = ItemModels.Icon(gear.id, ui.art, 52, UDim2.new())
			end
		end

		ui.glyph.Visible     = ui.icon == nil
		ui.glyph.TextColor3  = gear and GREEN or DIM
		ui.label.Text        = gear and string.upper(gear.name) or string.upper(slot.name)
		ui.label.TextColor3  = gear and INK or DIM
		ui.edge.Color        = gear and GREEN or Color3.fromRGB(70, 80, 95)
		ui.edge.Transparency = gear and 0 or 0.25
	end

	-- Which half of the panel is showing
	local bodyMode = previewMode == "body"
	for _, mode in ipairs({ "body", "pack" }) do
		local ui = modeTabs[mode]
		local on = previewMode == mode
		ui.button.BackgroundColor3 = on and Color3.fromRGB(43, 51, 63) or Color3.fromRGB(27, 33, 42)
		ui.button.TextColor3       = on and ORE or DIM
		ui.edge.Color              = on and ORE or Color3.fromRGB(57, 65, 78)
		ui.edge.Transparency       = on and 0 or 0.35
	end

	gateLine.Visible  = bodyMode
	setLine.Visible   = bodyMode
	lightLine.Visible = not bodyMode
	lightNote.Visible = not bodyMode
	for _, slot in ipairs(GearConfig.ArmorSlots) do
		slotButtons[slot.id].button.Visible = bodyMode
	end

	-- The mast
	local level = S.lightLevel or 1
	local spec  = StrataConfig.PackLightLevel(level)
	lightLine.Text       = ("PACK LIGHT  ·  LEVEL %d  ·  %s"):format(level, string.upper(spec.name))
	lightLine.TextColor3 = spec.colour
	lightNote.Text = ("throws light %d studs  ·  light +%d  ·  walk +%d\n\nThe mast is raised by prestige, never by mining. Every level is one more head on it, and everyone can see it.")
		:format(spec.range, spec.grants.light or 0, spec.grants.walkSpeed or 0)

	-- Heat is the number that opens a biome, and set progress is how you get it
	local heatGate = GearConfig.DepthGates[1]
	local heat     = (S.resistances and S.resistances.heat) or 0
	local needed   = heatGate and heatGate.level or 3
	gateLine.Text       = ("HEAT %d / %d"):format(heat, needed)
	gateLine.TextColor3 = heat >= needed and GREEN or CRIT

	local setLines = {}
	for _, p in ipairs(GearConfig.SetProgress(S.equipped)) do
		table.insert(setLines, ("%s  %s%s"):format(
			p.complete and "SET" or ("%d/%d"):format(p.worn, p.total),
			p.set.name,
			p.set.unlocks and ("  →  " .. p.set.unlocks) or ""))
	end
	setLine.Text = table.concat(setLines, "\n")

	-- Pack
	local carried, capacity = S.carried or 0, math.max(S.capacity or 1, 1)
	capValue.Text = ("%d / %d"):format(carried, capacity)
	capFill.Size  = UDim2.new(math.clamp(carried / capacity, 0, 1), 0, 1, 0)
	capFill.BackgroundColor3 = carried >= capacity and CRIT or ORE

	-- Categories
	for _, cat in ipairs(CATS) do
		local ui = catButtons[cat.id]
		local on = selectedCat == cat.id
		ui.button.BackgroundColor3 = on and Color3.fromRGB(43, 51, 63) or Color3.fromRGB(27, 33, 42)
		ui.button.TextColor3       = on and ORE or DIM
		ui.edge.Color              = on and ORE or Color3.fromRGB(57, 65, 78)
		ui.edge.Transparency       = on and 0 or 0.35
	end

	-- Tiles. Rebuilding these means rebuilding a 3D render per item, so it only
	-- happens when the contents actually changed — not on every state push.
	local items, keep = gatherItems(), {}
	local parts = { selectedCat }

	for _, item in ipairs(items) do
		if selectedCat == "all" or item.kind == selectedCat then
			table.insert(keep, item)
			table.insert(parts, ("%s:%s:%s:%s")
				:format(item.kind, item.id, tostring(item.count), tostring(item.worn)))
		end
	end

	local sig = table.concat(parts, "|")
	if sig ~= lastSig then
		lastSig = sig

		for _, c in ipairs(gridList:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		tiles, shownItems = {}, {}

		for order, item in ipairs(keep) do
			shownItems[item.kind .. ":" .. item.id] = item
			tile(order, item)
		end

		if #keep == 0 then
			local empty = text(gridList, "Nothing here yet.", UDim2.new(0, 300, 0, 60),
				DIM, 13, StrataConfig.UI.Body, Enum.TextXAlignment.Center)
			empty.LayoutOrder = 1
		end

		-- Whatever was selected may not exist any more
		if selectedKey and not shownItems[selectedKey] then selectedKey = nil end
		if selectedKey and tiles[selectedKey] then paintTile(tiles[selectedKey], true) end
	end

	kitCount.Text = #keep == 1 and "1 ITEM" or (#keep .. " ITEMS")
	updateDetail()
end

-- ── Opening ──────────────────────────────────────────────────────────────────

local function closeKit()
	if not kit.Visible then return end
	popOut(kit, kitScale)
end

local function openKit(category, mode)
	local sameView = (not category or category == selectedCat)
		and (not mode or mode == previewMode)
	if kit.Visible and sameView then
		closeKit()
		return
	end

	selectedCat = category or selectedCat
	previewMode = mode or previewMode

	-- Reopening starts with nothing selected, so no tile should still look picked
	selectedKey = nil
	for _, entry in pairs(tiles) do paintTile(entry, false) end

	if panel.Visible then closePanel() end
	rebuildPreview()
	refreshKit()

	if not kit.Visible then popIn(kit, kitScale) end
end

kitClose.Activated:Connect(closeKit)


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

	showAction("SELL ALL    +" .. commas(total), Color3.fromRGB(214, 164, 64), function()
		sellRequest:FireServer()
	end)
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
hazardBanner.Font                   = StrataConfig.UI.Head
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
	S = s
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
;(function()
-- ── Depth chart ──────────────────────────────────────────────────────────────
-- The ladder, down the right edge. Layers you have reached are lit in their own
-- colour; the ones below are sealed and read as ???. Segments are equal height
-- rather than to scale — this is a map, not a graph, and Topsoil would be a
-- sliver otherwise. The marker interpolates inside whichever layer you're in.

local RunSvc = game:GetService("RunService")

local CHART_W  = 76
local SEG_H    = 56
local SEG_GAP  = 5
local HEAD_H   = 40
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
task.spawn(function()
	while task.wait(0.4) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		chart.Visible = root == nil
			or root.Position.Y > StrataConfig.Mine.SurfaceY - 24
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

-- ── Surface cap, with drifting cloud bands ───────────────────────────────────

local cap = Instance.new("Frame")
cap.Size             = UDim2.new(1, -8, 0, HEAD_H - 6)
cap.Position         = UDim2.new(0, 4, 0, 4)
cap.BackgroundColor3 = Color3.new(1, 1, 1)
cap.BorderSizePixel  = 0
cap.ClipsDescendants = true
cap.ZIndex           = 2
cap.Parent           = chart
corner(cap, 10)

local capSky = Instance.new("UIGradient", cap)
capSky.Rotation = 90
capSky.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(126, 186, 224)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 220, 216)),
})

local clouds = {}
for i = 1, 3 do
	local c = Instance.new("Frame")
	c.Size                   = UDim2.new(0, 26 + i * 8, 0, 5)
	c.Position               = UDim2.new(0, -40, 0, 6 + i * 7)
	c.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	c.BackgroundTransparency = 0.45
	c.BorderSizePixel        = 0
	c.ZIndex                 = 3
	c.Parent                 = cap
	corner(c, 3)
	clouds[i] = { frame = c, x = -40 - i * 30, speed = 5 + i * 3 }
end

local capLabel = text(cap, "SURFACE", UDim2.new(1, 0, 1, 0),
	Color3.fromRGB(28, 44, 58), 12, StrataConfig.UI.Head, Enum.TextXAlignment.Center)
capLabel.ZIndex = 4

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

	-- Colour rail down the left of each segment
	local rail = Instance.new("Frame")
	rail.Size             = UDim2.new(0, 4, 1, -12)
	rail.Position         = UDim2.new(0, 5, 0, 6)
	rail.BackgroundColor3 = layer.color
	rail.BorderSizePixel  = 0
	rail.ZIndex           = 3
	rail.Parent           = seg
	corner(rail, 2)

	local name = text(seg, layer.name, UDim2.new(1, -18, 0, 30),
		Color3.fromRGB(255, 255, 255), 11, StrataConfig.UI.Head)
	name.Position       = UDim2.new(0, 14, 0, 6)
	name.TextWrapped    = true
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.ZIndex         = 3

	local depth = text(seg, math.floor(math.abs(layer.top)) .. "m", UDim2.new(1, -18, 0, 14),
		Color3.fromRGB(220, 228, 236), 10, StrataConfig.UI.Number)
	depth.Position = UDim2.new(0, 14, 1, -19)
	depth.ZIndex   = 3

	segments[i] = {
		layer = layer, frame = seg, fade = fade, edge = edge,
		rail = rail, name = name, depth = depth, y = y, lit = nil,
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
		cardHard.Text  = "hardness " .. (layer.hardness or 1)
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
				s.name.Text       = s.layer.name
				s.name.TextColor3 = Color3.fromRGB(255, 255, 255)
				s.depth.Text      = math.floor(math.abs(s.layer.top)) .. "m"
				s.rail.BackgroundColor3       = s.layer.color
				s.rail.BackgroundTransparency = 0
			else
				s.fade.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 38, 46)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 25, 31)),
				})
				s.name.Text       = goal and s.layer.name or "???"
				s.name.TextColor3 = goal and Color3.fromRGB(210, 216, 224)
					or Color3.fromRGB(96, 104, 116)
				s.depth.Text      = goal and (s.layer.requires or (math.floor(math.abs(s.layer.top)) .. "m")) or "?"
				s.depth.TextColor3 = goal and ORE or Color3.fromRGB(80, 88, 100)
				s.rail.BackgroundColor3       = Color3.fromRGB(70, 78, 90)
				s.rail.BackgroundTransparency = 0.3
			end
		end
	end
end

-- ── Live marker + idle animation ─────────────────────────────────────────────

local markerY   = HEAD_H
local pulse     = 0
local cloudTime = 0

RunSvc.RenderStepped:Connect(function(dt)
	pulse     += dt
	cloudTime += dt

	-- Clouds drift across the surface cap and wrap around
	for _, c in ipairs(clouds) do
		c.x += dt * c.speed
		if c.x > CHART_W then c.x = -50 end
		c.frame.Position = UDim2.new(0, c.x, 0, c.frame.Position.Y.Offset)
	end

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

	-- The layer you're standing in breathes so it reads as "you are here"
	for i, s in ipairs(segments) do
		if i == index and s.lit then
			s.edge.Color        = s.layer.color
			s.edge.Transparency = 0.15 + math.sin(pulse * 3) * 0.15
			s.edge.Thickness    = 2.6
		else
			s.edge.Color        = OUTLINE
			s.edge.Transparency = 0.2
			s.edge.Thickness    = 2
		end
	end
end)

end)()   -- depth chart

refreshChart()

print("[SurfaceUI] ready")
