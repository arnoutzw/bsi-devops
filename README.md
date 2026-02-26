# BSI DevOps

Release orchestration, manifest management, and platform documentation for [Black Sphere Industries](https://blacksphereindustries.nl).

## Quick Start

```bash
# Show status of all repos vs manifest
./scripts/bsi-dev.sh --status

# Checkout a feature branch for an app
./scripts/bsi-dev.sh forgeboard feature/my-feature

# Create a release (snapshot + commit + push)
./scripts/bsi-release.sh --bump patch --description "Bug fixes"

# Validate all repos match the manifest
./scripts/validate-manifest.sh

# Restore all repos to manifest-pinned commits
./scripts/checkout-manifest.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `bsi-dev.sh` | Feature branch workflow — checkout, status, reset |
| `bsi-release.sh` | Full 5-step release pipeline |
| `snapshot-manifest.sh` | Capture repo HEADs into `release-manifest.json` |
| `checkout-manifest.sh` | Restore repos to pinned commits (detached HEAD) |
| `validate-manifest.sh` | Pre-deploy gate — verify repos match manifest |

## Documentation

| Document | Description |
|----------|-------------|
| [Release Workflow](docs/release-workflow.md) | Release procedures, version bumping, rollback |
| [Architecture](docs/architecture.md) | High-level portal architecture |
| [SSO Integration](docs/sso-integration.md) | Iframe SSO protocol and postMessage auth |
| [Styling Guide](docs/styling-guide.md) | Design system, CSS variables, themes |
| [Firebase Architecture](docs/firebase-architecture.md) | Firestore patterns and data model |
| [PWA Testing](docs/pwa-testing.md) | Console-based testing for single-file HTML apps |

## Release Manifest

`release-manifest.json` pins 28+ repos to specific commits:

```json
{
  "version": "1.0.4",
  "date": "2026-02-26",
  "repos": {
    "erp-app": { "commit": "abc1234", "repo": "arnoutzw/erp-app" },
    "scrum-app": { "commit": "def5678", "repo": "arnoutzw/scrum-app" }
  }
}
```

See [RELEASES.md](RELEASES.md) for the full changelog.

## Workspace Layout

This repo lives at `repos/bsi-devops/` within the BSI workspace:

```
bsi-workspace/
├── repos/
│   ├── bsi-devops/    # This repo (scripts + docs + manifest)
│   ├── home/          # Portal SPA
│   ├── erp-app/       # ForgeERP
│   ├── scrum-app/     # ForgedAgile
│   └── ...            # 25+ more app repos
└── CLAUDE.md
```
