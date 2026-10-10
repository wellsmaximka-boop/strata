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
GLOBALS='^(game|workspace|script|math|table|string|os|task|pairs|ipairs|next|type|typeof|tostring|tonumber|print|warn|error|assert|select|unpack|pcall|xpcall|setmetatable|getmetatable|rawget|rawset|rawequal|rawlen|require|tick|time|wait|spawn|delay|Instance|Vector2|Vector3|CFrame|Color3|UDim|UDim2|Enum|Ray|Region3|NumberRange|NumberSequence|NumberSequenceKeypoint|ColorSequence|ColorSequenceKeypoint|TweenInfo|Random|bit32|utf8|coroutine|debug|buffer|Rect|Font|BrickColor|PhysicalProperties|Axes|Faces|DateTime|RaycastParams|OverlapParams|RaycastResult|Vector3int16|Vector2int16|Region3int16|_G|shared|collectgarbage|newproxy|loadstring|gcinfo|elapsedTime|settings|UserSettings|ctx)$'

status=0

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
	# Everything. The default used to be the two module folders, which is how
	# two shared modules spent weeks reporting their own parameters as
	# undefined with nobody running the check that would have said so.
	TARGETS=($(find src -name "*.lua"))
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

	# Fields and methods come out before anything is counted as used, rather
	# than being added to the bound list afterwards to cancel out.
	#
	# Those are not the same thing, and the difference hid a real one: adding
	# every field name to `bound` means any local that happens to share a name
	# with a field somewhere in the file can be deleted and never reported.
	# `stars` went that way — the table was removed, a loop over it was left
	# behind, and `s.stars` four lines further on was enough to call the file
	# clean.
	used=$(printf '%s\n' "$code" \
		| sed -E 's/[.:][A-Za-z_][A-Za-z0-9_]*/ /g' \
		| grep -oE '[A-Za-z_][A-Za-z0-9_]*' | sort -u)

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
			# The character class carries digits. Without them this pattern
			# missed every function whose name has a number in it — hash01
			# and friends — so none of their parameters counted as declared,
			# and two shared modules have been quietly reporting their own
			# arguments as undefined.
			# parameters of any function, including anonymous ones
			printf '%s\n' "$code" | grep -oE 'function *[A-Za-z_.:0-9]*\([^)]*\)' \
				| sed -E 's/.*\(//; s/\)//' | tr ',' '\n'
			# anything used as an assignment target or a table key. Fields
			# and methods are no longer collected here; they are stripped out
			# of `used` instead, which is where they actually belong.
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

	# ── Used before it exists ────────────────────────────────────────────────
	# The check above asks whether a name is bound anywhere in the file. That
	# is not the same question as whether it is bound *yet*, and the gap
	# between the two shipped a blank player card: UIP was declared a thousand
	# lines below the first line that read it, so up there it was a nil global
	# and the first index of it took out everything after it in the file. The
	# check said clean, because UIP is certainly a local — later.
	#
	# In Lua this is always a bug and never a style, which is what makes it
	# checkable: a reference above the `local` does not see it, it sees a
	# global of the same name.
	early=$(printf '%s\n' "$code" | awk '
		function note(name, ln) {
			if (name == "") { return }
			if (!(name in firstLocal)) { firstLocal[name] = ln }
			# Which wrapper, if any, the declaration sits in. A name declared
			# anywhere at the top level is reachable from anywhere, so one
			# such declaration clears it for good.
			if (!(name in declWrap)) { declWrap[name] = curWrap }
			else if (curWrap == 0)   { declWrap[name] = 0 }
		}
		function noteList(s, ln,   n, parts, i) {
			n = split(s, parts, /[, \t]+/)
			for (i = 1; i <= n; i++) { note(parts[i], ln) }
		}

		# Top-level wrappers: `;(function()` at column zero, closed by
		# `end)()` at column zero. The file uses them to keep a section s
		# locals out of the chunk s 200-name budget, which also keeps them
		# out of sight of everything else.
		/^;\(function\(\)/ { wrapId++; curWrap = wrapId; next }
		/^end\)\(\)/       { curWrap = 0; next }

		{
			line = $0

			if (match(line, /local[ \t]+function[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
				s = substr(line, RSTART, RLENGTH)
				sub(/local[ \t]+function[ \t]+/, "", s)
				note(s, NR)
			} else if (match(line, /local[ \t]+[A-Za-z_][A-Za-z0-9_, \t]*/)) {
				s = substr(line, RSTART, RLENGTH)
				sub(/local[ \t]+/, "", s)
				noteList(s, NR)
			}

			# Parameters and loop variables are declarations too, and the
			# first cut of this check did not know that — so it reported every
			# parameter that shared a name with a local further down the file,
			# which in a file this size is most of them.
			if (match(line, /function[ \t]*[A-Za-z_.:0-9]*\([^)]*\)/)) {
				s = substr(line, RSTART, RLENGTH)
				sub(/.*\(/, "", s)
				sub(/\).*/, "", s)
				noteList(s, NR)
			}
			if (match(line, /for[ \t]+[A-Za-z_][A-Za-z0-9_, \t]*[ \t]+in[ \t]/)) {
				s = substr(line, RSTART, RLENGTH)
				sub(/for[ \t]+/, "", s)
				sub(/[ \t]+in[ \t]*$/, "", s)
				noteList(s, NR)
			}
			if (match(line, /for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) {
				s = substr(line, RSTART, RLENGTH)
				sub(/for[ \t]+/, "", s)
				sub(/[ \t]*=.*/, "", s)
				note(s, NR)
			}

			# What counts as reading a name, and what does not.
			#
			# Fields and methods are not references to a local of that name.
			# Neither is the left side of an assignment, which matters more
			# than it sounds: a table constructor is a page of `id = ...`,
			# `name = ...`, `colour = ...`, and counting those as reads made
			# this check accuse every key of being a local used too early.
			# Equality is protected first, or `x == y` loses its x.
			rest = line
			gsub(/==/, " @@ ", rest)
			gsub(/[.:][A-Za-z_][A-Za-z0-9_]*/, " ", rest)
			gsub(/[A-Za-z_][A-Za-z0-9_]*[ \t]*=/, " ", rest)
			while (match(rest, /[A-Za-z_][A-Za-z0-9_]*/)) {
				id = substr(rest, RSTART, RLENGTH)
				if (!(id in firstUse)) { firstUse[id] = NR }
				# Remember one read from outside every wrapper, for the scope
				# check below.
				if (curWrap == 0 && !(id in useTop)) { useTop[id] = NR }
				rest = substr(rest, RSTART + RLENGTH)
			}
		}

		END {
			for (name in firstLocal) {
				if ((name in firstUse) && firstUse[name] < firstLocal[name]) {
					printf "TOO EARLY: %s (read at line %d, declared at %d)\n",
						name, firstUse[name], firstLocal[name]
				}
			}

			# Declared only inside a wrapper, read outside every wrapper.
			# `notice` went exactly this way: defined inside the hotbar s
			# wrapper and called from the bottom of the file. Both checks
			# above said clean, because it is certainly declared and
			# certainly before the call — just not anywhere the call sees.
			for (name in declWrap) {
				if (declWrap[name] > 0 && (name in useTop)) {
					printf "OUT OF SCOPE: %s (declared inside a wrapper, read at line %d from outside it)\n",
						name, useTop[name]
				}
			}
		}
	' | grep -vE "$KEYWORDS" | sort || true)

	if [ -n "$free" ] || [ -n "$early" ]; then
		echo "$module"
		[ -n "$free" ]  && printf '%s\n' "$free"  | sed 's/^/    UNBOUND: /'
		[ -n "$early" ] && printf '%s\n' "$early" | sed "s/^/    /"
		status=1
	else
		echo "$module: clean"
	fi
done

exit $status
