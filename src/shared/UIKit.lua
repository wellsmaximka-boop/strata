local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── UIKit ────────────────────────────────────────────────────────────────────
-- The parts an inventory screen in this genre is made of, built once and used
-- everywhere.
--
-- Look at any of them — the unit grids, the pet inventories, the card
-- collections — and it is the same five pieces every time:
--
--   a ribbon      the screen's name on a slanted plate that overhangs the panel
--                 edge, so the panel has a label rather than a caption
--   a tile        a square card whose *whole body* is the rarity colour, with a
--                 level badge in one corner, a mark in the other and a name
--                 plate along the bottom
--   a detail pane the selected thing, big, down the right-hand side
--   chunky bars   fat saturated buttons along the bottom
--   a red X       in the top-right, overhanging the corner
--
-- The thing that makes them read as one family is that the rarity colour is not
-- an accent on the card, it *is* the card. A grey card with a coloured edge is
-- a list row; a card that is entirely gold is a legendary.
--
-- This module builds instances and nothing else. It holds no state, knows
-- nothing about the game, and every function returns what it made.

local UIKit = {}

local UIP = StrataConfig.UI

-- ── Primitives ───────────────────────────────────────────────────────────────

function UIKit.Corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UIP.Corner)
	c.Parent = object
	return c
end

function UIKit.Outline(object, colour, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color        = colour or UIP.StoneDark
	s.Thickness    = thickness or UIP.Outline
	s.Transparency = transparency or 0
	s.Parent       = object
	return s
end

function UIKit.Gradient(object, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	g.Parent = object
	return g
end

-- Every piece of text in the kit carries a black outline. It is the single
-- change that makes a label on a coloured card read as a label rather than as a
-- stain, and it is why the references can put white text straight onto gold.
function UIKit.Text(parent, str, size, position, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.Position               = position or UDim2.new()
	l.BackgroundTransparency = 1
	l.Text                   = str
	l.TextColor3             = colour or UIP.Ink
	l.TextSize               = textSize or 14
	l.Font                   = font or UIP.Head
	l.TextXAlignment         = align or Enum.TextXAlignment.Center
	l.ZIndex                 = 6
	l.Parent                 = parent

	local edge = Instance.new("UIStroke")
	edge.Color           = UIP.StoneDark
	edge.Thickness       = math.clamp((textSize or 14) * 0.16, 1.2, 3.4)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	edge.Parent          = l
	return l
end

-- ── The ribbon ───────────────────────────────────────────────────────────────
-- The screen's name on a plate that sits proud of the panel's top-left corner.
-- A title inside the panel is a caption; a title hanging off it is a label on
-- an object, and that is the whole difference.

function UIKit.Ribbon(parent, title, accent)
	local plate = Instance.new("Frame")
	plate.Name             = "Ribbon"
	plate.AnchorPoint      = Vector2.new(0, 1)
	plate.Position         = UDim2.new(0, 18, 0, 16)
	plate.Size             = UDim2.new(0, 250, 0, 50)
	plate.BackgroundColor3 = accent or UIP.Ore
	plate.BorderSizePixel  = 0
	plate.Rotation         = -1.5
	plate.ZIndex           = 20
	plate.Parent           = parent
	UIKit.Corner(plate, 12)
	UIKit.Outline(plate, UIP.StoneDark, 4)
	UIKit.Gradient(plate, Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 180, 180))

	local label = UIKit.Text(plate, string.upper(title or ""),
		UDim2.new(1, -18, 1, -10), UDim2.new(0, 9, 0, 5),
		Color3.fromRGB(26, 20, 6), 26, UIP.Head, Enum.TextXAlignment.Left)
	label.ZIndex = 21

	return {
		frame = plate,
		label = label,
		Set = function(text, colour)
			label.Text = string.upper(text or "")
			if colour then plate.BackgroundColor3 = colour end
		end,
	}
end

-- ── The close button ─────────────────────────────────────────────────────────
-- Red, round, and overhanging the corner. Every reference has exactly this and
-- it is the only control on the screen that never needs a label.

function UIKit.Close(parent, onClick)
	local btn = Instance.new("TextButton")
	btn.Name             = "Close"
	btn.AnchorPoint      = Vector2.new(1, 0)
	btn.Position         = UDim2.new(1, 14, 0, -14)
	btn.Size             = UDim2.new(0, 42, 0, 42)
	btn.BackgroundColor3 = UIP.Warning
	btn.Text             = "X"
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.TextSize         = 22
	btn.Font             = UIP.Head
	btn.AutoButtonColor  = false
	btn.BorderSizePixel  = 0
	btn.ZIndex           = 22
	btn.Parent           = parent
	UIKit.Corner(btn, 12)
	UIKit.Outline(btn, UIP.StoneDark, 4)
	UIKit.Gradient(btn, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170))

	local edge = Instance.new("UIStroke")
	edge.Color           = UIP.StoneDark
	edge.Thickness       = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	edge.Parent          = btn

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12),
			{ BackgroundColor3 = Color3.fromRGB(255, 130, 140) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.16),
			{ BackgroundColor3 = UIP.Warning }):Play()
	end)
	if onClick then btn.Activated:Connect(onClick) end

	return btn
