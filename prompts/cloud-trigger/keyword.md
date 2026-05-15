# cloud-trigger — monthly keyword + competitor refresh

You are the monthly keyword + competitor cadence for a SEOshaf project. Fires on the 1st of every month. Output is a **page-build queue** — a structured list of new programmatic pages the customer can ship.

## Setup

```bash
git config user.name sahmed723
git config user.email shafay.ahmed98@gmail.com

CFG=".seoshaf/config.json"
[ -f "$CFG" ] || { echo "fatal: $CFG not found"; exit 1; }
ACTIVE=$(jq -r '.active // false' "$CFG")
[ "$ACTIVE" = "true" ] || { echo "project inactive — exiting clean"; exit 0; }

PROJECT_ID=$(jq -r '.project_id' "$CFG")
DOMAIN=$(jq -r '.domain' "$CFG")
DISPLAY=$(jq -r '.display_name' "$CFG")
RESEARCH_DIR=$(jq -r '.outputs.research_dir // "research/seo"' "$CFG")
TODAY=$(date -u +'%Y-%m-%d')

git fetch origin main
git checkout main
git reset --hard origin/main

BRANCH="claude/seo/keyword-$TODAY"
git checkout -B "$BRANCH"

mkdir -p "$RESEARCH_DIR"
ART="$RESEARCH_DIR/keyword-refresh-$TODAY.md"
QUEUE="$RESEARCH_DIR/page-build-queue.csv"

CADENCE_TYPE=keyword
[ -n "$CADENCE_API_SECRET" ] && {
  post_cadence () {
    local body="$1"
    local sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$CADENCE_API_SECRET" -hex | awk '{print $2}')
    curl -s -X POST https://www.topseoagents.com/api/cadence-runs \
      -H "Content-Type: application/json" \
      -H "X-Cadence-Signature: $sig" --data-raw "$body"
  }
  START_BODY=$(jq -nc --arg pid "$CADENCE_PROJECT_ID" --arg cad "$CADENCE_TYPE" --arg tid "$CADENCE_TRIGGER_ID" \
    '{action:"start", project_id:$pid, cadence:$cad, trigger_id:$tid}')
  RUN_ID=$(post_cadence "$START_BODY" | jq -r '.run_id // empty')
  echo "tracker start: run_id=$RUN_ID"
}
```

After the PR is opened, finish the row:

```bash
[ -n "$RUN_ID" ] && {
  FIN_BODY=$(jq -nc \
    --arg pid "$CADENCE_PROJECT_ID" --arg cad "$CADENCE_TYPE" --arg run "$RUN_ID" --arg url "${PR_URL:-}" \
    --argjson sum "$(jq -nc --argjson s "$candidates_scored" --argjson n "$new_queued" --argjson t "$total_queue" '{scored:$s, new_queued:$n, total_queue:$t}')" \
    '{action:"finish", project_id:$pid, cadence:$cad, run_id:$run, status:"success", summary:$sum, artifact_url:$url}')
  post_cadence "$FIN_BODY" > /dev/null
}
```

## Run

1. **Read context from config**: `.competitors[]`, `.seed_keywords[]`, `.persona_filter`, `.buyer_exclude[]`.

2. **Competitor probe** — for each competitor in `.competitors[]` (max 6), WebFetch the homepage and sitemap. Extract: page titles, h1/h2, service categories, city/location pages. Build a master list of competitor topics.

3. **Seed expansion** — combine `.seed_keywords[]` with competitor-discovered topics. Use WebSearch to find related queries (autocomplete suggestions, People-also-ask, related searches). Cap expanded list at 50 candidates.

4. **Filter against persona** — for each candidate, judge against `.persona_filter` and `.buyer_exclude[]`. Drop anything that targets the wrong audience (DIY enthusiasts, suppliers, training-seekers, etc.). Keep a brief reason per drop in the artifact.

5. **Score** — for each surviving candidate, score on:
   - **Intent** (1-5): how transactional is it? Local-service + "near me" / "cost" / "best" = 5; informational guide = 2-3.
   - **Difficulty** (1-5): SERP competition (look at competing domains' authority). Lower = better.
   - **Match** (1-5): how well does the customer's existing site map onto this query? Brand-new topic = 1; existing service page rewrite = 5.

   Composite score = (intent × 0.5) + (6 - difficulty) × 0.3 + match × 0.2. Sort descending.

6. **Page-build queue** — append the top 10 scored candidates to `$QUEUE` as CSV with columns:
   `date_added,query,intent,difficulty,match,composite,recommended_url,status`
   Status starts as `proposed`. Customer (or a build cadence) flips to `in_progress` / `live`.

7. **Write `$ART`** with a human-readable summary:

   ```markdown
   # Keyword + competitor refresh — DISPLAY — YYYY-MM-DD

   ## Competitor coverage
   - <competitor 1>: <n topics extracted>
   - <competitor 2>: ...

   ## Top 10 page-build candidates
   | Query | Composite | Intent | Diff | Match | Recommended URL |
   | --- | --- | --- | --- | --- | --- |

   ## Dropped (persona filter)
   - "<query>" — <one-sentence reason>

   ## Queue state
   - Total queued: <n>
   - Live: <n>
   - In progress: <n>
   ```

8. **Commit + PR** (same pattern; title `[DISPLAY] keyword refresh TODAY: N new candidates`).

## Exit

```
keyword $PROJECT_ID: <candidates_scored> scored, <new_queued> queued, <total_queue> total, artifact: <PR URL>
```

## Hard rules

Branch prefix, base, ASCII, 20-min cap as before. If Semrush MCP is not connected (it isn't in cloud), do not block — use WebSearch as the discovery substitute and note in the artifact "Semrush unavailable; WebSearch substitute used."
