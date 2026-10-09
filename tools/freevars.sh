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
#   ./tools/freevars.sh                      # the UI and movement modules
#   ./tools/freevars.sh path/to/one.lua      # or just the one you are writing
#
set -euo pipefail
cd "$(dirname "$0")/.."

KEYWORDS='^(and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while|continue|export|type|self)$'
GLOBALS='^(game|workspace|script|math|table|string|os|task|pairs|ipairs|next|type|typeof|tostring|tonumber|print|warn|error|assert|select|unpack|pcall|xpcall|setmetatable|getmetatable|rawget|rawset|rawequal|rawlen|require|tick|time|wait|spawn|delay|Instance|Vector2|Vector3|CFrame|Color3|UDim|UDim2|Enum|Ray|Region3|NumberRange|NumberSequence|NumberSequenceKeypoint|ColorSequence|ColorSequenceKeypoint|TweenInfo|Random|bit32|utf8|coroutine|debug|buffer|Rect|Font|BrickColor|PhysicalProperties|Axes|Faces|DateTime|RaycastParams|OverlapParams|RaycastResult|Vector3int16|Vector2int16|Region3int16|ctx)$'

status=0

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
	TARGETS=(src/client/ui/*.lua src/client/movement/*.lua)
fi

for module in "${TARGETS[@]}"; do
	# Prose is not code. Comments and string bodies go first, or every word of
	# every explanation comes back as an undefined variable.
	# Numbers go too. Nothing else in here cares about them, and the identifier
	# pattern below happily reads the tail of 1e6 as a variable named e6 and
	# then reports it missing.
	code=$(sed -E '
		s/--.*$//
		s/"[^"]*"/""/g
		s/'"'"'[^'"'"']*'"'"'/'"''"'/g
		s/0[xX][0-9a-fA-F]+/0/g
		s/[0-9]+[eE][+-]?[0-9]+/0/g
	' "$module")

	used=$(printf '%s\n' "$code" | grep -oE '[A-Za-z_][A-Za-z0-9_]*' | sort -u)

	bound=$(
		# A grep that matches nothing exits 1, and this file is nothing but
		# greps that are each allowed to match nothing. Two separate things went
		# wrong because of it, and both killed the whole run with no output at
		# all, so the harness silently reported success on any module that did
		# not happen to use every construct it looks for. The first file without
		# a for loop in it was the one that found this.
		#
		#   set +e here, because under errexit a grep that matches nothing
		#   aborts the group it is in and the rest of the names are never
		#   collected.
		#
		#   || true on the pipeline below, because pipefail hands that same
		#   status out of the command substitution, which fails the assignment
		#   itself — and no amount of set +e in here changes the status this
		#   subshell returns.
		set +e
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
		} | tr -d ' ' | sort -u || true
	)

	# Was comm against two process substitutions, which died under errexit
	# without printing a thing and took the rest of the run with it. awk needs
	# neither sorted input nor /dev/fd, and says what it means.
	free=$(printf '%s\n' "$used" | awk -v bound="$bound" '
			BEGIN {
				n = split(bound, known, "\n")
				for (i = 1; i <= n; i++) { seen[known[i]] = 1 }
			}
			$0 != "" && !($0 in seen) { print }
		' | grep -vE "$KEYWORDS" | grep -vE "$GLOBALS" || true)

	if [ -n "$free" ]; then
		echo "$module"
		printf '%s\n' "$free" | sed 's/^/    UNBOUND: /'
		status=1
	else
		echo "$module: clean"
	fi
done

exit $status
