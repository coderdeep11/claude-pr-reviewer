#!/usr/bin/env bash
# Check the mechanical rules of a review file, without printing the anchors.
#
#   check-review.sh pr-reviews/<branch-key>.md <base>...<head> [-- <paths>]
#
# Each inline header's path:line, and every line of a path:start-end range, must
# be a line the diff added. Headers must be numbered from 1 in severity order.
# The file must hold no em dash.
# Prints one line per problem and exits 1, or prints "ok: <n> comments".
set -euo pipefail

if [ "$#" -lt 2 ]; then
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 2
fi

review=$1; shift
added=$(mktemp); trap 'rm -f "$added"' EXIT
bash "$(dirname "$0")/anchors.sh" "$@" > "$added"

awk '
  BEGIN { n = split("blocker major minor question nit", order, " ")
          for (i = 1; i <= n; i++) rank[order[i]] = i }
  FILENAME == ARGV[1] { if (match($0, /:[0-9]+:/)) added[substr($0, 1, RSTART + RLENGTH - 2)] = 1; next }
  /—/                 { printf "em dash on line %d\n", FNR; bad = 1 }
  /^## /              { if ($0 !~ /^## [0-9]+\. \[[a-z]+\] (inline .+:[0-9]+(-[0-9]+)?|general)$/) {
                          printf "malformed header on line %d: %s\n", FNR, $0; bad = 1; next }
                        count++; num = $2; sub(/\.$/, "", num); sev = $3; gsub(/[][]/, "", sev)
                        if (num + 0 != count) { printf "header %s is numbered %s, expected %d\n", $0, num, count; bad = 1 }
                        if (!(sev in rank)) { printf "unknown severity: %s\n", $0; bad = 1 }
                        else if (rank[sev] < last) { printf "out of severity order: %s\n", $0; bad = 1 }
                        else last = rank[sev]
                        if ($4 == "inline") { target = $0; sub(/^## [0-9]+\. \[[a-z]+\] inline /, "", target)
                                              match(target, /:[0-9]+(-[0-9]+)?$/)
                                              path = substr(target, 1, RSTART - 1)
                                              k = split(substr(target, RSTART + 1), r, "-"); lo = r[1] + 0; hi = (k > 1 ? r[2] : r[1]) + 0
                                              if (hi < lo) { printf "range ends before it starts: %s\n", target; bad = 1 }
                                              for (i = lo; i <= hi; i++)
                                                if (!((path ":" i) in added)) { printf "not a line this diff added: %s:%d\n", path, i; bad = 1 } } }
  END                 { if (bad) exit 1; printf "ok: %d comments\n", count }
' "$added" "$review"
