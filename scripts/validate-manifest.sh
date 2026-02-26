#!/usr/bin/env bash
# validate-manifest.sh — Pre-deploy gate: verify all repos match the manifest
#
# Usage:
#   ./scripts/validate-manifest.sh [manifest-file]
#
# Checks:
#   - Each repo's HEAD matches the pinned commit
#   - No uncommitted changes (clean working tree)
#   - No unpushed commits (not ahead of remote)
#
# Exit codes:
#   0 = all repos valid
#   1 = one or more issues found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${1:-$DEVOPS_ROOT/release-manifest.json}"
WORKSPACE="$(cd "$DEVOPS_ROOT/../.." && pwd)"
REPOS_DIR="$WORKSPACE/repos"

if [[ ! -f "$MANIFEST" ]]; then
  echo "✗ Manifest not found: $MANIFEST"
  exit 1
fi

VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])")
echo "╔══════════════════════════════════════════════════╗"
echo "║  BSI Manifest Validation — v$VERSION"
echo "╚══════════════════════════════════════════════════╝"
echo ""

ERRORS=0
WARNINGS=0
PASS=0
MISSING=0

while IFS='|' read -r name expected_commit; do
  dir="$REPOS_DIR/$name"

  if [[ ! -d "$dir/.git" ]]; then
    echo "  ✗ $name — repo not found at $dir"
    ((MISSING++))
    ((ERRORS++))
    continue
  fi

  actual_commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | grep -v '^\?\?' | head -1 || true)
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

  issues=()

  # Check commit match
  if [[ "$actual_commit" != "$expected_commit" ]]; then
    issues+=("commit mismatch: expected $expected_commit, got $actual_commit ($branch)")
  fi

  # Check for uncommitted changes (excluding untracked files)
  if [[ -n "$dirty" ]]; then
    issues+=("dirty working tree")
  fi

  # Check for unpushed commits
  ahead=$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
  if [[ "$ahead" =~ ^[0-9]+$ ]] && [[ "$ahead" -gt 0 ]]; then
    issues+=("$ahead unpushed commit(s)")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    echo "  ✓ $name — $actual_commit"
    ((PASS++))
  else
    for issue in "${issues[@]}"; do
      echo "  ✗ $name — $issue"
    done
    ((ERRORS++))
  fi

done < <(python3 -c "
import json
m = json.load(open('$MANIFEST'))
for name, info in sorted(m.get('repos', {}).items()):
    print(f\"{name}|{info['commit']}\")
")

echo ""
echo "  ✓ $PASS passed  ✗ $ERRORS failed  ⚠ $MISSING missing"
echo ""

if [[ $ERRORS -gt 0 ]]; then
  echo "VALIDATION FAILED — resolve issues before releasing"
  exit 1
else
  echo "ALL REPOS VALID"
  exit 0
fi
