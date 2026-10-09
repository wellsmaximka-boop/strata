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

print("")
if bad > 0 then
	print(("FAILED: %d problem(s)"):format(bad))
	os.exit(1)
end
print("clean")
LUA
} > "$OUT"

"$LUAU" "$OUT"
