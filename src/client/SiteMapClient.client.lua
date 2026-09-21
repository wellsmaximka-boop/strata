local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

local player = Players.LocalPlayer

local remotes      = ReplicatedStorage:WaitForChild("MineRemotes")
local siteMap      = remotes:WaitForChild("SiteMap")
local siteProgress = remotes:WaitForChild("SiteProgress")
local stateChanged = remotes:WaitForChild("StateChanged")

-- ── Knowing where to go ──────────────────────────────────────────────────────
-- Three things, all fed by the one plan the server sends when a run starts:
--
--   the map      bottom of the right-hand column, M for the big one. Colour is
--                the whole language of it — a hall is painted for what it *is*,
--                so the vault reads differently from the ordinary workings at a
--                glance and without a legend.
--   the arrow    a chevron on the floor a few studs ahead of you, pointing at
--                whatever you are supposed to be doing right now. Straight out
--                of BioShock and for the same reason: a map says where things
--                are, an arrow says where to *go*, and in a cave with six
--                mouths off it those are not the same question.
--   the banner   one line across the top naming the job, because a quota in
--                small type inside a card in a corner is a quota nobody reads.
--
-- The map reveals rather than shows: halls you have not walked into are
-- outlines. That is the difference between a map and a solution, and it is why
-- the far half of a site stays a decision rather than a checklist.
--
-- North is up and stays up. A map that rotates with you is easier to walk by
-- and impossible to remember, and remembering where the vault was is the thing
-- you are actually doing.

local UIP = StrataConfig.UI

-- ── Chrome ───────────────────────────────────────────────────────────────────
-- One place a panel gets its corner, its edge and its shadow, so every panel
-- has the same ones.

local function corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UIP.Corner)
	c.Parent = object
	return c
end

local function outline(object, colour, thickness)
	local s = Instance.new("UIStroke")
	s.Color     = colour or UIP.StoneDark
	s.Thickness = thickness or UIP.Outline
	s.Parent    = object
	return s
end

local function label(parent, str, size, position, colour, textSize, font, align)
	local l = Instance.new("TextLabel")
	l.Size                   = size
	l.Position               = position
	l.BackgroundTransparency = 1
	l.Text                   = str
	l.TextColor3             = colour or UIP.Ink
	l.TextSize               = textSize or 13
	l.Font                   = font or UIP.Head
	l.TextXAlignment         = align or Enum.TextXAlignment.Center
	l.ZIndex                 = 6
	l.Parent                 = parent

	local edge = Instance.new("UIStroke")
	edge.Color            = UIP.StoneDark
	edge.Thickness        = math.clamp((textSize or 13) * 0.15, 1.1, 3.2)
	edge.ApplyStrokeMode  = Enum.ApplyStrokeMode.Contextual
	edge.Parent           = l
	return l
end

-- Dark face, heavy black edge, lit top, and a shadow underneath so the panel
-- sits above the game rather than being printed on it.
local function panel(parent, size, position, anchor)
	local shadow = Instance.new("Frame")
	shadow.AnchorPoint            = anchor or Vector2.new(0, 0)
	shadow.Position               = position + UDim2.fromOffset(0, UIP.ShadowDrop)
	shadow.Size                   = size
	shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = UIP.Shadow
	shadow.BorderSizePixel        = 0
	shadow.ZIndex                 = 1
	shadow.Parent                 = parent
	corner(shadow)

	local face = Instance.new("Frame")
	face.AnchorPoint      = anchor or Vector2.new(0, 0)
	face.Position         = position
	face.Size             = size
	face.BackgroundColor3 = UIP.Stone
	face.BorderSizePixel  = 0
	face.ClipsDescendants = true
	face.ZIndex           = 2
	face.Parent           = parent
	corner(face)
	outline(face)

	local lit = Instance.new("UIGradient", face)
	lit.Rotation = 90
	lit.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIP.StoneLit),
		ColorSequenceKeypoint.new(0.3, UIP.Stone),
		ColorSequenceKeypoint.new(1, UIP.StoneDeep),
	})

	return face, shadow
