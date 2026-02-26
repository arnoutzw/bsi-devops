# Firebase Architecture — Black Sphere Industries

> Last updated: 2026-02-16
> Firebase project: `arnout-s-homelab` (project number `258011834485`)
> Domain: `blacksphereindustries.nl`
> All apps hosted on Cloudflare Pages under `{app-name}.pages.dev/`

---

## 1. System Overview

The platform consists of a **home portal** and multiple **child apps** loaded as cross-origin iframes. All apps share a single Firebase project. The home portal is the single source of truth for Firebase configuration and authentication.

```
blacksphereindustries.nl (home portal)
├── scrum-app.pages.dev/              (iframe)
├── erp-app-eqo.pages.dev/           (iframe)
├── req-management.pages.dev/        (iframe)
└── alm-app.pages.dev/               (iframe)
```

All apps are **single-file HTML PWAs** using React via CDN and Firebase compat SDK v10.x.

---

## 2. Firebase Configuration

### 2.1 The Config Object

The canonical Firebase config lives in `home/index.html`:

```javascript
const FIREBASE_CONFIG = {
  apiKey: "AIzaSyAJ6y1Jz8OHj2gbnWRZIk1TGZLcggvAMQ4",
  authDomain: "arnout-s-homelab.firebaseapp.com",
  projectId: "arnout-s-homelab",
  storageBucket: "arnout-s-homelab.firebasestorage.app",
  messagingSenderId: "258011834485",
  appId: "1:258011834485:web:5afb1efaa303b4dd93f03c",
  measurementId: "G-VXDKDLXP7L"
};
```

### 2.2 Config Distribution

The home portal sends the config to every child iframe via `postMessage`. Child apps **must never hardcode** Firebase config or API keys. They receive it from the parent.

**Critical rule:** Child apps must **always prefer the parent portal's config** (`SSO_FIREBASE_CONFIG` or `data.firebaseConfig`) over any locally cached config. The ForgeERP app had a bug where it preferred `loadFirebaseConfig()` (localStorage) over the parent's config, causing stale expired API keys to persist. The fix is:

```javascript
// CORRECT — parent config takes priority
const cfgToUse = SSO_FIREBASE_CONFIG || loadFirebaseConfig();

// WRONG — stale local config wins
const cfgToUse = loadFirebaseConfig() || SSO_FIREBASE_CONFIG;
```

### 2.3 Config Patterns by App

| App | Config source | Stores locally? | Notes |
|-----|--------------|-----------------|-------|
| home | Hardcoded `FIREBASE_CONFIG` | No | Single source of truth |
| scrum-app | `data.firebaseConfig` via postMessage | No | `initFirebaseIfNeeded(config)` — runs once, no localStorage |
| req-management | `data.firebaseConfig` via postMessage | No | Same pattern as scrum-app |
| erp-app | `SSO_FIREBASE_CONFIG` via postMessage | Yes (`forgeERP_firebaseConfig`) | Has standalone login screen; prefers parent config when available |

**If adding a new app:** Use the scrum-app pattern (no local storage of config). Only store config locally if the app needs standalone login capability outside the portal.

---

## 3. Authentication & SSO

### 3.1 How SSO Works

1. User clicks "Sign in" on the home portal
2. Home portal calls `auth.signInWithPopup(googleProvider)`
3. The popup returns a `result` object containing `result.credential.idToken` — this is the **Google OAuth ID token** (issued by Google, not Firebase)
4. Home portal stores this token in memory (`_googleOAuthIdToken`) and `sessionStorage` for page-refresh survival
5. For each child iframe, home portal calls `iframe.contentWindow.postMessage(...)` with the config, SSO data, and tokens

### 3.2 The postMessage Payload

```javascript
{
  type: 'admin-auth',
  isAdmin: true/false,
  firebaseConfig: FIREBASE_CONFIG,
  sso: {
    uid: "user-uid",
    email: "user@example.com",
    displayName: "User Name",
    photoURL: "https://...",
    idToken: "Google OAuth ID token",     // For GoogleAuthProvider.credential()
    firebaseIdToken: "Firebase ID token"  // For display-only fallback
  }
}
```

### 3.3 Child App Sign-In Flow

Each child app receives the postMessage and signs in:

```javascript
window.addEventListener('message', async (event) => {
  const data = event.data;
  if (!data || data.type !== 'admin-auth') return;

  // 1. Initialize Firebase with parent's config
  if (data.firebaseConfig) initFirebaseIfNeeded(data.firebaseConfig);

  // 2. Sign in using Google OAuth ID token
  if (data.sso && data.sso.idToken) {
    const credential = firebase.auth.GoogleAuthProvider.credential(data.sso.idToken);
    await auth.signInWithCredential(credential);
  }
});
```

### 3.4 Token Types — Critical Distinction

