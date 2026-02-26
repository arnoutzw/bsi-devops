#!/usr/bin/env bash
# checkout-manifest.sh — Restore all repos to the commits pinned in a manifest
#
# Usage:
#   ./scripts/checkout-manifest.sh [manifest-file]
#
# Default: ./release-manifest.json
#
# This puts repos in detached HEAD state at the exact pinned commit.
# Use bsi-dev.sh --reset-all to return to branch tracking.

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
DATE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['date'])")

echo "╔══════════════════════════════════════════════════╗"
echo "║  BSI Manifest Checkout — v$VERSION ($DATE)"
echo "╚══════════════════════════════════════════════════╝"
echo ""

SUCCESS=0
SKIPPED=0
FAILED=0
MISSING=0

while IFS='|' read -r name expected_commit gh_repo; do
  dir="$REPOS_DIR/$name"

  if [[ ! -d "$dir/.git" ]]; then
    echo "  ⚠ $name — repo not found, skipping"
    ((MISSING++))
    continue
  fi

  actual_commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)

  # Already at the right commit
  if [[ "$actual_commit" == "$expected_commit" ]]; then
    echo "  ✓ $name — already at $expected_commit"
    ((SKIPPED++))
    continue
  fi

  # Fetch and checkout
  if git -C "$dir" fetch origin --quiet 2>/dev/null; then
    if git -C "$dir" checkout "$expected_commit" --quiet 2>/dev/null; then
      echo "  ✓ $name — checked out $expected_commit (was $actual_commit)"
      ((SUCCESS++))
    else
      echo "  ✗ $name — failed to checkout $expected_commit"
      ((FAILED++))
    fi
  else
    echo "  ✗ $name — failed to fetch from origin"
    ((FAILED++))
  fi

done < <(python3 -c "
import json
m = json.load(open('$MANIFEST'))
for name, info in sorted(m.get('repos', {}).items()):
    print(f\"{name}|{info['commit']}|{info['repo']}\")
")

echo ""
echo "  ✓ $SUCCESS checked out  ● $SKIPPED already correct  ✗ $FAILED failed  ⚠ $MISSING missing"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
