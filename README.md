# SOC 2 Evidence Collector

Automates SOC 2 Type II evidence collection — maps trust service criteria to controls, collects evidence from git and GitHub, detects gaps, generates remediation tasks, and compiles auditor-ready evidence packages.

---

## Workflow Diagram

```
QUARTERLY COLLECTION (evidence-collection)
─────────────────────────────────────────
load-control-framework          [criteria-mapper / Sonnet]
  │  Reads control-framework.yaml → control-map.json
  │  Reads evidence-sources.yaml → collection-manifest.json
  ▼
collect-git-evidence            [command: bash]
  │  git log + gh api → git-commits.json, branch-protection.json, pr-reviews.json
  ▼
collect-cicd-evidence           [command: bash]
  │  gh api → workflows.json, workflow-runs.json, environments.json
  ▼
collect-access-evidence         [command: bash]
  │  gh api → org-members.json, teams.json, repo-access.json
  ▼
collect-config-evidence         [command: bash]
  │  gh api → security-settings.json, repo-configs.json, secrets-audit.json
  ▼
normalize-evidence              [evidence-analyzer / Haiku]
  │  Reads data/raw/* → evidence-records/CC.json, A.json, PI.json, C.json, P.json
  │  Writes evidence-summary.json
  ▼
analyze-gaps                    [gap-analyzer / Sonnet]
  │  Compares required vs collected → gap-analysis.json
  │  Loads memory baseline for trend tracking
  │  Uses sequential-thinking for complex assessments
  │
  ├─ verdict: advance ──────────────────────────┐
  │                                             ▼
  └─ verdict: rework                    compile-audit-package
       │                                [report-compiler / Opus]
       ▼                                  Saves baseline to memory
  plan-remediation                        Generates 8 output documents
  [remediation-planner / Sonnet]
  │  Creates GitHub issues for P0/P1
  │  Writes remediation-plan.json
  │  Writes output/remediation-tracker.md
  └──────────────────────────────────────┘


WEEKLY FRESHNESS CHECK (gap-monitor)
─────────────────────────────────────
quick-collect                   [command: bash]
  │  Checks timestamps and counts only
  ▼
check-freshness                 [gap-analyzer / Sonnet]
     Compares to last full collection
     Creates GitHub issue if stale
```

---

## Quick Start

```bash
# 1. Configure your organization
cp config/org-config.yaml config/org-config.local.yaml
# Edit org-config.yaml with your GitHub org name, repos in scope, and audit period

# 2. Authenticate with GitHub
gh auth login

# 3. Start the AO daemon and run a full collection
cd examples/soc2-evidence
ao daemon start
ao queue enqueue --title "Q4 2025 SOC 2 Evidence" --workflow-ref evidence-collection

# 4. Watch it run
ao daemon stream --pretty

# 5. Review the output
cat output/executive-summary.md
cat output/auditor-summary.md
ls output/evidence-package/
```

To run manually on a schedule:
```bash
# Full quarterly collection (also runs automatically via cron)
ao workflow run evidence-collection

# Weekly freshness check (also runs automatically every Monday)
ao workflow run gap-monitor
```

---

## Agents

| Agent | Model | Role |
|---|---|---|
| **criteria-mapper** | claude-sonnet-4-6 | Reads control framework config, validates criteria coverage, produces control-map.json and collection-manifest.json |
| **evidence-analyzer** | claude-haiku-4-5 | Normalizes raw JSON evidence into structured records with criteria mappings and status assessments |
| **gap-analyzer** | claude-sonnet-4-6 | Compares required vs collected evidence, classifies control effectiveness, detects trends vs historical baseline |
| **remediation-planner** | claude-sonnet-4-6 | Creates prioritized (P0–P3) remediation tasks, creates GitHub issues for critical gaps |
| **report-compiler** | claude-opus-4-6 | Generates 8 auditor-ready output documents including formal AICPA-format audit summary |

---

## Output Files

After a successful run:

```
output/
├── evidence-package/
│   ├── CC-security.md          # All CC criteria with evidence and narratives
│   ├── A-availability.md       # Availability criteria evidence
│   ├── PI-processing-integrity.md
│   ├── C-confidentiality.md
│   └── P-privacy.md
├── control-matrix.md           # Controls × criteria grid with ✓/⚠/✗ status
├── executive-summary.md        # One-page compliance posture summary
├── auditor-summary.md          # Formal AICPA-format audit document
├── evidence-index.md           # Numbered inventory of all evidence
└── remediation-tracker.md      # Prioritized task list (if gaps found)
```

---

## AO Features Demonstrated

| Feature | Where Used |
|---|---|
| **Decision routing** | `analyze-gaps` routes to `plan-remediation` on `rework`, skips it on `advance` |
| **Command phases** | All 4 evidence collection phases use bash scripts with real CLI tools |
| **Memory MCP** | `gap-analyzer` loads previous baseline; `report-compiler` saves new baseline |
| **Sequential-thinking MCP** | `criteria-mapper` and `gap-analyzer` for complex compliance reasoning |
| **GitHub MCP** | `remediation-planner` creates issues for P0/P1 gaps |
| **Retry policies** | All command phases have `max_attempts: 2` for transient API failures |
| **Cron schedules** | Quarterly full collection + weekly freshness check |
| **Multiple models** | Opus for report compilation, Sonnet for analysis, Haiku for normalization |
| **Rework loop** | `analyze-gaps` can trigger `plan-remediation` before final compilation |

---

## Requirements

### Tools
- `gh` — GitHub CLI (authenticated: `gh auth login`)
- `git` — for commit history collection
- `python3` — for JSON processing in scripts (stdlib only)
- `jq` — optional, used by some gh API calls

### API Keys / Auth
- `GH_TOKEN` — GitHub Personal Access Token with:
  - `repo` scope (for private repos)
  - `read:org` scope (for org member/team data)
  - `admin:org` scope (optional, for credential authorizations)
  - Or use `gh auth login` and set `GH_TOKEN=$(gh auth token)`

### MCP Servers (auto-installed via npx)
- `@modelcontextprotocol/server-filesystem`
- `@modelcontextprotocol/server-sequential-thinking`
- `@modelcontextprotocol/server-memory`
- `gh-cli-mcp`

### Configuration
Edit `config/org-config.yaml`:
- `github_org`: your GitHub organization name
- `repos_in_scope`: list of repository names to collect evidence from
- `audit_period.start/end`: your SOC 2 audit period dates
- `auditor`: name of your external audit firm

Edit `config/control-framework.yaml` to match your organization's actual controls.
The default framework includes common controls for CC1–CC9, A1, PI1, C1, and P1/P3.

---

## Trust Service Criteria Coverage

| Category | Code | Criteria Covered |
|---|---|---|
| Security | CC | CC1.1, CC2.1, CC3.1, CC6.1–CC6.3, CC7.1–CC7.2, CC8.1, CC9.1 |
| Availability | A | A1.1, A1.2 |
| Processing Integrity | PI | PI1.1, PI1.2 |
| Confidentiality | C | C1.1, C1.2 |
| Privacy | P | P1.1, P3.1 |

Extend `config/control-framework.yaml` to add more criteria for your scope.
