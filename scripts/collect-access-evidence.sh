#!/usr/bin/env bash
# collect-access-evidence.sh
# Collects access control evidence from GitHub org and repo permissions
# Evidence covers: CC6.1 (logical access), CC6.2 (new users), CC6.3 (remove access)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"
CONFIG="$PROJECT_ROOT/config/org-config.yaml"

mkdir -p "$RAW_DIR"

ORG=$(grep 'github_org:' "$CONFIG" | awk '{print $2}' | tr -d '"')
REPOS=$(grep -A 20 'repos_in_scope:' "$CONFIG" | grep '  - ' | awk '{print $2}' | tr -d '"')
COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "==> Collecting access control evidence for org: $ORG"

# ── 1. Org members and roles (CC6.1, CC6.2) ──────────────────────────────────
echo "==> Collecting org members..."

MEMBERS=$(gh api "orgs/$ORG/members?per_page=100" \
  --jq '[.[] | {login: .login, type: .type, site_admin: .site_admin}]' \
  2>/dev/null || echo '[]')

ADMIN_MEMBERS=$(gh api "orgs/$ORG/members?role=admin&per_page=100" \
  --jq '[.[] | .login]' \
  2>/dev/null || echo '[]')

MEMBER_COUNT=$(echo "$MEMBERS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
ADMIN_COUNT=$(echo "$ADMIN_MEMBERS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

python3 -c "
import json
members = json.loads('''$MEMBERS''')
admins = json.loads('''$ADMIN_MEMBERS''')

# Mark admins
for m in members:
    m['is_org_admin'] = m['login'] in admins

output = {
  'collected_at': '$COLLECTED_AT',
  'organization': '$ORG',
  'total_members': $MEMBER_COUNT,
  'admin_count': $ADMIN_COUNT,
  'member_count': $MEMBER_COUNT - $ADMIN_COUNT,
  'admin_ratio': round($ADMIN_COUNT / max($MEMBER_COUNT, 1) * 100, 1),
  'members': members
}
print(json.dumps(output, indent=2))
" > "$RAW_DIR/org-members.json"

echo "    Total members: $MEMBER_COUNT (admins: $ADMIN_COUNT)"

# ── 2. Teams and permissions (CC6.1, CC6.2) ──────────────────────────────────
echo "==> Collecting team structure..."

TEAMS=$(gh api "orgs/$ORG/teams?per_page=100" \
  --jq '[.[] | {
    id: .id,
    name: .name,
    slug: .slug,
    description: .description,
    privacy: .privacy,
    permission: .permission,
    members_count: .members_count,
    repos_count: .repos_count
  }]' 2>/dev/null || echo '[]')

TEAM_COUNT=$(echo "$TEAMS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

python3 -c "
import json
teams = json.loads('''$TEAMS''')
output = {
  'collected_at': '$COLLECTED_AT',
  'organization': '$ORG',
  'total_teams': $TEAM_COUNT,
  'teams': teams
}
print(json.dumps(output, indent=2))
" > "$RAW_DIR/teams.json"

echo "    Total teams: $TEAM_COUNT"

# ── 3. Repository access and collaborators (CC6.1, CC6.3) ────────────────────
echo "==> Collecting repository access permissions..."

REPO_ACCESS_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

TOTAL_OUTSIDE_COLLABORATORS=0

for REPO in $REPOS; do
  echo "    Collecting access for $ORG/$REPO..."

  # Get collaborators with permissions
  COLLABORATORS=$(gh api "repos/$ORG/$REPO/collaborators?per_page=100" \
    --jq '[.[] | {login: .login, role_name: .role_name, type: .type}]' \
    2>/dev/null || echo '[]')

  # Get outside collaborators specifically
  OUTSIDE=$(gh api "repos/$ORG/$REPO/collaborators?affiliation=outside&per_page=100" \
    --jq '[.[] | .login]' \
    2>/dev/null || echo '[]')

  COLLAB_COUNT=$(echo "$COLLABORATORS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  OUTSIDE_COUNT=$(echo "$OUTSIDE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  ADMIN_COLLAB=$(echo "$COLLABORATORS" | python3 -c "import json,sys; c=json.load(sys.stdin); print(sum(1 for x in c if x.get('role_name')=='admin'))")
  WRITE_COLLAB=$(echo "$COLLABORATORS" | python3 -c "import json,sys; c=json.load(sys.stdin); print(sum(1 for x in c if x.get('role_name') in ['write','maintain']))")

  TOTAL_OUTSIDE_COLLABORATORS=$((TOTAL_OUTSIDE_COLLABORATORS + OUTSIDE_COUNT))

  REPO_ACCESS_DATA=$(echo "$REPO_ACCESS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
collabs = json.loads('''$COLLABORATORS''')
outside = json.loads('''$OUTSIDE''')
data['repos'].append({
  'repo': '$REPO',
  'total_collaborators': $COLLAB_COUNT,
  'admin_collaborators': $ADMIN_COLLAB,
  'write_collaborators': $WRITE_COLLAB,
  'outside_collaborators': $OUTSIDE_COUNT,
  'outside_collaborator_logins': outside,
  'collaborators': collabs
})
print(json.dumps(data, indent=2))
")
done

# Add org-wide summary
REPO_ACCESS_DATA=$(echo "$REPO_ACCESS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['total_outside_collaborators'] = $TOTAL_OUTSIDE_COLLABORATORS
data['outside_collaborator_risk'] = 'high' if $TOTAL_OUTSIDE_COLLABORATORS > 5 else ('medium' if $TOTAL_OUTSIDE_COLLABORATORS > 0 else 'low')
print(json.dumps(data, indent=2))
")

echo "$REPO_ACCESS_DATA" > "$RAW_DIR/repo-access.json"
echo "    Total outside collaborators: $TOTAL_OUTSIDE_COLLABORATORS"

echo ""
echo "==> Access evidence collection complete:"
echo "    - data/raw/org-members.json"
echo "    - data/raw/teams.json"
echo "    - data/raw/repo-access.json"
