local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local GearConfig   = require(ReplicatedStorage:WaitForChild("GearConfig"))
local Remotes     = require(script.Parent.Remotes)
local PlayerState = require(script.Parent.PlayerState)

-- ── Hazard service ───────────────────────────────────────────────────────────
-- Depth is gated by resistance, not by a level number. Go below a gate without
-- the gear and the layer starts taking you apart — which is the whole reason
-- crafting has a point.

local hazardState = Remotes.Event("HazardState")

-- ── Gate markers ─────────────────────────────────────────────────────────────
-- A hazard you cannot see is a hazard players think is a bug. Each gate gets a
-- translucent boundary spanning the mine, so breaking through the ceiling of a
-- layer is a visible event rather than a silent health drain.

local function buildGateMarkers()
	local mine = StrataConfig.Mine
	local folder = Instance.new("Folder")
	folder.Name   = "GateMarkers"
	folder.Parent = workspace

	for _, gate in ipairs(GearConfig.DepthGates) do
		local plane = Instance.new("Part")
		plane.Name         = "Gate_" .. gate.label
		plane.Size         = Vector3.new(mine.SizeX, 0.6, mine.SizeZ)
		plane.Position     = Vector3.new(0, gate.belowY, 0)
		plane.Anchored     = true
		plane.CanCollide   = false
		plane.CanQuery     = false
		plane.CanTouch     = false
		plane.CastShadow   = false
		plane.Material     = Enum.Material.Neon
		plane.Color        = Color3.fromRGB(196, 68, 48)
		plane.Transparency = 0.82
		plane.Parent       = folder
	end
end

buildGateMarkers()

local TICK = 0.5

-- [player] = the gate label currently hurting them, or nil
local active = {}

task.spawn(function()
	while task.wait(TICK) do
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				local gate = GearConfig.GateAt(root.Position.Y)
				local exposed = false

				if gate then
					local level = PlayerState.Resistance(player, gate.resistance)
					if level < gate.level then
						exposed = true
						humanoid:TakeDamage(gate.damage * TICK)
					end
				end

				local label = exposed and gate.label or nil
				if label ~= active[player] then
					active[player] = label
					hazardState:FireClient(player, exposed and {
						label   = gate.label,
						warning = gate.warning,
					} or nil)
				end
			elseif active[player] then
				active[player] = nil
				hazardState:FireClient(player, nil)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
end)

print("[HazardService] online")
