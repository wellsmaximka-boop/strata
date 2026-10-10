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

# Every first-level Hud field the source actually reads, so that renaming one
# in the config is caught here rather than by a nil landing in an addition.
#
# This has now happened twice. Card.X survived a move because nothing looked
# for it, and Hud.Width survived a rename and would have shipped a hard error
# on the line that positions every screen in the game — found by a grep that
# happened to be run for another reason. freevars.sh cannot see these: HUD is
# bound, and it does not know what is inside it.
FIELDS=$(
	sed -E 's/--.*$//' $(find src -name '*.lua') \
		| grep -ohE '\b(HUD|StrataConfig\.Hud)\.[A-Za-z_][A-Za-z0-9_]*' \
		| sed -E 's/.*\.//' \
		| sort -u \
		| tr '\n' ' '
)

{
	cat tools/sitecheck/prelude.lua
	echo "local USED_HUD_FIELDS = \"$FIELDS\""
	echo
	echo "local StrataConfig = (function()"
	grep -v "GetService\|WaitForChild" src/shared/StrataConfig.lua
	echo "end)()"
	cat <<'LUA'

local H = StrataConfig.Hud

-- Declared up here because the first check now runs before the layout tables
-- are built, and incrementing a nil is its own small outage.
local bad = 0

-- Checked at several window sizes, because the column is a share of the width
-- now and the thing that went wrong last time only went wrong on a small one:
-- a flat 326 is a fifth of a big screen and better than a quarter of a 1216,
-- and nobody notices until they see a screenshot from the smaller machine.
local VIEWPORTS = {
	{ 2560, 1440 },
	{ 1920, 1080 },
	{ 1600,  900 },
	{ 1366,  768 },
	{ 1216,  970 },
	{  960,  760 },
	{  848,  676 },   -- small windows: where the clamp used to take over
	{ 1280,  720 },
}

print("")
print("-- column width against the window --")
print(("  %-12s %7s %7s %8s"):format("window", "column", "share", "nav row"))
for _, v in ipairs(VIEWPORTS) do
	local m = StrataConfig.HudMetrics(v[1], v[2])
	print(("  %4dx%-7d %7d %6d%% %4d (list %d)"):format(
		v[1], v[2], m.Width,
		math.floor(m.Width / v[1] * 100 + 0.5),
		m.Nav.RowH, m.Nav.H_total))
end
local stack = StrataConfig.HudMetrics(1216, 970)
-- A floor that is reached on a window people actually use is not a floor, it
-- is the answer — and it hands every one of those windows a column at the
-- wrong proportion while the share sits in the config looking correct. That is
-- what shipped twice. Only the bottom end is checked: a wide monitor hitting
-- the ceiling is deliberate, since past a point more width should not buy a
-- wider slab.
print("")
print("-- is the share actually in charge --")
local pinned = 0
for _, v in ipairs(VIEWPORTS) do
	local m = StrataConfig.HudMetrics(v[1], v[2])
	if m.Width <= H.WidthMin and v[1] * H.WidthShare < H.WidthMin then
		print(("  %dp: the minimum is winning, column is %d%% not %d%%")
			:format(v[1],
				math.floor(m.Width / v[1] * 100 + 0.5),
				math.floor(H.WidthShare * 100 + 0.5)))
		pinned += 1
	end
end
print(("  %d window(s) pinned to the minimum"):format(pinned))
bad += pinned

print("")
print("-- the rest, solved for 1216 wide --")

-- Name, the key its top is stored under, height. The nav's two differ: Nav
-- holds the row metrics and NavY holds where the list starts, and reading the
-- table where the number was meant is how this check first fell over.
local rows = {
	{ "Card",     "Card",     H.Card.H },
	{ "Strength", "Strength", H.Strength.H },
	{ "Pack",     "Pack",     H.Pack.H },
	{ "Nav",      "NavY",     stack.Nav.H_total },
}


print("")
print("-- left column --")
print(("  %-10s %6s %6s %6s"):format("row", "top", "height", "bottom"))
for _, row in ipairs(rows) do
	local name, key, height = row[1], row[2], row[3]
	local top = stack[key]
	if type(top) ~= "number" then
		print(("  %-10s MISSING FROM HudMetrics (key %s)"):format(name, key))
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
	local aboveName, aboveKey, aboveH = rows[i - 1][1], rows[i - 1][2], rows[i - 1][3]
	local hereName, hereKey           = rows[i][1], rows[i][2]
	local aboveEnd = (stack[aboveKey] or 0) + aboveH
	local hereTop  = stack[hereKey] or 0
	if hereTop < aboveEnd then
		print(("  %s starts %d past the bottom of %s")
			:format(hereName, aboveEnd - hereTop, aboveName))
		clashes += 1
	end
end
print(("  %d overlapping rows"):format(clashes))
bad += clashes

-- Fit, per window, because the nav rows are solved against the height now and
-- a stack measured at one size says nothing about another. The bottom-left
-- corner belongs to the run manifest, so the column has to stop above that and
-- not merely above the bottom of the screen.
print("")
print("-- fit, at each window, against the manifest in the corner below --")
local floor = H.Manifest.Bottom + H.Manifest.H + H.Gap
local tight = 0
for _, v in ipairs(VIEWPORTS) do
	local m     = StrataConfig.HudMetrics(v[1], v[2])
	local spare = v[2] - floor - m.Bottom
	local verdict = "ok"
	if m.Nav.Cramped or spare < 0 then
		verdict = "OVERFLOWS"
		tight += 1
	elseif spare < 24 then
		verdict = "tight"
	end
	print(("  %4dx%-5d  column ends %4d, %4d spare   %s")
		:format(v[1], v[2], m.Bottom, spare, verdict))
end
bad += tight

-- The column is one width. An element that sets its own is the thing that
-- made it look like three unrelated panels rather than a column.
print("")
print("-- nav rows stay usable --")
local squashed = 0
for _, v in ipairs(VIEWPORTS) do
	local m = StrataConfig.HudMetrics(v[1], v[2])
	-- A row has to hold an icon plate with air around it. Below that the list
	-- stops being a list of buttons and becomes a stack of lines.
	if m.Nav.RowH < m.Nav.Icon + 6 then
		print(("  %dx%d: rows are %d tall for a %d icon")
			:format(v[1], v[2], m.Nav.RowH, m.Nav.Icon))
		squashed += 1
	end
end
print(("  rows clear the icon at %d of %d sizes")
	:format(#VIEWPORTS - squashed, #VIEWPORTS))
bad += squashed

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
-- Fields the source reads that the config does not have.
print("")
print("-- config fields the game reads --")
local missing = {}
for field in USED_HUD_FIELDS:gmatch("%S+") do
	if H[field] == nil then
		table.insert(missing, field)
	end
end
if #missing > 0 then
	for _, field in ipairs(missing) do
		print(("  Hud.%s is read in src/ and does not exist"):format(field))
	end
	bad += #missing
else
	print(("  all %d resolve"):format(#(USED_HUD_FIELDS:split(" ")) - 1))
end

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
