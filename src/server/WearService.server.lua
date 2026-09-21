local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrataConfig = require(ReplicatedStorage:WaitForChild("StrataConfig"))
local ItemModels   = require(ReplicatedStorage:WaitForChild("ItemModels"))
local PlayerState = require(script.Parent.PlayerState)

-- ── Wear service ─────────────────────────────────────────────────────────────
-- Equipped armour, welded onto the character by the server. It has to be the
-- server, because anything a client builds for itself only that client sees —
-- and armour is the thing other players are meant to notice.
--
-- Rebuilt whenever a player's state is pushed, but only if what they have on
-- actually changed, so a sale or a pickup costs nothing here.

local FOLDER = "StrataArmour"

-- [player] = sorted list of the gear ids currently attached
local wornSignature = {}

local function signatureOf(equipped, extra)
	local ids = {}
	for _, id in pairs(equipped) do table.insert(ids, id) end
	table.sort(ids)
	return table.concat(ids, ",") .. "|" .. (extra or "")
end

-- Hats and hair poke straight through a helmet, so while one is worn they are
-- hidden, and restored exactly as they were when it comes off.
local function hideHeadAccessories(character, hide)
	local head = character:FindFirstChild("Head")
	if not head then return end

	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local weld   = handle and handle:FindFirstChild("AccessoryWeld")
			if weld and (weld.Part0 == head or weld.Part1 == head) then
				if hide then
					if handle:GetAttribute("StrataShownAt") == nil then
						handle:SetAttribute("StrataShownAt", handle.Transparency)
					end
					handle.Transparency = 1
				elseif handle:GetAttribute("StrataShownAt") ~= nil then
					handle.Transparency = handle:GetAttribute("StrataShownAt")
					handle:SetAttribute("StrataShownAt", nil)
				end
			end
		end
	end
end

-- The backpack is worn like armour, so it is welded here too. It used to be
-- built on the client, which meant only you could see it — and if anything went
-- wrong in that one script it simply was not there. On the server it either
-- exists for everybody or the failure is visible in the log.
local function packSpec(player)
	local s = PlayerState.Get(player)
	return {
		tier  = s.owned.PackI and 2 or 1,
		light = s.lightLevel or 1,
	}
end

local function attachPack(player, character, folder)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then return end

	local spec = packSpec(player)
	local model, body = ItemModels.Backpack(spec.tier, spec.light)

	local grip = character:FindFirstChild("UpperTorso")
		and StrataConfig.Grip.PackR15
		or  StrataConfig.Grip.PackR6

	model:PivotTo(torso.CFrame * grip)

	local weld = Instance.new("Weld")
	weld.Part0  = torso
	weld.Part1  = body
	weld.C0     = grip
	weld.Parent = body

	model.Parent = folder
end

local function dress(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local equipped  = PlayerState.Get(player).equipped
	local spec      = packSpec(player)
	local signature = signatureOf(equipped, ("pack%d/%d"):format(spec.tier, spec.light))
	local folder    = character:FindFirstChild(FOLDER)

	-- Nothing changed and the armour is still on this body: leave it alone.
	-- A respawn gives a new body with no folder, so it always rebuilds.
	if folder and wornSignature[player] == signature then return end

	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name   = FOLDER
	folder.Parent = character
	wornSignature[player] = signature

	local helmetOn = false

	for _, gearId in pairs(equipped) do
		for _, spec in ipairs(ItemModels.WornPieces(gearId)) do
			local limb = ItemModels.FindLimb(character, spec.limb)
			if limb then
				local model = spec.build(limb.Size)
				model:PivotTo(limb.CFrame)

				local weld = Instance.new("Weld")
				weld.Part0  = limb
				weld.Part1  = model.PrimaryPart
				weld.C0     = CFrame.new()
				weld.Parent = model.PrimaryPart

				model.Parent = folder
				if spec.limb == "Head" then helmetOn = true end
			end
		end
	end

	attachPack(player, character, folder)
	hideHeadAccessories(character, helmetOn)
end

PlayerState.Changed.Event:Connect(dress)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait for the limbs to exist before welding anything to them
		character:WaitForChild("HumanoidRootPart", 10)
		character:WaitForChild("Head", 10)
		task.wait(0.3)
		dress(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	wornSignature[player] = nil
end)

print("[WearService] online")
