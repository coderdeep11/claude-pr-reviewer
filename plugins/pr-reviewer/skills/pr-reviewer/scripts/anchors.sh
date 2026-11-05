#!/usr/bin/env bash
# Print the lines a diff added or removed, as path:LINE:content.
#
#   anchors.sh <base>...<head> [-- <paths>]            added lines; path and LINE are head-side
#   anchors.sh --removed <base>...<head> [-- <paths>]  removed lines; path and LINE are base-side
#   anchors.sh <base>...<head> | grep -n 'symbol'      find the anchor for a symbol
#
# GitHub anchors an inline comment on the head-side number, so only added lines
# are anchors. Removed lines have no head-side number: use them to audit what
# the change took away, then anchor the comment on the line that replaced it.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 2
fi

side=new
if [ "$1" = "--removed" ]; then side=old; shift; fi

git diff --find-renames --unified=0 "$@" | awk -v side="$side" '
  function name(line, prefix,   p) { p = substr(line, 5)          # drop "--- " or "+++ "
                                     sub(/\t.*$/, "", p)          # git tab-delimits paths with spaces
                                     if (p == "/dev/null") return ""
                                     sub("^" prefix, "", p); return p }
  /^diff --git /             { header = 1; path = ""; next }
  header && /^--- /          { if (side == "old") path = name($0, "a/"); next }
  header && /^\+\+\+ /       { if (side == "new") path = name($0, "b/"); next }
  /^@@/                      { header = 0                         # a "---" or "+++" after this is content
                               match($0, side == "new" ? "\\+[0-9]+" : "-[0-9]+")
                               n = substr($0, RSTART + 1, RLENGTH - 1); next }
  header || /^\\ No newline/ { next }
  side == "new" && /^\+/     { if (path != "") printf "%s:%d:%s\n", path, n, substr($0, 2); n++; next }
  side == "old" && /^-/      { if (path != "") printf "%s:%d:%s\n", path, n, substr($0, 2); n++; next }
'
