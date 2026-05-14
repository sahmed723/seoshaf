---
name: seo-geo-audit-monthly
description: Monthly GEO+SEO audit wrapper for a SEOshaf project. Takes one argument — path to project config. Thin orchestrator that fires the existing `geo-audit` skill against the configured domain, then runs `geo-compare` against the prior month's audit when one exists. Writes audit + delta artifacts and patches the cross-project dashboard. Use when "/seo-geo-audit-monthly <config>" or fired by a 1st-of-month scheduled routine.
allowed-tools: Read, Bash, Glob, Write
---

# seo-geo-audit-monthly — Monthly GEO audit + delta

## Contract

**Input:** path to `projects/<project_id>.json`.

**Output:**
1. `<repo>/<geo_dir>/audit-YYYY-MM.md` — full geo-audit output for `<config.domain>`.
2. `<repo>/<geo_dir>/delta-YYYY-MM.md` — geo-compare output vs prior month (skipped if no prior).
3. Mirrored to `dashboard/runs/<project_id>/`.
4. JSON patch to `update-dashboard.sh` setting `geo_score`, `geo_score_delta`, `last_run.geo`.

This skill is intentionally a thin wrapper. The intelligence lives in the existing `geo-audit` and `geo-compare` skills — this one just feeds them the right domain and shuttles their outputs into the cross-project layout.

## Run procedure

### 1. Validate + load config

```bash
CONFIG="$1"
jq -e .project_id "$CONFIG" >/dev/null || exit 1
[ "$(jq -r '.active // true' "$CONFIG")" = "true" ] || exit 0

PROJECT_ID=$(jq -r '.project_id' "$CONFIG")
DOMAIN=$(jq -r '.domain' "$CONFIG")
DISPLAY=$(jq -r '.display_name' "$CONFIG")
REPO=$(jq -r '.repo_path' "$CONFIG")
GEO_DIR=$(jq -r '.outputs.geo_dir // "research/geo"' "$CONFIG")
YYYYMM=$(date +'%Y-%m')
AUDIT_LOCAL="$REPO/$GEO_DIR/audit-$YYYYMM.md"
DELTA_LOCAL="$REPO/$GEO_DIR/delta-$YYYYMM.md"
AUDIT_MIRROR="$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID/audit-$YYYYMM.md"
DELTA_MIRROR="$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID/delta-$YYYYMM.md"
mkdir -p "$REPO/$GEO_DIR" "$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID"
```

### 2. Run geo-audit

Invoke the `geo-audit` skill against `https://$DOMAIN`. The skill produces a composite GEO Score (0–100) and a per-dimension breakdown (citability, crawlers, llms.txt, brand mentions, content, schema, technical, platform readiness).

Write the geo-audit output to `$AUDIT_LOCAL` and mirror to `$AUDIT_MIRROR`. Parse the composite score from the output for the dashboard patch.

### 3. Run geo-compare (only if prior month exists)

Glob for the most recent `audit-YYYY-MM.md` in `$REPO/$GEO_DIR` that is NOT the current month. If found, invoke `geo-compare` with the prior file as baseline and this run's audit as current. Output to `$DELTA_LOCAL` mirrored to `$DELTA_MIRROR`. Parse the score delta.

If no prior audit exists (first run for this project), skip the compare step cleanly and set delta to `null`.

### 4. Patch dashboard

```bash
NOW=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
PATCH=$(jq -n \
  --arg pid "$PROJECT_ID" \
  --argjson score "$GEO_SCORE" \
  --argjson delta "${GEO_DELTA:-null}" \
  --arg ts "$NOW" \
  '{projects: {($pid): {geo_score: $score, geo_score_delta: $delta, last_run: {geo: $ts}}}}')
echo "$PATCH" | "$HOME/Documents/SEOshaf/lib/update-dashboard.sh"
```

### 5. Exit summary

`geo <project_id>: score=<n>, delta=<±n|first-run>, artifact: <path>`

## Generalization invariant

This skill never references a specific domain, vertical, or buyer persona. `$DOMAIN` flows entirely from the config. The geo-audit and geo-compare skills are already domain-agnostic; this wrapper preserves that property by passing the value through.
