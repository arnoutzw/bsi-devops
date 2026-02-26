# Firebase Architecture — Optimization Brainstorm

> Date: 2026-02-25
> Scope: Cross-app synergy, data model optimization, performance
> Reference: [FIREBASE-ARCHITECTURE.md](./FIREBASE-ARCHITECTURE.md)

---

## Current State Summary

**Single Firebase project** (`arnout-s-homelab`) serving 9 apps through a portal architecture:

| Tier | Apps | Storage |
|------|------|---------|
| **Firebase + SSO** | scrum-app, erp-app, req-management, alm-app, filaments-inventory, Notes_App, py-lab-app, datasheet-search | Firestore per-project collections |
| **localStorage only** | forgeboard, mindforge, label-designer, jk/pq-bms, serial-app, mijia_monitor | Local browser storage |
| **Stateless tools** | 13 engineering calculators/viewers | No persistence |

**Data Model**: `/projects/{pid}/[app]/state` — each app nests under a shared project registry.

---

## Project Governance Model — ERP as Master

### Vision

**ForgeERP is the single source of truth for projects.** All projects are created in ERP, where the project metadata, budget, timeline, and resource allocation are defined. Every other business app operates within the context of a project owned by ERP.

### Hierarchy

```
ForgeERP (Project Master)
  ├── Creates projects, defines budget & timeline
  ├── Manages BOMs, Work Orders, Invoices, Quotes
  └── Shows overview of ALL projects with status/budget roll-up

ForgedAgile (Planning)
  ├── Plans work within a project using KDD milestones & backlog
  ├── Sprint planning, Kanban, Retro — all project-scoped
  └── Board state stored per-project in Firebase

ReqForge (Requirements)
  ├── Requirements authored per-project
  ├── V-Cycle traceability within project scope
  └── Links to scrum cards and test results

ForgedOps / RCA Studio (Quality)
  ├── Incidents & defects tracked per-project workspace
  ├── Root cause analysis linked to project artifacts
  └── Quality metrics per project

ForgeBoard (Visual Design)
  ├── Whiteboards & diagrams per-project workspace
  ├── System architecture, schematics, flowcharts
  └── Boards linked to scrum cards & requirements

MindForge (Ideation)
  ├── Mind maps per-project workspace
  ├── Brainstorms, design explorations
  └── Maps linkable to requirements & stories

Notes App (Documentation)
  ├── Project-scoped notes (personal + shared)
  ├── Meeting notes, design decisions, logs
  └── Per-project collections in Firestore
```

### App Behavior Modes

| Mode | Apps | Behavior |
|------|------|----------|
| **Overview / Multi-project** | ForgeERP | Shows all projects, budget dashboard, cross-project reporting |
| **Workspace / Single-project** | ForgedAgile, ForgedOps, ForgeBoard, MindForge, Notes, ReqForge | Operates within the active project context set by the portal |

### Project Lifecycle

1. **Creation** — Project created in ForgeERP with name, description, budget, timeline, owner
2. **Registration** — ERP writes to Firestore `/projects/{pid}` (global registry)
3. **Broadcast** — Portal detects new project via `onSnapshot`, broadcasts to all iframes via `postMessage`
4. **Planning** — ForgedAgile picks up the project, creates KDD milestones, populates backlog
5. **Execution** — All workspace apps operate within the project scope, storing state at `/projects/{pid}/{app}/...`
6. **Tracking** — ERP shows aggregated status: budget burn, milestone progress, open defects, BOM cost

### Firestore Data Model

```
/projects/{pid}                          ← Project registry (owned by ERP)
  ├── name, description, status, owner
  ├── budget: { allocated, spent, currency }
  ├── timeline: { start, end, milestones[] }
  ├── createdAt, updatedAt
  │
  ├── /erp/
  │   ├── parts                          ← BOM items, inventory
  │   ├── work-orders                    ← Manufacturing/assembly orders
  │   ├── invoices                       ← Project invoices
  │   └── quotes                         ← Project quotes
  │
  ├── /scrum/state                       ← Kanban board state (columns, cards, sprints)
  ├── /requirements/state                ← Requirements, documents, work items
  ├── /rca_incidents/                    ← Defects, incidents, RCA data
  │
  ├── /forgeboard/boards/               ← Whiteboard diagrams
  ├── /mindforge/maps/                  ← Mind maps
  ├── /notes/                           ← Shared project notes
  │
  ├── /links/                           ← Cross-app entity links (see #1 below)
  └── /activity/                        ← Unified activity feed (see #4 below)

/users/{uid}/
  ├── /notes/                           ← Personal (non-project) notes
  ├── /app_data/forgeboard/             ← Personal (unlinked) boards
  └── /app_data/mindforge/              ← Personal (unlinked) maps
```

