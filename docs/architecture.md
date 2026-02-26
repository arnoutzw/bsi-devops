# Black Sphere Industries — Architecture Overview

## Portal

**Repo:** `arnoutzw/home` (formerly `arnoutzw/pages`)
**URL:** [blacksphereindustries.nl](https://blacksphereindustries.nl)
**Hosting:** Cloudflare Pages

Single-page React app (Babel standalone, no build step) that serves as the hub for all tools. Features:

- Engineering blog with markdown articles
- App grid organized by discipline categories
- Firebase Auth (Google SSO + anonymous/guest)
- Iubenda cookie consent (with autoBlocking workaround for marked.js)
- Feedback form → Firestore
- ASML light theme CSS + postMessage listener (receives theme changes from child apps)
- Apps load in iframes within the portal

---

## Business Apps (Firebase-backed, now with demo mode)

| App | Repo | Pages.dev URL | Description |
|-----|------|---------------|-------------|
| **Kanban / Agile** | `arnoutzw/scrum-app` | scrum-app.pages.dev | Project planner with drag-and-drop boards, sprints, retro, Scrum ceremonies |
| **ReqForge** | `arnoutzw/req-management` | req-management.pages.dev | Requirements management — create, trace, coverage analysis |
| **ForgeERP** | `arnoutzw/erp-app` | erp-app-eqo.pages.dev | Lightweight ERP — parts, assemblies, BOMs, inventory, lab tracking |
| **ForgedOps** | `arnoutzw/alm-app` | alm-app.pages.dev | Application Lifecycle Management — defects, work items, releases |

All four use Firebase Auth + Firestore with a `projects → subcollection` pattern:
- scrum-app: `projects/{id}/scrum` (tasks)
- req-management: `projects/{id}/requirements`
- erp-app: `projects/{id}/erp` (parts/assemblies)
- alm-app: `projects/{id}/defects`

**Demo mode** (`?demo=true`): DemoFirestore shim intercepts all Firebase calls, routes to localStorage-backed local database with seeded demo data. Blue banner at top with Exit/Reset controls.

---

## Electrical Engineering Apps

| App | Repo | Description |
|-----|------|-------------|
| **Filter Design Studio** | `arnoutzw/filter-design-studio-app` | Design Butterworth/Chebyshev/Bessel filters, interactive Bode plots |
| **Control Loop Tuner** | `arnoutzw/control-tuner-app` | PID tuning with Ziegler-Nichols, Cohen-Coon, step response (Three.js + Chart.js) |
| **Engineering Calculators** | `arnoutzw/engineering-calcs-app` | PWA with contact mechanics, bearings, fasteners, fatigue, fluid flow calcs |

---

## Mechanical Engineering Apps

| App | Repo | Description |
|-----|------|-------------|
| **RoboKin** | `arnoutzw/kinematics-studio-app` | Robot kinematics simulator (Three.js) |
| **BeamFEA** | `arnoutzw/mech-fea-app` | 2D finite element beam analysis (Three.js) |
| **SuspensionViz** | `arnoutzw/suspension-viz-app` | Car suspension model visualizer (Three.js) |

---

## Physics Apps

| App | Repo | Description |
|-----|------|-------------|
| **Magnetic Field Calculator** | `arnoutzw/magfield-app` | 3D magnetic field visualization (Three.js) |

---

## Fabrication / Hardware Apps

| App | Repo | Description |
|-----|------|-------------|
| **Bambu 3MF Viewer** | `arnoutzw/bambu-viewer` | View Bambu Lab 3MF print files (Three.js) |
| **G-code Viewer** | `arnoutzw/g-code-viewer` | Visualize CNC/3D printer G-code toolpaths (Canvas) |
| **Wood Cutting Optimizer** | `arnoutzw/woodcut-optimizer` | Optimize panel cuts for Hornbach lumber (Canvas + drag-and-drop) |
| **Label Designer** | `arnoutzw/label-designer-app` | Design and print labels (Canvas + drag-and-drop) |

---

## Software / Dev Tools

| App | Repo | Description |
|-----|------|-------------|
| **PyLab** | `arnoutzw/py-lab-app` | Browser-based Python environment (Firebase-backed) |
| **Datasheet Search** | `arnoutzw/datasheet-search-app` | Search electronic component datasheets (Firebase) |

---

## Hardware Communication Apps

| App | Repo | Description |
|-----|------|-------------|
| **ESP Flash Tool** | `arnoutzw/serial-app` | Flash ESP32/ESP8266 via Web Serial API |
| **JK BMS Monitor** | `arnoutzw/jk-bms-app` | JK Battery Management System monitor (Web Serial + Bluetooth) |
| **Powerqueen BMS Monitor** | `arnoutzw/pq-bms-app` | Powerqueen BMS monitor (Web Bluetooth + Canvas) |

---

## 404 / Unavailable Repos

These are referenced in the portal config but return 404:
- `arnoutzw/gear-calculator`
- `arnoutzw/vibration-mode-visualizer`
- `arnoutzw/notes-app` (Business category)
- `arnoutzw/mijia-monitor`
- `arnoutzw/neural-terminal`

---

## Cross-Cutting Features (all apps)

- **Theme:** Dark (default) + ASML light theme (`data-theme="asml"`)
- **postMessage signalling:** All apps send `{ type: "theme-change", theme: "dark"|"asml" }` to parent portal on theme toggle
- **PWA:** Most apps register service workers for offline use
- **Single-file architecture:** Each app is a single `index.html` (no build step, inline JS/CSS)
- **Hosting:** All on Cloudflare Pages, deployed from GitHub repos

## Tech Stack Summary

- **Frontend:** Vanilla JS / React (via Babel standalone) / Tailwind CSS
- **3D:** Three.js (9 apps)
- **Charts:** Chart.js (3 apps)
- **Backend:** Firebase Auth + Firestore (6 apps)
- **Hardware:** Web Serial API (2 apps), Web Bluetooth API (2 apps)
- **Hosting:** Cloudflare Pages (all repos)
