# cloud-trigger — weekly SERP + AI-citation tracker

You are the weekly SERP + AI-citation cadence for a SEOshaf project. Fires every Monday morning.

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

BRANCH="claude/seo/serp-$TODAY"
git checkout -B "$BRANCH"

mkdir -p "$RESEARCH_DIR"
ART="$RESEARCH_DIR/serp-citations-$TODAY.md"
```

## Run

1. **SERP capture** — for each query in `.queries.serp[]`, use WebSearch to capture the Google top 10. Record:
   - Rank of `$DOMAIN` in the top 10 (or "not in top 10").
   - Featured snippet / AI overview presence (if WebSearch surfaces it).
   - Top 3 competing domains.

2. **AI-citation capture** — for each prompt in `.queries.ai[]`, WebFetch the public answer URLs (or use WebSearch with platform-specific filters). For each platform — ChatGPT, Perplexity, Gemini — record:
   - Was `$DOMAIN` cited? (yes / no)
   - If yes, the citation phrasing snippet.
   - If no, which domains were cited instead.

   Skip a platform cleanly if you cannot retrieve a clean answer — note "platform unavailable this run" rather than guessing.

3. **WoW delta** — find the most recent prior `serp-citations-*.md` in `$RESEARCH_DIR`. For each SERP query, compute rank delta vs prior run. For each AI prompt, compute citation count delta.

4. **Write `$ART`**:

   ```markdown
   # SERP + AI citations — DISPLAY — YYYY-MM-DD

   ## SERP — Google top 10
   | Query | Rank | Δ vs last week | Top competitors |
   | --- | --- | --- | --- |

   ## AI citations
   | Prompt | ChatGPT | Perplexity | Gemini | Δ cites |
   | --- | --- | --- | --- | --- |

   ## Notes
   - <one-paragraph summary of biggest movements>
   - <platforms unavailable, if any>
   ```

5. **Commit + push + PR** (use the same branch / push / `gh pr create` pattern as indexation; title `[DISPLAY] SERP + AI citations TODAY`).

## Exit

```
serp $PROJECT_ID: <queries_tracked> queries, <ai_prompts> AI prompts, <ranks_improved> up, <ranks_dropped> down, artifact: <PR URL>
```

## Hard rules

Same as indexation: branch prefix `claude/seo/`, PR base `main`, never push to main, never auto-merge, ASCII-only messages, 20-minute wall clock cap. Skip platforms that fail to respond cleanly — never fabricate a citation result.
