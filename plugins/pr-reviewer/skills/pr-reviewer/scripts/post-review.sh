#!/usr/bin/env bash
# Post a review file to its PR as one COMMENT review.
#
#   post-review.sh pr-reviews/<branch-key>.md <pr> <base>...<head>
#
# Re-runs check-review.sh, then stops unless the PR's head commit is <head>.
# Inline blocks become line comments. General blocks become the review body, or
# the Recommendation line when there are none. Nothing else in the file is posted.
# Prints the review URL.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 2
fi

review=$1 pr=$2 range=$3
case "$range" in *...*) ;; *) echo "range must be <base>...<head>: $range" >&2; exit 2 ;; esac

bash "$(dirname "$0")/check-review.sh" "$review" "$range"

head=$(git rev-parse --verify "${range#*...}^{commit}")
pr_head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid)
if [ "$head" != "$pr_head" ]; then
  echo "PR #$pr head is $pr_head but the review read $head; push or re-review first" >&2
  exit 1
fi

payload=$(mktemp); trap 'rm -f "$payload"' EXIT

# One record per block, fields split by \001 and records by \002, so jq does the JSON escaping.
awk '
  function flush() { if (kind != "") { sub(/\n+$/, "", body); printf "%s\001%s\001%s\001%s\001%s\002", kind, path, lo, hi, body }
                     kind = ""; body = "" }
  /^\*\*Recommendation:/ && rec == "" { rec = $0; gsub(/\*\*/, "", rec); next }
  /^## /       { flush()
                 if ($4 == "general") { kind = "general"; path = lo = hi = ""; next }
                 target = $0; sub(/^## [0-9]+\. \[[a-z]+\] inline /, "", target)
                 match(target, /:[0-9]+(-[0-9]+)?$/)
                 path = substr(target, 1, RSTART - 1)
                 k = split(substr(target, RSTART + 1), r, "-"); lo = r[1]; hi = (k > 1 ? r[2] : r[1]); kind = "inline"; next }
  /^---$/      { flush(); next }
  kind == ""   { next }
  /^>/         { line = $0; sub(/^> ?/, "", line); body = body line "\n"; next }
  /^$/         { if (body != "") body = body "\n" }
  END          { flush(); printf "recommendation\001\001\001\001%s\002", rec }
' "$review" | jq -Rs --arg commit "$head" '
  [split("\u0002")[] | select(length > 0) | split("\u0001") | {kind: .[0], path: .[1], lo: .[2], hi: .[3], body: .[4]}] as $blocks
  | ([$blocks[] | select(.kind == "general") | .body] | join("\n\n")) as $general
  | {
      commit_id: $commit,
      event: "COMMENT",
      body: (if $general != "" then $general else ([$blocks[] | select(.kind == "recommendation") | .body] | first // "") end),
      comments: [$blocks[] | select(.kind == "inline")
        | {path, line: (.hi | tonumber), side: "RIGHT", body}
          + (if .lo != .hi then {start_line: (.lo | tonumber), start_side: "RIGHT"} else {} end)]
    }' > "$payload"

if ! jq -e '.body != ""' "$payload" > /dev/null; then
  echo "no general comment or Recommendation line to use as the review body" >&2
  exit 1
fi

gh api --method POST "repos/{owner}/{repo}/pulls/$pr/reviews" --input "$payload" --jq .html_url
