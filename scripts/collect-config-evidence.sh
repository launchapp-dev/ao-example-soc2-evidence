#!/usr/bin/env bash
# collect-config-evidence.sh
# Collects security configuration and repository policy evidence
# Evidence covers: CC3.1 (risk), CC6.1 (access), CC7.1/7.2 (monitoring), C1.1 (confidentiality), P1.1 (privacy)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"
CONFIG="$PROJECT_ROOT/config/org-config.yaml"

mkdir -p "$RAW_DIR"

ORG=$(grep 'github_org:' "$CONFIG" | awk '{print $2}' | tr -d '"')
REPOS=$(grep -A 20 'repos_in_scope:' "$CONFIG" | grep '  - ' | awk '{print $2}' | tr -d '"')
COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "==> Collecting security configuration evidence for org: $ORG"

# ── 1. Repository security settings (CC3.1, CC7.1, CC7.2) ───────────────────
echo "==> Collecting security settings..."

SECURITY_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Collecting security settings for $ORG/$REPO..."

  # Vulnerability alerts
  VULN_ALERTS_ENABLED=$(gh api "repos/$ORG/$REPO/vulnerability-alerts" \
    -X GET \
    -H "Accept: application/vnd.github+json" \
    --silent && echo "true" || echo "false" 2>/dev/null)

  # Automated security fixes (Dependabot)
  DEPENDABOT_ENABLED=$(gh api "repos/$ORG/$REPO/automated-security-fixes" \
    -X GET \
    -H "Accept: application/vnd.github+json" \
    --jq '.enabled // false' 2>/dev/null || echo "false")

  # Repo info including security features
  REPO_INFO=$(gh api "repos/$ORG/$REPO" \
    --jq '{
      private: .private,
      default_branch: .default_branch,
      has_issues: .has_issues,
      has_wiki: .has_wiki,
      archived: .archived,
      pushed_at: .pushed_at,
      created_at: .created_at
    }' 2>/dev/null || echo '{}')

  # Check for secret scanning alerts (just count, no content)
  SECRET_SCAN_ALERTS=$(gh api "repos/$ORG/$REPO/secret-scanning/alerts?state=open&per_page=1" \
    --jq 'length' 2>/dev/null || echo "0")

  # Code scanning alerts
  CODE_SCAN_ALERTS=$(gh api "repos/$ORG/$REPO/code-scanning/alerts?state=open&per_page=1" \
    --jq 'length' 2>/dev/null || echo "0")

  SECURITY_DATA=$(echo "$SECURITY_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
repo_info = json.loads('''$REPO_INFO''')
data['repos'].append({
  'repo': '$REPO',
  'vulnerability_alerts': $VULN_ALERTS_ENABLED,
  'dependabot_auto_fix': '$DEPENDABOT_ENABLED' == 'true',
  'open_secret_scan_alerts': int('$SECRET_SCAN_ALERTS' or 0),
  'open_code_scan_alerts': int('$CODE_SCAN_ALERTS' or 0),
  'repo_info': repo_info
})
print(json.dumps(data, indent=2))
")
done

echo "$SECURITY_DATA" > "$RAW_DIR/security-settings.json"
echo "    Security settings collected"

# ── 2. Policy and configuration files (CC1.1, CC2.1, CC6.1, P1.1) ──────────
echo "==> Collecting policy and configuration files..."

CONFIGS_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

for REPO in $REPOS; do
  echo "    Collecting config files for $ORG/$REPO..."

  # Check for key governance files
  has_codeowners=$(gh api "repos/$ORG/$REPO/contents/.github/CODEOWNERS" --jq '.name' 2>/dev/null && echo "true" || echo "false")
  has_security_md=$(gh api "repos/$ORG/$REPO/contents/SECURITY.md" --jq '.name' 2>/dev/null && echo "true" || echo "false")
  has_contributing=$(gh api "repos/$ORG/$REPO/contents/CONTRIBUTING.md" --jq '.name' 2>/dev/null && echo "true" || echo "false")
  has_issue_templates=$(gh api "repos/$ORG/$REPO/contents/.github/ISSUE_TEMPLATE" --jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
  has_pr_template=$(gh api "repos/$ORG/$REPO/contents/.github/pull_request_template.md" --jq '.name' 2>/dev/null && echo "true" || echo "false")
  has_dependabot_yaml=$(gh api "repos/$ORG/$REPO/contents/.github/dependabot.yml" --jq '.name' 2>/dev/null && echo "true" || echo "false")

  # Get CODEOWNERS content (first 20 lines) if it exists
  CODEOWNERS_CONTENT=""
  if [ "$has_codeowners" = "true" ]; then
    CODEOWNERS_CONTENT=$(gh api "repos/$ORG/$REPO/contents/.github/CODEOWNERS" \
      --jq '.content' | base64 -d 2>/dev/null | head -20 || echo "")
  fi

  CONFIGS_DATA=$(echo "$CONFIGS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['repos'].append({
  'repo': '$REPO',
  'governance_files': {
    'CODEOWNERS': $has_codeowners,
    'SECURITY_md': $has_security_md,
    'CONTRIBUTING_md': $has_contributing,
    'issue_templates': int('$has_issue_templates' or 0),
    'pr_template': $has_pr_template,
    'dependabot_yaml': $has_dependabot_yaml
  },
  'governance_score': sum([
    $has_codeowners == 'true',
    $has_security_md == 'true',
    $has_contributing == 'true',
    int('$has_issue_templates' or 0) > 0,
    $has_pr_template == 'true'
  ]),
  'codeowners_preview': '''$CODEOWNERS_CONTENT'''[:500] if '''$CODEOWNERS_CONTENT''' else None
})
print(json.dumps(data, indent=2))
")
done

echo "$CONFIGS_DATA" > "$RAW_DIR/repo-configs.json"
echo "    Config file inventory collected"

# ── 3. Secrets audit (CC6.1, C1.1, C1.2) ────────────────────────────────────
echo "==> Collecting secrets audit (counts only, no values)..."

SECRETS_DATA='{"collected_at":"'"$COLLECTED_AT"'","repos":[]}'

# Org-level secrets (count only)
ORG_SECRETS=$(gh api "orgs/$ORG/actions/secrets?per_page=100" \
  --jq '[.secrets[] | {name: .name, created_at: .created_at, updated_at: .updated_at, visibility: .visibility}]' \
  2>/dev/null || echo '[]')
ORG_SECRET_COUNT=$(echo "$ORG_SECRETS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

for REPO in $REPOS; do
  echo "    Auditing secrets for $ORG/$REPO..."
  REPO_SECRETS=$(gh api "repos/$ORG/$REPO/actions/secrets?per_page=100" \
    --jq '[.secrets[] | {name: .name, created_at: .created_at, updated_at: .updated_at}]' \
    2>/dev/null || echo '[]')
  REPO_SECRET_COUNT=$(echo "$REPO_SECRETS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

  SECRETS_DATA=$(echo "$SECRETS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
secrets = json.loads('''$REPO_SECRETS''')
# Extract just names and dates — never values
data['repos'].append({
  'repo': '$REPO',
  'secret_count': $REPO_SECRET_COUNT,
  'secret_names': [s['name'] for s in secrets],
  'oldest_secret': min((s['created_at'] for s in secrets), default=None),
  'newest_secret': max((s['updated_at'] for s in secrets), default=None)
})
print(json.dumps(data, indent=2))
")
done

# Add org-level summary
SECRETS_DATA=$(echo "$SECRETS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
org_secrets = json.loads('''$ORG_SECRETS''')
data['org_secrets_count'] = $ORG_SECRET_COUNT
data['org_secret_names'] = [s['name'] for s in org_secrets]
data['total_secrets'] = $ORG_SECRET_COUNT + sum(r['secret_count'] for r in data['repos'])
print(json.dumps(data, indent=2))
")

echo "$SECRETS_DATA" > "$RAW_DIR/secrets-audit.json"
echo "    Secrets audit complete — $ORG_SECRET_COUNT org-level secrets catalogued"

echo ""
echo "==> Configuration evidence collection complete:"
echo "    - data/raw/security-settings.json"
echo "    - data/raw/repo-configs.json"
echo "    - data/raw/secrets-audit.json"
