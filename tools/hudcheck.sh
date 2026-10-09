#!/usr/bin/env bash
#
# Checks the left-hand HUD column fits on a screen and does not overlap itself.
#
# The column is four stacked elements whose positions used to be hand-written
# constants in two different files. That arrangement cannot be verified by
# reading it: you find out a panel is sitting on top of another one by looking
# at a screenshot, which means somebody has to be at a keyboard with the game
# running, and the person who can see it is never the person who moved it.
#
# So: run the real StrataConfig against the same stand-ins the site checks use,
# ask it for the stack it computed, and assert the two things that actually go
# wrong — rows overlapping, and the column running off the bottom of a short
# window.
#
#   ./tools/hudcheck.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
LUAU="${LUAU:-$HOME/.rokit/bin/luau.exe}"
OUT="$(mktemp -t hudcheck.XXXXXX.lua)"
trap 'rm -f "$OUT"' EXIT

{
	cat tools/sitecheck/prelude.lua
	echo
	echo "local StrataConfig = (function()"
	grep -v "GetService\|WaitForChild" src/shared/StrataConfig.lua
	echo "end)()"
	cat <<'LUA'

local H     = StrataConfig.Hud
local stack = StrataConfig.HudStack()

local rows = {
	{ "Card",     H.Card.H },
	{ "Strength", H.Strength.H },
	{ "Pack",     H.Pack.H },
	{ "Grid",     H.Button.H * H.Button.Rows + H.Button.Gap * (H.Button.Rows - 1) },
}

local bad = 0

print("")
print("-- left column --")
print(("  %-10s %6s %6s %6s"):format("row", "top", "height", "bottom"))
for _, row in ipairs(rows) do
	local name, height = row[1], row[2]
	local top = stack[name]
	if not top then
		print(("  %-10s MISSING FROM HudStack"):format(name))
		bad += 1
	else
		print(("  %-10s %6d %6d %6d"):format(name, top, height, top + height))
	end
end
print(("  %-10s %6s %6s %6d"):format("total", "", "", stack.Bottom))

-- Overlap. Each row has to start at or after the end of the one above it.
print("")
print("-- overlap --")
local clashes = 0
for i = 2, #rows do
	local aboveName, aboveH = rows[i - 1][1], rows[i - 1][2]
	local hereName          = rows[i][1]
	local aboveEnd = (stack[aboveName] or 0) + aboveH
	local hereTop  = stack[hereName] or 0
	if hereTop < aboveEnd then
		print(("  %s starts %d past the bottom of %s")
			:format(hereName, aboveEnd - hereTop, aboveName))
		clashes += 1
	end
end
print(("  %d overlapping rows"):format(clashes))
bad += clashes

-- Fit. The bottom-left corner belongs to the run manifest now, so the column
-- has to stop above it as well as above the bottom of the window.
print("")
print("-- fit, against the manifest in the corner below --")
local floor = H.Manifest.Bottom + H.Manifest.H + H.Gap
local tight = 0
for _, height in ipairs({ 1080, 900, 864, 768, 720 }) do
	local room  = height - floor
	local spare = room - stack.Bottom
	local verdict = "ok"
	if spare < 0 then
		verdict = "OVERFLOWS"
		tight += 1
	elseif spare < 40 then
		verdict = "tight"
	end
	print(("  %4dp high   %4d spare   %s"):format(height, spare, verdict))
end
bad += tight

-- The column is one width. An element that sets its own is the thing that
-- made it look like three unrelated panels rather than a column.
print("")
print("-- width --")
print(("  column %d, buttons %d across = %d"):format(
	H.Width,
	H.Button.Columns,
	H.Button.W * H.Button.Columns + H.Button.Gap * (H.Button.Columns - 1)))
local gridW = H.Button.W * H.Button.Columns + H.Button.Gap * (H.Button.Columns - 1)
if gridW > H.Width then
	print(("  button grid is %d wider than the column"):format(gridW - H.Width))
	bad += 1
end

-- The bottom edge, built by three different scripts. Same failure, other axis.
print("")
print("-- bottom edge, up from the floor --")
local B   = H.Bottom
local bot = StrataConfig.HudBottom()
print(("  %-14s %6s %6s %6s"):format("row", "bottom", "height", "top"))
local reach = 0
for _, row in ipairs(B.Order) do
	local r = bot[row.id]
	print(("  %-14s %6d %6d %6d"):format(row.id, r.y, r.h, r.y + r.h))
	reach = math.max(reach, r.y + r.h)
end

local botClashes = 0
for i = 2, #B.Order do
	local below = bot[B.Order[i - 1].id]
	local here  = bot[B.Order[i].id]
	if here.y < below.y + below.h then
		print(("  %s overlaps %s by %d")
			:format(B.Order[i].id, B.Order[i - 1].id, below.y + below.h - here.y))
		botClashes += 1
	end
end
print(("  %d overlapping rows, %d tall in total"):format(botClashes, reach))
bad += botClashes

-- Not checked against the left column, deliberately. This stack is centred and
-- the column is pinned sixteen pixels from the left edge, so the two never
-- share a pixel however short the window gets. The first version of this check
-- compared their heights, reported a collision at 864p, and was wrong: what
-- the column actually has to clear is the run manifest below it, which is the
-- test further up.
--
-- What this stack owes is restraint. It is the middle of the screen and the
-- game is behind it.
print("")
print("-- how much of the view the bottom edge takes --")
for _, height in ipairs({ 1080, 720 }) do
	local share   = reach / height
	local verdict = "ok"
	if share > 0.4 then
		verdict = "TOO TALL"
		bad += 1
	elseif share > 0.3 then
		verdict = "tight"
	end
	print(("  %4dp high   %2d%% of the screen   %s")
		:format(height, math.floor(share * 100 + 0.5), verdict))
end

print("")
if bad > 0 then
	-- Not os.exit: the luau CLI does not have it. The shell greps for this.
	print(("HUDCHECK-FAILED: %d problem(s)"):format(bad))
else
	print("clean")
end
LUA
} > "$OUT"

REPORT="$("$LUAU" "$OUT")"
printf '%s\n' "$REPORT"

if printf '%s' "$REPORT" | grep -q "HUDCHECK-FAILED"; then
	exit 1
fi
