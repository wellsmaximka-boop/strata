local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Sign fade ────────────────────────────────────────────────────────────────
-- The camp's signs tell you what a building is. That is a question you ask
-- about the building in front of you, and the signs were answering it for
-- every building at once: stand anywhere near the middle of the deck and the
-- depot, the forge, the pick works, the lift and the shaft are all in range
-- together. Four labels for places you are not at, two of them landing on top
-- of the HUD, and the one you are actually walking towards no louder than the
-- rest.
--
-- Cutting the draw distance fixes the clutter and breaks the signs: you can no
-- longer find the depot from across the camp, which is the only reason it has
-- a sign. So they all stay drawn and the far ones go quiet instead. The one in
-- front of you is solid, the rest are ghosts you can still navigate by.
--
-- One number does it, because the server hangs every sign's contents off a
-- CanvasGroup — fading twelve descendants individually would cost more than
-- the signs do.

local NEAR  = 34    -- fully solid inside this
local FAR   = 150   -- gone by here
local FLOOR = 0.86  -- how faint a distant sign gets, never quite nothing
local EVERY = 0.12  -- seconds between passes; they do not move

local player = Players.LocalPlayer

local signs = {}

local function collect(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("CanvasGroup") and d.Name == "Fade" and d.Parent:IsA("BillboardGui") then
			table.insert(signs, d)
		end
	end
end

task.spawn(function()
	local camp = workspace:WaitForChild("SurfaceCamp", 30)
	if not camp then
		warn("[SignFade] no SurfaceCamp; signs will not fade")
		return
	end

	collect(camp)

	-- The camp is built in pieces and some of it lands after this runs, so
	-- keep watching rather than taking one census and trusting it.
	camp.DescendantAdded:Connect(function(d)
		if d:IsA("CanvasGroup") and d.Name == "Fade" and d.Parent:IsA("BillboardGui") then
			table.insert(signs, d)
		end
	end)

	print(("[SignFade] watching %d signs"):format(#signs))
end)

local since = 0

RunService.Heartbeat:Connect(function(dt)
	since += dt
	if since < EVERY then return end
	since = 0

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local here = root.Position

	for i = #signs, 1, -1 do
		local fade = signs[i]
		if not fade.Parent then
			-- A sign whose building has gone. Swapped with the last entry
			-- rather than removed in place, so this stays cheap.
			signs[i] = signs[#signs]
			table.remove(signs)
		else
			local gui = fade.Parent
			local at  = gui.Adornee or gui.Parent
			if at and at:IsA("BasePart") then
				local d = (at.Position - here).Magnitude
				local t = math.clamp((d - NEAR) / (FAR - NEAR), 0, 1)
				-- Squared, so the fade holds on near the sign and falls away
				-- quickly once you have left it. Linear reads as every sign
				-- being half there at once, which is the thing being fixed.
				fade.GroupTransparency = t * t * FLOOR
			end
		end
	end
end)

print("[SignFade] ready")
