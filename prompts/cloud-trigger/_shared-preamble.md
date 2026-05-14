# Shared preamble — every cloud-trigger cadence opens with this block

The RemoteTrigger has cloned the customer repo and you are inside its working tree. Set up git identity, refuse to run if config is missing or `active: false`, and exit cleanly.

```bash
git config user.name sahmed723
git config user.email shafay.ahmed98@gmail.com

CFG=".seoshaf/config.json"
[ -f "$CFG" ] || { echo "fatal: $CFG not found — repo is not seoshaf-enabled"; exit 1; }
ACTIVE=$(jq -r '.active // false' "$CFG")
[ "$ACTIVE" = "true" ] || { echo "project inactive — exiting clean"; exit 0; }

PROJECT_ID=$(jq -r '.project_id' "$CFG")
DOMAIN=$(jq -r '.domain' "$CFG")
DISPLAY=$(jq -r '.display_name' "$CFG")
RESEARCH_DIR=$(jq -r '.outputs.research_dir // "research/seo"' "$CFG")
GEO_DIR=$(jq -r '.outputs.geo_dir // "research/geo"' "$CFG")
TODAY=$(date -u +'%Y-%m-%d')

# Sanity — make sure we're on a fresh branch off main
git fetch origin main
git checkout main
git reset --hard origin/main
```

Hard rules:

- Branch prefix: `claude/seo/<cadence>-<YYYY-MM-DD>`.
- Base branch for the PR: `main`.
- Commit messages and PR titles: ASCII-only (no em-dashes).
- Wall clock cap: 20 minutes. If you're nearing the cap, commit what you have, open the PR, and exit.
- Never push directly to `main`. Never auto-merge.
- If anything in this preamble fails, exit non-zero so the next-run notification surfaces the failure.
