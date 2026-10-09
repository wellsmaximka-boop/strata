-- ── Kit screen ───────────────────────────────────────────────────────────────
-- One screen for everything you carry and everything you wear. Your body and
-- its slots on the left, every item you own as a grid of tiles on the right,
-- categories along the bottom.
--
-- Wide rather than tall on purpose: a tall list makes you scroll past ore to
-- reach armour, and the two belong side by side.
--
-- Lifted out of SurfaceUI as the second step of the split. It is the largest
-- single screen in the game — nearly eight hundred lines — and in its own module
-- its locals are its own rather than competing for the parent's 200.
--
-- Takes what it needs through `ctx`; hands back the five names the rest of the
-- interface actually touches.

return function(ctx)

local gui          = ctx.gui
local S            = ctx.state
local player       = ctx.player
-- Required here rather than taken from ctx: the parent only ever requires UIKit
-- inside its own IIFEs, so there is no top-level name to hand over.
local UIKit = require(game:GetService("ReplicatedStorage"):WaitForChild("UIKit"))
local StrataConfig = ctx.StrataConfig

local text      = ctx.text
local corner    = ctx.corner
local stroked   = ctx.stroked
local pressable = ctx.pressable
local popIn     = ctx.popIn
local popOut    = ctx.popOut
local scaler    = ctx.scaler

local panel        = ctx.panel
local closePanel   = ctx.closePanel
local equipRequest = ctx.equipRequest
local dress        = ctx.dress

-- Required here rather than passed. Both are ReplicatedStorage modules that the
-- parent happened to keep in top-level locals, which is exactly the invisible
-- coupling the split exists to end: a screen should fetch what it needs, not
-- inherit it from whichever file it used to live in.
local GearConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("GearConfig"))
local ItemModels = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemModels"))

-- Required here, not passed. Both are ReplicatedStorage modules the parent
-- happened to hold in top-level locals, which is exactly the kind of invisible
-- coupling the split is meant to end.
local GearConfig  = require(game:GetService("ReplicatedStorage"):WaitForChild("GearConfig"))
local ItemModels  = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemModels"))

local INK, DIM, ORE     = ctx.INK, ctx.DIM, ctx.ORE
local CRIT, GREEN       = ctx.CRIT, ctx.GREEN
local SIGNAL            = ctx.SIGNAL
local PANEL, SLOT       = ctx.PANEL, ctx.SLOT

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

-- This used to re-require UIKit inside its own IIFE, because in the parent file
-- a second local would have cost a register it could not spare. The IIFE also
-- reached for ReplicatedStorage, which was a top-level local of that file and is
-- not one here — so the module threw on its first line of real work. In here
-- there is no register pressure and UIKit is already required at the top, so the
-- wrapper does nothing but hide a dependency.
UIKit.Ribbon(kit, "KIT", ORE)

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
	b.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, b.TextSize)
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
	detailAct.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, detailAct.TextSize)
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
	b.Font = StrataConfig.FaceFor(StrataConfig.UI.Head, b.TextSize)
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


-- The close plate dress() handed back. Wired here rather than by the parent,
-- which is where it used to live and where it was easy to drop in the move.
kitClose.Activated:Connect(closeKit)

return {
	frame   = kit,
	width   = KIT_W,
	height  = KIT_H,
	scale   = kitScale,
	open    = openKit,
	close   = closeKit,
	refresh = refreshKit,
}
end
