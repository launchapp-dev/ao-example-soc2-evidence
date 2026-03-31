# SOC 2 Evidence Collector — Build Plan

## Overview

SOC 2 Type II evidence collection pipeline — maps trust service criteria (TSC) to
organizational controls, automatically collects evidence from git history, CI/CD configs,
access reviews, and infrastructure configurations, detects gaps between required and
collected evidence, generates remediation tasks for missing controls, and compiles
auditor-ready evidence packages organized by criteria.

All evidence collection uses command phases with real CLI tools (`gh`, `git`, `jq`, `find`).
Agent phases handle criteria mapping, gap analysis, remediation planning, and report compilation.
Memory MCP stores evidence baselines for tracking collection completeness across quarterly cycles.
Sequential-thinking MCP helps with complex multi-criteria control mapping decisions.

---

## Agents (5)

| Agent | Model | Role |
|---|---|---|
| **criteria-mapper** | claude-sonnet-4-6 | Maps TSC criteria to organizational controls, reads control framework config |
| **evidence-analyzer** | claude-haiku-4-5 | Normalizes raw collected evidence into structured evidence records |
| **gap-analyzer** | claude-sonnet-4-6 | Compares required vs collected evidence, identifies gaps and staleness |
| **remediation-planner** | claude-sonnet-4-6 | Creates prioritized remediation tasks for evidence gaps |
| **report-compiler** | claude-opus-4-6 | Generates auditor-ready evidence packages and compliance narratives |

### MCP Servers Used by Agents

- **filesystem** — all agents read/write JSON/markdown evidence files
- **github** (gh-cli-mcp) — remediation-planner creates issues for gaps; evidence-analyzer reads repo metadata
- **memory** — gap-analyzer loads previous evidence baseline for trend tracking; report-compiler stores current baseline
- **sequential-thinking** — criteria-mapper uses for complex TSC→control mapping; gap-analyzer uses for multi-factor gap assessment

---

## Trust Service Criteria Categories

The pipeline covers all 5 TSC categories:

| Category | Code | Focus |
|---|---|---|
| Security | CC | Common criteria — access, change mgmt, risk assessment |
| Availability | A | System uptime, disaster recovery, monitoring |
| Processing Integrity | PI | Data validation, error handling, completeness |
| Confidentiality | C | Data classification, encryption, retention |
| Privacy | P | PII handling, consent, disclosure |

---

## Workflows (2)

### 1. `evidence-collection` (primary — triggered quarterly or on-demand)

Full evidence collection cycle: criteria mapping → evidence collection → gap analysis → remediation → audit package.

**Phases:**

1. **load-control-framework** (agent: criteria-mapper)
   - Reads `config/control-framework.yaml` which maps TSC criteria → controls
   - Reads `config/evidence-sources.yaml` which defines where evidence lives
   - Validates completeness — every CC/A/PI/C/P criterion has at least one control mapped
   - Writes `data/control-map.json` — structured mapping of criteria → controls → evidence requirements
   - Writes `data/collection-manifest.json` — list of all evidence items to collect with source type and path

2. **collect-git-evidence** (command)
   - Command: `bash scripts/collect-git-evidence.sh`
   - Collects change management evidence from git:
     - `git log --format=json` for recent commits (change management — CC8.1)
     - `git log --all --grep="review" --grep="approve"` for code review evidence (CC6.1)
     - Branch protection rules via `gh api repos/{owner}/{repo}/branches/{branch}/protection`
     - PR merge data via `gh api repos/{owner}/{repo}/pulls?state=closed --jq`
   - Writes `data/raw/git-commits.json`, `data/raw/branch-protection.json`, `data/raw/pr-reviews.json`

3. **collect-cicd-evidence** (command)
   - Command: `bash scripts/collect-cicd-evidence.sh`
   - Collects CI/CD and deployment evidence:
     - GitHub Actions workflows via `gh api repos/{owner}/{repo}/actions/workflows`
     - Recent workflow runs via `gh api repos/{owner}/{repo}/actions/runs`
     - Environment configs via `gh api repos/{owner}/{repo}/environments`
     - Deployment frequency and success rates
   - Writes `data/raw/workflows.json`, `data/raw/workflow-runs.json`, `data/raw/environments.json`

4. **collect-access-evidence** (command)
   - Command: `bash scripts/collect-access-evidence.sh`
   - Collects access control evidence:
     - Org members and roles via `gh api orgs/{org}/members`
     - Team structure via `gh api orgs/{org}/teams`
     - Repo collaborators and permission levels
     - Outside collaborators list
     - SSO/SAML identity data via `gh api orgs/{org}/credential-authorizations` (if available)
   - Writes `data/raw/org-members.json`, `data/raw/teams.json`, `data/raw/repo-access.json`

