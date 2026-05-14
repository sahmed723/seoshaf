#!/usr/bin/env bash
# Deterministic cron-minute computation for SEOshaf project routines.
#
# Goal: every project gets a stable, non-colliding cron-minute per cadence with
# zero human input. Re-running for the same project yields the same minutes.
# Avoids the :00 and :30 marks (per ScheduleWakeup guidance — every fleet
# scheduled to fire on the hour mark hits the API at the same instant).
#
# Usage:
#   deterministic-cron.sh <project_id> <cadence>
#   cadence ∈ {indexation, serp, keyword, geo}
#
# Output: a single 5-field cron expression to stdout. Times below are local.
#
#   indexation : daily              "M  8  *  *  *"
#   serp       : weekly Mondays     "M  9  *  *  1"
#   keyword    : monthly 1st        "M 10  1  *  *"
#   geo        : monthly 1st        "M 11  1  *  *"
#
# Minute M is hash(project_id) + cadence_offset, mod 60, then bumped off
# {0, 30} to {3, 33}. Cadence offsets stagger same-project tasks within the
# hour so a long-running cadence doesn't bleed into the next.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <project_id> <cadence:indexation|serp|keyword|geo>" >&2
  exit 2
fi

project_id="$1"
cadence="$2"

# Stable hash: sum of byte values of the project_id. Good enough for 60-bucket
# distribution at the scale of dozens of projects — no need for shasum here.
hash=$(printf '%s' "$project_id" | od -An -tu1 | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s}')

case "$cadence" in
  indexation) offset=0;  hour=8;  dom='*'; dow='*' ;;
  serp)       offset=14; hour=9;  dom='*'; dow=1   ;;
  keyword)    offset=28; hour=10; dom=1;   dow='*' ;;
  geo)        offset=42; hour=11; dom=1;   dow='*' ;;
  *) echo "unknown cadence: $cadence" >&2; exit 2 ;;
esac

minute=$(( (hash + offset) % 60 ))
# Nudge off the {0, 30} fleet-collision marks.
if (( minute == 0  )); then minute=3;  fi
if (( minute == 30 )); then minute=33; fi

printf '%d %d %s * %s\n' "$minute" "$hour" "$dom" "$dow"
