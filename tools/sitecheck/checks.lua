
-- ── Checks ───────────────────────────────────────────────────────────────────
-- Everything measured here is something that is invisible in Studio until you
-- are standing in it, and most of it has been a real bug at least once.

local CFG = StrataConfig.Site

local function note(t, v) t[#t + 1] = v end

local function stats(t, label, unit)
	if #t == 0 then print(("  %-12s (none)"):format(label)) return end
	table.sort(t)
	local sum = 0
	for _, v in ipairs(t) do sum += v end
	print(("  %-12s min %8.1f   median %8.1f   p95 %8.1f   max %8.1f %s")
		:format(label, t[1], t[math.ceil(#t / 2)], t[math.ceil(#t * 0.95)],
			t[#t], unit or ""))
end

local function sweep(perSite)
	for li, stratum in ipairs(StrataConfig.Strata) do
		local hubY = StrataConfig.LandingY(stratum)
			- StrataConfig.Descent.LandingHalf + 1.4
		for tier = 1, 4 do
			for s = 1, 40 do
				perSite(DigSite.Build(li * 100000 + tier * 7777 + s * 131,
					stratum, tier, hubY), stratum, hubY)
			end
		end
	end
end

-- ── Galleries ────────────────────────────────────────────────────────────────
-- A gallery is carved as a run of overlapping balls. Any pair further apart
-- than their two radii leaves rock between them: a tunnel you can see down and
-- cannot walk. This has broken twice and is the first thing checked.

local segs, breaks, slack = 0, 0, math.huge
local chokeRuns, drifts, narrowest = 0, 0, math.huge
local halls, voids, voidH, voxels, grades, lamps = {}, 0, {}, {}, {}, {}
local chambers, sites = {}, 0

sweep(function(site)
	sites += 1
	local vol, lamp = 0, 0
	note(chambers, #site.chambers)

	for _, c in ipairs(site.chambers) do
		note(halls, c.radius)
		if c.void then
			voids += 1
			note(voidH, (c.radius / c.flatten) * 2)
		end
		for _, b in ipairs(c.blobs) do vol += (4 / 3) * math.pi * b.radius ^ 3 end
		for _, g in ipairs(c.rough or {}) do vol += (4 / 3) * math.pi * g.radius ^ 3 end
	end

	for _, d in ipairs(site.drifts) do
		drifts += 1
		local rs, run = d.radii, 0
		if rs then
			local lo = math.huge
			for _, r in ipairs(rs) do lo = math.min(lo, r) end
			if lo < d.radius - 0.5 then
				chokeRuns += 1
				narrowest = math.min(narrowest, lo)
			end
		end

		for i = 1, #d.points - 1 do
			segs += 1
			local gap = (d.points[i + 1] - d.points[i]).Magnitude
			local r1  = rs and rs[i] or d.radius
			local r2  = rs and rs[i + 1] or d.radius
			if gap >= r1 + r2 then breaks += 1 end
			slack = math.min(slack, (r1 + r2) - gap)
			vol  += (4 / 3) * math.pi * r1 ^ 3 * 0.34
			run  += gap
		end
		lamp += math.floor(run / CFG.LampEvery)

		local across = math.sqrt((d.b.X - d.a.X) ^ 2 + (d.b.Z - d.a.Z) ^ 2)
		if across > 1 then
			note(grades, math.deg(math.atan(math.abs(d.b.Y - d.a.Y) / across)))
		end
	end

	note(voxels, vol / 64)
	note(lamps, lamp)
end)

print(("\n== %d sites, %d galleries =="):format(sites, drifts))

print("\n-- galleries: are they open? --")
print(("  %d segments, SEALED BREAKS: %d"):format(segs, breaks))
print(("  tightest pair still had %.2f studs of overlap to spare"):format(slack))
print(("  galleries that pinch: %d of %d (%.0f%%), narrowest throat %.1f studs")
	:format(chokeRuns, drifts, chokeRuns / drifts * 100, narrowest))

print("\n-- halls --")
stats(halls, "radius", "studs")
stats(chambers, "per site")
print(("  voids cut: %d of %d sites (%.0f%%)"):format(voids, sites, voids / sites * 100))
stats(voidH, "void height", "studs")

print("\n-- cost --")
stats(voxels, "voxels/site")
stats(lamps, "lamps/site")

print("\n-- gallery steepness --")
stats(grades, "degrees")

-- ── The master cavern ────────────────────────────────────────────────────────
-- Its floor has to be the station deck. Anywhere else and you step off the cage
-- into open air, or the cage is buried in rock.

print("\n-- master cavern --")
for li, stratum in ipairs(StrataConfig.Strata) do
	local hubY = StrataConfig.LandingY(stratum)
		- StrataConfig.Descent.LandingHalf + 1.4
	local off, rad, hgt = 0, 0, 0
	for tier = 1, 4 do
		for s = 1, 20 do
			local m = DigSite.Build(li * 100000 + tier * 7777 + s * 131,
				stratum, tier, hubY).chambers[1]
			if m then
				local v = m.radius / m.flatten
				off = math.max(off, math.abs((m.centre.Y - v) - hubY))
				rad, hgt = m.radius, v * 2
			end
		end
	end
	print(("  %-11s deck %7.1f   r=%5.1f (%4.0f across, %4.0f tall)   floor off deck by %.2f")
		:format(stratum.name, hubY, rad, rad * 2, hgt, off))
end

-- ── Terraces ─────────────────────────────────────────────────────────────────
-- A slab whose underside is above the floor at that offset is a platform
-- hanging in clear air.

local slabs, floating = 0, 0
sweep(function(site)
	for _, c in ipairs(site.chambers) do
		local v = c.radius / c.flatten
		for _, sh in ipairs(c.shelves) do
			slabs += 1
			local d = math.sqrt(sh.offset.X ^ 2 + sh.offset.Z ^ 2) / math.max(c.radius, 1)
			local under = -v * math.sqrt(math.max(1 - d * d, 0))
			if sh.offset.Y - sh.size.Y * 0.5 > under then floating += 1 end
		end
	end
end)
print("\n-- terraces --")
print(("  %d slabs, FLOATING: %d"):format(slabs, floating))

-- ── Holes you cannot climb out of ────────────────────────────────────────────
-- Only blobs tagged as a pit or an alcove count. A hall body is itself a cluster
-- of spheres and its floor is uneven on purpose, so a core blob dipping below
-- the nominal ellipsoid is the floor, not a shaft.
--
-- JumpHeight is 7.2, so anything deeper needs a stair, and a tread rising more
-- than that is not a way out.

local holes, deepest, worstRise, trapped = 0, 0, 0, 0
sweep(function(site)
	for _, c in ipairs(site.chambers) do
		local v, stairs = c.radius / c.flatten, c.ramps or {}

		for _, b in ipairs(c.blobs) do
			if b.kind then
				local below = (-v) - (b.offset.Y - b.radius)
				if below > 2 then
					holes  += 1
					deepest = math.max(deepest, below)
					if below > 7.2 and #stairs == 0 then trapped += 1 end
				end
			end
		end

		for i = 2, #stairs do
			if stairs[i].stair == stairs[i - 1].stair then
				worstRise = math.max(worstRise,
					math.abs(stairs[i - 1].offset.Y - stairs[i].offset.Y))
			end
		end
	end
end)

print("\n-- holes in the floor --")
print(("  %d cut, deepest %.0f studs below the hall floor"):format(holes, deepest))
print(("  worst rise between stair treads: %.1f studs (jump height 7.2)")
	:format(worstRise))
print(("  deeper than a jump with NO stair: %d"):format(trapped))