5. **collect-config-evidence** (command)
   - Command: `bash scripts/collect-config-evidence.sh`
   - Collects infrastructure and configuration evidence:
     - Repository security settings (vulnerability alerts, secret scanning, Dependabot)
       via `gh api repos/{owner}/{repo}/vulnerability-alerts` etc.
     - `.github/` directory contents (CODEOWNERS, security policy, issue templates)
     - Secrets audit (count of secrets, no values) via `gh api repos/{owner}/{repo}/actions/secrets`
     - Finds config files: `find . -name "*.yaml" -o -name "*.yml" -o -name "*.json" | head -50`
   - Writes `data/raw/security-settings.json`, `data/raw/repo-configs.json`, `data/raw/secrets-audit.json`

6. **normalize-evidence** (agent: evidence-analyzer)
   - Reads all raw evidence from `data/raw/`
   - For each evidence item, creates a structured record:
     - `evidence_id`: unique identifier
     - `criteria`: which TSC criteria this satisfies (e.g., CC6.1, CC8.1)
     - `control`: which control this maps to
     - `evidence_type`: "automated" | "manual" | "configuration"
     - `source`: where the evidence came from
     - `collected_at`: timestamp
     - `status`: "current" | "stale" | "incomplete"
     - `summary`: human-readable description of what the evidence shows
     - `raw_reference`: path to raw data file
   - Writes `data/evidence-records/` — one JSON file per criteria category (CC.json, A.json, etc.)
   - Writes `data/evidence-summary.json` — totals by category, status, and type

