-- ── Remotes ──────────────────────────────────────────────────────────────────
-- One place that owns the remotes folder, so services never race each other to
-- create it and never have to WaitForChild on a sibling's work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = ReplicatedStorage:FindFirstChild("MineRemotes")
if not folder then
	folder      = Instance.new("Folder")
	folder.Name = "MineRemotes"
	folder.Parent = ReplicatedStorage
end

Remotes.Folder = folder

function Remotes.Event(name)
	local existing = folder:FindFirstChild(name)
	if existing then return existing end

	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = folder
	return r
end

return Remotes
