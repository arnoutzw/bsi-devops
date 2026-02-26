#!/usr/bin/env bash
# snapshot-manifest.sh — Capture current HEAD of all repos into release-manifest.json
#
# Usage:
#   ./scripts/snapshot-manifest.sh [options]
#
# Options:
#   --bump major|minor|patch   Version bump type (default: patch)
#   --description "text"       Release description
#   --workspace PATH           Workspace root (default: auto-detect)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$DEVOPS_ROOT/release-manifest.json"

# Default workspace: two levels up from bsi-devops repo (repos/home -> repos -> workspace)
WORKSPACE="${WORKSPACE:-$(cd "$DEVOPS_ROOT/../.." && pwd)}"
REPOS_DIR="$WORKSPACE/repos"

BUMP="patch"
DESCRIPTION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)       BUMP="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --workspace)  WORKSPACE="$2"; REPOS_DIR="$WORKSPACE/repos"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--bump major|minor|patch] [--description \"text\"] [--workspace PATH]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Delegate to python3 for all JSON + logic (avoids bash 4 associative array requirement)
python3 - "$MANIFEST" "$REPOS_DIR" "$BUMP" "$DESCRIPTION" << 'PYEOF'
import json, os, subprocess, sys
from datetime import date

manifest_path = sys.argv[1]
repos_dir = sys.argv[2]
bump_type = sys.argv[3]
description = sys.argv[4]

# Read old manifest
old_version = "0.0.0"
old_commits = {}
if os.path.exists(manifest_path):
    with open(manifest_path) as f:
        old = json.load(f)
        old_version = old.get("version", "0.0.0")
        for name, info in old.get("repos", {}).items():
            old_commits[name] = info["commit"]

# Bump version
major, minor, patch = (int(x) for x in old_version.split("."))
if bump_type == "major":
    major, minor, patch = major + 1, 0, 0
elif bump_type == "minor":
    minor, patch = minor + 1, 0
else:
    patch += 1
new_version = f"{major}.{minor}.{patch}"
today = date.today().isoformat()

if not description:
    description = f"Release {new_version}"

print("╔══════════════════════════════════════════════════╗")
print("║  BSI Manifest Snapshot                           ║")
print("╚══════════════════════════════════════════════════╝")
print()
print(f"  Version: {old_version} → {new_version}")
print(f"  Date:    {today}")
print(f"  Desc:    {description}")
print()

# Collect current state from all repos
new_repos = {}
changed = []

for name in sorted(os.listdir(repos_dir)):
    repo_path = os.path.join(repos_dir, name)
    git_dir = os.path.join(repo_path, ".git")
    if not os.path.isdir(git_dir):
        continue

    try:
        commit = subprocess.check_output(
            ["git", "-C", repo_path, "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL
        ).decode().strip()

        remote_url = subprocess.check_output(
            ["git", "-C", repo_path, "config", "--get", "remote.origin.url"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        gh_repo = remote_url.replace("https://github.com/", "").replace(".git", "")
    except subprocess.CalledProcessError:
        continue

    new_repos[name] = {"commit": commit, "repo": gh_repo}

    old_commit = old_commits.get(name, "")
    if old_commit != commit:
        changed.append((name, old_commit or "new", commit))

# Write manifest
manifest = {
    "version": new_version,
    "date": today,
    "description": description,
    "repos": new_repos
}

with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

# Print summary
print(f"  Repos:   {len(new_repos)} total")
print(f"  Changed: {len(changed)}")
print()

if changed:
    print("  Changed repos:")
    for name, old, new in changed:
        print(f"    {name}: {old} → {new}")
    print()

print(f"✓ Manifest written to {manifest_path}")
PYEOF
