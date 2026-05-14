---
name: seo-keyword-competitor-refresh
description: Monthly keyword and competitor research pipeline for a SEOshaf project. Takes one argument — path to project config. Generalized port of the Flexbone research-agent runbook (competitor keyword mining, seed expansion, scoring, page-topic clustering). All proper nouns and audience filters are read from the config — no project name is hard-coded. Requires the Semrush MCP to be connected; exits cleanly with an actionable message if it isn't. Use when "/seo-keyword-competitor-refresh <config>" or fired by a 1st-of-month scheduled routine.
allowed-tools: Read, Bash, WebFetch, Write, Glob
---

# seo-keyword-competitor-refresh — Monthly keyword + competitor refresh

## Contract

**Input:** path to `projects/<project_id>.json`.

**Output:**
1. Markdown artifacts at:
   - `<repo>/<research_dir>/keyword-refresh-YYYY-MM.md` (master ranked list)
   - `<repo>/<research_dir>/competitor-keywords-YYYY-MM.md` (raw Semrush dump per competitor)
   - `<repo>/<research_dir>/page-build-queue-YYYY-MM.md` (clustered into pages to build)
2. Mirrored copies under `dashboard/runs/<project_id>/`.
3. JSON patch to `update-dashboard.sh` setting `keyword_pipeline_count`, `quick_wins_count`, `last_run.keywords`.

## Run procedure

### 1. Validate + load config

Same boilerplate as the other cadence skills. Additionally extract:

```bash
PERSONA=$(jq -r '.persona_filter // ""' "$CONFIG")
EXCLUDE=$(jq -r '.buyer_exclude // [] | join(", ")' "$CONFIG")
SEMRUSH_DB=$(jq -r '.integrations.semrush_db // "us"' "$CONFIG")
COMPETITORS=$(jq -r '.competitors // [] | .[]' "$CONFIG")
SEEDS=$(jq -r '.seed_keywords // [] | .[]' "$CONFIG")
DISPLAY=$(jq -r '.display_name' "$CONFIG")
```

### 2. Semrush availability check

This skill is heavyweight and depends entirely on Semrush. Before doing anything else, check the Semrush MCP is connected. If not:

```
Semrush MCP not connected. To activate this skill:
  1. Authenticate the marketing_supermetrics or Semrush MCP (run /mcp).
  2. Re-fire this routine with: <task-id reference>

Exiting clean — no artifact written. Dashboard not patched.
```

Exit 0 (clean) — this is a config issue, not an error.

### 3. PHASE 1 — Competitor keyword mining

For each domain in `COMPETITORS`:
- Run `semrush_domain_organic_keywords` with database `$SEMRUSH_DB`, limit 200.
- Filter keywords using `$PERSONA` and `$EXCLUDE` as a prompt-side filter: drop anything that violates the buyer-exclude list (e.g. patient-facing, driver-facing, consumer-side terms).

Save raw filtered output to `competitor-keywords-YYYY-MM.md` with sections per competitor.

### 4. PHASE 2 — Seed expansion (three streams)

For each seed in `SEEDS`:
- Stream A (solution-aware): `semrush_broad_match_keywords` database `$SEMRUSH_DB`, limit 50.
- Stream B (problem-aware): if `config.seed_keywords_pain` exists, expand it the same way. (Optional field — defaults to empty.)
- Stream C (questions): `semrush_phrase_questions` database `$SEMRUSH_DB`, limit 30.

Apply the same persona/exclude filter to all expansions.

### 5. PHASE 3 — Scoring

Take the deduplicated union of competitor + seed expansion outputs.

Run `semrush_batch_keyword_overview` (batches of 100) for volume + difficulty, then `semrush_keyword_difficulty` on the top candidates.

Apply the scoring formula:

```
OPPORTUNITY_SCORE = (Search_Volume * 2) / (Keyword_Difficulty + 1)
```

Label each keyword:

| Label | Criteria |
|---|---|
| 🔥 QUICK WIN | Volume ≥ 100 AND Difficulty < 35 |
| ⭐ HIGH OPPORTUNITY | Volume ≥ 300 AND Difficulty < 55 |
| 📈 WORTH BUILDING | Volume ≥ 500 AND Difficulty < 70 |
| 🎯 LONG SHOT | Volume ≥ 1000 AND Difficulty ≥ 70 |
| ❌ SKIP | Volume < 50 OR (Volume < 100 AND Difficulty > 60) |

### 6. PHASE 4 — Page topic clustering

Group the non-SKIP keywords into page-topic clusters. The cluster taxonomy is intentionally generic — DO NOT specialize it per project here. Let the persona_filter shape the clustering result via the LLM, not hard-coded category names. Suggested generic buckets the agent should consider:

1. **Capability/feature pages** — keywords describing what the product does
2. **Competitor / comparison pages** — `X alternative`, `X vs Y`
3. **Integration pages** — `<integration partner> + <category>` patterns
4. **Vertical pages** — keywords scoped by buyer segment in `$PERSONA`
5. **Problem-awareness blog content** — pain-point queries
6. **Question / FAQ content** — "how to / what is" queries
7. **Top-of-funnel category pages** — broad category captures

### 7. Artifacts

Write three files this run, all under `<repo>/<research_dir>/`:

**`keyword-refresh-YYYY-MM.md`** — executive summary:

```markdown
# Keyword refresh — <display_name> — YYYY-MM

## Pipeline counts
| Bucket | Count |
| --- | --- |
| 🔥 Quick Wins | <n> |
| ⭐ High Opportunity | <n> |
| 📈 Worth Building | <n> |
| 🎯 Long Shots | <n> |
| ❌ Skipped | <n> |
| **Total in pipeline** | <n> |

## Top 10 by Opportunity Score
| # | Keyword | Volume | KD | Opp Score | Label |
| --- | --- | --- | --- | --- | --- |

## Top 5 competitor keyword gaps
| Gap | Competitors ranking | Combined volume | Why it matters |

## Recommended focus — pages to build first
1. ...
```

**`competitor-keywords-YYYY-MM.md`** — raw competitor dump.

**`page-build-queue-YYYY-MM.md`** — clustered, prioritized.

Mirror all three to `dashboard/runs/<project_id>/`.

### 8. Patch dashboard

```bash
NOW=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
PATCH=$(jq -n \
  --arg pid "$PROJECT_ID" \
  --argjson pipeline "$PIPELINE_TOTAL" \
  --argjson quickwins "$QUICK_WINS" \
  --arg ts "$NOW" \
  '{projects: {($pid): {keyword_pipeline_count: $pipeline, quick_wins_count: $quickwins, last_run: {keywords: $ts}}}}')
echo "$PATCH" | "$HOME/Documents/SEOshaf/lib/update-dashboard.sh"
```

### 9. Exit summary

`keywords <project_id>: pipeline=<n>, quick_wins=<n>, artifact: <path>`

## Generalization invariant

The persona_filter, competitor list, and seed keywords are the ENTIRE project-specific surface area of this skill. Two projects with very different verticals (freight TMS vs healthcare RCM) must run through the same code path, with only the config differing.

The Flexbone "what is prior authorization" filter (B2B operations, not patient) and the Keelway "broker-side, not driver-side" filter both ride on `$PERSONA` + `$EXCLUDE`. Do not add `if project == 'flexbone'` branches anywhere.