| Token | Source | Used for | Obtained via |
|-------|--------|----------|-------------|
| Google OAuth ID token | Google's OAuth server | `GoogleAuthProvider.credential()` in child apps | `result.credential.idToken` from `signInWithPopup()` |
| Firebase ID token | Firebase Auth | API calls, display-only fallback | `currentUser.getIdToken()` |

**The Google OAuth token** is what child apps need for `signInWithCredential()`. Using a Firebase ID token will cause `auth/invalid-credential` errors ("id token is not issued by Google").

### 3.5 Token Lifecycle

- The Google OAuth token is captured **only** during `signInWithPopup()` in the home portal
- It's stored in `sessionStorage` so it survives page refreshes within the same tab
- If the user was already signed in before the portal loaded (Firebase auth persistence), the OAuth token is **not available** — only the Firebase ID token is
- This means: if auth flows break, users may need to **sign out and sign back in** to trigger a fresh `signInWithPopup()` and capture a new OAuth token

---

## 4. Firestore Data Schema

### 4.1 Collection Map

```
Firestore
├── /projects/{projectId}                          # Shared project registry
│   ├── id, name, ownerApp, createdAt, updatedAt, archived
│   ├── /scrum/state                               # Scrum-app per-project data
│   ├── /requirements/state                        # Req-management per-project data
│   └── /erp/state                                 # ForgeERP per-project data
│
├── /users/{userId}/app_data/
│   ├── reqforge_state                             # Legacy req-management (full state dump)
│   └── erp_global                                 # ForgeERP global data (POs, invoices, contacts, inventory)
│
├── /kanban-boards/shared                          # Legacy scrum-app (full state dump)
├── /github_cache/{document}                       # GitHub API response cache
├── /pdf_cache/{document}                          # PDF document cache
├── /feedback/{document}                           # User feedback submissions
├── /retro-nicknames/{document}                    # Retro session nicknames (public)
└── /retro-presence/{document}                     # Retro session presence (public)
```

### 4.2 Shared Project Registry

**Collection:** `/projects/{projectId}`

**Owner:** scrum-app (creates and updates projects)
**Readers:** All apps (erp-app, req-management read via `onSnapshot`)

**Document structure:**
```javascript
{
  id: "mlkp5k8bmnjgdo",        // Same as document ID
  name: "My Project Name",
  ownerApp: "scrum-app",
  createdAt: 1770975612587,     // Unix timestamp ms
  updatedAt: 1771215219575,
  archived: false               // CRITICAL: must be boolean false, not missing/null
}
```

**Important:** ForgeERP and other apps query with `.where('archived', '==', false)`. If this field is missing or has a non-boolean value, projects won't appear in child apps.

### 4.3 Per-Project App Data

#### Scrum: `/projects/{pid}/scrum/state`

Contains the full project object from scrum-app's `state.projects[]` entry:

```javascript
{
  id: "mlkp5k8bmnjgdo",
  name: "My Project",
  columns: [{ id, name, wipLimit }],
  cards: [{ id, columnId, title, description, priority, labels, members, ... }],
  labels: [{ name, color }],
  members: [{ id, name, email, avatar }],
  retro: { ... },
  // ... all scrum project fields
}
```

**Write pattern:** Debounced (500ms), writes active project on every state change. Also dual-writes to legacy `/kanban-boards/shared`.

#### Requirements: `/projects/{pid}/requirements/state`

```javascript
{
  workItems: [{ id, project, type, title, status, priority, ... }],
  documents: [{ id, project, title, content, ... }],
  links: [{ id, project, sourceId, targetId, type }],
  baselines: [{ id, project, name, snapshot, ... }],
  activity: [{ project, action, timestamp, ... }],  // capped at 200 entries
  nextId: 42,
  nextDocId: 10,
  updatedAt: 1771215219575
}
```

**Write pattern:** Filters items by `project === currentProject` before writing. Also dual-writes full state to legacy `/users/{uid}/app_data/reqforge_state`.

#### ForgeERP: `/projects/{pid}/erp/state`

```javascript
{
  bom: [{ id, projectId, invId, partName, qty, refDes, notes }],
  workOrders: [{ id, projectId, name, station, status, priority, qty, completed, assignee, ... }],
  quotes: [{ id, client, project, type, status, items, total, ... }],
  projectMeta: { client, status, priority, lead, startDate, deadline, progress, description, budget },
  updatedAt: 1771215219575
}
```

**Write pattern:** Debounced (800ms). Iterates ALL projects and writes each one's data filtered by `projectId` (for BOM/workOrders) or matched by project `name` (for quotes).

### 4.4 Global/User-Scoped Data

#### ForgeERP Global: `/users/{uid}/app_data/erp_global`

```javascript
{
  purchaseOrders: [...],
  invoices: [...],
  contacts: [...],
  inventory: [...],
  updatedAt: 1771215219575
}
```

