#!/usr/bin/env bash
# quick-collect.sh
# Lightweight weekly freshness check — checks timestamps and counts only
# Used by the gap-monitor workflow to detect stale evidence without a full collection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"
CONFIG="$PROJECT_ROOT/config/org-config.yaml"

mkdir -p "$RAW_DIR"

ORG=$(grep 'github_org:' "$CONFIG" | awk '{print $2}' | tr -d '"')
REPOS=$(grep -A 20 'repos_in_scope:' "$CONFIG" | grep '  - ' | awk '{print $2}' | tr -d '"')
COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%Y-%m-%d)

echo "==> Quick freshness check for org: $ORG"

# ── Check 1: Recent git activity ─────────────────────────────────────────────
echo "==> Checking recent git activity..."

LAST_COMMIT_DATE=$(git log -1 --format="%aI" 2>/dev/null || echo "unknown")
COMMITS_LAST_30_DAYS=$(git log --since="30 days ago" --oneline 2>/dev/null | wc -l | tr -d ' ')

# ── Check 2: Last evidence collection timestamps ──────────────────────────────
echo "==> Checking last evidence collection timestamps..."

LAST_GIT_COLLECTION="never"
LAST_ACCESS_COLLECTION="never"
LAST_CICD_COLLECTION="never"
LAST_CONFIG_COLLECTION="never"
LAST_SUMMARY_COLLECTION="never"

[ -f "$RAW_DIR/git-commits.json" ] && \
  LAST_GIT_COLLECTION=$(python3 -c "import json; d=json.load(open('$RAW_DIR/git-commits.json')); print(d.get('collected_at','unknown'))" 2>/dev/null || echo "unknown")

[ -f "$RAW_DIR/org-members.json" ] && \
  LAST_ACCESS_COLLECTION=$(python3 -c "import json; d=json.load(open('$RAW_DIR/org-members.json')); print(d.get('collected_at','unknown'))" 2>/dev/null || echo "unknown")

[ -f "$RAW_DIR/workflows.json" ] && \
  LAST_CICD_COLLECTION=$(python3 -c "import json; d=json.load(open('$RAW_DIR/workflows.json')); print(d.get('collected_at','unknown'))" 2>/dev/null || echo "unknown")

[ -f "$RAW_DIR/security-settings.json" ] && \
  LAST_CONFIG_COLLECTION=$(python3 -c "import json; d=json.load(open('$RAW_DIR/security-settings.json')); print(d.get('collected_at','unknown'))" 2>/dev/null || echo "unknown")

[ -f "$PROJECT_ROOT/data/evidence-summary.json" ] && \
  LAST_SUMMARY_COLLECTION=$(python3 -c "import json; d=json.load(open('$PROJECT_ROOT/data/evidence-summary.json')); print(d.get('collected_at','unknown'))" 2>/dev/null || echo "unknown")

# ── Check 3: Current org member count ────────────────────────────────────────
echo "==> Checking current org member count..."
CURRENT_MEMBER_COUNT=$(gh api "orgs/$ORG/members" --jq 'length' 2>/dev/null || echo "0")

PREVIOUS_MEMBER_COUNT=0
[ -f "$RAW_DIR/org-members.json" ] && \
  PREVIOUS_MEMBER_COUNT=$(python3 -c "import json; d=json.load(open('$RAW_DIR/org-members.json')); print(d.get('total_members',0))" 2>/dev/null || echo "0")

NEW_MEMBERS=$((CURRENT_MEMBER_COUNT - PREVIOUS_MEMBER_COUNT))

# ── Check 4: Recent CI/CD runs ────────────────────────────────────────────────
echo "==> Checking CI/CD run recency..."

RECENT_RUNS_COUNT=0
for REPO in $REPOS; do
  REPO_RECENT=$(gh api "repos/$ORG/$REPO/actions/runs?created=>$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-14d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "2025-09-17T00:00:00Z")&per_page=1" \
    --jq 'length' 2>/dev/null || echo "0")
  RECENT_RUNS_COUNT=$((RECENT_RUNS_COUNT + REPO_RECENT))
done

# ── Calculate days since last full collection ─────────────────────────────────
DAYS_SINCE_COLLECTION=999
if [ "$LAST_SUMMARY_COLLECTION" != "never" ] && [ "$LAST_SUMMARY_COLLECTION" != "unknown" ]; then
  DAYS_SINCE_COLLECTION=$(python3 -c "
from datetime import datetime, timezone
last = datetime.fromisoformat('$LAST_SUMMARY_COLLECTION'.replace('Z','+00:00'))
now = datetime.now(timezone.utc)
print((now - last).days)
" 2>/dev/null || echo "999")
fi

# ── Write quick-check.json ────────────────────────────────────────────────────
python3 -c "
import json
output = {
  'collected_at': '$COLLECTED_AT',
  'check_date': '$TODAY',
  'organization': '$ORG',
  'git': {
    'last_commit_date': '$LAST_COMMIT_DATE',
    'commits_last_30_days': $COMMITS_LAST_30_DAYS,
    'active': $COMMITS_LAST_30_DAYS > 0
  },
  'evidence_timestamps': {
    'git_evidence': '$LAST_GIT_COLLECTION',
    'access_evidence': '$LAST_ACCESS_COLLECTION',
    'cicd_evidence': '$LAST_CICD_COLLECTION',
    'config_evidence': '$LAST_CONFIG_COLLECTION',
    'last_full_summary': '$LAST_SUMMARY_COLLECTION'
  },
  'days_since_full_collection': $DAYS_SINCE_COLLECTION,
  'collection_stale': $DAYS_SINCE_COLLECTION > 90,
  'access_control': {
    'current_member_count': $CURRENT_MEMBER_COUNT,
    'previous_member_count': $PREVIOUS_MEMBER_COUNT,
    'new_members_delta': $NEW_MEMBERS,
    'new_members_detected': abs($NEW_MEMBERS) > 0
  },
  'cicd': {
    'recent_runs_count': $RECENT_RUNS_COUNT,
    'recent_ci_activity': $RECENT_RUNS_COUNT > 0
  }
}
print(json.dumps(output, indent=2))
" > "$RAW_DIR/quick-check.json"

echo ""
echo "==> Quick check complete:"
echo "    Days since full collection: $DAYS_SINCE_COLLECTION"
echo "    Collection stale: $([ $DAYS_SINCE_COLLECTION -gt 90 ] && echo 'YES - trigger full collection' || echo 'No')"
echo "    Member count change: $NEW_MEMBERS ($PREVIOUS_MEMBER_COUNT → $CURRENT_MEMBER_COUNT)"
echo "    Recent CI/CD runs: $RECENT_RUNS_COUNT"
echo "    Output: data/raw/quick-check.json"