end

-- ── The shell ────────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name           = "StrataSiteMap"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 12
gui.Enabled        = false
gui.Parent         = player:WaitForChild("PlayerGui")

local SMALL, BIG = 236, 540

local card, cardShadow = panel(gui, UDim2.new(0, SMALL, 0, SMALL + 62),
	UDim2.new(1, -16, 0, 122), Vector2.new(1, 0))

-- A coloured header bar. Every panel in the references has one and it is most
-- of why they read as objects rather than as rectangles with text on them.
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = UIP.Ore
header.BorderSizePixel  = 0
header.ZIndex           = 4
header.Parent           = card

local headerShine = Instance.new("UIGradient", header)
headerShine.Rotation = 90
headerShine.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(198, 142, 42)),
})

local title = label(card, "DIG SITE", UDim2.new(1, -78, 0, 20),
	UDim2.new(0, 12, 0, 5), Color3.fromRGB(40, 25, 4), 15, UIP.Head,
	Enum.TextXAlignment.Left)
title.ZIndex = 5

local hint = label(card, "[M]", UDim2.new(0, 68, 0, 18), UDim2.new(1, -11, 0, 6),
	Color3.fromRGB(62, 40, 6), 12, UIP.Number, Enum.TextXAlignment.Right)
hint.AnchorPoint = Vector2.new(1, 0)
hint.ZIndex      = 5

local plan = Instance.new("Frame")
plan.Name             = "Plan"
plan.Position         = UDim2.new(0, 8, 0, 36)
plan.Size             = UDim2.new(1, -16, 1, -68)
plan.BackgroundColor3 = Color3.fromRGB(12, 11, 22)
plan.BorderSizePixel  = 0
plan.ClipsDescendants = true
plan.ZIndex           = 3
plan.Parent           = card
corner(plan, UIP.CornerSm)
outline(plan, UIP.StoneDeep, UIP.EdgeThin)

local footer = label(card, "", UDim2.new(1, -20, 0, 16), UDim2.new(0, 11, 1, -22),
	UIP.Dim, 11, UIP.Number, Enum.TextXAlignment.Left)
footer.AnchorPoint = Vector2.new(0, 1)
footer.ZIndex      = 5

-- ── The objective banner ─────────────────────────────────────────────────────
-- Top centre, under the clock, and deliberately hard to miss.

local bannerFace = panel(gui, UDim2.new(0, 470, 0, 52),
	UDim2.new(0.5, 0, 0, 116), Vector2.new(0.5, 0))
bannerFace.Visible = false

local bannerStripe = Instance.new("Frame")
bannerStripe.Size             = UDim2.new(0, 7, 1, -18)
bannerStripe.Position         = UDim2.new(0, 7, 0, 9)
bannerStripe.BackgroundColor3 = UIP.Ore
bannerStripe.BorderSizePixel  = 0
bannerStripe.ZIndex           = 5
bannerStripe.Parent           = bannerFace
corner(bannerStripe, 4)

local bannerKind = label(bannerFace, "OBJECTIVE", UDim2.new(0, 280, 0, 15),
	UDim2.new(0, 24, 0, 7), UIP.Ore, 12, UIP.Head, Enum.TextXAlignment.Left)

local bannerLine = label(bannerFace, "", UDim2.new(1, -150, 0, 22),
	UDim2.new(0, 24, 0, 23), UIP.Ink, 18, UIP.Head, Enum.TextXAlignment.Left)

local bannerCount = label(bannerFace, "", UDim2.new(0, 120, 0, 28),
	UDim2.new(1, -16, 0, 12), UIP.Crystal, 22, UIP.Number, Enum.TextXAlignment.Right)
bannerCount.AnchorPoint = Vector2.new(1, 0)

-- ── The arrow ────────────────────────────────────────────────────────────────
-- A chevron floating at knee height a few studs ahead of you, lying flat and
-- pointing along the ground. Three neon blocks, and it does more for finding
-- your way around than the map does.

local guide = Instance.new("Folder")
guide.Name   = "ObjectiveArrow"
guide.Parent = workspace