### Current Implementation Status

| App | Project-Aware? | Project Source | Storage Path | Notes |
|-----|---------------|----------------|--------------|-------|
| Portal | ✅ Full | Firestore `projects` collection | — | Broadcasts via postMessage: `admin-auth`, `active-project`, `projects-registry` |
| ForgeERP | ✅ Full | Creates projects | `/projects/{pid}/erp/` | Should become sole project creator (currently scrum-app also creates) |
| ForgedAgile | ✅ Full | Portal postMessage | `/projects/{pid}/scrum/state` | Has own project creation — should migrate to consuming from ERP |
| ReqForge | ✅ Full | Portal postMessage | `/projects/{pid}/requirements/state` | Project selector populated from portal |
| ForgedOps/RCA | ✅ Full | Portal postMessage | `/projects/{pid}/rca_incidents/` | Multi-project subscription, `_unassigned` fallback |
| Notes App | ✅ Full | Portal postMessage | `/projects/{pid}/notes/` + `/users/{uid}/projects/{pid}/notes/` | Personal + shared per-project notes |
| ForgeBoard | ⚠️ Partial | Portal postMessage | localStorage (not yet Firebase) | Has project selector UI + postMessage handler, but data still local |
| MindForge | ❌ None | — | localStorage only | No project awareness yet |

### Migration Tasks

