
-- ── Checks ───────────────────────────────────────────────────────────────────
local CFG = StrataConfig.Site

local breaks, segs, worstOver = 0, 0, -math.huge
local chokeRuns, chokeMin, driftCount = 0, math.huge, 0
local halls, voids, voidH, voxels, grades = {}, 0, {}, {}, {}
local sites = 0

local function note(t, v) t[#t + 1] = v end

for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
	for tier = 1, 4 do
		for s = 1, 60 do
			sites += 1
			local site = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY)

			local vol = 0
			for _, c in ipairs(site.chambers) do
				note(halls, c.radius)
				if c.void then
					voids += 1
					note(voidH, (c.radius / c.flatten) * 2)
				end
				for _, b in ipairs(c.blobs) do
					vol += (4 / 3) * math.pi * b.radius ^ 3
				end
			end

			for _, d in ipairs(site.drifts) do
				driftCount += 1
				local rs = d.radii
				if rs then
					local lo = math.huge
					for _, r in ipairs(rs) do lo = math.min(lo, r) end
					if lo < d.radius - 0.5 then
						chokeRuns += 1
						chokeMin = math.min(chokeMin, lo)
					end
				end

				for i = 1, #d.points - 1 do
					segs += 1
					local gap = (d.points[i + 1] - d.points[i]).Magnitude
					local r1  = rs and rs[i] or d.radius
					local r2  = rs and rs[i + 1] or d.radius
					-- Two balls leave rock between them once their centres are
					-- further apart than the two radii together. Measured
					-- against the pair, not against a nominal width.
					if gap >= r1 + r2 then breaks += 1 end
					worstOver = math.max(worstOver, gap - (r1 + r2))
					vol += (4 / 3) * math.pi * r1 ^ 3 * 0.34
				end

				local run = math.sqrt((d.b.X - d.a.X) ^ 2 + (d.b.Z - d.a.Z) ^ 2)
				if run > 1 then
					note(grades, math.deg(math.atan(math.abs(d.b.Y - d.a.Y) / run)))
				end
			end
			note(voxels, vol / 64)
		end
	end
end

local function stats(t, label, unit)
	table.sort(t)
	local sum = 0
	for _, v in ipairs(t) do sum += v end
	print(("  %-12s min %8.1f   median %8.1f   p95 %8.1f   max %8.1f %s")
		:format(label, t[1], t[math.ceil(#t / 2)], t[math.ceil(#t * 0.95)],
			t[#t], unit or ""))
end

print(("\n== %d sites, %d galleries =="):format(sites, driftCount))

print("\n-- galleries: are they open? --")
print(("  %d segments, SEALED BREAKS: %d"):format(segs, breaks))
print(("  closest any pair came to breaking: %.2f studs of spare overlap")
	:format(-worstOver))
print(("  galleries that pinch: %d of %d (%.0f%%), narrowest throat %.1f studs")
	:format(chokeRuns, driftCount, chokeRuns / driftCount * 100, chokeMin))

print("\n-- halls --")
stats(halls, "radius", "studs")
print(("  voids cut: %d of %d sites (%.0f%%)"):format(voids, sites, voids / sites * 100))
if #voidH > 0 then stats(voidH, "void height", "studs") end

print("\n-- carve cost --")
stats(voxels, "voxels/site")

print("\n-- gallery steepness --")
stats(grades, "degrees")
local over = 0
for _, g in ipairs(grades) do if g > 45 then over += 1 end end
print(("  over 45 degrees: %.2f%%"):format(over / #grades * 100))

-- Did raising the floor on hall size cost sites their halls?
local counts, vaults = {}, 0
for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
	for tier = 1, 4 do
		for s = 1, 60 do
			local site = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY)
			note(counts, #site.chambers)
			for _, c in ipairs(site.chambers) do
				if c.role == "vault" then vaults += 1 end
			end
		end
	end
end
print("\n-- halls per site --")
stats(counts, "chambers")
local short = 0
for _, c in ipairs(counts) do if c < 4 then short += 1 end end
print(("  sites with fewer than 4 halls: %d of %d"):format(short, #counts))
print(("  sites with a vault: %d of %d"):format(vaults, #counts))

-- Lights per site. Lamps are strung down galleries every LampEvery studs, and
-- halls got bigger, so this is the number that decides whether a dark cave is
-- also a cheap one.
local lamps = {}
for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
	for tier = 1, 4 do
		for s = 1, 20 do
			local site = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY)
			local n = 0
			for _, d in ipairs(site.drifts) do
				local run = 0
				for i = 1, #d.points - 1 do
					run += (d.points[i + 1] - d.points[i]).Magnitude
				end
				n += math.floor(run / CFG.LampEvery)
			end
			note(lamps, n)
		end
	end
end
print("\n-- gallery lamps per site --")
stats(lamps, "lamps")

-- Grain: how much it adds, and whether a bulge is ever big enough to be an
-- obstacle rather than a surface.
local grains, biggest = {}, 0
local extra = 0
for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
	for tier = 1, 4 do
		for s = 1, 20 do
			local site = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY)
			local n, vol = 0, 0
			for _, c in ipairs(site.chambers) do
				n += #c.rough
				for _, g in ipairs(c.rough) do
					biggest = math.max(biggest, g.radius)
					vol += (4 / 3) * math.pi * g.radius ^ 3
				end
			end
			note(grains, n)
			extra = math.max(extra, vol / 64)
		end
	end
end
print("\n-- grain --")
stats(grains, "per site")
print(("  biggest bulge radius: %.1f studs"):format(biggest))
print(("  worst extra carve: %.0f voxels (vs ~450k for a site)"):format(extra))

-- The master cavern: is its floor the station deck? If it sits below, you walk
-- out of the cage into open air; if above, the cage is buried in rock.
print("\n-- master cavern --")
for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
		- StrataConfig.Descent.LandingHalf + 1.4
	local worst, rad, hgt = 0, 0, 0
	for tier = 1, 4 do
		for s = 1, 40 do
			local site = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY)
			local m = site.chambers[1]
			if m then
				local v = m.radius / m.flatten
				worst = math.max(worst, math.abs((m.centre.Y - v) - hubY))
				rad, hgt = m.radius, v * 2
			end
		end
	end
	print(("  %-11s deck %7.1f   master r=%5.1f (%5.0f across, %5.0f tall)   floor off deck by %.2f")
		:format(stratum.name, hubY, rad, rad * 2, hgt, worst))
end