end

-- ── Chunky buttons ───────────────────────────────────────────────────────────
-- Fat, saturated, black-edged, with the label in the heavy face. The references
-- run a row of four along the bottom in four different colours, and that colour
-- coding does more work than any of the words on them.

function UIKit.Chunky(parent, spec)
	local btn = Instance.new("TextButton")
	btn.Name             = spec.name or "Button"
	btn.Size             = spec.size or UDim2.new(0, 132, 0, 40)
	btn.Position         = spec.position or UDim2.new()
	btn.AnchorPoint      = spec.anchor or Vector2.new(0, 0)
	btn.BackgroundColor3 = spec.colour or UIP.Ore
	btn.Text             = string.upper(spec.text or "")
	btn.TextColor3       = spec.ink or Color3.fromRGB(255, 255, 255)
	btn.TextSize         = spec.textSize or 16
	btn.Font             = UIP.Head
	btn.AutoButtonColor  = false
	btn.BorderSizePixel  = 0
	btn.LayoutOrder      = spec.order or 1
	btn.ZIndex           = spec.zIndex or 8
	btn.Parent           = parent
	UIKit.Corner(btn, 10)
	UIKit.Outline(btn, UIP.StoneDark, 4)
	UIKit.Gradient(btn, Color3.fromRGB(255, 255, 255), Color3.fromRGB(166, 166, 166))

	local edge = Instance.new("UIStroke")
	edge.Color           = UIP.StoneDark
	edge.Thickness       = 2.6
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	edge.Parent          = btn

	-- Presses down rather than lighting up. A button that moves is a button you
	-- believe you pressed.
	local nudge = Instance.new("UIScale")
	nudge.Parent = btn

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(nudge, TweenInfo.new(0.06), { Scale = 0.95 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(nudge, TweenInfo.new(0.12, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(nudge, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	if spec.onClick then btn.Activated:Connect(spec.onClick) end
	return btn
end

-- ── The tile ─────────────────────────────────────────────────────────────────
-- The centrepiece. A square card whose whole body is the rarity colour.
--
--   top left      the level, on a dark plate
--   top right     a mark — equipped, locked, owned
--   middle        the thing itself
--   bottom        a dark name plate across the full width
--   bottom right  how many you have
--
-- Dimmed rather than hidden when you cannot have it: a greyed card still says
-- the thing exists, which is most of why a shop is worth looking at.

local TILE_W, TILE_H = UIP.TileW, UIP.TileH
UIKit.TileSize = UDim2.new(0, TILE_W, 0, TILE_H)

function UIKit.Tile(parent, spec)
	local rarity = spec.rarity or StrataConfig.RarityAt(1)
	local live   = spec.enabled ~= false

	local tile = Instance.new(spec.onClick and "TextButton" or "Frame")
	tile.Name             = spec.name or "Tile"
	tile.Size             = UIKit.TileSize
	tile.BackgroundColor3 = live and rarity.deep or Color3.fromRGB(34, 34, 44)
	tile.BorderSizePixel  = 0
	tile.LayoutOrder      = spec.order or 1
	tile.ClipsDescendants = true
	tile.ZIndex           = 4
	tile.Parent           = parent
	if tile:IsA("TextButton") then
		tile.Text            = ""
		tile.AutoButtonColor = false
	end
	UIKit.Corner(tile, 12)

	-- The rarity colour washing up the card, strongest at the top. This is what
	-- makes a legendary look gold from across the screen.
	local wash = Instance.new("Frame")
	wash.Size                   = UDim2.new(1, 0, 1, 0)
	wash.BackgroundColor3       = live and rarity.colour or Color3.fromRGB(96, 96, 112)
	wash.BackgroundTransparency = live and 0.24 or 0.72
	wash.BorderSizePixel        = 0
	wash.ZIndex                 = 4
	wash.Parent                 = tile
	UIKit.Corner(wash, 12)
	UIKit.Gradient(wash, Color3.fromRGB(255, 255, 255), Color3.fromRGB(70, 70, 70))

	local rim = UIKit.Outline(tile, live and rarity.colour or Color3.fromRGB(78, 78, 94), 3)

	-- A second, black outline outside the coloured one. Two rings is what stops
	-- a bright card bleeding into the dark panel behind it.
	local shell = Instance.new("Frame")
	shell.Size                   = UDim2.new(1, 6, 1, 6)
	shell.Position               = UDim2.new(0, -3, 0, -3)
	shell.BackgroundTransparency = 1
	shell.ZIndex                 = 3
	shell.Parent                 = tile
	UIKit.Corner(shell, 14)
	UIKit.Outline(shell, UIP.StoneDark, 4)

	-- The art, floating on the colour rather than sunk into a well
	local art = Instance.new("Frame")
	art.Name                   = "Art"
	art.Size                   = UDim2.new(0, 78, 0, 70)
	art.Position               = UDim2.new(0.5, -39, 0, 26)
	art.BackgroundTransparency = 1
	art.ZIndex                 = 6
	art.Parent                 = tile

	if spec.art then spec.art(art) end

	-- Level, top left
	if spec.level then
		local plate = Instance.new("Frame")
		plate.Size             = UDim2.new(0, 48, 0, 18)
		plate.Position         = UDim2.new(0, 5, 0, 5)
		plate.BackgroundColor3 = Color3.fromRGB(14, 13, 22)
		plate.BorderSizePixel  = 0
		plate.ZIndex           = 7
		plate.Parent           = tile
		UIKit.Corner(plate, 6)
		UIKit.Text(plate, spec.level, UDim2.new(1, 0, 1, 0), UDim2.new(),
			rarity.colour, 11).ZIndex = 8
	end

	-- A mark, top right
	if spec.mark then
		local pip = Instance.new("Frame")
		pip.Size             = UDim2.new(0, 22, 0, 22)
		pip.Position         = UDim2.new(1, -27, 0, 5)
		pip.BackgroundColor3 = spec.markColour or UIP.Moss
		pip.BorderSizePixel  = 0
		pip.ZIndex           = 7
		pip.Parent           = tile
		UIKit.Corner(pip, 7)
		UIKit.Outline(pip, UIP.StoneDark, 2.5)
		UIKit.Text(pip, spec.mark, UDim2.new(1, 0, 1, 0), UDim2.new(),
			Color3.fromRGB(16, 16, 20), 13).ZIndex = 8
	end

	-- The name plate along the bottom
	local plate = Instance.new("Frame")
	plate.Size             = UDim2.new(1, 0, 0, 34)
	plate.Position         = UDim2.new(0, 0, 1, -34)
	plate.BackgroundColor3 = Color3.fromRGB(13, 12, 20)
	plate.BackgroundTransparency = 0.12
	plate.BorderSizePixel  = 0
	plate.ZIndex           = 7
	plate.Parent           = tile

	local name = UIKit.Text(plate, spec.title or "", UDim2.new(1, -8, 0, 16),
		UDim2.new(0, 4, 0, 2), live and UIP.Ink or UIP.Dim, 13)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex       = 8

	-- The line under the name is whatever the screen wants it to be: a price in
	-- a shop, a count in a pack, a rarity in a collection.
	local under = UIKit.Text(plate, spec.line or rarity.name, UDim2.new(1, -8, 0, 13),
		UDim2.new(0, 4, 0, 18), spec.lineColour or rarity.colour, 11)
	under.TextTruncate = Enum.TextTruncate.AtEnd
	under.ZIndex       = 8

	-- How many, bottom right over the art
	if spec.count then
		local chip = Instance.new("Frame")
		chip.AnchorPoint      = Vector2.new(1, 1)
		chip.Size             = UDim2.new(0, 44, 0, 20)
		chip.Position         = UDim2.new(1, -5, 1, -38)
		chip.BackgroundColor3 = Color3.fromRGB(14, 13, 22)
		chip.BorderSizePixel  = 0
		chip.ZIndex           = 7
		chip.Parent           = tile
		UIKit.Corner(chip, 6)
		UIKit.Text(chip, spec.count, UDim2.new(1, 0, 1, 0), UDim2.new(),
			UIP.Ink, 12, UIP.Number).ZIndex = 8
	end

	if spec.onClick and live then
		tile.Activated:Connect(function() spec.onClick(tile) end)

		local lift = Instance.new("UIScale")
		lift.Parent = tile

		tile.MouseEnter:Connect(function()
			TweenService:Create(lift, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
			TweenService:Create(rim, TweenInfo.new(0.12), { Thickness = 5 }):Play()
		end)
		tile.MouseLeave:Connect(function()
			TweenService:Create(lift, TweenInfo.new(0.16), { Scale = 1 }):Play()
			TweenService:Create(rim, TweenInfo.new(0.16), { Thickness = 3 }):Play()
		end)
	end

	return tile, rim
end

-- ── The detail pane ──────────────────────────────────────────────────────────
-- The right-hand column: whatever is selected, big, with its rarity named in
-- its own colour, a stack of stat rows and room for a button underneath.
--
-- Returns a handle rather than the frame, because every screen fills it with
-- different things and none of them should be reaching into its children.

function UIKit.Detail(parent, width)
	local pane = Instance.new("Frame")
	pane.Name             = "Detail"
	pane.AnchorPoint      = Vector2.new(1, 0)
	pane.Position         = UDim2.new(1, -16, 0, 62)
	pane.Size             = UDim2.new(0, width or 236, 1, -118)
	pane.BackgroundColor3 = UIP.StoneDeep
	pane.BorderSizePixel  = 0
	pane.ClipsDescendants = true
	pane.ZIndex           = 6
	pane.Parent           = parent
	UIKit.Corner(pane, UIP.Corner)
	UIKit.Outline(pane, UIP.StoneDark, UIP.Outline)

	-- The rarity colour bled up from behind the art. In the references this is
	-- the loudest thing on the screen and it is what tells you, before you have
	-- read anything, that you clicked on something good.
	local glow = Instance.new("Frame")
	glow.Size                   = UDim2.new(1, 0, 0, 200)
	glow.BackgroundColor3       = UIP.Ore
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel        = 0
	glow.ZIndex                 = 6
	glow.Parent                 = pane
	local glowFade = Instance.new("UIGradient", glow)
	glowFade.Rotation      = 90
	glowFade.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})

	local title = UIKit.Text(pane, "", UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 10),
		UIP.Ink, 22, UIP.Head, Enum.TextXAlignment.Left)
	title.ZIndex = 9

	local rank = UIKit.Text(pane, "", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 0, 36),
		UIP.Ore, 15, UIP.Head, Enum.TextXAlignment.Left)
	rank.ZIndex = 9

	local art = Instance.new("Frame")
	art.Name                   = "Art"
	art.Size                   = UDim2.new(1, -40, 0, 150)
	art.Position               = UDim2.new(0, 20, 0, 60)
	art.BackgroundTransparency = 1
	art.ZIndex                 = 9
	art.Parent                 = pane

	local rows = Instance.new("Frame")
	rows.Size                   = UDim2.new(1, -24, 0, 150)
	rows.Position               = UDim2.new(0, 12, 0, 218)
	rows.BackgroundTransparency = 1
	rows.ZIndex                 = 9
	rows.Parent                 = pane

	local rowLayout = Instance.new("UIListLayout", rows)
	rowLayout.Padding   = UDim.new(0, 5)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local foot = Instance.new("Frame")
	foot.AnchorPoint            = Vector2.new(0.5, 1)
	foot.Position               = UDim2.new(0.5, 0, 1, -10)
	foot.Size                   = UDim2.new(1, -20, 0, 42)
	foot.BackgroundTransparency = 1
	foot.ZIndex                 = 9
	foot.Parent                 = pane

	local empty = UIKit.Text(pane, "PICK SOMETHING", UDim2.new(1, -20, 0, 20),
		UDim2.new(0, 10, 0.5, -10), UIP.Dim, 14)
	empty.ZIndex = 9

	local handle = { frame = pane, art = art, foot = foot }

	function handle.Clear()
		title.Text   = ""
		rank.Text    = ""
		empty.Visible = true
		for _, c in ipairs(art:GetChildren()) do c:Destroy() end
		for _, c in ipairs(rows:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for _, c in ipairs(foot:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	-- `info` is { title, rarity, stats = { { label, value, colour } } }
	function handle.Show(info)
		handle.Clear()
		empty.Visible = false

		local rarity = info.rarity or StrataConfig.RarityAt(1)
		title.Text        = string.upper(info.title or "")
		rank.Text         = rarity.name
		rank.TextColor3   = rarity.colour
		glow.BackgroundColor3 = rarity.colour

		for i, stat in ipairs(info.stats or {}) do
			local row = Instance.new("Frame")
			row.Size             = UDim2.new(1, 0, 0, 24)
			row.BackgroundColor3 = Color3.fromRGB(16, 15, 26)
			row.BorderSizePixel  = 0
			row.LayoutOrder      = i
			row.ZIndex           = 9
			row.Parent           = rows
			UIKit.Corner(row, 6)

			UIKit.Text(row, stat.label or "", UDim2.new(0.55, -8, 1, 0),
				UDim2.new(0, 8, 0, 0), UIP.Dim, 12, UIP.Head,
				Enum.TextXAlignment.Left).ZIndex = 10

			UIKit.Text(row, tostring(stat.value or ""), UDim2.new(0.45, -8, 1, 0),
				UDim2.new(0.55, 0, 0, 0), stat.colour or UIP.Ink, 13, UIP.Number,
				Enum.TextXAlignment.Right).ZIndex = 10
		end
	end

	handle.Clear()
	return handle
end


-- ── Chips ────────────────────────────────────────────────────────────────────
-- A row of small pills under the ribbon: the category you are looking at, or
-- the order you want things in.
--
-- This is what the vertical icon rails in the references are actually *for* —
-- switching between slices of one screen. Laid out across the top rather than
-- down the side because the side is the detail pane, and because a rail would
-- be a second navigation arguing with the button bar that already switches
-- screens.
--
-- It owns which chip is live, so the screen that uses it does not need a
-- variable to remember.

function UIKit.Chips(parent, position)
	local row = Instance.new("Frame")
	row.Name                   = "Chips"
	row.Position               = position
	row.Size                   = UDim2.new(1, -40, 0, 28)
	row.BackgroundTransparency = 1
	row.Visible                = false
	row.ZIndex                 = 7
	row.Parent                 = parent

	local layout = Instance.new("UIListLayout", row)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding       = UDim.new(0, 7)
	layout.SortOrder     = Enum.SortOrder.LayoutOrder

	local handle = { frame = row, active = nil }

	function handle.Active() return handle.active end

	-- Hiding does not forget which chip was live. A screen rebuilding itself
	-- to apply the chip you just clicked goes through here first, and
	-- clearing it there meant the filter never took. Switching screens
	-- resets it anyway: Set falls back to the first option whenever the id
	-- it is holding is not one the new screen offers.
	function handle.Hide()
		row.Visible = false
	end

	-- `options` is { { id, text }, ... }. `onPick` is called with the id, and
	-- not called for the one already live — re-picking the tab you are on
	-- should not rebuild the screen under you.
	function handle.Set(options, accent, onPick)
		for _, c in ipairs(row:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end

		row.Visible = #options > 0
		if #options == 0 then return end

		if not handle.active then handle.active = options[1].id end

		-- Still holding an id this screen does not offer? Fall back to the first.
		local held = false
		for _, o in ipairs(options) do if o.id == handle.active then held = true end end
		if not held then handle.active = options[1].id end

		for i, option in ipairs(options) do
			local live = option.id == handle.active

			local chip = Instance.new("TextButton")
			chip.Size             = UDim2.new(0, 11 * #option.text + 26, 1, 0)
			chip.BackgroundColor3 = live and (accent or UIP.Ore) or Color3.fromRGB(20, 19, 32)
			chip.Text             = string.upper(option.text)
			chip.TextColor3       = live and Color3.fromRGB(24, 18, 6) or UIP.Dim
			chip.TextSize         = 13
			chip.Font             = UIP.Head
			chip.AutoButtonColor  = false
			chip.BorderSizePixel  = 0
			chip.LayoutOrder      = i
			chip.ZIndex           = 8
			chip.Parent           = row
			UIKit.Corner(chip, 8)
			UIKit.Outline(chip, UIP.StoneDark, 3)

			local edge = Instance.new("UIStroke")
			edge.Color           = UIP.StoneDark
			edge.Thickness       = 2
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			edge.Parent          = chip

			chip.Activated:Connect(function()
				if handle.active == option.id then return end
				handle.active = option.id
				if onPick then onPick(option.id) end
			end)
		end
	end

	return handle
end

-- ── A search and sort row ────────────────────────────────────────────────────

function UIKit.Search(parent, position, width, onChange)
	local box = Instance.new("TextBox")
	box.Name             = "Search"
	box.Position         = position
	box.Size             = UDim2.new(0, width, 0, 30)
	box.BackgroundColor3 = Color3.fromRGB(16, 15, 26)
	box.BorderSizePixel  = 0
	box.Text             = ""
	box.PlaceholderText  = "Search..."
	box.PlaceholderColor3 = UIP.Dim
	box.TextColor3       = UIP.Ink
	box.TextSize         = 14
	box.Font             = UIP.Body
	box.TextXAlignment   = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.ZIndex           = 7
	box.Parent           = parent
	UIKit.Corner(box, UIP.CornerSm)
	UIKit.Outline(box, UIP.StoneDark, 3)

	local pad = Instance.new("UIPadding", box)
	pad.PaddingLeft = UDim.new(0, 10)

	if onChange then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			onChange(string.lower(box.Text))
		end)
	end
	return box
end

return UIKit
