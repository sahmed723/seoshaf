# cloud-trigger — monthly GEO audit

You are the monthly GEO (Generative Engine Optimization) audit cadence. Fires on the 1st of every month. Produces a composite GEO score 0-100 + a prioritized action plan.

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
GEO_DIR=$(jq -r '.outputs.geo_dir // "research/geo"' "$CFG")
TODAY=$(date -u +'%Y-%m-%d')

git fetch origin main
git checkout main
git reset --hard origin/main

BRANCH="claude/seo/geo-$TODAY"
git checkout -B "$BRANCH"

mkdir -p "$GEO_DIR"
ART="$GEO_DIR/geo-audit-$TODAY.md"

CADENCE_TYPE=geo
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
    --argjson sum "$(jq -nc --argjson c "$composite" --argjson p0 "$p0_count" --argjson p1 "$p1_count" --argjson p2 "$p2_count" '{composite:$c, p0:$p0, p1:$p1, p2:$p2}')" \
    '{action:"finish", project_id:$pid, cadence:$cad, run_id:$run, status:"success", summary:$sum, artifact_url:$url}')
  post_cadence "$FIN_BODY" > /dev/null
}
```

## Run — score the domain across five dimensions (0-100 each)

For each, WebFetch the homepage + 3-5 priority pages. Score and note evidence.

### 1. AI Citability (weight 25%)
- First 100 words: is there a direct, quotable answer to the page's primary topic?
- Schema markup: Article / Product / Service / LocalBusiness present with required fields?
- Speakable selectors for voice / AI assistants?
- llms.txt present at `/llms.txt`?

### 2. Platform Readiness (weight 25%)
- Google AI Overviews: structured data + answer-first content
- ChatGPT / Perplexity: clean HTML, sitemap, robots.txt allows AI crawlers (GPTBot, ClaudeBot, anthropic-ai, PerplexityBot, Google-Extended)
- Bing Copilot: msvalidate, schema
- Each platform 0-100, then average.

### 3. Technical SEO (weight 20%)
- HTTPS, valid SSL
- Core Web Vitals (use PageSpeed estimate from the HTML — render-blocking resources, LCP target image)
- Mobile responsiveness (viewport meta + media queries)
- Sitemap valid, robots.txt valid, canonical tags present

### 4. Content Quality / E-E-A-T (weight 15%)
- Author bylines / expertise signals
- Last-updated dates
- Citations / sources
- Original imagery vs stock
- Depth: average word count on priority pages

### 5. Schema Markup (weight 15%)
- JSON-LD presence
- Required vs recommended fields populated
- Cross-page consistency (Organization repeated, sameAs links)

## Compute composite

```
composite = 0.25*citability + 0.25*platform + 0.20*technical + 0.15*content + 0.15*schema
```

## Compare to prior run

Find the most recent prior `geo-audit-*.md` in `$GEO_DIR`. Parse its composite + per-dimension scores. Compute deltas.

## Action plan

Generate up to 8 prioritized action items, each tagged P0 / P1 / P2:
- P0: scores < 50 in any dimension, or a critical regression vs prior month (>10pt drop)
- P1: scores 50-75
- P2: scores > 75 (refinements)

Each action: title (one line), why (one line), how (2-3 lines with concrete file / page references), expected impact (estimated score lift).

## Write `$ART`

```markdown
# GEO audit — DISPLAY — YYYY-MM-DD

## Composite: <n>/100 (prior: <m>, Δ <delta>)

| Dimension | This run | Prior | Δ |
| --- | --- | --- | --- |
| AI Citability    | x/100 | y/100 | z |
| Platform Ready   | x/100 | y/100 | z |
| Technical SEO    | x/100 | y/100 | z |
| Content / E-E-A-T| x/100 | y/100 | z |
| Schema Markup    | x/100 | y/100 | z |

## Action plan
### P0
1. **<title>** — <why>. <how>. Expected lift: +<n>.

### P1
...

### P2
...

## Evidence notes
<one paragraph per dimension explaining the score>
```

## Commit + PR

Same pattern. Title: `[DISPLAY] GEO audit TODAY: composite N/100 (Δ z)`.

## Exit

```
geo $PROJECT_ID: composite <n>/100 (Δ <delta>), P0=<n> P1=<n> P2=<n>, artifact: <PR URL>
```

## Hard rules

Branch prefix, base, ASCII, 20-min cap. If a third-party API (PageSpeed, etc.) is unavailable, score the dimension on the evidence you can fetch and note the limitation in the evidence-notes section. Never fabricate a score.