#### Legacy Req State: `/users/{uid}/app_data/reqforge_state`

Full state dump of all requirement data across all projects. Kept for backward compatibility. Will be auto-migrated to per-project docs on first load.

---

## 5. Firestore Security Rules

Rules are defined in `home/firestore.rules` and deployed via:

```bash
cd home-repo
firebase use arnout-s-homelab
firebase deploy --only firestore:rules
```

**Rule patterns:**

| Path | Read | Write |
|------|------|-------|
| `/github_cache/*`, `/pdf_cache/*` | Public | Authenticated |
| `/feedback/*` | Authenticated | Anyone (with schema validation) |
| `/users/{userId}/**` | Owner only | Owner only |
| `/projects/{projectId}` | Authenticated | Authenticated |
| `/projects/{pid}/scrum/*` | Authenticated | Authenticated |
| `/projects/{pid}/requirements/*` | Authenticated | Authenticated |
| `/projects/{pid}/erp/*` | Authenticated | Authenticated |
| `/kanban-boards/**` | Authenticated | Authenticated |
| `/retro-nicknames/*`, `/retro-presence/*` | Public | Public |

**After adding new subcollections**, you must add a matching rule and redeploy.

---

## 6. Data Flow Patterns

### 6.1 Project Lifecycle

```
1. User creates project in scrum-app
2. scrum-app writes to /projects/{id} (registry) + /projects/{id}/scrum/state
3. Other apps read /projects via onSnapshot listener
4. When data is created in ForgeERP/ReqForge for that project:
   - Written to /projects/{id}/erp/state or /projects/{id}/requirements/state
```

### 6.2 Migration Pattern

All apps use the same auto-migration strategy:

1. On sign-in, try loading from new per-project location first
2. If not found, load from legacy location
3. If legacy data found, auto-migrate to per-project docs
4. Check migration by testing if first project's doc exists in new location
5. Continue dual-writing to legacy location for backward compat

```javascript
// Migration check pattern
const checkDoc = await getProjectDoc(firstProject.id).get();
if (checkDoc.exists) return; // already migrated
// ... migrate data ...
```

### 6.3 Write Patterns

| App | Trigger | Debounce | Dual-write |
|-----|---------|----------|------------|
| scrum-app | Every `save()` call | 500ms | Per-project + `/kanban-boards/shared` |
| req-management | Every `saveStateToFirestore()` | None (explicit) | Per-project + `/users/{uid}/app_data/reqforge_state` |
| erp-app | Every `saveDB()` (localStorage write) | 800ms | Per-project + `/users/{uid}/app_data/erp_global` |

### 6.4 Real-time Listeners

| App | Collection | Purpose |
|-----|-----------|---------|
| scrum-app | `/kanban-boards/shared` | Legacy full-state sync |
| scrum-app | `/projects/{pid}/scrum/state` | Per-project real-time updates |
| erp-app | `/projects` (where archived==false) | Sync project list from registry |

---

## 7. Adding a New App

Follow these steps to add a new child app to the platform:

### 7.1 Firebase Setup in the App

Use the scrum-app pattern (simplest, no local config storage):

```javascript
// 1. Load Firebase compat SDK in <head>
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore-compat.js"></script>

// 2. Lazy Firebase init — NEVER hardcode config
let db = null;
let auth = null;
let _firebaseInitialized = false;

function initFirebaseIfNeeded(config) {
  if (_firebaseInitialized || !config || !config.apiKey) return;
  firebase.initializeApp(config);
  db = firebase.firestore();
  auth = firebase.auth();
  _firebaseInitialized = true;
}

// 3. Receive config + SSO from parent portal
let currentUser = null;

window.addEventListener('message', async (event) => {
  const data = event.data;
  if (!data || data.type !== 'admin-auth') return;

  if (data.firebaseConfig) initFirebaseIfNeeded(data.firebaseConfig);

  if (data.sso) {
    currentUser = {
      uid: data.sso.uid,
      email: data.sso.email,
      displayName: data.sso.displayName,
      photoURL: data.sso.photoURL,
    };

    if (auth && data.sso.idToken) {
      try {
        const credential = firebase.auth.GoogleAuthProvider.credential(data.sso.idToken);
        await auth.signInWithCredential(credential);
        // SUCCESS — now Firestore operations will work
        onSignedIn();
      } catch (err) {
        console.warn('SSO sign-in failed:', err.message);
        // Display-only mode — Firestore writes will fail
      }
    }
  } else {
    currentUser = null;
    if (auth) { try { await auth.signOut(); } catch {} }
    onSignedOut();
  }
});
```

### 7.2 Per-Project Data Storage

