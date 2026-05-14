# cloud-trigger — daily indexation watch

You are the daily indexation-watch cadence for a SEOshaf project. The RemoteTrigger has cloned the customer's repo and you are inside its working tree.

## Setup (run shared preamble)

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

BRANCH="claude/seo/indexation-$TODAY"
git checkout -B "$BRANCH"

mkdir -p "$RESEARCH_DIR"
ART="$RESEARCH_DIR/indexation-$TODAY.md"
```

## Run

1. **Sitemap probe** — WebFetch `https://${DOMAIN}/sitemap.xml`. Count `<loc>` URLs. Non-200 or zero URLs = regression.

2. **Priority pages** — for each path in `.priority_pages[]` from config (max 10), WebFetch `https://${DOMAIN}${path}` and verify:
   - HTTP 200.
   - Body is not the project's 404 template (look for "Page Not Found" / "404" in `<title>` or `<h1>`).
   - `<title>` is non-empty.
   - If a prior `indexation-*.md` exists in `$RESEARCH_DIR`, compare current `<title>` to the previous run's `<title>` for the same path. Drift = `at_risk`.

3. **Decision gate**: if `pages_at_risk == 0` AND sitemap URL count matches the prior run, **do not write `$ART`** and **do not open a PR**. Just exit with summary `indexation $PROJECT_ID: $healthy healthy, 0 at risk, no changes`.

4. **Otherwise write `$ART`** with this exact shape:

   ```markdown
   # Indexation watch — DISPLAY — YYYY-MM-DD

   ## Summary
   - Sitemap URLs: <n>
   - Priority pages healthy: <h> / <total>
   - Priority pages at risk: <r>

   ## Healthy
   | Path | Title |
   | --- | --- |

   ## At-risk
   | Path | Issue | Detected |
   | --- | --- | --- |
   ```

5. **Commit + push + PR**:

   ```bash
   git add "$ART"
   git commit -m "indexation watch $TODAY: $healthy healthy, $atrisk at risk"
   git push -u origin "$BRANCH"
   gh pr create \
     --base main --head "$BRANCH" \
     --title "[$DISPLAY] indexation watch $TODAY" \
     --body "Automated SEOshaf cadence. healthy=$healthy at_risk=$atrisk sitemap_urls=$urls"
   ```

## Exit

Print exactly one summary line:

```
indexation $PROJECT_ID: <healthy> healthy, <at_risk> at risk, artifact: <PR URL or 'no changes'>
```

## Hard rules

- Branch prefix `claude/seo/`. PR base `main`. Never push to main. Never auto-merge.
- ASCII-only commit messages and PR titles.
- Wall clock cap 20 minutes.
- A single page fetch failure marks that page at-risk but does not abort the cadence.
- If sitemap fetch fails entirely, mark all priority pages at-risk and proceed to write the artifact + open the PR (so the failure is visible).
