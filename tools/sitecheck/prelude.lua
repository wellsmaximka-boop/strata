-- Minimal Roblox stand-ins, enough to run StrataConfig and DigSite offline.
local V = {}
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
local VM = {
	Lerp = function(self, o, a)
		return vec(self.X + (o.X - self.X) * a, self.Y + (o.Y - self.Y) * a,
			self.Z + (o.Z - self.Z) * a)
	end,
}
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m < 1e-9 then return vec(0, 0, 0) end
		return vec(t.X / m, t.Y / m, t.Z / m)
	end
	return VM[k]
end
Vector3 = { new = vec, zero = vec(0, 0, 0) }

Color3 = {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
	new     = function(r, g, b) return { R = r, G = g, B = b } end,
	fromHSV = function(h, s, v) return { H = h, S = s, V = v } end,
}
Enum = setmetatable({}, { __index = function(t, k)
	local pool = setmetatable({}, { __index = function(p, n)
		local e = { Name = n, EnumType = k, Value = 0 }
		p[n] = e
		return e
	end })
	t[k] = pool
	return pool
end })
Vector2        = { new = function(x, y) return { X = x, Y = y } end }
UDim2          = { new = function(...) return { ... } end }
UDim           = { new = function(...) return { ... } end }
local CF = {}
CF.__mul   = function(a, b) return setmetatable({ a, b }, CF) end
CF.__index = function() return 0 end
local function cf(...) return setmetatable({ ... }, CF) end
CFrame = { new = cf, Angles = cf, fromEulerAnglesXYZ = cf, lookAt = cf }
NumberRange    = { new = function(...) return { ... } end }
ColorSequence  = { new = function(...) return { ... } end }
ColorSequenceKeypoint = { new = function(...) return { ... } end }
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
TweenInfo      = { new = function(...) return { ... } end }
Region3        = { new = function(...) return { ... } end }