7. **analyze-gaps** (agent: gap-analyzer)
   - Reads `data/control-map.json` (what's required)
   - Reads `data/evidence-records/` (what was collected)
   - Uses memory MCP to load previous collection baseline (`evidence-baseline-latest`)
   - Uses sequential-thinking for multi-factor gap assessment
   - For each control, determines:
     - `control_status`: "effective" | "deficiency" | "material_weakness"
     - `evidence_coverage`: percentage of required evidence collected
     - `gaps[]`: list of missing or stale evidence items
     - `trend`: "improving" | "stable" | "degrading" (vs previous baseline)
   - Writes `data/gap-analysis.json`
   - Writes `data/gap-analysis-summary.json` — counts by status and severity
   - **Decision contract:** `{verdict, reasoning}`
     - `advance` — no material weaknesses found, proceed to reporting
     - `rework` — material weaknesses detected, needs remediation first

8. **plan-remediation** (agent: remediation-planner)
   - Only reached if gap-analyzer returns `rework` OR if there are any deficiencies
   - Reads `data/gap-analysis.json`
   - For each gap, creates a remediation task:
     - `task_id`, `priority` (P0-P3), `title`, `description`
     - `affected_criteria[]`, `affected_controls[]`
     - `remediation_type`: "collect_evidence" | "implement_control" | "update_config" | "manual_review"
     - `assignee_suggestion` based on gap type
     - `due_date_suggestion` based on priority and next audit date
   - Creates GitHub issues for P0 and P1 items via github MCP
   - Checks `data/issue-tracker.json` for deduplication before creating issues
   - Writes `data/remediation-plan.json`
   - Writes `output/remediation-tracker.md` — prioritized human-readable task list

9. **compile-audit-package** (agent: report-compiler)
   - Reads all evidence records, gap analysis, and remediation plan
   - Stores current evidence snapshot to memory MCP as `evidence-baseline-latest`
   - Generates auditor-ready output documents:
     - `output/evidence-package/` — organized by TSC category:
       - `CC-security.md` — all security criteria with control narratives and evidence links
       - `A-availability.md` — availability criteria evidence
       - `PI-processing-integrity.md` — processing integrity evidence
       - `C-confidentiality.md` — confidentiality evidence
       - `P-privacy.md` — privacy evidence
     - `output/control-matrix.md` — full control × criteria mapping with status
     - `output/executive-summary.md` — one-page compliance posture summary
     - `output/auditor-summary.md` — formal audit-ready document with:
       - Scope and methodology
       - Control environment description
       - Test results by criteria
       - Exceptions and remediation status
       - Management assertions
     - `output/evidence-index.md` — numbered evidence inventory with cross-references
   - Writes final status to `data/collection-status.json`

### 2. `gap-monitor` (lightweight — weekly schedule)

Quick check for evidence staleness and control drift.

**Phases:**

1. **quick-collect** (command)
   - Command: `bash scripts/quick-collect.sh`
   - Lightweight collection — only checks timestamps and counts, not full evidence
   - Checks: recent commits exist, CI/CD runs recent, access reviews current
   - Writes `data/raw/quick-check.json`

2. **check-freshness** (agent: gap-analyzer)
   - Reads `data/raw/quick-check.json` and previous `data/evidence-summary.json`
   - Checks each evidence category for staleness (>90 days since collection)
   - Checks for new repos/members not covered by last full collection
   - Writes `output/freshness-report.md`
   - If any category is stale: creates a GitHub issue recommending a full collection run

---

## Phase Routing

### evidence-collection workflow
```
load-control-framework
  → collect-git-evidence
  → collect-cicd-evidence
  → collect-access-evidence
  → collect-config-evidence
  → normalize-evidence
  → analyze-gaps
    ├─ advance → compile-audit-package (done)
    └─ rework → plan-remediation → compile-audit-package (done)
```

### gap-monitor workflow
```
quick-collect → check-freshness (done)
```

---

## Schedules

| Schedule | Cron | Workflow | Purpose |
|---|---|---|---|
| `quarterly-collection` | `0 6 1 */3 *` | evidence-collection | Full evidence collection every quarter (1st of Jan/Apr/Jul/Oct at 6am) |
| `weekly-freshness` | `0 8 * * 1` | gap-monitor | Weekly Monday freshness check |

---

## Config Files

### `config/control-framework.yaml`
Defines the complete TSC → control mapping. Pre-populated with common SOC 2 controls:
- CC1.x: Control environment (governance, org structure)
- CC2.x: Communication and information
- CC3.x: Risk assessment
- CC4.x: Monitoring activities
- CC5.x: Control activities
- CC6.x: Logical and physical access (access reviews, MFA, least privilege)
- CC7.x: System operations (change detection, incident response)
- CC8.x: Change management (SDLC, code review, testing)
- CC9.x: Risk mitigation
- A1.x: Availability commitments (monitoring, DR, backups)
- PI1.x: Processing integrity (validation, error handling)
- C1.x: Confidentiality (classification, encryption)
- P1.x–P8.x: Privacy (notice, consent, use, disclosure, retention)

### `config/evidence-sources.yaml`
Maps each control to where evidence can be found:
```yaml
sources:
  git_history:
    type: command
    description: "Git commit history for change management evidence"
    criteria: [CC8.1, CC8.2, CC8.3]
  branch_protection:
    type: gh_api
    description: "Branch protection rules for access control evidence"
    criteria: [CC6.1, CC6.3, CC8.1]
  ci_cd_workflows:
    type: gh_api
    description: "CI/CD pipeline configs for change management evidence"
    criteria: [CC8.1, CC7.1]
  access_reviews:
    type: gh_api
    description: "Org member and team data for access control evidence"
    criteria: [CC6.1, CC6.2, CC6.3]
  security_settings:
    type: gh_api
    description: "Repo security features for risk management evidence"
    criteria: [CC3.1, CC7.1, CC7.2]
```

### `config/org-config.yaml`
```yaml
organization: "example-org"
audit_period:
  start: "2025-01-01"
  end: "2025-12-31"
repos_in_scope:
  - "main-app"
  - "api-service"
  - "infrastructure"
report_title: "SOC 2 Type II Evidence Package"
auditor: "External Audit Firm LLP"
```

---

## Supporting Files

### Scripts (command phase scripts)
- `scripts/collect-git-evidence.sh` — git log + gh API for change management evidence
- `scripts/collect-cicd-evidence.sh` — gh API for CI/CD workflows, runs, environments
- `scripts/collect-access-evidence.sh` — gh API for org members, teams, permissions
- `scripts/collect-config-evidence.sh` — gh API for security settings, configs
- `scripts/quick-collect.sh` — lightweight freshness check

### Data directories
- `data/raw/` — raw collected evidence (JSON from APIs)
- `data/evidence-records/` — normalized evidence records by category
- `data/` — control maps, gap analysis, remediation plans

### Output
- `output/evidence-package/` — auditor-ready evidence by TSC category
- `output/` — executive summary, control matrix, remediation tracker, auditor summary

### Templates
- `templates/control-narrative.md` — template for control description sections
- `templates/evidence-record.md` — template for individual evidence items
- `templates/auditor-summary.md` — template for formal auditor document

---

## Decision Contracts

### analyze-gaps phase
```yaml
required_fields: [verdict, reasoning]
# verdict: "advance" | "rework"
# reasoning: explanation of gap analysis findings
# advance = no material weaknesses, safe to compile final package
# rework = material weaknesses found, must plan remediation first
```

---

## What Makes This Example Interesting

1. **Real compliance workflow** — SOC 2 evidence collection is a genuine pain point for engineering teams; this automates the tedious parts
2. **Command phases with real tools** — all evidence collection uses `gh` CLI and `git` commands that produce real data
3. **Multi-criteria reasoning** — mapping evidence to trust service criteria requires nuanced judgment (sequential-thinking MCP)
4. **Decision routing** — material weakness detection triggers remediation before final package compilation
5. **Temporal awareness** — tracks evidence freshness, staleness, and trends across quarterly collection cycles (memory MCP)
6. **Auditor-ready output** — generates formal documents that could actually be handed to an auditor
7. **Variety of models** — uses Opus for complex report compilation, Sonnet for analysis, Haiku for data normalization
