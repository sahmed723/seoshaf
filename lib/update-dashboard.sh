#!/usr/bin/env bash
# Patch dashboard/state.json with a JSON patch on stdin, then regenerate
# dashboard/DASHBOARD.md from state.json + projects/*.json.
#
# Usage:
#   echo '{"projects": {"keelway": {"serp_rank_avg": 7.2, "last_run": {"serp": "2026-05-12T09:23:00-07:00"}}}}' | update-dashboard.sh
#
# Concurrency: protected by flock on state.json. Safe for parallel scheduled
# routine runs.

set -euo pipefail

HOME_DIR="/Users/shafayahmed/Documents/SEOshaf"
STATE="$HOME_DIR/dashboard/state.json"
DASH="$HOME_DIR/dashboard/DASHBOARD.md"
PROJECTS_DIR="$HOME_DIR/projects"

# Read the patch from stdin (or treat absence as a no-op refresh).
patch="$(cat)"
if [[ -z "$patch" ]]; then patch='{}'; fi

# Initialize state.json if missing.
if [[ ! -f "$STATE" ]]; then
  echo '{"updated_at": null, "projects": {}}' > "$STATE"
fi

# Single-writer lock. flock on macOS (Homebrew util-linux) or fall back to a
# mkdir-based mutex. Most Macs do not ship flock, so use the fallback path.
lockdir="$STATE.lock"
trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
tries=0
while ! mkdir "$lockdir" 2>/dev/null; do
  tries=$((tries + 1))
  if (( tries > 50 )); then
    echo "update-dashboard.sh: stale lock $lockdir, removing" >&2
    rmdir "$lockdir" 2>/dev/null || true
  fi
  sleep 0.1
done

# Apply patch via jq deep-merge (`*` operator merges objects recursively).
# `now` from jq gives a unix timestamp; we render an ISO string with date.
now_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
tmp="$(mktemp)"
jq --arg now "$now_iso" --argjson patch "$patch" \
  '. * $patch | .updated_at = $now' "$STATE" > "$tmp"
mv "$tmp" "$STATE"

# Regenerate DASHBOARD.md. Project list = union of projects/*.json keys and
# state.projects keys — drop a new config in projects/ and it appears here
# automatically.
{
  echo "# SEOshaf — Cross-Project Dashboard"
  echo
  echo "_Generated: $now_iso. Source of truth: \`dashboard/state.json\` + \`projects/*.json\`. Regenerated after every scheduled run._"
  echo
  echo "| Project | Active | Domain | GEO Score (Δ) | Avg SERP | AI Citations | Quick Wins | Pages Healthy / At Risk | Last Indexation | Last SERP | Last Keywords | Last GEO |"
  echo "|---|---|---|---|---|---|---|---|---|---|---|---|"

  for cfg in "$PROJECTS_DIR"/*.json; do
    [[ "$(basename "$cfg")" == _* ]] && continue
    [[ -f "$cfg" ]] || continue
    pid=$(jq -r '.project_id' "$cfg")
    name=$(jq -r '.display_name' "$cfg")
    domain=$(jq -r '.domain' "$cfg")
    active=$(jq -r '.active // true' "$cfg")

    # Per-project rolled-up state with nullable fallbacks.
    row=$(jq -r --arg pid "$pid" '
      .projects[$pid] // {} as $p
      | [
          ($p.geo_score // "—" | tostring),
          ($p.geo_score_delta // "—" | tostring),
          ($p.serp_rank_avg // "—" | tostring),
          ($p.ai_citations_count // "—" | tostring),
          ($p.quick_wins_count // "—" | tostring),
          ($p.pages_healthy // "—" | tostring),
          ($p.pages_at_risk // "—" | tostring),
          ($p.last_run.indexation // "—"),
          ($p.last_run.serp // "—"),
          ($p.last_run.keywords // "—"),
          ($p.last_run.geo // "—")
        ] | @tsv
    ' "$STATE")

    IFS=$'\t' read -r geo geo_d serp_r ai_c qw ph par lri lrs lrk lrg <<< "$row"
    echo "| [$name](./runs/$pid/) | $active | $domain | $geo ($geo_d) | $serp_r | $ai_c | $qw | $ph / $par | $lri | $lrs | $lrk | $lrg |"
  done

  echo
  echo "## Per-project artifact archives"
  echo
  for cfg in "$PROJECTS_DIR"/*.json; do
    [[ "$(basename "$cfg")" == _* ]] && continue
    [[ -f "$cfg" ]] || continue
    pid=$(jq -r '.project_id' "$cfg")
    name=$(jq -r '.display_name' "$cfg")
    echo "- **$name** → [\`dashboard/runs/$pid/\`](./runs/$pid/)"
  done
} > "$DASH"

echo "updated: $STATE"
echo "regenerated: $DASH"
