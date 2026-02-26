# BSI Release Workflow

How to develop a feature, test it live, and cut a release across the 28-repo BSI portal.

---

## Quick Reference

| Task | Command |
|------|---------|
| Start working on an app | `./scripts/bsi-dev.sh <app> <branch>` |
| Check workspace status | `./scripts/bsi-dev.sh --status` |
| Reset an app to stable | `./scripts/bsi-dev.sh --reset <app>` |
| Reset all apps to stable | `./scripts/bsi-dev.sh --reset-all` |
| Dry-run a release | `./scripts/bsi-release.sh --dry-run` |
| Cut a patch release | `./scripts/bsi-release.sh` |
| Cut a minor release | `./scripts/bsi-release.sh --bump minor --description "..."` |
| Validate manifest integrity | `./scripts/validate-manifest.sh` |
| Restore to a known release | `./scripts/checkout-manifest.sh` |

All commands are run from the **home** repo root:
```
cd ~/workspaces/BSI/bsi-workspace/repos/home
```

---

## 1 — Develop a Feature

### Start a feature branch

```bash
./scripts/bsi-dev.sh forgeboard feature/firebase-sync
```

This will:
- Fetch the latest from origin
- Create the branch (or check out an existing one)
- Push it to GitHub with tracking set up

The app automatically deploys to its **Cloudflare Pages preview URL** on push.

### Check what's in flight

```bash
./scripts/bsi-dev.sh --status
```

Output shows every repo and whether it's stable (on manifest), on a dev branch, or ahead of the manifest:

```
REPO                           STATUS     BRANCH                    COMMIT
----                           ------     ------                    ------
forgeboard                     ▶ dev      feature/firebase-sync     a1b2c3d
scrum-app                      ● stable   main                      b618735
...
```

Status icons:
- **● stable** — on main, matches manifest
- **● pinned** — matches manifest commit but not on main (detached)
- **▶ dev** — on a feature branch
- **△ ahead** — on main but ahead of manifest (new commits since last release)
- **⚠ new** — repo exists locally but isn't in the manifest yet

### Work on the feature

Develop as normal — edit, commit, push:

```bash
cd ~/workspaces/BSI/bsi-workspace/repos/forgeboard
# ... make changes ...
git add -A && git commit -m "feat: add firebase sync"
git push
```

Each push triggers a Cloudflare Pages preview deployment for that branch.

---

## 2 — Merge to Main

When the feature is ready, merge it back to main. You can do this via GitHub PR or locally:

**Option A — GitHub PR (recommended)**
```bash
gh pr create --title "Add firebase sync" --body "..."
# review, then merge on GitHub
```

**Option B — Local merge**
```bash
cd ~/workspaces/BSI/bsi-workspace/repos/forgeboard
git checkout main
git pull origin main
git merge feature/firebase-sync
git push origin main
```

### Clean up the feature branch

After merging, reset the app back to main tracking:

```bash
cd ~/workspaces/BSI/bsi-workspace/repos/home
./scripts/bsi-dev.sh --reset forgeboard
```

Optionally delete the remote branch:
```bash
cd ~/workspaces/BSI/bsi-workspace/repos/forgeboard
git branch -d feature/firebase-sync
git push origin --delete feature/firebase-sync
```

---

## 3 — Cut a Release

Once all features are merged and every app is on main, cut a release from the home repo.

### Pre-flight check

```bash
./scripts/bsi-dev.sh --status
```

Make sure all repos show **● stable** or **△ ahead**. No repo should be on a feature branch (▶ dev) when you release.

### Dry run

See what would happen without making any changes:

```bash
./scripts/bsi-release.sh --dry-run
```

### Release

```bash
./scripts/bsi-release.sh --bump patch --description "Firebase sync for ForgeBoard"
```

The pipeline runs five steps automatically:

1. **Pull** — fetches latest for all 28 repos
2. **Validate** — checks for uncommitted changes or dirty state
3. **Snapshot** — captures every repo's HEAD into `release-manifest.json`, bumps the version
4. **Commit** — commits the updated manifest to the home repo
5. **Push** — pushes home to origin

Version bump options:
- `--bump patch` → 1.0.0 → 1.0.**1** (default — bug fixes, small changes)
- `--bump minor` → 1.0.0 → 1.**1**.0 (new features)
- `--bump major` → 1.0.0 → **2**.0.0 (breaking changes)

### Verify

```bash
./scripts/validate-manifest.sh
```

All repos should report ✓ matching the new manifest.

---

## 4 — Roll Back to a Previous Release

If something goes wrong, restore every repo to the commits pinned in the manifest:

```bash
./scripts/checkout-manifest.sh
```

This puts repos in **detached HEAD** state at the exact pinned commits. To return to normal branch tracking afterward:

```bash
./scripts/bsi-dev.sh --reset-all
```

To roll back to an older release, check out that version of the manifest first:

```bash
cd ~/workspaces/BSI/bsi-workspace/repos/home
git log --oneline release-manifest.json   # find the release commit
git checkout <commit> -- release-manifest.json
./scripts/checkout-manifest.sh
```

---

## 5 — Working on Multiple Apps at Once

You can have several apps on feature branches simultaneously:

```bash
./scripts/bsi-dev.sh forgeboard feature/firebase-sync
./scripts/bsi-dev.sh scrum-app feature/new-sprint-view
./scripts/bsi-dev.sh --status   # see both marked as ▶ dev
```

Merge and reset each one independently before releasing:

```bash
# After merging both PRs on GitHub:
./scripts/bsi-dev.sh --reset forgeboard
./scripts/bsi-dev.sh --reset scrum-app
./scripts/bsi-release.sh --bump minor --description "Firebase sync + new sprint view"
```

---

## Typical End-to-End Example

```bash
cd ~/workspaces/BSI/bsi-workspace/repos/home

# 1. Start feature
./scripts/bsi-dev.sh forgeboard feature/dark-mode-fix

# 2. Develop
cd ../forgeboard
# ... edit index.html ...
git add index.html && git commit -m "fix: dark mode toggle in embedded view"
git push

# 3. Test on Cloudflare preview URL, iterate as needed

# 4. Create PR and merge on GitHub
gh pr create --title "Fix dark mode toggle" --body "Fixes toggle visibility when embedded"
gh pr merge --squash

# 5. Clean up and release
cd ~/workspaces/BSI/bsi-workspace/repos/home
./scripts/bsi-dev.sh --reset forgeboard
./scripts/bsi-release.sh --description "Fix dark mode toggle in ForgeBoard"

# Done — manifest updated, committed, and pushed
```

---

## File Reference

| File | Purpose |
|------|---------|
| `release-manifest.json` | Pins every repo to a commit hash for the current release |
| `scripts/bsi-release.sh` | Full release pipeline (pull → validate → snapshot → commit → push) |
| `scripts/bsi-dev.sh` | Feature branch workflow (checkout, status, reset) |
| `scripts/snapshot-manifest.sh` | Captures current repo HEADs into the manifest |
| `scripts/validate-manifest.sh` | Checks all repos match the manifest |
| `scripts/checkout-manifest.sh` | Restores all repos to manifest-pinned commits |