local arrowParts = {}

local function blade(size, offset, spin)
	local p = Instance.new("Part")
	p.Name         = "Chevron"
	p.Size         = size
	p.Color        = UIP.Ore
	p.Material     = Enum.Material.Neon
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false
	p.CanTouch     = false
	p.CastShadow   = false
	p.Transparency = 1
	p.Parent       = guide
	table.insert(arrowParts, { part = p, offset = offset, spin = spin })
end

blade(Vector3.new(1.4, 0.35, 8), Vector3.new(0, 0, 0), 0)
blade(Vector3.new(1.4, 0.35, 4.8), Vector3.new(-1.45, 0, -3.1), math.rad(-42))
blade(Vector3.new(1.4, 0.35, 4.8), Vector3.new(1.45, 0, -3.1), math.rad(42))

local function showArrow(shown, colour)
	for _, piece in ipairs(arrowParts) do
		piece.part.Transparency = shown and 0.22 or 1
		if colour then piece.part.Color = colour end
	end
end

-- ── The waypoint ─────────────────────────────────────────────────────────────
-- A tag on the target itself, readable through rock. The distance is the half
-- that matters: "the vault" means nothing, "the vault, 210 m" is a decision.

local beaconAnchor = Instance.new("Part")
beaconAnchor.Name         = "Waypoint"
beaconAnchor.Size         = Vector3.new(0.4, 0.4, 0.4)
beaconAnchor.Transparency = 1
beaconAnchor.Anchored     = true
beaconAnchor.CanCollide   = false
beaconAnchor.CanQuery     = false
beaconAnchor.CanTouch     = false
beaconAnchor.Parent       = guide

local beacon = Instance.new("BillboardGui")
beacon.Name           = "Tag"
beacon.Size           = UDim2.new(0, 220, 0, 66)
beacon.StudsOffset    = Vector3.new(0, 5, 0)
beacon.AlwaysOnTop    = true
beacon.LightInfluence = 0
beacon.Enabled        = false
beacon.Parent         = beaconAnchor

local beaconPlate = Instance.new("Frame")
beaconPlate.Size             = UDim2.new(1, 0, 0, 42)
beaconPlate.Position         = UDim2.new(0, 0, 0, 22)
beaconPlate.BackgroundColor3 = UIP.StoneDeep
beaconPlate.BorderSizePixel  = 0
beaconPlate.Parent           = beacon
corner(beaconPlate, UIP.CornerSm)
outline(beaconPlate, UIP.StoneDark, 3)

local beaconName  = label(beaconPlate, "", UDim2.new(1, -10, 0, 18),
	UDim2.new(0, 5, 0, 3), UIP.Ore, 15)
local beaconRange = label(beaconPlate, "", UDim2.new(1, -10, 0, 17),
	UDim2.new(0, 5, 0, 21), UIP.Ink, 14, UIP.Number)

local beaconPip = Instance.new("Frame")
beaconPip.AnchorPoint      = Vector2.new(0.5, 0)
beaconPip.Position         = UDim2.new(0.5, 0, 0, 3)
beaconPip.Size             = UDim2.new(0, 16, 0, 16)
beaconPip.Rotation         = 45
beaconPip.BackgroundColor3 = UIP.Ore
beaconPip.BorderSizePixel  = 0
beaconPip.Parent           = beacon
outline(beaconPip, UIP.StoneDark, 3)

-- ── State ────────────────────────────────────────────────────────────────────

local ink      = nil
local site     = nil
local marks    = {}
local visited  = {}
local runState = nil
-- Counted down locally between pushes. `remaining` is only true at the moment
-- the server sent it, and "time is short" has to change the arrow on the second
-- it becomes true rather than on the next ore you pick up.
local runClock = 0
local scale    = 1
local expanded = false
local cleared, needed = 0, 0

-- Colour is the language of the map. The vault is violet wherever it is, so it
-- never has to be looked up.
local function colourOf(chamber)
	if chamber.role == "vault" then return UIP.Violet end
	return chamber.colour or UIP.Iron
