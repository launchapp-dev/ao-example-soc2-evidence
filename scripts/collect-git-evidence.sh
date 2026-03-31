#!/usr/bin/env bash
# collect-git-evidence.sh
# Collects change management evidence from git history and GitHub API
# Evidence covers: CC8.1 (change management), CC6.1 (access control via branch protection)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"
CONFIG="$PROJECT_ROOT/config/org-config.yaml"

mkdir -p "$RAW_DIR"

# Read org config (simple grep since we don't want to depend on yq)
ORG=$(grep 'github_org:' "$CONFIG" | awk '{print $2}' | tr -d '"')
DEFAULT_BRANCH=$(grep 'default_branch:' "$CONFIG" | awk '{print $2}' | tr -d '"')
AUDIT_START=$(grep 'start:' "$CONFIG" | head -1 | awk '{print $2}' | tr -d '"')

echo "==> Collecting git evidence for org: $ORG, branch: $DEFAULT_BRANCH"
echo "    Audit period start: $AUDIT_START"

# ── 1. Git commit history (change management — CC8.1) ────────────────────────
echo "==> Collecting git commit history..."

# Get recent commits since audit period start in JSON-friendly format
git log \
  --since="$AUDIT_START" \
  --format='{"hash":"%H","author":"%an","author_email":"%ae","date":"%aI","subject":"%s","refs":"%D"}' \
  --no-merges \
  2>/dev/null \
| python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
commits = []
for line in lines:
    try:
        commits.append(json.loads(line))
    except json.JSONDecodeError:
        pass  # skip malformed lines
output = {
    'collected_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
    'audit_period_start': '$AUDIT_START',
    'total_commits': len(commits),
    'commits': commits[:500]  # cap at 500 for evidence purposes
}
print(json.dumps(output, indent=2))
" > "$RAW_DIR/git-commits.json"

COMMIT_COUNT=$(python3 -c "import json; d=json.load(open('$RAW_DIR/git-commits.json')); print(d['total_commits'])")
echo "    Collected $COMMIT_COUNT commits since $AUDIT_START"

# ── 2. Branch protection rules (CC6.1, CC8.1) ────────────────────────────────
echo "==> Collecting branch protection rules..."

# Get list of repos in scope from config
REPOS=$(grep -A 20 'repos_in_scope:' "$CONFIG" | grep '  - ' | awk '{print $2}' | tr -d '"')

BRANCH_PROTECTION_DATA='{"collected_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Checking branch protection for $ORG/$REPO..."
  PROTECTION=$(gh api "repos/$ORG/$REPO/branches/$DEFAULT_BRANCH/protection" \
    --jq '{
      repo: "'"$REPO"'",
      branch: "'"$DEFAULT_BRANCH"'",
      required_reviews: .required_pull_request_reviews.required_approving_review_count // 0,
      dismiss_stale_reviews: .required_pull_request_reviews.dismiss_stale_reviews // false,
      require_code_owner_reviews: .required_pull_request_reviews.require_code_owner_reviews // false,
      required_status_checks: (.required_status_checks.contexts // []) | length,
      enforce_admins: .enforce_admins.enabled // false,
      restrictions_enabled: ((.restrictions // null) != null),
      allow_force_pushes: .allow_force_pushes.enabled // false,
      allow_deletions: .allow_deletions.enabled // false
    }' 2>/dev/null || echo '{"repo":"'"$REPO"'","error":"branch protection not configured or not accessible"}')

  BRANCH_PROTECTION_DATA=$(echo "$BRANCH_PROTECTION_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
repo_data = json.loads('''$PROTECTION''')
data['repos'].append(repo_data)
print(json.dumps(data, indent=2))
")
done

echo "$BRANCH_PROTECTION_DATA" > "$RAW_DIR/branch-protection.json"
echo "    Branch protection collected for $(echo "$REPOS" | wc -l | tr -d ' ') repos"

# ── 3. Pull request review evidence (CC6.1, CC8.1) ──────────────────────────
echo "==> Collecting PR review evidence..."

PR_DATA='{"collected_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Collecting PRs for $ORG/$REPO..."
  PRS=$(gh api "repos/$ORG/$REPO/pulls?state=closed&per_page=50" \
    --jq '[.[] | {
      number: .number,
      title: .title,
      author: .user.login,
      merged_at: .merged_at,
      merged: (.merged_at != null),
      review_count: (if .requested_reviewers then (.requested_reviewers | length) else 0 end),
      base_branch: .base.ref
    }]' 2>/dev/null || echo '[]')

  # Count merged PRs and those with reviews
  MERGED=$(echo "$PRS" | python3 -c "import json,sys; prs=json.load(sys.stdin); print(sum(1 for p in prs if p.get('merged')))")
  WITH_REVIEWS=$(echo "$PRS" | python3 -c "import json,sys; prs=json.load(sys.stdin); print(sum(1 for p in prs if p.get('review_count',0) > 0))")

  PR_DATA=$(echo "$PR_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['repos'].append({
  'repo': '$REPO',
  'total_closed_prs': $(echo "$PRS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"),
  'merged_prs': $MERGED,
  'prs_with_reviews': $WITH_REVIEWS,
  'recent_prs': json.loads('''$(echo "$PRS" | head -c 4000)''')
})
print(json.dumps(data, indent=2))
")
done

echo "$PR_DATA" > "$RAW_DIR/pr-reviews.json"
echo "    PR review evidence collected"

echo ""
echo "==> Git evidence collection complete:"
echo "    - data/raw/git-commits.json"
echo "    - data/raw/branch-protection.json"
echo "    - data/raw/pr-reviews.json"
