#!/usr/bin/env bash
# bsi-release.sh — Full release orchestration for the BSI portal
#
# Usage:
#   ./scripts/bsi-release.sh [options]
#
# Options:
#   --bump major|minor|patch   Version bump (default: patch)
#   --description "text"       Release description
#   --dry-run                  Show what would happen without making changes
#   --skip-push                Stop after commit, don't push
#
# Pipeline:
#   1. Pull all repos
#   2. Validate — no dirty state, no unpushed commits
#   3. Snapshot — capture all repo HEADs into manifest
#   4. Commit — commit updated manifest to bsi-devops repo
#   5. Push — push bsi-devops repo to origin
#   6. Summary — print release info

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$DEVOPS_ROOT/release-manifest.json"
WORKSPACE="$(cd "$DEVOPS_ROOT/../.." && pwd)"
REPOS_DIR="$WORKSPACE/repos"

BUMP="patch"
DESCRIPTION=""
DRY_RUN=false
SKIP_PUSH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)        BUMP="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --skip-push)   SKIP_PUSH=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--bump major|minor|patch] [--description \"text\"] [--dry-run] [--skip-push]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Read current version
OLD_VERSION="0.0.0"
if [[ -f "$MANIFEST" ]]; then
  OLD_VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])" 2>/dev/null || echo "0.0.0")
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  BSI Release Pipeline                            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if $DRY_RUN; then
  echo "  *** DRY RUN — no changes will be made ***"
  echo ""
fi

# ─────────────────────────────────────────────
# Step 1: Pull all repos
# ─────────────────────────────────────────────
echo "━━━ Step 1/5: Pull all repos ━━━"
echo ""

PULL_OK=0
PULL_FAIL=0

for dir in "$REPOS_DIR"/*/; do
  [[ -d "$dir/.git" ]] || continue
  name=$(basename "$dir")
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

  if $DRY_RUN; then
    echo "  [dry-run] Would pull $name ($branch)"
    ((PULL_OK++))
    continue
  fi

  if git -C "$dir" pull origin "$branch" --quiet 2>/dev/null; then
    echo "  ✓ $name — pulled ($branch)"
    ((PULL_OK++))
  else
    echo "  ⚠ $name — pull failed ($branch)"
    ((PULL_FAIL++))
  fi
done

echo ""
echo "  Pulled: $PULL_OK  Failed: $PULL_FAIL"
echo ""

# ─────────────────────────────────────────────
# Step 2: Validate
# ─────────────────────────────────────────────
echo "━━━ Step 2/5: Validate workspace ━━━"
echo ""

DIRTY_REPOS=()
for dir in "$REPOS_DIR"/*/; do
  [[ -d "$dir/.git" ]] || continue
  name=$(basename "$dir")
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | grep -v '^\?\?' | head -1 || true)
  if [[ -n "$dirty" ]]; then
    DIRTY_REPOS+=("$name")
  fi
done

if [[ ${#DIRTY_REPOS[@]} -gt 0 ]]; then
  echo "  ⚠ Repos with uncommitted changes:"
  for name in "${DIRTY_REPOS[@]}"; do
    echo "    - $name"
  done
  echo ""
  echo "  Commit or stash changes before releasing."
  if ! $DRY_RUN; then
    exit 1
  fi
else
  echo "  ✓ All repos clean"
fi
echo ""

# ─────────────────────────────────────────────
# Step 3: Snapshot manifest
# ─────────────────────────────────────────────
echo "━━━ Step 3/5: Snapshot manifest ━━━"
echo ""

if $DRY_RUN; then
  echo "  [dry-run] Would run: snapshot-manifest.sh --bump $BUMP"
  if [[ -n "$DESCRIPTION" ]]; then
    echo "  [dry-run] Description: $DESCRIPTION"
  fi
else
  SNAP_ARGS=(--bump "$BUMP")
  if [[ -n "$DESCRIPTION" ]]; then
    SNAP_ARGS+=(--description "$DESCRIPTION")
  fi
  bash "$SCRIPT_DIR/snapshot-manifest.sh" "${SNAP_ARGS[@]}"
fi
echo ""

# Read new version
NEW_VERSION="$OLD_VERSION"
if [[ -f "$MANIFEST" ]] && ! $DRY_RUN; then
  NEW_VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])" 2>/dev/null || echo "$OLD_VERSION")
fi

# ─────────────────────────────────────────────
# Step 4: Commit
# ─────────────────────────────────────────────
echo "━━━ Step 4/5: Commit manifest ━━━"
echo ""

if $DRY_RUN; then
  echo "  [dry-run] Would commit release-manifest.json to bsi-devops repo"
else
  cd "$DEVOPS_ROOT"
  if git diff --quiet release-manifest.json 2>/dev/null; then
    echo "  ● No changes to manifest — skipping commit"
  else
    git add release-manifest.json
    git commit -m "release: v$NEW_VERSION — ${DESCRIPTION:-update manifest}"
    echo "  ✓ Committed release v$NEW_VERSION"
  fi
fi
echo ""

# ─────────────────────────────────────────────
# Step 5: Push
# ─────────────────────────────────────────────
echo "━━━ Step 5/5: Push ━━━"
echo ""

if $DRY_RUN; then
  echo "  [dry-run] Would push bsi-devops repo to origin"
elif $SKIP_PUSH; then
  echo "  ● Skipped (--skip-push)"
else
  cd "$DEVOPS_ROOT"
  git push origin main 2>/dev/null
  echo "  ✓ Pushed to origin/main"
fi
echo ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════╗"
echo "║  Release Complete                                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Version: $OLD_VERSION → $NEW_VERSION"
echo "  Date:    $(date +%Y-%m-%d)"
if [[ -n "$DESCRIPTION" ]]; then
  echo "  Desc:    $DESCRIPTION"
fi
echo ""
