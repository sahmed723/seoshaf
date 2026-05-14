---
name: seo-serp-citation-tracker
description: Weekly SERP rank and AI-citation tracker for a SEOshaf project. Takes one argument — path to project config. For each SERP query, captures Google top-10 (Semrush MCP preferred, WebSearch fallback). For each AI query, captures whether the project domain is cited in ChatGPT/Perplexity/Gemini responses. Computes week-over-week delta, writes a structured artifact, patches the cross-project dashboard. Use when "/seo-serp-citation-tracker <config>" or fired by a Monday-morning scheduled routine.
allowed-tools: Read, Bash, WebSearch, WebFetch, Write, Glob
---

# seo-serp-citation-tracker — Weekly SERP + AI-citation tracker

## Contract

**Input:** path to `projects/<project_id>.json`.

**Output:**
1. Markdown artifact at `<repo>/<research_dir>/serp-tracking-YYYY-MM-DD.md` mirrored to `dashboard/runs/<project_id>/serp-tracking-YYYY-MM-DD.md`.
2. JSON patch to `update-dashboard.sh` setting `serp_rank_avg`, `ai_citations_count`, `last_run.serp`.

Generalizes Keelway runbook §5 (SERP tracking) + §6 (AI-citation tracking) into one project-agnostic pass.

## Run procedure

### 1. Validate + load config

```bash
CONFIG="$1"
jq -e .project_id "$CONFIG" >/dev/null || exit 1
[ "$(jq -r '.active // true' "$CONFIG")" = "true" ] || exit 0

PROJECT_ID=$(jq -r '.project_id' "$CONFIG")
DOMAIN=$(jq -r '.domain' "$CONFIG")
REPO=$(jq -r '.repo_path' "$CONFIG")
RESEARCH_DIR=$(jq -r '.outputs.research_dir // "research/seo"' "$CONFIG")
TODAY=$(date +'%Y-%m-%d')
ART_LOCAL="$REPO/$RESEARCH_DIR/serp-tracking-$TODAY.md"
ART_MIRROR="$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID/serp-tracking-$TODAY.md"
mkdir -p "$REPO/$RESEARCH_DIR" "$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID"
```

### 2. SERP pass

For each query in `config.queries.serp`:

- **If a Semrush MCP is connected:** use `semrush_keyword_position_tracking` for `$DOMAIN` on the query, record current position.
- **Otherwise (default):** WebSearch the query, find the bare domain (or `<DOMAIN>` host) in the result list. Record:
  - Position (1–10), or `>10` if absent from top 10.
  - The top-3 competitors actually ranking.

Compute `serp_rank_avg` = mean of in-top-10 positions; queries not in top 10 count as 11 for averaging (consistent penalty).

### 3. AI-citation pass

For each prompt in `config.queries.ai`:

- WebFetch a public Perplexity URL if accessible (`https://www.perplexity.ai/search/?q=<urlencoded>`). Parse the response for any mention of `<DOMAIN>` or `<display_name>`.
- For ChatGPT and Gemini — no public no-auth API for live search. Emit a structured "manual check required" row. The artifact format below has columns ready; user fills them in by hand from logged-in sessions during the Monday review.

Compute `ai_citations_count` = count of (engine, prompt) pairs where the project domain or name appears in the answer.

### 4. Week-over-week delta

Find the prior `serp-tracking-*.md` in `<RESEARCH_DIR>` via Glob, parse its summary line for prior `serp_rank_avg` and `ai_citations_count`. Compute the delta and include in the new artifact.

### 5. Artifact format

```markdown
# SERP + AI citation tracking — <display_name> — <YYYY-MM-DD>

## Summary
- Avg SERP rank (this week): <avg>  (Δ from last week: <±>)
- AI citations (this week): <n>  (Δ from last week: <±>)
- Method: Semrush MCP / WebSearch fallback

## SERP positions
| Query | Pos this week | Pos last week | Δ | Top-3 competitors |
| --- | --- | --- | --- | --- |
| <query> | 7 | 9 | +2 | a.com, b.com, c.com |

## AI citation log
| Engine | Prompt | Cited? | Position in answer | Notes |
| --- | --- | --- | --- | --- |
| Perplexity | <prompt> | ✅ | mentioned in para 2 | direct quote of /pricing |
| ChatGPT | <prompt> | ⬜ MANUAL | — | paste from logged-in session |
| Gemini | <prompt> | ⬜ MANUAL | — | |
| Google AI Overviews | <prompt> | ⬜ MANUAL | — | |

## Notes
- ...
```

### 6. Patch dashboard

```bash
NOW=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
PATCH=$(jq -n \
  --arg pid "$PROJECT_ID" \
  --argjson avg "$SERP_AVG" \
  --argjson cites "$AI_CITES" \
  --arg ts "$NOW" \
  '{projects: {($pid): {serp_rank_avg: $avg, ai_citations_count: $cites, last_run: {serp: $ts}}}}')
echo "$PATCH" | "$HOME/Documents/SEOshaf/lib/update-dashboard.sh"
```

### 7. Exit summary

`serp <project_id>: avg=<x>, ai_cites=<y>, artifact: <path>`

## Generalization invariant

A new project with `queries.serp: []` and `queries.ai: []` should produce an empty-but-valid artifact and patch the dashboard with `serp_rank_avg: null, ai_citations_count: 0`. Never error on missing optional fields.
