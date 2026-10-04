#!/usr/bin/env bash
# Runs the dig-site geometry checks outside Roblox.
#
#   ./tools/sitecheck/run.sh
#
# Builds 720 sites across every layer and difficulty tier and measures the
# things that are invisible in Studio until you are standing in them: whether
# any gallery has broken into sealed pockets, how big the halls came out, how
# steep the tunnels are, and what the carve is going to cost in voxels.
#
# The one that matters is SEALED BREAKS. It must be 0. A gallery is carved as a
# run of overlapping balls, and any pair further apart than their two radii
# leaves rock between them — a tunnel you can see down and cannot walk.
set -euo pipefail

cd "$(dirname "$0")/../.."
LUAU="${LUAU:-$HOME/.rokit/bin/luau.exe}"
OUT="$(mktemp -t sitecheck.XXXXXX.lua)"
trap 'rm -f "$OUT"' EXIT

# StrataConfig and DigSite both open with a ReplicatedStorage require, which has
# no meaning outside Roblox. Those lines come out and the modules are inlined as
# IIFEs against the stand-ins in prelude.lua.
{
	cat tools/sitecheck/prelude.lua
	echo
	echo "local StrataConfig = (function()"
	grep -v "GetService\|WaitForChild" src/shared/StrataConfig.lua
	echo "end)()"
	echo
	echo "local DigSite = (function()"
	grep -v "GetService\|WaitForChild" src/shared/DigSite.lua
	echo "end)()"
	cat tools/sitecheck/checks.lua
} > "$OUT"

"$LUAU" "$OUT"
