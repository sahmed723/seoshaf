---
name: seo-indexation-watch
description: Daily indexation health check for a SEOshaf project. Takes one argument — the path to a project config under ~/Documents/SEOshaf/projects/. Validates the sitemap loads, samples up to 10 priority pages for HTTP 200 / title regression / redirect-to-404, and emits a JSON dashboard patch. Only writes a markdown artifact when something changed. Use when invoked directly ("/seo-indexation-watch <config-path>") or when a scheduled routine fires it.
allowed-tools: Read, Bash, WebFetch, Write
---

# seo-indexation-watch — Daily indexation health check

## Contract

**Input:** one positional argument, an absolute path to a project config JSON under `~/Documents/SEOshaf/projects/<project_id>.json`.

**Output:**
1. A JSON patch piped to `~/Documents/SEOshaf/lib/update-dashboard.sh` updating `pages_healthy`, `pages_at_risk`, and `last_run.indexation`.
2. **Only if something changed since yesterday** — a markdown artifact at `<repo_path>/<outputs.research_dir>/indexation-YYYY-MM-DD.md` mirrored to `~/Documents/SEOshaf/dashboard/runs/<project_id>/indexation-YYYY-MM-DD.md`.

Hard rule: this skill MUST NOT contain any project name, competitor, or domain literal. Everything project-specific comes from the config path. If you find yourself typing "keelway" or "flexbone" anywhere in the body of this skill, stop and parameterize.

## Run procedure

### 1. Validate config

```bash
CONFIG="$1"
[ -f "$CONFIG" ] || { echo "config not found: $CONFIG" >&2; exit 1; }
jq -e .project_id "$CONFIG" >/dev/null || { echo "invalid config json" >&2; exit 1; }
ACTIVE=$(jq -r '.active // true' "$CONFIG")
[ "$ACTIVE" = "true" ] || { echo "project inactive, exiting clean"; exit 0; }
```

Pull out the fields you need:

```bash
PROJECT_ID=$(jq -r '.project_id' "$CONFIG")
DOMAIN=$(jq -r '.domain' "$CONFIG")
REPO=$(jq -r '.repo_path' "$CONFIG")
RESEARCH_DIR=$(jq -r '.outputs.research_dir // "research/seo"' "$CONFIG")
TODAY=$(date +'%Y-%m-%d')
ART_LOCAL="$REPO/$RESEARCH_DIR/indexation-$TODAY.md"
ART_MIRROR="$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID/indexation-$TODAY.md"
mkdir -p "$REPO/$RESEARCH_DIR" "$HOME/Documents/SEOshaf/dashboard/runs/$PROJECT_ID"
```

### 2. Sitemap probe

Fetch `https://<DOMAIN>/sitemap.xml` with WebFetch and extract every `<loc>` URL. If the sitemap returns non-200 or zero URLs, that itself is a regression — record it.

### 3. Priority page sampling

For each path in `config.priority_pages` (max 10):

- WebFetch `https://<DOMAIN><path>` and verify:
  - HTTP 200
  - The response body is not the project's 404 template (look for "Page Not Found" / "404" in `<title>` or `<h1>`)
  - The `<title>` is non-empty
  - If we have a prior artifact (the most recent `indexation-*.md` in `<RESEARCH_DIR>`), the current `<title>` matches the prior `<title>` for the same path. Title drift = at-risk.

Track each page as `healthy` or `at_risk` with a short reason.

### 4. Optional integration checks

These run only when the config field is present — never hard-coded.

```bash
GSC=$(jq -r '.integrations.gsc_property // empty' "$CONFIG")
BING=$(jq -r '.integrations.bing_site // empty' "$CONFIG")
```

If a GSC MCP server is connected and `$GSC` is set, pull coverage report. Otherwise log "GSC check skipped — not configured" and move on. Same logic for Bing.

### 5. Decide whether to write an artifact

- If `pages_at_risk == 0` AND there were no sitemap/coverage changes vs the prior run, do NOT write `$ART_LOCAL` — just bump the dashboard.
- Otherwise write a short markdown artifact:

```markdown
# Indexation watch — <display_name> — <YYYY-MM-DD>

## Summary
- Sitemap URLs: <n>
- Priority pages healthy: <h> / <total>
- Priority pages at risk: <r>

## At-risk pages
| Path | Issue | Detected |
| --- | --- | --- |
| /pricing | title regressed: "Pricing — Keelway" → "Untitled" | YYYY-MM-DD |

## Integrations
- GSC: <coverage delta or "not configured">
- Bing: <coverage delta or "not configured">
```

Copy the same file to `$ART_MIRROR`.

### 6. Patch the dashboard

```bash
NOW=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
PATCH=$(jq -n \
  --arg pid "$PROJECT_ID" \
  --argjson healthy "$HEALTHY_COUNT" \
  --argjson atrisk "$ATRISK_COUNT" \
  --arg ts "$NOW" \
  '{projects: {($pid): {pages_healthy: $healthy, pages_at_risk: $atrisk, last_run: {indexation: $ts}}}}')
echo "$PATCH" | "$HOME/Documents/SEOshaf/lib/update-dashboard.sh"
```

### 7. Exit summary

Print one line to stdout summarizing the run: `indexation <project_id>: <healthy> healthy, <atrisk> at risk, artifact: <path or 'none'>`.

## Failure handling

- Sitemap fetch fails → record as a regression in the artifact, set `pages_at_risk` to total priority pages count, exit 0 (don't break the schedule).
- A single page fetch fails → mark that page at-risk, continue with the rest.
- Config invalid → exit non-zero so the scheduled task surfaces the failure on the next run notification.

## Generalization invariant

If this skill is ever called against a fresh `projects/<new-id>.json` without prior modification, it must work. Test: a project with only `project_id`, `display_name`, `domain`, `repo_path` set (no priority_pages, no integrations) should produce a sitemap-only artifact with `pages_healthy: 0, pages_at_risk: 0` and not error.
