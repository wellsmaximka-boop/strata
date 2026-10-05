#!/usr/bin/env bash
#
# Lists every name a UI module uses that it never declares and never receives.
#
# The split shipped three bugs of exactly one kind: a screen lifted out of
# SurfaceUI kept reaching for a name that had been a top-level local of that
# file — ReplicatedStorage, dress, GearConfig. Each time I checked against a
# hand-written list of suspects, and each time the list missed one, because the
# whole nature of the bug is that it is a name nobody thought of.
#
# So this guesses nothing. It strips comments and strings, takes every
# identifier left, subtracts what the module declares, receives from ctx, uses
# as a field or key, or takes as a parameter, subtracts the Lua and Roblox
# globals, and prints the rest. Anything printed is a dependency to pass in, a
# module to require, or a typo.
#
#   ./tools/freevars.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

KEYWORDS='^(and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while|continue|export|type|self)$'
GLOBALS='^(game|workspace|script|math|table|string|os|task|pairs|ipairs|next|type|typeof|tostring|tonumber|print|warn|error|assert|select|unpack|pcall|xpcall|setmetatable|getmetatable|rawget|rawset|rawequal|rawlen|require|tick|time|wait|spawn|delay|Instance|Vector2|Vector3|CFrame|Color3|UDim|UDim2|Enum|Ray|Region3|NumberRange|NumberSequence|NumberSequenceKeypoint|ColorSequence|ColorSequenceKeypoint|TweenInfo|Random|bit32|utf8|coroutine|debug|buffer|Rect|Font|BrickColor|PhysicalProperties|Axes|Faces|DateTime|ctx)$'

status=0

for module in src/client/ui/*.lua; do
	# Prose is not code. Comments and string bodies go first, or every word of
	# every explanation comes back as an undefined variable.
	code=$(sed -E 's/--.*$//; s/"[^"]*"/""/g; s/'"'"'[^'"'"']*'"'"'/'"''"'/g' "$module")

	used=$(printf '%s\n' "$code" | grep -oE '[A-Za-z_][A-Za-z0-9_]*' | sort -u)

	bound=$(
		{
			# local x, local function x
			printf '%s\n' "$code" | grep -oE 'local +(function +)?[A-Za-z_][A-Za-z0-9_]*' \
				| sed -E 's/local +(function +)?//'
			# local a, b, c =
			printf '%s\n' "$code" | grep -oE 'local +[A-Za-z_][A-Za-z0-9_, ]*=' \
				| sed -E 's/local +//; s/=//' | tr ',' '\n'
			# function name(...)
			printf '%s\n' "$code" | grep -oE 'function +[A-Za-z_][A-Za-z0-9_]*' \
				| sed -E 's/function +//'
			# parameters of any function, including anonymous ones
			printf '%s\n' "$code" | grep -oE 'function *[A-Za-z_.:]*\([^)]*\)' \
				| sed -E 's/.*\(//; s/\)//' | tr ',' '\n'
			# anything used as a field, method or assignment target
			printf '%s\n' "$code" | grep -oE '\.[A-Za-z_][A-Za-z0-9_]*' | sed 's/^\.//'
			printf '%s\n' "$code" | grep -oE ':[A-Za-z_][A-Za-z0-9_]*' | sed 's/^://'
			printf '%s\n' "$code" | grep -oE '[A-Za-z_][A-Za-z0-9_]* *=' | sed -E 's/ *=//'
			# loop variables
			printf '%s\n' "$code" | grep -oE 'for +[A-Za-z_][A-Za-z0-9_, ]* +in' \
				| sed -E 's/for +//; s/ +in//' | tr ',' '\n'
			printf '%s\n' "$code" | grep -oE 'for +[A-Za-z_][A-Za-z0-9_]* *=' \
				| sed -E 's/for +//; s/ *=//'
		} | tr -d ' ' | sort -u
	)

	free=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") \
		| grep -vE "$KEYWORDS" | grep -vE "$GLOBALS" || true)

	if [ -n "$free" ]; then
		echo "$module"
		printf '%s\n' "$free" | sed 's/^/    UNBOUND: /'
		status=1
	else
		echo "$module: clean"
	fi
done

exit $status
