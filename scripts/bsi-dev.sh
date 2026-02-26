#!/usr/bin/env bash
# bsi-dev.sh — Feature branch development workflow
#
# Usage:
#   ./scripts/bsi-dev.sh <app-name> <branch>     Checkout app to feature branch and push
#   ./scripts/bsi-dev.sh --status                 Show which apps diverge from manifest
#   ./scripts/bsi-dev.sh --reset <app-name>       Reset one app to manifest-pinned main
#   ./scripts/bsi-dev.sh --reset-all              Reset ALL apps to manifest state
#
# Examples:
#   ./scripts/bsi-dev.sh forgeboard feature/firebase-sync
#   ./scripts/bsi-dev.sh --status
#   ./scripts/bsi-dev.sh --reset forgeboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$DEVOPS_ROOT/release-manifest.json"
WORKSPACE="$(cd "$DEVOPS_ROOT/../.." && pwd)"
REPOS_DIR="$WORKSPACE/repos"

if [[ ! -f "$MANIFEST" ]]; then
  echo "✗ Manifest not found: $MANIFEST"
  echo "  Run snapshot-manifest.sh first"
  exit 1
fi

# Helper: get manifest commit for a repo
_manifest_commit() {
  python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['repos'].get('$1',{}).get('commit',''))" 2>/dev/null
}

# Helper: get manifest repo URL for a repo
_manifest_repo() {
  python3 -c "import json; m=json.load(open('$MANIFEST')); print(m['repos'].get('$1',{}).get('repo','arnoutzw/$1'))" 2>/dev/null
}

# --- Status: show all repos vs manifest ---
do_status() {
  local version
  version=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])")

  echo "╔══════════════════════════════════════════════════╗"
  echo "║  BSI Dev Status — manifest v$version"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""
  printf "  %-30s %-10s %-25s %s\n" "REPO" "STATUS" "BRANCH" "COMMIT"
  printf "  %-30s %-10s %-25s %s\n" "----" "------" "------" "------"

  for dir in "$REPOS_DIR"/*/; do
    [[ -d "$dir/.git" ]] || continue
    local name actual_commit branch expected status_icon
    name=$(basename "$dir")
    actual_commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    expected=$(_manifest_commit "$name")

    if [[ -z "$expected" ]]; then
      status_icon="⚠ new"
    elif [[ "$actual_commit" == "$expected" && "$branch" == "main" ]]; then
      status_icon="● stable"
    elif [[ "$actual_commit" == "$expected" ]]; then
      status_icon="● pinned"
    elif [[ "$branch" != "main" ]]; then
      status_icon="▶ dev"
    else
      status_icon="△ ahead"
    fi

    printf "  %-30s %-10s %-25s %s\n" "$name" "$status_icon" "$branch" "$actual_commit"
  done
  echo ""
}

# --- Checkout app to feature branch ---
do_checkout() {
  local app="$1" branch="$2"
  local dir="$REPOS_DIR/$app"

  if [[ ! -d "$dir/.git" ]]; then
    echo "✗ Repo not found: $dir"
    echo "  Available repos:"
    for d in "$REPOS_DIR"/*/; do [[ -d "$d/.git" ]] && echo "    $(basename "$d")"; done
    exit 1
  fi

  echo "╔══════════════════════════════════════════════════╗"
  echo "║  BSI Dev — $app → $branch"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # Fetch latest
  echo "  Fetching origin..."
  git -C "$dir" fetch origin --quiet 2>/dev/null || true

  # Check if branch exists on remote
  local remote_exists
  remote_exists=$(git -C "$dir" ls-remote --heads origin "$branch" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$remote_exists" -gt 0 ]]; then
    git -C "$dir" checkout "$branch" 2>/dev/null || git -C "$dir" checkout -b "$branch" "origin/$branch" 2>/dev/null
    git -C "$dir" pull origin "$branch" --quiet 2>/dev/null || true
    echo "  ✓ Checked out existing branch: $branch"
  else
    local current_branch
    current_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" != "$branch" ]]; then
      git -C "$dir" checkout -b "$branch" 2>/dev/null
      echo "  ✓ Created new branch: $branch"
    else
      echo "  ✓ Already on branch: $branch"
    fi

    echo "  Pushing to origin..."
    git -C "$dir" push -u origin "$branch" 2>/dev/null
    echo "  ✓ Branch pushed to remote"
  fi

  local commit gh_repo
  commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  gh_repo=$(_manifest_repo "$app")

  echo ""
  echo "  App:    $app"
  echo "  Branch: $branch"
  echo "  Commit: $commit"
  echo "  Remote: https://github.com/$gh_repo/tree/$branch"
  echo ""
  echo "  The app will deploy to its Cloudflare Pages preview URL"
  echo "  once changes are pushed to this branch."
}

# --- Reset app to manifest state ---
do_reset() {
  local app="$1"
  local dir="$REPOS_DIR/$app"

  if [[ ! -d "$dir/.git" ]]; then
    echo "✗ Repo not found: $dir"
    exit 1
  fi

  local expected
  expected=$(_manifest_commit "$app")
  if [[ -z "$expected" ]]; then
    echo "✗ $app not found in manifest"
    exit 1
  fi

  echo "  Resetting $app → main (manifest: $expected)..."
  git -C "$dir" checkout main --quiet 2>/dev/null
  git -C "$dir" pull origin main --quiet 2>/dev/null || true

  local actual
  actual=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  echo "  ✓ $app — on main at $actual"
}

# --- Reset all apps ---
do_reset_all() {
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  BSI Dev — Reset All to Manifest                ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  read -p "  Reset all repos to main? [y/N] " -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Cancelled."
    exit 0
  fi
  echo ""

  for dir in "$REPOS_DIR"/*/; do
    [[ -d "$dir/.git" ]] || continue
    local name actual
    name=$(basename "$dir")
    git -C "$dir" checkout main --quiet 2>/dev/null || true
    git -C "$dir" pull origin main --quiet 2>/dev/null || true
    actual=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    echo "  ✓ $name — main @ $actual"
  done
  echo ""
  echo "  All repos reset to main."
}

# --- Main ---
if [[ $# -eq 0 ]]; then
  echo "Usage:"
  echo "  $0 <app-name> <branch>     Checkout app to feature branch"
  echo "  $0 --status                Show repo status vs manifest"
  echo "  $0 --reset <app-name>      Reset app to main"
  echo "  $0 --reset-all             Reset all apps to main"
  exit 0
fi

case "$1" in
  --status)
    do_status
    ;;
  --reset-all)
    do_reset_all
    ;;
  --reset)
    if [[ $# -lt 2 ]]; then echo "Usage: $0 --reset <app-name>"; exit 1; fi
    do_reset "$2"
    ;;
  -h|--help)
    echo "Usage:"
    echo "  $0 <app-name> <branch>     Checkout app to feature branch"
    echo "  $0 --status                Show repo status vs manifest"
    echo "  $0 --reset <app-name>      Reset app to main"
    echo "  $0 --reset-all             Reset all apps to main"
    ;;
  *)
    if [[ $# -lt 2 ]]; then echo "Usage: $0 <app-name> <branch>"; exit 1; fi
    do_checkout "$1" "$2"
    ;;
esac
