# SEOshaf

A managed-agent SEO + GEO operations system. Four autonomous cadence skills run against a project's live domain on a fixed schedule:

| Cadence | When | What it does |
|---|---|---|
| `seo-indexation-watch` | Daily | Pulls sitemap + samples priority pages. HTTP 200, title regression, redirect-to-404. Silent unless something changed. |
| `seo-serp-citation-tracker` | Weekly (Mon) | Google top-10 capture + AI-citation check (ChatGPT, Perplexity, Gemini) for every query in config. WoW delta. |
| `seo-keyword-competitor-refresh` | Monthly (1st) | Semrush competitor mining + seed expansion + page-build queue. |
| `seo-geo-audit-monthly` | Monthly (1st) | Full GEO audit (AI citability, platform readiness, technical, content, schema). Composite GEO score + delta vs prior month. |

## How it works

Each project is a single JSON file matching `projects/_schema.json`. The file lives in the project's own GitHub repo at `.seoshaf/config.json` (private — your domain, queries, persona filter). The four cadence skills clone this repo, read the config, run the cadence, write artifacts back to the repo, and optionally open a PR.

Scheduling is via `RemoteTrigger` (claude.ai routines) — one cron-scheduled cloud session per cadence, 24/7, no laptop dependency.

## Repo layout

```
seoshaf/
├── skills/                          # The four cadence skills (SKILL.md each)
│   ├── seo-indexation-watch/
│   ├── seo-serp-citation-tracker/
│   ├── seo-keyword-competitor-refresh/
│   └── seo-geo-audit-monthly/
├── lib/                             # Shared scripts
│   ├── deterministic-cron.sh        # Hash project_id → cron minute/hour offsets
│   ├── schedule-routines.sh         # Emit the 4 trigger specs for a project
│   ├── update-dashboard.sh          # Patch DASHBOARD.md / state.json
│   └── README.md
├── projects/
│   ├── _schema.json                 # JSONSchema contract
│   └── _template.json               # Starter template
└── .gitignore
```

## Adding a new project

1. Copy `projects/_template.json` → your project repo at `.seoshaf/config.json`.
2. Fill in the fields (especially `persona_filter`, `queries.serp`, `queries.ai`).
3. Set `"active": true`.
4. Register the four cadences (one of):
   - Use the `onboard-cadences` Claude Code skill: `/onboard-cadences <project-id> <github-repo-url>`
   - Or call the claude.ai routines API directly with the four prompts emitted by `lib/schedule-routines.sh`.

## License

MIT.
