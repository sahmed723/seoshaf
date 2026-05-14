#!/usr/bin/env bash
# Print the four cron expressions and proposed scheduled-task definitions for
# a SEOshaf project. Designed to be CALLED FROM CLAUDE — the agent reads the
# output and then invokes mcp__scheduled-tasks__create_scheduled_task four
# times, once per cadence.
#
# This script does NOT itself call the scheduled-tasks MCP server (no shell
# binding available). It is the "specification generator" — the agent is the
# executor. This separation keeps the imperative MCP calls visible in the
# Claude transcript instead of buried inside a shell script.
#
# Usage:
#   schedule-routines.sh <project_id>
#
# Output: JSON to stdout, one object with `taskId`, `cronExpression`,
# `description`, and `prompt` per cadence. Pipe-friendly for jq.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <project_id>" >&2
  exit 2
fi

PROJECT_ID="$1"
HOME_DIR="/Users/shafayahmed/Documents/SEOshaf"
CONFIG="$HOME_DIR/projects/$PROJECT_ID.json"
DETERMINISTIC="$HOME_DIR/lib/deterministic-cron.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "config not found: $CONFIG" >&2
  exit 1
fi

if [[ ! -x "$DETERMINISTIC" ]]; then
  echo "deterministic-cron.sh missing or not executable: $DETERMINISTIC" >&2
  exit 1
fi

DISPLAY=$(jq -r '.display_name' "$CONFIG")

emit_task () {
  local cadence="$1" skill="$2" summary="$3"
  local cron
  cron="$("$DETERMINISTIC" "$PROJECT_ID" "$cadence")"
  jq -n \
    --arg task_id "$PROJECT_ID-$cadence" \
    --arg cron "$cron" \
    --arg desc "[$DISPLAY] $summary" \
    --arg prompt "Invoke the \`$skill\` skill with this exact argument: \`$CONFIG\`. The skill validates the config, runs the cadence, writes the artifact, and patches the dashboard via lib/update-dashboard.sh. Report the final exit-summary line at the end of your response." \
    '{taskId: $task_id, cronExpression: $cron, description: $desc, prompt: $prompt}'
}

# Emit all four. One JSON object per line; the agent reads them in order.
emit_task indexation seo-indexation-watch         "daily indexation watch"
emit_task serp       seo-serp-citation-tracker    "weekly SERP + AI-citation tracking"
emit_task keyword    seo-keyword-competitor-refresh "monthly keyword + competitor refresh"
emit_task geo        seo-geo-audit-monthly         "monthly GEO audit + delta"