end

local function project(x, z, size)
	return x * scale + size / 2, z * scale + size / 2
end

local function line(parent, x1, y1, x2, y2, thickness, colour, z)
	local dx, dy = x2 - x1, y2 - y1
	local bar = Instance.new("Frame")
	bar.AnchorPoint      = Vector2.new(0.5, 0.5)
	bar.Position         = UDim2.new(0, (x1 + x2) / 2, 0, (y1 + y2) / 2)
	bar.Size             = UDim2.new(0, math.max(math.sqrt(dx * dx + dy * dy), 1), 0, thickness)
	bar.Rotation         = math.deg(math.atan2(dy, dx))
	bar.BackgroundColor3 = colour
	bar.BorderSizePixel  = 0
	bar.ZIndex           = z or 4
	bar.Parent           = parent
	return bar
end

local function diamond(parent, x, y, size, colour, z)
	local d = Instance.new("Frame")
	d.AnchorPoint      = Vector2.new(0.5, 0.5)
	d.Position         = UDim2.new(0, x, 0, y)
	d.Size             = UDim2.new(0, size, 0, size)
	d.Rotation         = 45
	d.BackgroundColor3 = colour
	d.BorderSizePixel  = 0
	d.ZIndex           = z or 7
	d.Parent           = parent
	outline(d, UIP.StoneDark, 2)
	return d
end

local function draw(size)
	if not site then return end
	if ink then ink:Destroy() end

	ink = Instance.new("Frame")
	ink.Size                   = UDim2.fromScale(1, 1)
	ink.BackgroundTransparency = 1
	ink.ZIndex                 = 4
	ink.Parent                 = plan

	local reach = 60
	for _, c in ipairs(site.chambers) do
		reach = math.max(reach, math.sqrt(c.x * c.x + c.z * c.z) + c.radius)
	end
	scale = (size * 0.5 - 22) / reach

	-- Galleries first, so everything else sits on top of them
	for _, d in ipairs(site.drifts) do
		local x1, y1 = project(d.ax, d.az, size)
		local x2, y2 = project(d.bx, d.bz, size)
		local known  = visited[d.to] or d.from == 0
		line(ink, x1, y1, x2, y2, known and 4 or 2,
			known and UIP.Vein or Color3.fromRGB(40, 36, 62), 4)
	end

	marks = {}
	for _, c in ipairs(site.chambers) do
		local x, y   = project(c.x, c.z, size)
		local colour = colourOf(c)
		local r      = math.max(c.radius * scale, 7)

		local ring = Instance.new("Frame")
		ring.AnchorPoint            = Vector2.new(0.5, 0.5)
		ring.Position               = UDim2.new(0, x, 0, y)
		ring.Size                   = UDim2.new(0, r * 2, 0, r * 2)
		ring.BackgroundColor3       = colour
		ring.BackgroundTransparency = visited[c.index] and 0.4 or 0.9
		ring.BorderSizePixel        = 0
		ring.ZIndex                 = 5
		ring.Parent                 = ink
		corner(ring, math.floor(r))

		local edge = outline(ring, colour, c.role == "vault" and 3.5 or 2)
		edge.Transparency = visited[c.index] and 0 or 0.35

		local name = label(ink, visited[c.index] and string.upper(c.name) or "",
			UDim2.new(0, 132, 0, 13), UDim2.new(0, x, 0, y + r + 2),
			colour, expanded and 12 or 10)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.ZIndex      = 8

		-- The vault gets a mark of its own: it is the one hall on the map worth
		-- a detour and it should look like it.
		if c.role == "vault" then
			diamond(ink, x, y, expanded and 15 or 11, UIP.Violet, 7)
		end

		marks[c.index] = { ring = ring, edge = edge, label = name, chamber = c }
	end

	local hx, hy = project(0, 0, size)
	diamond(ink, hx, hy, expanded and 18 or 14, UIP.Ore, 8)

	local cage = label(ink, "THE CAGE", UDim2.new(0, 112, 0, 14),
		UDim2.new(0, hx, 0, hy - 22), UIP.Ore, expanded and 12 or 10)
	cage.AnchorPoint = Vector2.new(0.5, 0)
	cage.ZIndex      = 9

	local you = Instance.new("Frame")
	you.Name             = "You"
	you.AnchorPoint      = Vector2.new(0.5, 0.5)
	you.Size             = UDim2.new(0, 11, 0, 11)
	you.BackgroundColor3 = UIP.Ink
	you.BorderSizePixel  = 0
	you.ZIndex           = 10
	you.Parent           = ink
	corner(you, 6)
	outline(you, UIP.StoneDark, 2.5)
