local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))

-- ── Momentum ─────────────────────────────────────────────────────────────────
-- One VectorForce on the character, and this is the only thing that writes to
-- it. Air steering, rope steering, the reel, and the slide out of a landing are
-- all the same force summed once per frame, because two scripts pushing the
-- same body is how you get a fight you cannot tune your way out of.
--
-- Nothing here touches WalkSpeed. PlayerState owns WalkSpeed and pushes it on
-- every state change, and the sprint code in MineClient reads it — a third
-- writer would be a bug with three authors. Forces add on top of all of it
-- and need no permission from any of them.
--
-- Nothing here touches the Humanoid's state either. The version this replaced
-- slammed ChangeState(Freefall) sixty times a second to beat ground friction,
-- which was a real fix for a real problem and also exactly the controller
-- fight the brief warns about. With a constraint doing the physics the friction
-- is correct: dragging along a shelf *should* slow you down.

local CFG = StrataConfig.Grapple

local Momentum = {}
Momentum.__index = Momentum

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Steering that adds rather than replaces, with the speed cap applied to the
-- push instead of to the velocity.
--
-- The tempting version of a speed cap is to clamp the velocity once it is too
-- high. That is a reset, and a reset at the top of every swing is precisely the
-- sudden velocity loss the brief rules out. So instead: if you are already over
-- the cap, the component of your steering that points further along where you
-- are already going is removed, and the rest is kept. You can still turn at
-- full authority. You just cannot add speed you have not got room for.
local function steer(velocity, want, accel, cap, mass)
	if want.Magnitude < 0.05 then return Vector3.zero end

	local dir   = want.Unit
	local speed = velocity.Magnitude

	if speed > cap and speed > 0.05 then
		local heading = velocity.Unit
		local along   = dir:Dot(heading)
		if along > 0 then
			dir = dir - heading * along
			if dir.Magnitude < 0.05 then return Vector3.zero end
			dir = dir.Unit
		end
	end

	return dir * (mass * accel)
end

function Momentum.new(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum  = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return nil end

	local self = setmetatable({}, Momentum)
	self.root        = root
	self.hum         = hum
	self.slide       = nil
	self.wasGrounded = true

	self.att        = Instance.new("Attachment")
	self.att.Name   = "MomentumHold"
	self.att.Parent = root

	self.force                     = Instance.new("VectorForce")
	self.force.Name                = "MomentumForce"
	self.force.Attachment0         = self.att
	self.force.ApplyAtCenterOfMass = true
	self.force.RelativeTo          = Enum.ActuatorRelativeTo.World
	self.force.Force               = Vector3.zero
	self.force.Parent              = root

	return self
end

-- rig may be nil. strafe is a flat world vector from A/D and is only read while
-- on a rope, because up there W and S are the cable.
function Momentum:Step(dt, rig, strafe, reelIn)
	local root, hum = self.root, self.hum
	if not root or not root.Parent or hum.Health <= 0 then
		-- Cleared rather than just abandoned. A force left set keeps being
		-- applied every frame by the engine, so an early return without this
		-- shoves the ragdoll around for as long as it lies there.
		if self.force and self.force.Parent then
			self.force.Force = Vector3.zero
		end
		self.slide = nil
		return
	end

	local mass     = root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity
	local gravity  = workspace.Gravity
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local force    = Vector3.zero

	if rig then
		-- ── On the rope ──────────────────────────────────────────────────────
		-- The bite: the first fraction of a second after a hook lands reels
		-- whether or not anything is held. A hook that attaches and then waits
		-- politely for input reads as a hook that missed.
		local pull = 0
		if os.clock() - rig.bornAt < CFG.BiteTime then
			pull = CFG.BiteForce
		elseif reelIn then
			pull = CFG.ReelForce
		end

		-- Through the same cap as the steering, which matters more than it
		-- looks: the rope limits how far you can be from the anchor and does
		-- nothing whatsoever about how fast you travel toward it. A long reel
		-- left uncapped builds a few hundred studs a second over a hundred
		-- studs of cable and arrives at the rock like a thrown brick.
		if pull > 0 then
			force += steer(velocity, rig.direction,
				gravity * pull, CFG.MaxSwingSpeed, mass)
		end

		force += steer(velocity, strafe or Vector3.zero,
			CFG.SwingControl, CFG.MaxSwingSpeed, mass)

	elseif not grounded then
		-- ── In the air ───────────────────────────────────────────────────────
		-- Full WASD here, read off MoveDirection, which is already
		-- camera-relative and already flat.
		force += steer(velocity, hum.MoveDirection,
			CFG.AirControl, CFG.MaxAirSpeed, mass)
	end

	-- ── Landing ──────────────────────────────────────────────────────────────
	-- Roblox clamps you to WalkSpeed the instant you touch down, which deletes
	-- the swing you just spent four seconds building and is the single biggest
	-- reason momentum systems feel sticky. This is the slide that gives a swing
	-- somewhere to go.
	if grounded and not self.wasGrounded then
		local horizontal = flat(velocity)
		if horizontal.Magnitude - hum.WalkSpeed > CFG.LandFloor then
			self.slide = {
				dir   = horizontal.Unit,
				speed = horizontal.Magnitude * CFG.LandKeep,
			}
		end
	end
	self.wasGrounded = grounded

	if self.slide then
		self.slide.speed *= math.exp(-CFG.LandDecay * dt)

		if self.slide.speed <= hum.WalkSpeed + 1 then
			-- Handed back to the Humanoid rather than braked. By here the slide
			-- is no faster than walking, so there is nothing left to preserve.
			self.slide = nil
		else
			-- Steerable, so a landing can be ridden instead of only endured.
			local move = hum.MoveDirection
			if move.Magnitude > 0.05 then
				local blended = self.slide.dir:Lerp(move.Unit, math.min(dt * 2.4, 1))
				if blended.Magnitude > 0.05 then
					self.slide.dir = blended.Unit
				end
			end

			local gap = self.slide.dir * self.slide.speed - flat(velocity)
			if gap.Magnitude > 0.05 then
				-- Capped, because the honest correction is gap/dt and on a
				-- stutter frame that is a number large enough to fire someone
				-- through a wall.
				local accel = math.min(gap.Magnitude / math.max(dt, 1 / 240),
					CFG.LandAssist)
				force += gap.Unit * (mass * accel)
			end
		end
	end

	self.force.Force = force
end

function Momentum:Destroy()
	if self.force then self.force:Destroy() end
	if self.att   then self.att:Destroy() end
	self.force, self.att, self.slide = nil, nil, nil
end

return Momentum