```javascript
// Helper to get your app's per-project doc
function getMyAppProjectDoc(projectId) {
  if (!db || !projectId) return null;
  return db.collection('projects').doc(projectId).collection('myapp').doc('state');
}

// Read project list from shared registry
function syncProjectsFromRegistry() {
  if (!currentUser || !db) return;
  db.collection('projects')
    .where('archived', '==', false)
    .onSnapshot(snapshot => {
      const projects = [];
      snapshot.forEach(doc => projects.push(doc.data()));
      // Use these projects — DO NOT merge with hardcoded demo data
      myState.projects = projects;
      render();
    });
}
```

### 7.3 Firestore Rules

Add rules for your new subcollection in `home/firestore.rules`:

```
match /projects/{projectId}/myapp/{document} {
  allow read, write: if request.auth != null;
}
```

Then deploy:
```bash
cd home-repo && firebase deploy --only firestore:rules
```

### 7.4 Register in Home Portal

Add the app to the home portal's app list in `home/index.html` so it appears in the grid and navigation.

---

## 8. Common Issues & Fixes

### 8.1 `auth/invalid-credential` — "id token is not issued by Google"

**Cause:** Child app received a Firebase ID token instead of Google OAuth ID token.
**Fix:** Ensure home portal captures `result.credential.idToken` from `signInWithPopup()` and sends it as `sso.idToken`. The child needs the Google-issued token for `GoogleAuthProvider.credential()`.

### 8.2 `auth/api-key-expired`

**Cause:** Child app has a stale API key cached in localStorage.
**Fix:** Ensure the app prefers `SSO_FIREBASE_CONFIG` (from parent postMessage) over `loadFirebaseConfig()` (from localStorage). Clear stale keys: `localStorage.removeItem('forgeERP_firebaseConfig')`.

### 8.3 `permission-denied` on Firestore operations

**Cause:** Firestore rules haven't been deployed for the new collection/subcollection.
**Fix:** Add rules to `home/firestore.rules` and deploy with `firebase deploy --only firestore:rules`.

### 8.4 Projects not syncing to child apps

**Cause:** The `/projects` documents must have `archived: false` (boolean). If the field is missing, `null`, or a string, the `.where('archived', '==', false)` query won't match.
**Fix:** Ensure scrum-app always writes `archived: false` when creating projects.

### 8.5 SSO works but Firestore operations fail

**Cause:** SSO sign-in might have fallen back to "display-only" mode (fake `_currentUser` object without actual Firebase auth). In this mode, Firestore operations fail because `request.auth` is null.
**Fix:** Check console for "SSO sign-in failed" messages. User needs to sign out and sign back in to get a fresh Google OAuth token.

### 8.6 Service worker caching stale code

**Cause:** PWA service workers cache `index.html`. Even though most use network-first for navigation, the old code may persist.
**Fix:** Bump the `CACHE_NAME` version in `sw.js`. User can also run in console:
```javascript
navigator.serviceWorker.getRegistrations().then(r => r.forEach(sw => sw.unregister()));
caches.keys().then(keys => keys.forEach(k => caches.delete(k)));
location.reload();
```

### 8.7 postMessage not reaching child iframe

**Cause:** Cross-origin postMessage requires correct target origin.
**Fix:** Home portal computes `iframeOrigin` from the iframe's `src` URL. Verify the iframe URL matches what's expected (e.g., `https://scrum-app.pages.dev`).

---

## 9. Deployment Checklist

### Deploying Firestore Rules
```bash
cd ~/repos/home
firebase use arnout-s-homelab   # only needed once
firebase deploy --only firestore:rules
```

### Deploying an App
```bash
cd ~/repos/{app-name}
git add . && git commit -m "description"
git push origin main
# GitHub Pages auto-deploys in 1-5 minutes
# Check: github.com/arnoutzw/{app-name}/actions
```

### After Deploying
1. Wait for GitHub Pages build to complete (check Actions tab)
2. Hard refresh the site (Cmd+Shift+R)
3. If PWA cached: clear service worker (see 8.6)
4. If auth issues: sign out and sign back in
5. If new collections: deploy Firestore rules FIRST

---

## 10. File Locations

| File | Repo | Purpose |
|------|------|---------|
| `firestore.rules` | home | Firestore security rules (deploy from here) |
| `index.html` | home | Portal + Firebase config + SSO + postMessage |
| `index.html` | scrum-app | Scrum board + project registry owner |
| `index.html` | req-management | ReqForge |
| `index.html` | erp-app | ForgeERP (has standalone login + localStorage config) |
| `sw.js` | erp-app | Service worker (bump `CACHE_NAME` on deploy) |
| `.firebaserc` | home | Firebase project alias (`arnout-s-homelab`) |

---

## 11. Firebase SDK Versions

All apps use Firebase compat SDK loaded via CDN:

```html
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore-compat.js"></script>
```

Keep versions aligned when updating.

The compat SDK provides the `firebase.` namespace API (v8-style). Do not mix with modular SDK imports.
