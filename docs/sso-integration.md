# SSO Integration Guide for Child PWAs

> Last updated: 2026-02-25

This document describes how embedded PWA apps (iframes) receive and use Firebase SSO credentials from the BSI home portal.

---

## How It Works

The home portal (`blacksphereindustries.nl`) authenticates users via Firebase Auth (Google SSO). When a user signs in, the portal broadcasts auth credentials **and** the Firebase config to every embedded iframe via `postMessage`. Child PWAs listen for this message, initialize Firebase with the parent's config, and sign in using a 3-step fallback chain.

---

## Message Format

The parent sends a message of type `admin-auth` to all embedded iframes:

```javascript
{
  type: 'admin-auth',
  isAdmin: boolean,
  firebaseConfig: {              // Firebase project config (single source of truth)
    apiKey: string,
    authDomain: string,
    projectId: string,
    storageBucket: string,
    messagingSenderId: string,
    appId: string,
  },
  projects: [                    // Real-time project registry from Firestore
    { id: string, name: string },
    ...
  ],
  sso: {                         // null when no user is signed in
    uid: string,                 // Firebase user ID
    email: string,               // User email address
    displayName: string,         // User display name
    photoURL: string,            // User avatar URL
    idToken: string,             // Google OAuth ID token (from signInWithPopup)
    firebaseIdToken: string,     // Firebase ID token (for Cloud Function fallback)
  } | null,
}
```

### Token Types

| Token | Field | Source | Used For |
|-------|-------|--------|----------|
| Google OAuth ID token | `sso.idToken` | `signInWithPopup().credential.idToken` | `GoogleAuthProvider.credential()` in child apps |
| Firebase ID token | `sso.firebaseIdToken` | `auth.currentUser.getIdToken()` | Cloud Function `mintCustomToken()` fallback |

The Google OAuth token is the **primary** auth mechanism. The Firebase ID token is a **fallback** for when the OAuth token has expired.

---

## Parent Portal Behavior

The portal (`home/index.html`) handles:

1. **Initial auth**: `auth.signInWithPopup(googleProvider)` captures the Google OAuth token
2. **Token storage**: OAuth token stored in memory + `sessionStorage` (survives tab refresh)
3. **Broadcasting**: Sends `admin-auth` to all child iframes on sign-in, sign-out, and iframe load
4. **Auto-refresh**: Re-broadcasts auth state every 30 minutes
5. **Theme-request response**: Caches `_lastSSOData` and responds to child `sso-ready` requests

```javascript
// Portal sends to each iframe:
iframe.contentWindow.postMessage({
  type: 'admin-auth',
  isAdmin: isAdmin,
  firebaseConfig: FIREBASE_CONFIG,
  projects: projectList,
  sso: ssoPayload
}, '*');
```

---

## Receiving Auth in a Child PWA

### Recommended Pattern (3-Step Fallback)

All current BSI apps use this pattern. It handles token expiry gracefully:

```javascript
const ALLOWED_SSO_ORIGINS = [
  'https://blacksphereindustries.nl',
  'https://arnout-s-homelab.firebaseapp.com',
  'https://arnout-s-homelab.web.app'
];

let db = null;
let auth = null;
let _firebaseInitialized = false;
let currentUser = null;

function initFirebaseIfNeeded(config) {
  if (_firebaseInitialized || !config || !config.apiKey) return;
  firebase.initializeApp(config);
  db = firebase.firestore();
  auth = firebase.auth();
  _firebaseInitialized = true;
}

window.addEventListener('message', async (event) => {
  // Validate origin in production
  // if (!ALLOWED_SSO_ORIGINS.includes(event.origin)) return;

  const data = event.data;
  if (!data || data.type !== 'admin-auth') return;

  // 1. Initialize Firebase with parent's config (single source of truth)
  if (data.firebaseConfig) initFirebaseIfNeeded(data.firebaseConfig);

  if (data.sso) {
    currentUser = {
      uid: data.sso.uid,
      email: data.sso.email,
      displayName: data.sso.displayName,
      photoURL: data.sso.photoURL,
    };

    // 3-Step Firebase Auth
    try {
      // Step 0: Reuse existing session if UID matches
      if (auth.currentUser && auth.currentUser.uid === data.sso.uid) {
        console.log('SSO: reusing existing session');
      }
      // Step 1: Try Google OAuth token
      else if (data.sso.idToken) {
        const credential = firebase.auth.GoogleAuthProvider.credential(data.sso.idToken);
        await auth.signInWithCredential(credential);
        console.log('SSO: signed in via Google OAuth token');
      }
      // Step 2: Fallback to Cloud Function (mintCustomToken)
      else if (data.sso.firebaseIdToken) {
        const fn = firebase.functions().httpsCallable('mintCustomToken');
        const result = await fn({ idToken: data.sso.firebaseIdToken });
        await auth.signInWithCustomToken(result.data.customToken);
        console.log('SSO: signed in via Cloud Function fallback');
      }

      onUserSignedIn(currentUser);
    } catch (err) {
      console.warn('SSO sign-in failed:', err.message);
      // Display-only mode: UI shows user info but Firestore writes will fail
      onUserSignedIn(currentUser);
    }
  } else {
    currentUser = null;
    if (auth) { try { await auth.signOut(); } catch {} }
    onUserSignedOut();
  }
});
```