1. **Move project creation authority to ERP** — scrum-app should consume projects from the registry, not create them. ERP defines name, budget, timeline; scrum-app adds sprint/KDD planning on top.
2. **Enrich project registry schema** — Add `budget`, `timeline`, `status`, `owner` fields to `/projects/{pid}` doc (currently minimal).
3. **ForgeBoard → Firebase** — Migrate board data to `/projects/{pid}/forgeboard/boards/` (see optimization #2).
4. **MindForge → Firebase + project awareness** — Add postMessage listener, project selector, store maps at `/projects/{pid}/mindforge/maps/` (see optimization #6).
5. **ERP dashboard** — Build aggregated project overview pulling status from scrum, requirements, defects, and budget data across all sub-collections.

---

## Optimization Opportunities

### 1. Cross-App Entity Linking (High Impact)

Right now each app is a silo under a project — they share the project ID but nothing else. A **links collection** could tie entities together:

```
/projects/{pid}/links/{linkId}
{
  sourceApp: "scrum-app",
  sourceId: "card-abc123",
  sourceLabel: "STORY-42: Motor mount redesign",
  targetApp: "req-management",
  targetId: "REQ-17",
  targetLabel: "REQ-17: Torque spec >= 2.5Nm",
  linkType: "implements",   // implements | traces-to | blocks | references
  createdAt, createdBy
}
```

**What this enables:**
- Scrum card -> "Implements" -> Requirement -> "Traced by" -> ForgeBoard diagram
- ERP BOM item -> "References" -> Datasheet (from datasheet-search cache)
- RCA incident -> "Caused by" -> Scrum story (root cause traceability)
- Requirement -> "Verified by" -> Test result (future)

Each app adds a small "Linked Items" widget — reads from `/projects/{pid}/links` filtered by its own `sourceApp` or `targetApp`. This is a **V-model traceability** layer connecting design to implementation to verification.

---

### 2. ForgeBoard & MindForge to Firebase (High Impact)

These are the two creative/collaborative tools that currently use only localStorage. They're the most obvious candidates for Firebase integration:

- **ForgeBoard** already has the SSO listener (`sso-user` postMessage) but doesn't use it for data
- **MindForge** same situation
- Both would benefit from: **multi-device sync**, **project-linked boards**, and **cross-app references**

**Proposed collections:**
```
/projects/{pid}/forgeboard/boards     -> per-project whiteboards
/projects/{pid}/mindforge/maps        -> per-project mind maps
/users/{uid}/app_data/forgeboard      -> personal/unlinked boards
/users/{uid}/app_data/mindforge       -> personal/unlinked maps
```

**Synergy unlock**: A scrum card or requirement could link to a ForgeBoard diagram or a MindForge map. An engineer opens the card, clicks "View Diagram", and ForgeBoard opens with that board loaded.

---

### 3. Eliminate Legacy Dual-Writes (Quick Win)

Three apps currently dual-write to both new and legacy locations:

| App | New Path | Legacy Path | Action |
|-----|----------|-------------|--------|
| scrum-app | `/projects/{pid}/scrum/state` | `/kanban-boards/shared` | Drop legacy after migration check |
| req-management | `/projects/{pid}/requirements/state` | `/users/{uid}/app_data/reqforge_state` | Drop legacy |
| erp-app | `/projects/{pid}/erp/state` | `/users/{uid}/app_data/erp_global` | Keep global (POs/invoices are cross-project) |

Dropping dual-writes halves Firestore write operations for those two apps. Add a one-time migration flag (`_migrated_v2: true`) to skip legacy reads entirely.

---

### 4. Unified Activity Feed

Each app writes state changes but there's no cross-app activity view. A lightweight activity collection:

```
/projects/{pid}/activity/{auto}
{
  app: "scrum-app",
  action: "card_moved",
  summary: "STORY-42 moved to Done",
  entityId: "card-abc123",
  user: { uid, displayName },
  timestamp: serverTimestamp()
}
```

The **home portal dashboard** could show a unified project timeline: "Arnout moved STORY-42 to Done" -> "REQ-17 marked Verified" -> "BOM updated in ERP" — all in one feed. Capped at ~200 entries per project.

---

### 5. Offline-First with Firestore Persistence

None of the apps currently enable Firestore's built-in offline persistence:

```javascript
firebase.firestore().enablePersistence({ synchronizeTabs: true })
```

This gives:
- **Offline editing** — changes queued locally, synced when back online
- **Faster cold starts** — reads served from IndexedDB cache
- **Multi-tab sync** — changes propagate between tabs automatically

ForgeBoard and MindForge especially benefit since engineers might use them on the shop floor with spotty WiFi.

---

### 6. MindForge to Firebase

Same pattern as ForgeBoard (see #2). Lower priority since mind maps are less frequently shared, but still valuable for:
- Cross-device access
- Project-linked brainstorms
- Linking mind map nodes to requirements or scrum cards

---

### 7. Batch Save Optimization

Current write patterns are inefficient:

| App | Pattern | Issue |
|-----|---------|-------|
| erp-app | 800ms debounce, writes **all projects** iteratively | N Firestore writes per save |
| scrum-app | 500ms debounce + dual-write | 2 writes per save |
| forgeboard | 2s auto-save + 500ms debounce | Writes entire board state every 2s |

**Fixes:**
- **erp-app**: Only write the *active* project's state, not all projects. Dirty-flag per project.
- **scrum-app**: Drop dual-write (see #3 above)
- **forgeboard** (if migrated to Firebase): Use Firestore's `updateDoc` with field-level updates instead of full-state replacement. Or use a write-ahead log pattern: queue changes, batch-commit every 5s.

---

### 8. Shared Attachments / File References

Currently:
- ForgeBoard stores diagram PNGs as base64 data URLs in localStorage
- Datasheet-search caches PDFs as base64 in `/pdf_cache` (up to 700KB per doc)
- No shared file storage

**Proposal**: Use **Firebase Storage** (already available in the project) for shared artifacts:

```
gs://arnout-s-homelab/projects/{pid}/attachments/{fileId}
```

Firestore doc references the storage path. Any app can read/display the file. This unblocks:
- Attaching ForgeBoard exports to scrum cards
- Linking datasheets to ERP BOM line items
- Embedding mind maps in requirements documents

---

### 9. Project Template System

ForgeERP creates projects, but there's no way to spin up a project with pre-configured structure across apps. A template could create:

```javascript
// Template: "V-Cycle Hardware Project"
{
  scrum: { columns: ["Backlog","Design","Review","Test","Done"], labels: [...] },
  requirements: { categories: ["System","Mechanical","Electrical","Software"] },
  erp: { bomTemplate: true },
  forgeboard: { defaultBoard: "System Architecture" },
  mindforge: { defaultMap: "Design Brainstorm" }
}
```

Stored in `/project-templates/{templateId}`. When creating a new project in ForgeERP, the user picks a template and all apps get bootstrapped with sensible defaults.

---

## Priority Ranking

| # | Optimization | Effort | Impact | Synergy |
|---|-------------|--------|--------|---------|
| 1 | Cross-app entity linking | Medium | High | ★★★ |
| 2 | ForgeBoard to Firebase | Medium | High | ★★★ |
| 3 | Drop legacy dual-writes | Low | Medium | ★ |
| 4 | Unified activity feed | Low | Medium | ★★ |
| 5 | Firestore offline persistence | Low | Medium | ★★ |
| 6 | MindForge to Firebase | Medium | Medium | ★★ |
| 7 | Batch save optimization | Low | Low | ★ |
| 8 | Shared file storage | High | Medium | ★★ |
| 9 | Project templates | Medium | Medium | ★★ |

---

## Recommended Starting Point

**Start with #1 (cross-app linking) + #3 (drop dual-writes).**

The linking layer is the biggest force multiplier — it turns the collection of independent apps into an integrated engineering platform with V-model traceability. And dropping dual-writes is a quick win that reduces Firestore costs immediately.

After that, **#2 (ForgeBoard to Firebase)** opens the door for diagram-linked scrum cards and collaborative whiteboarding.
