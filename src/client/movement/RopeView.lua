local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── The cable you can see ────────────────────────────────────────────────────
-- Deliberately not the RopeConstraint's own Visible property, which draws a
-- grey hairline, and deliberately not a Beam, which needs a texture to look
-- like anything. A stretched part reads as steel cable and takes the cave
-- lighting, and the hook head is Neon so it stays findable in the dark.
--
-- One of these per rope on screen: one for the local player, and one for each
-- other player who is currently swinging. Theirs are redrawn every frame from
-- their character's replicated position and an anchor sent once, which is why
-- co-op ropes cost no per-frame network traffic at all.

local CFG = StrataConfig.Grapple

local RopeView = {}
RopeView.__index = RopeView

local function home()
	local f = workspace:FindFirstChild("GrappleRope")
	if not f then
		f        = Instance.new("Folder")
		f.Name   = "GrappleRope"
		f.Parent = workspace
	end
	return f
end

local function piece(name, size, colour, material)
	local p          = Instance.new("Part")
	p.Name           = name
	p.Size           = size
	p.Color          = colour
	p.Material       = material
	p.Anchored       = true
	p.CanCollide     = false
	p.CanQuery       = false
	p.CanTouch       = false
	p.CastShadow     = false
	p.Transparency   = 1
	p.Parent         = home()
	return p
end

function RopeView.new(tag)
	local self = setmetatable({}, RopeView)
	local thin = CFG.Rope.Thickness

	self.line = piece("Line_" .. tag, Vector3.new(thin, thin, 1),
		CFG.Rope.Colour, Enum.Material.SmoothPlastic)
	self.head = piece("Hook_" .. tag, Vector3.new(0.9, 0.9, 0.9),
		CFG.Rope.Hook, Enum.Material.Neon)

	return self
end

function RopeView:Draw(from, to)
	if not self.line or not self.line.Parent then return end

	local span = (to - from).Magnitude
	if span < 0.2 then
		self:Hide()
		return
	end

	self.line.Size         = Vector3.new(CFG.Rope.Thickness, CFG.Rope.Thickness, span)
	self.line.CFrame       = CFrame.lookAt(from:Lerp(to, 0.5), to)
	self.line.Transparency = 0

	self.head.CFrame       = CFrame.new(to)
	self.head.Transparency = 0
end

function RopeView:Hide()
	if self.line then self.line.Transparency = 1 end
	if self.head then self.head.Transparency = 1 end
end

function RopeView:Destroy()
	if self.line then self.line:Destroy() end
	if self.head then self.head:Destroy() end
	self.line, self.head = nil, nil
end

return RopeView
