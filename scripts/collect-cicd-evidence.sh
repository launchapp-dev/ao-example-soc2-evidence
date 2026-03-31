#!/usr/bin/env bash
# collect-cicd-evidence.sh
# Collects CI/CD and deployment evidence from GitHub Actions
# Evidence covers: CC7.1 (monitoring), CC8.1 (change management), A1.1 (availability), PI1.1 (integrity)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"
CONFIG="$PROJECT_ROOT/config/org-config.yaml"

mkdir -p "$RAW_DIR"

ORG=$(grep 'github_org:' "$CONFIG" | awk '{print $2}' | tr -d '"')
REPOS=$(grep -A 20 'repos_in_scope:' "$CONFIG" | grep '  - ' | awk '{print $2}' | tr -d '"')
COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "==> Collecting CI/CD evidence for org: $ORG"

# ── 1. Workflow definitions (CC8.1, CC7.1) ───────────────────────────────────
echo "==> Collecting GitHub Actions workflow definitions..."

WORKFLOWS_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Collecting workflows for $ORG/$REPO..."
  WORKFLOWS=$(gh api "repos/$ORG/$REPO/actions/workflows" \
    --jq '[.workflows[] | {
      id: .id,
      name: .name,
      state: .state,
      path: .path,
      created_at: .created_at,
      updated_at: .updated_at
    }]' 2>/dev/null || echo '[]')

  WORKFLOW_COUNT=$(echo "$WORKFLOWS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  ACTIVE_COUNT=$(echo "$WORKFLOWS" | python3 -c "import json,sys; wf=json.load(sys.stdin); print(sum(1 for w in wf if w.get('state')=='active'))")

  WORKFLOWS_DATA=$(echo "$WORKFLOWS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
workflows = json.loads('''$WORKFLOWS''')
data['repos'].append({
  'repo': '$REPO',
  'total_workflows': $WORKFLOW_COUNT,
  'active_workflows': $ACTIVE_COUNT,
  'workflows': workflows
})
print(json.dumps(data, indent=2))
")
done

echo "$WORKFLOWS_DATA" > "$RAW_DIR/workflows.json"
echo "    Workflow definitions collected"

# ── 2. Recent workflow runs (CC7.1, CC8.1, A1.1) ────────────────────────────
echo "==> Collecting recent workflow runs..."

RUNS_DATA='{"collected_at":"'"$COLLECTED_AT"'","summary":{"total_runs":0,"successful":0,"failed":0,"deployment_frequency":"unknown"},"repos":[]}'

TOTAL_RUNS=0
TOTAL_SUCCESS=0
TOTAL_FAILED=0

for REPO in $REPOS; do
  echo "    Collecting workflow runs for $ORG/$REPO..."
  RUNS=$(gh api "repos/$ORG/$REPO/actions/runs?per_page=100" \
    --jq '[.workflow_runs[] | {
      id: .id,
      name: .name,
      status: .status,
      conclusion: .conclusion,
      event: .event,
      branch: .head_branch,
      created_at: .created_at,
      updated_at: .updated_at,
      run_number: .run_number
    }]' 2>/dev/null || echo '[]')

  REPO_RUNS=$(echo "$RUNS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  REPO_SUCCESS=$(echo "$RUNS" | python3 -c "import json,sys; r=json.load(sys.stdin); print(sum(1 for x in r if x.get('conclusion')=='success'))")
  REPO_FAILED=$(echo "$RUNS" | python3 -c "import json,sys; r=json.load(sys.stdin); print(sum(1 for x in r if x.get('conclusion')=='failure'))")

  TOTAL_RUNS=$((TOTAL_RUNS + REPO_RUNS))
  TOTAL_SUCCESS=$((TOTAL_SUCCESS + REPO_SUCCESS))
  TOTAL_FAILED=$((TOTAL_FAILED + REPO_FAILED))

  RUNS_DATA=$(echo "$RUNS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
runs = json.loads(r'''$RUNS''')
data['repos'].append({
  'repo': '$REPO',
  'total_runs': $REPO_RUNS,
  'successful': $REPO_SUCCESS,
  'failed': $REPO_FAILED,
  'success_rate': round(($REPO_SUCCESS / max($REPO_RUNS, 1)) * 100, 1),
  'recent_runs': runs[:20]
})
print(json.dumps(data, indent=2))
")
done

# Update summary counts
RUNS_DATA=$(echo "$RUNS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['summary']['total_runs'] = $TOTAL_RUNS
data['summary']['successful'] = $TOTAL_SUCCESS
data['summary']['failed'] = $TOTAL_FAILED
data['summary']['overall_success_rate'] = round(($TOTAL_SUCCESS / max($TOTAL_RUNS, 1)) * 100, 1)
print(json.dumps(data, indent=2))
")

echo "$RUNS_DATA" > "$RAW_DIR/workflow-runs.json"
echo "    Workflow runs: $TOTAL_RUNS total, $TOTAL_SUCCESS succeeded, $TOTAL_FAILED failed"

# ── 3. Deployment environments (CC8.1, A1.1, A1.2) ──────────────────────────
echo "==> Collecting deployment environment configurations..."

ENVS_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Collecting environments for $ORG/$REPO..."
  ENVS=$(gh api "repos/$ORG/$REPO/environments" \
    --jq '[.environments[] | {
      id: .id,
      name: .name,
      created_at: .created_at,
      updated_at: .updated_at,
      protection_rules: [.protection_rules[] | {type: .type}],
      has_deployment_branch_policy: (.deployment_branch_policy != null)
    }]' 2>/dev/null || echo '[]')

  ENV_COUNT=$(echo "$ENVS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  ENVS_DATA=$(echo "$ENVS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
envs = json.loads('''$ENVS''')
data['repos'].append({'repo': '$REPO', 'environment_count': $ENV_COUNT, 'environments': envs})
print(json.dumps(data, indent=2))
")
done

echo "$ENVS_DATA" > "$RAW_DIR/environments.json"
echo "    Environment configurations collected"

echo ""
echo "==> CI/CD evidence collection complete:"
echo "    - data/raw/workflows.json"
echo "    - data/raw/workflow-runs.json"
echo "    - data/raw/environments.json"
