# Shared tracker write-back — drop into every cadence prompt

Each cadence records a `cadence_runs` row in the topseoagents.com Supabase database at start, then updates it with status + summary + artifact URL at finish. The launcher prompt (per-trigger) exports `CADENCE_API_SECRET`, `CADENCE_PROJECT_ID`, and `CADENCE_TRIGGER_ID` — these are required.

## Start (immediately after the preamble validates the config)

```bash
[ -n "$CADENCE_API_SECRET" ] || { echo "warn: CADENCE_API_SECRET not set — skipping tracker writes"; CADENCE_API_SECRET=""; }

post_cadence () {
  local body="$1"
  local sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$CADENCE_API_SECRET" -hex | awk '{print $2}')
  curl -s -X POST https://www.topseoagents.com/api/cadence-runs \
    -H "Content-Type: application/json" \
    -H "X-Cadence-Signature: $sig" \
    --data-raw "$body"
}

# CADENCE_TYPE must be set by the calling cadence (indexation|serp|keyword|geo)
RUN_ID=""
if [ -n "$CADENCE_API_SECRET" ]; then
  START_BODY=$(jq -nc \
    --arg action start \
    --arg pid "$CADENCE_PROJECT_ID" \
    --arg cad "$CADENCE_TYPE" \
    --arg tid "$CADENCE_TRIGGER_ID" \
    '{action: $action, project_id: $pid, cadence: $cad, trigger_id: $tid}')
  START_RES=$(post_cadence "$START_BODY")
  RUN_ID=$(echo "$START_RES" | jq -r '.run_id // empty')
  echo "tracker start: run_id=$RUN_ID"
fi
```

## Finish (immediately after the PR is opened or the cadence decides not to write)

```bash
finish_cadence () {
  local status="$1"     # success | failed
  local summary="$2"    # JSON string, e.g. '{"healthy":10,"at_risk":0}'
  local artifact="$3"   # PR URL or empty
  if [ -z "$RUN_ID" ] || [ -z "$CADENCE_API_SECRET" ]; then return 0; fi
  local body=$(jq -nc \
    --arg action finish \
    --arg pid "$CADENCE_PROJECT_ID" \
    --arg cad "$CADENCE_TYPE" \
    --arg run "$RUN_ID" \
    --arg s "$status" \
    --arg url "$artifact" \
    --argjson sum "$summary" \
    '{action: $action, project_id: $pid, cadence: $cad, run_id: $run, status: $s, summary: $sum, artifact_url: $url}')
  post_cadence "$body" > /dev/null
}

# At the end of the cadence:
#   finish_cadence success '{"healthy":10,"at_risk":0,"sitemap_urls":62}' "$PR_URL"
# Or on failure path:
#   finish_cadence failed   '{"error":"sitemap_fetch_failed"}' ""
```