### Handling Race Conditions (sso-ready)

If your app loads before the portal sends auth, request it:

```javascript
// On app init, request SSO data from parent
if (window.parent !== window) {
  window.parent.postMessage({ type: 'sso-ready' }, '*');
}
```

The portal caches `_lastSSOData` and responds immediately.

---

## Firebase Config — Single Source of Truth

**Child apps must NEVER hardcode Firebase config.** They receive it from the parent via `data.firebaseConfig`.

```javascript
// CORRECT — use parent's config
if (data.firebaseConfig) initFirebaseIfNeeded(data.firebaseConfig);

// WRONG — hardcoded config goes stale
firebase.initializeApp({ apiKey: "old-key-that-will-expire", ... });

// WRONG — localStorage config takes priority over parent
const cfg = loadFirebaseConfig() || data.firebaseConfig;

// CORRECT — parent config takes priority
const cfg = data.firebaseConfig || loadFirebaseConfig();
```

Only store config in localStorage if the app needs standalone login capability outside the portal (e.g., erp-app).

---

## Nested Iframe Forwarding

Apps that host their own child iframes (e.g., erp-app hosts lab-inventory and filaments) must forward SSO:

```javascript
// erp-app forwards SSO to its own child iframes
const childIframe = document.getElementById('lab-inventory-frame');
if (childIframe) {
  childIframe.contentWindow.postMessage(data, '*');
}
```

---

## Storing Per-User and Per-Project Data

### Per-Project Data (preferred)

```javascript
function getAppProjectDoc(projectId) {
  return db.collection('projects').doc(projectId)
    .collection('myapp').doc('state');
}
```

### Per-User Data

```javascript
async function saveUserData(key, value) {
  if (!auth.currentUser) return;
  await db.collection('users').doc(auth.currentUser.uid)
    .collection('app_data').doc(key)
    .set(value, { merge: true });
}
```

### Reading the Project Registry

```javascript
function syncProjects() {
  db.collection('projects')
    .where('archived', '==', false)
    .onSnapshot(snapshot => {
      const projects = [];
      snapshot.forEach(doc => projects.push(doc.data()));
      // Use projects — must check archived === false (boolean, not null/missing)
    });
}
```

---

## Security Notes

1. **Validate `event.origin`** — Use `ALLOWED_SSO_ORIGINS` to restrict which parent can send auth messages.
2. **Never trust `isAdmin` for server-side decisions** — Use it for UI toggling only. Verify the ID token server-side for sensitive operations.
3. **Tokens expire after ~1 hour** — The portal re-broadcasts every 30 minutes. The 3-step fallback handles expiry gracefully.
4. **Google OAuth token vs Firebase ID token** — The `idToken` field is a Google-issued OAuth token, NOT a Firebase ID token. Using it directly with Firestore APIs will fail. Always use `GoogleAuthProvider.credential()` to convert it.
5. **Session persistence** — If a user was already signed in before the portal loaded (Firebase auth persistence), the OAuth token may not be available. Users may need to sign out and back in to trigger a fresh `signInWithPopup()`.

---

## Checklist for Adding SSO to a New Child PWA

- [ ] Load Firebase compat SDK (app, auth, firestore) from CDN — match version `10.12.0`
- [ ] Add `postMessage` listener for `admin-auth` messages
- [ ] Call `initFirebaseIfNeeded(data.firebaseConfig)` — never hardcode config
- [ ] Implement 3-step auth: reuse session → OAuth credential → Cloud Function fallback
- [ ] Send `{ type: 'sso-ready' }` to parent on init (handles race conditions)
- [ ] Define `ALLOWED_SSO_ORIGINS` for origin validation
- [ ] Update UI on sign-in / sign-out
- [ ] Store data under `/projects/{pid}/myapp/state` (per-project) or `/users/{uid}/app_data/` (per-user)
- [ ] Add Firestore rules for new subcollection in `home/firestore.rules` and deploy
- [ ] Test: sign in, sign out, token refresh (wait 30 min), page reload
