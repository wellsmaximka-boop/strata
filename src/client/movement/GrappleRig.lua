local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── The rope, as an actual rope ───────────────────────────────────────────────
-- One rig is one hook in the air: an anchor, a RopeConstraint, and a length.
-- It owns no forces. Momentum owns every force on the character so that there
-- is exactly one thing writing to the body, and this owns the geometry.
--
-- Why a RopeConstraint, out of everything Roblox offers:
--
--   It is a hard distance limit that can pull and cannot push, which is the
--   definition of a rope. Below the limit you are in free fall and the rope is
--   not there. At the limit you are on a pendulum, and the pendulum is solved
--   by Roblox against your real mass and your real velocity — so swinging,
--   accelerating out of the bottom of an arc, and keeping every bit of that
--   speed when you let go are not features that had to be written. They are
--   what the constraint already does.
--
--   A SpringConstraint oscillates, which is the bounce the brief asks us to
--   avoid. AlignPosition and the deprecated BodyPosition chase a target, which
--   is the magnetic pull it also asks us to avoid. Writing velocity every frame
--   — which is what this file replaced — throws away the momentum it is
--   supposed to be preserving, every frame, by definition.

local CFG = StrataConfig.Grapple

local GrappleRig = {}
GrappleRig.__index = GrappleRig

-- Where the hand is. The rope hangs off a point above the root rather than the
-- root itself, so the character swings below the cable instead of through it.
local HAND = Vector3.new(0, 0.6, 0)

-- Anchors have to be parts, because a RopeConstraint needs an Attachment and an
-- Attachment needs a part to live on. Terrain cannot hold one and nearly every
-- surface in this game is terrain, so every hook spawns one of these and takes
-- it away again. They live in one folder so the aiming ray can ignore the lot
-- of them in a single filter entry.
local function anchorHome()
	local f = workspace:FindFirstChild("GrappleAnchors")
	if not f then
		f        = Instance.new("Folder")
		f.Name   = "GrappleAnchors"
		f.Parent = workspace
	end
	return f
end

function GrappleRig.new(character, anchorPos)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local self = setmetatable({}, GrappleRig)
	self.character = character
	self.root      = root
	self.anchor    = anchorPos
	self.bornAt    = os.clock()

	self.part              = Instance.new("Part")
	self.part.Name         = "Anchor"
	self.part.Size         = Vector3.new(0.4, 0.4, 0.4)
	self.part.Position     = anchorPos
	self.part.Anchored     = true
	self.part.CanCollide   = false
	self.part.CanQuery     = false
	self.part.CanTouch     = false
	self.part.CastShadow   = false
	self.part.Transparency = 1
	self.part.Parent       = anchorHome()

	self.anchorAtt        = Instance.new("Attachment")
	self.anchorAtt.Name   = "GrappleAnchorPoint"
	self.anchorAtt.Parent = self.part

	self.hand          = Instance.new("Attachment")
	self.hand.Name     = "GrappleHand"
	self.hand.Position = HAND
	self.hand.Parent   = root

	-- The length starts at exactly where the player already is. Attaching
	-- should never move anybody — if the rope began shorter it would yank, and
	-- if it began longer the hook would catch a moment after the button.
	self.length = math.clamp((anchorPos - self.hand.WorldPosition).Magnitude,
		CFG.MinLength, CFG.MaxLength)

	self.rope             = Instance.new("RopeConstraint")
	self.rope.Attachment0 = self.hand
	self.rope.Attachment1 = self.anchorAtt
	self.rope.Length      = self.length
	self.rope.Restitution = 0
	self.rope.Visible     = false   -- we draw a nicer one; see RopeView
	self.rope.Parent      = root

	self.distance  = self.length
	self.direction = Vector3.yAxis
	self.taut      = true

	return self
end

-- Returns false when the rig has outlived whatever it was attached to and the
-- caller should drop it.
function GrappleRig:Step(dt, reelIn, reelOut)
	local root = self.root
	if not root or not root.Parent or not self.part.Parent then return false end

	-- The attachment's own world position, not root.Position + HAND, because
	-- HAND is a point on the body and the body tilts in freefall. A studs-worth
	-- of error in the rope direction is a studs-worth of error in every force
	-- that gets pointed along it.
	local toward = self.anchor - self.hand.WorldPosition
	local dist   = toward.Magnitude

	self.distance  = dist
	self.direction = dist > 0.05 and toward.Unit or Vector3.yAxis

	-- ── The ratchet ──────────────────────────────────────────────────────────
	-- This is the one idea that makes the whole thing stable, so it is worth
	-- being explicit about.
	--
	-- Reeling in is done by force, over in Momentum. It is never done by
	-- setting Length. Winching a hard constraint shorter than the player
	-- actually is hauls them along it inside a single frame, and that haul is
	-- the snapping and jittering that grapple systems get accused of.
	--
	-- So the force closes the gap, and the limit follows along behind at a
	-- bounded rate, never set shorter than the real distance. There is no frame
	-- on which the rope has to move anyone. It only ever stops them.
	--
	-- And it only follows while reeling. Doing it all the time would be a
	-- mistake that looks subtle and feels terrible: on the slack side of a
	-- swing you are closer to the anchor than the rope is long, so the limit
	-- would quietly shrink to meet you and you could never swing back out.
	if reelIn and dist < self.length then
		self.length = math.max(dist, self.length - CFG.ReelFollow * dt, CFG.MinLength)
	end

	if reelOut then
		self.length = math.min(self.length + CFG.PayoutSpeed * dt, CFG.MaxLength)
	end

	self.rope.Length = self.length
	self.taut        = dist >= self.length - 0.5

	return true
end

function GrappleRig:Destroy()
	if self.rope      then self.rope:Destroy() end
	if self.hand      then self.hand:Destroy() end
	if self.anchorAtt then self.anchorAtt:Destroy() end
	if self.part      then self.part:Destroy() end
	self.rope, self.hand, self.anchorAtt, self.part = nil, nil, nil, nil
end

return GrappleRig
