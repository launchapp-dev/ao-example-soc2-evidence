# SOC 2 Evidence Collector — Agent Context

This repo is an AO workflow that automates SOC 2 Type II evidence collection for
engineering organizations. It collects evidence from GitHub (git history, branch
protection, CI/CD, access controls), analyzes gaps against AICPA Trust Service
Criteria, and compiles auditor-ready evidence packages.

## Project Layout

```
soc2-evidence/
├── .ao/workflows/          # AO workflow definitions
├── config/
│   ├── org-config.yaml     # EDIT THIS: your org name, repos in scope, audit period
│   ├── control-framework.yaml  # TSC criteria → control mappings
│   └── evidence-sources.yaml  # Evidence source definitions
├── scripts/
│   ├── collect-git-evidence.sh     # git log + branch protection + PR reviews
│   ├── collect-cicd-evidence.sh    # GitHub Actions workflows, runs, environments
│   ├── collect-access-evidence.sh  # Org members, teams, repo permissions
│   ├── collect-config-evidence.sh  # Security settings, policy files, secrets audit
│   └── quick-collect.sh            # Lightweight freshness check
├── templates/
│   ├── control-narrative.md   # Template for per-criterion evidence narratives
│   ├── evidence-record.md     # Template for individual evidence items
│   └── auditor-summary.md     # Template for formal AICPA-format document
├── data/                   # Generated during runs (gitignored in production)
│   ├── raw/                # Raw JSON from CLI tools
│   ├── evidence-records/   # Normalized evidence records by TSC category
│   ├── control-map.json    # Structured criteria → controls mapping
│   ├── gap-analysis.json   # Gap analysis results with per-control status
│   └── ...
└── output/                 # Auditor-ready documents (gitignored in production)
    ├── evidence-package/   # Per-category evidence documents (CC, A, PI, C, P)
    ├── control-matrix.md
    ├── executive-summary.md
    ├── auditor-summary.md
    └── evidence-index.md
```

## Key Data Formats

### control-map.json
```json
{
  "CC6.1": {
    "criterion_id": "CC6.1",
    "category": "Security",
    "title": "Logical access security",
    "controls": [
      {
        "control_id": "AC-01",
        "description": "...",
        "evidence_requirements": [
          { "evidence_id": "ev-access-review", "type": "gh_api", "source": "access_reviews" }
        ]
      }
    ]
  }
}
```

### evidence-records/CC.json (array)
```json
[
  {
    "evidence_id": "ev-001",
    "criteria": ["CC6.1", "CC6.2"],
    "control_id": "AC-01",
    "evidence_type": "automated",
    "source": "GitHub API - org members",
    "collected_at": "2025-10-01T06:00:00Z",
    "status": "current",
    "summary": "...",
    "raw_reference": "data/raw/org-members.json",
    "data_points": {}
  }
]
```

### gap-analysis.json (array)
```json
[
  {
    "control_id": "AC-01",
    "criteria": ["CC6.1"],
    "control_status": "effective",
    "evidence_coverage": 100,
    "gaps": [],
    "trend": "stable"
  }
]
```

## Decision Contract

The `analyze-gaps` phase outputs a JSON verdict as its final line:
```json
{ "verdict": "advance", "reasoning": "All controls effective. No material weaknesses." }
```
or
```json
{ "verdict": "rework", "reasoning": "CC6.1 AC-01: outside collaborator access unreviewed for 200 days." }
```

- `advance` → workflow proceeds directly to `compile-audit-package`
- `rework` → workflow routes to `plan-remediation` first, then `compile-audit-package`

## Important Notes

- **Never log secret values** — scripts collect secret names and counts only, never values
- **PII awareness** — org member logins are collected; treat output files as internal
- **Staleness thresholds** — evidence >90 days old is "stale"; >180 days is "expired"
- **Compensating controls** — gap-analyzer should recognize when multiple evidence items
  together satisfy a criterion even if no single item fully satisfies it
- **Audit tone** — report-compiler output must be professional and suitable for external auditors

## Customization

To add a new TSC criterion:
1. Add it to `config/control-framework.yaml` with its control(s) and evidence sources
2. Add the evidence source to `config/evidence-sources.yaml`
3. Update the relevant collection script if a new API endpoint is needed

To add a new in-scope repo:
1. Add the repo name to `repos_in_scope` in `config/org-config.yaml`
2. Re-run the full `evidence-collection` workflow

## Running Locally

```bash
# Prerequisites
gh auth login
export GH_TOKEN=$(gh auth token)

# Run a single collection script manually
bash scripts/collect-access-evidence.sh

# Or run the full workflow
ao workflow run evidence-collection
```