end

local function markVisited(index)
	if visited[index] then return end
	visited[index] = true

	local mark = marks[index]
	if mark then
		mark.label.Text = string.upper(mark.chamber.name)
		TweenService:Create(mark.ring, TweenInfo.new(0.45),
			{ BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(mark.edge, TweenInfo.new(0.45), { Transparency = 0 }):Play()
	end
	draw(expanded and BIG or SMALL)
end

-- ── What to do right now ─────────────────────────────────────────────────────
-- One function, and everything visible answers to it: the arrow points at what
-- it returns, the waypoint tags it, the banner names it.

local depositFolder = workspace:WaitForChild("SiteDeposits")

local function nearestDeposit(from)
	local best, bestDist = nil, math.huge
	for _, model in ipairs(depositFolder:GetChildren()) do
		local pivot = model.PrimaryPart
		if pivot then
			local d = (pivot.Position - from).Magnitude
			if d < bestDist then best, bestDist = pivot.Position, d end
		end
	end
	return best
end

local function nearestUnseen(from)
	if not site then return nil end
	local best, bestDist = nil, math.huge
	for _, c in ipairs(site.chambers) do
		if not visited[c.index] then
			local d = (Vector3.new(c.x, c.y, c.z) - from).Magnitude
			if d < bestDist then best, bestDist = c, d end
		end
	end
	return best
end

local function objective(from)
	if not runState then return nil end

	local contract = runState.contract or {}
	local cage     = Vector3.new(0, from.Y, 0)

	-- Done, or nearly out of time: the only thing that matters is the way back
	if runState.met or runClock < 45 then
		return cage, "THE CAGE", "EXTRACT", runState.met
			and "objective complete — get back to the cage"
			or "time is short — get back to the cage", UIP.Ore
	end

	if contract.kind == "extract" then
		local at = nearestDeposit(from)
		if at then
			return at, "DEPOSIT", "EXTRACT",
				contract.line or "break the deposits", UIP.Crystal
		end
		return cage, "THE CAGE", "EXTRACT", "all deposits cleared — get back", UIP.Ore
	end

	if contract.kind == "survey" and site then
		for _, c in ipairs(site.chambers) do
			if not visited[c.index] and c.role == "vault" then
				return Vector3.new(c.x, c.y, c.z), string.upper(c.name), "SURVEY",
					contract.line or "find the room", UIP.Violet
			end
		end
	end

	-- Haul, or anything else: the nearest hall you have not been in yet
	local hall = nearestUnseen(from)
	if hall then
		return Vector3.new(hall.x, hall.y, hall.z), string.upper(hall.name),
			contract.title or "HAUL",
			runState.progress or contract.line or "", colourOf(hall)
	end

	return cage, "THE CAGE", contract.title or "HAUL",
		runState.progress or "get back to the cage", UIP.Ore
end

-- ── Frame ────────────────────────────────────────────────────────────────────

local bob = 0

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")

	if not hrp or not runState then
		showArrow(false)
		beacon.Enabled     = false
		bannerFace.Visible = false
		return
	end

	runClock = math.max(runClock - dt, 0)

	local at = hrp.Position
	local target, name, kind, line, tone = objective(at)

	bannerFace.Visible    = true
	bannerKind.Text       = kind or "OBJECTIVE"
	bannerKind.TextColor3 = tone or UIP.Ore
	bannerStripe.BackgroundColor3 = tone or UIP.Ore
	bannerLine.Text       = line or ""
	bannerCount.Text      = needed > 0 and ("%d/%d"):format(cleared, needed) or ""
	bannerCount.TextColor3 = tone or UIP.Crystal

	if not target then
		showArrow(false)
		beacon.Enabled = false
		return
	end

	local flat = Vector3.new(target.X - at.X, 0, target.Z - at.Z)
	local dist = (target - at).Magnitude

	-- Hidden once you are on top of it. An arrow still pointing when you have
	-- arrived is an arrow people stop believing.
	if flat.Magnitude < 6 or dist < 18 then
		showArrow(false)
	else
		bob += dt
		local aim  = flat.Unit
		local base = CFrame.lookAt(
			at + aim * 8 + Vector3.new(0, -1.4 + math.sin(bob * 3) * 0.35, 0),
			at + aim * 20)
		showArrow(true, tone)
		for _, piece in ipairs(arrowParts) do
			piece.part.CFrame = base * CFrame.new(piece.offset)
				* CFrame.Angles(0, piece.spin, 0)
		end
	end

	beaconAnchor.Position      = target
	beacon.Enabled             = true
	beaconName.Text            = name or ""
	beaconName.TextColor3      = tone or UIP.Ore
	beaconPip.BackgroundColor3 = tone or UIP.Ore
	beaconRange.Text           = ("%d m"):format(math.floor(dist))

	if not site or not ink then return end

	local size = expanded and BIG or SMALL
	local x, y = project(at.X, at.Z, size)
	local dot  = ink:FindFirstChild("You")
	if dot then
		dot.Position = UDim2.new(0, math.clamp(x, 0, size), 0, math.clamp(y, 0, size))
	end

	for _, c in ipairs(site.chambers) do
		if not visited[c.index] then
			local dx, dz = at.X - c.x, at.Z - c.z
			if dx * dx + dz * dz <= c.radius * c.radius
				and math.abs(at.Y - c.y) <= c.radius then
				markVisited(c.index)
			end
		end
	end

	local found = 0
	for _ in pairs(visited) do found += 1 end
	footer.Text = ("%s%d m to cage  ·  %d/%d halls")
		:format(needed > 0 and ("%d/%d deposits  ·  "):format(cleared, needed) or "",
			math.floor(math.sqrt(at.X * at.X + at.Z * at.Z)), found, #site.chambers)
end)

-- ── Opening and closing ──────────────────────────────────────────────────────

local function resize()
	local size = expanded and BIG or SMALL
	local pos  = expanded and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -16, 0, 122)

	card.Size        = UDim2.new(0, size, 0, size + 62)
	card.AnchorPoint = expanded and Vector2.new(0.5, 0.5) or Vector2.new(1, 0)
	card.Position    = pos

	cardShadow.Size        = card.Size
	cardShadow.AnchorPoint = card.AnchorPoint
	cardShadow.Position    = pos + UDim2.fromOffset(0, UIP.ShadowDrop)

	hint.Text = expanded and "[M] CLOSE" or "[M]"
	draw(size)
end

UserInputService.InputBegan:Connect(function(input, typing)
	if typing or input.KeyCode ~= Enum.KeyCode.M or not site then return end
	expanded = not expanded
	resize()
end)

siteMap.OnClientEvent:Connect(function(incoming)
	if type(incoming) ~= "table" or not incoming.chambers or #incoming.chambers == 0 then
		if ink then ink:Destroy() end
		ink, site, marks, visited = nil, nil, {}, {}
		cleared, needed = 0, 0
		expanded    = false
		gui.Enabled = false
		return
	end

	site    = incoming
	visited = {}
	cleared, needed = 0, 0
	title.Text  = "DIG SITE  ·  " .. string.upper(incoming.layerName or "")
	gui.Enabled = true
	expanded    = false
	resize()
end)

siteProgress.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	cleared = info.taken or 0
	needed  = info.need or 0
end)

stateChanged.OnClientEvent:Connect(function(s)
	runState = s and s.run or nil
	runClock = runState and (runState.remaining or 0) or 0
end)

print("[SiteMapClient] ready")
