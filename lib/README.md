# SEOshaf — Operator guide

Single home for managed SEO/GEO agents that run across multiple projects.

## Mental model

Three layers. Only the bottom layer is project-specific.

```
Scheduled routines (cron → Claude)   ← created from configs, not hand-written
Skill templates (~/.claude/skills)   ← written ONCE, never edited per-project
Project configs (projects/*.json)    ← the ONLY file you add per project
```

If you ever find yourself editing a `seo-*` skill or `_schema.json` because of a new project, stop — the system has regressed.

## Day-to-day commands

### Add a new project
```
/seo-onboard <project-id> https://<domain> /absolute/path/to/repo
```
Probes the domain, scaffolds `projects/<project-id>.json`, asks you to fill in the persona filter + queries, registers 4 cron routines. Done.

### Fire a cadence manually
```
/seo-indexation-watch         /Users/shafayahmed/Documents/SEOshaf/projects/<id>.json
/seo-serp-citation-tracker    /Users/shafayahmed/Documents/SEOshaf/projects/<id>.json
/seo-keyword-competitor-refresh /Users/shafayahmed/Documents/SEOshaf/projects/<id>.json
/seo-geo-audit-monthly        /Users/shafayahmed/Documents/SEOshaf/projects/<id>.json
```

### See the dashboard
```
open ~/Documents/SEOshaf/dashboard/DASHBOARD.md
```

### Pause a project without deleting history
Set `"active": false` in `projects/<id>.json`. All four cadences will exit clean on their next fire; the dashboard hides the row.

## Files

| Path | Purpose |
|---|---|
| `projects/_schema.json` | The contract every project config validates against. |
| `projects/<id>.json` | Per-project parameters. |
| `dashboard/state.json` | Source-of-truth metrics, patched on every run. |
| `dashboard/DASHBOARD.md` | Generated view. Regenerated after every patch. |
| `dashboard/runs/<id>/` | Mirror of every artifact a cadence produced for the project. |
| `lib/update-dashboard.sh` | jq merger. Reads a patch on stdin, applies to state.json, regenerates DASHBOARD.md. |
| `lib/deterministic-cron.sh` | `hash(project_id) + cadence_offset` → cron minute. Stable per project, no fleet pile-ups. |
| `lib/schedule-routines.sh` | Emits the 4 scheduled-task JSON specs for a project. The agent reads them and calls `mcp__scheduled-tasks__create_scheduled_task`. |

## Skills

| Skill | Cadence | What it does |
|---|---|---|
| `seo-indexation-watch` | daily | Sitemap + priority-page health check. Writes artifact only on regression. |
| `seo-serp-citation-tracker` | weekly (Mon) | SERP rank + AI-citation snapshot, week-over-week delta. |
| `seo-keyword-competitor-refresh` | monthly (1st) | Semrush competitor mining + seed expansion + scoring + page-build queue. |
| `seo-geo-audit-monthly` | monthly (1st) | Wrapper over `geo-audit` + `geo-compare`. Score delta vs prior month. |
| `seo-onboard-project` | on demand | The generalization tool — scaffolds a new project end-to-end. |

## The three rules

1. **Configs are the only place project-specific data lives.** Never edit a skill to add a competitor list, a domain, a buyer term. If a skill needs more context, add a field to `_schema.json` (which is project-agnostic) and read it from there.
2. **Cron times are deterministic.** Never hand-pick a schedule minute. `deterministic-cron.sh` exists so that adding the 10th project doesn't require auditing 9 prior schedules for collisions.
3. **History is append-only.** Artifacts are timestamped. State is patched, not replaced. A project marked `active: false` retains its history; setting it back to `true` resumes from where it left off.

## Two ways things can break

- **Semrush MCP not connected** → `seo-keyword-competitor-refresh` exits clean with a "connect Semrush" message and patches nothing. Run `/mcp` to fix.
- **Project repo path moved** → the cadence skill creates the artifact mirror in `dashboard/runs/<id>/` even when the local artifact write fails, but the local copy will be missing. Edit `repo_path` in the config and re-fire the cadence.

## Adding a new cadence (rare — think twice)

If you decide a 5th cadence is genuinely needed across all projects (e.g. quarterly content audit):

1. Add the cadence label to `deterministic-cron.sh` with its hour and an unused offset.
2. Write the new template skill at `~/.claude/skills/seo-<new>/` following the same shape as the others.
3. Add the new task spec to `schedule-routines.sh`.
4. Re-run `/seo-onboard` against each existing project ID to register the new routine (it will be additive — existing routines untouched).

This is the only case where editing a non-config file is correct. It still changes the system uniformly across all projects, not per-project.
