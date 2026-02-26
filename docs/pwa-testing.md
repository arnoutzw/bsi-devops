# PWA Unit Testing via Console Injection

A practical guide for testing single-file HTML Progressive Web Apps deployed on Cloudflare Pages, using localStorage-backed data and browser DevTools.

## 1. Overview

### Why Console Injection Testing?

These PWAs have characteristics that make traditional testing frameworks impractical:

- **Single-file HTML** - No build system or bundling
- **No test framework** - Would require adding external dependencies
- **localStorage data layer** - In-memory state with DemoFirestore shim
- **Cloudflare Pages deployment** - Changes verify through live site reload

**Solution: JavaScript console injection** - Run verification scripts directly in the browser, leveraging the app's own runtime environment, DOM access, and localStorage.

### Testing Scope

Console injection testing covers:
1. Data layer verification (localStorage seed integrity)
2. UI component rendering (DOM queries, styles, event handlers)
3. Theme system functionality (CSS variables, persistence)
4. Encoding/UTF-8 integrity (detecting and fixing mojibake)

---

## 2. Data Layer Testing

### Reading localStorage Seeds

```javascript
window._checkLocalStorage = () => {
  const keys = Object.keys(localStorage);
  console.log(`Found ${keys.length} localStorage keys:`);

  keys.forEach(key => {
    const value = localStorage.getItem(key);
    const size = new Blob([value]).size;
    console.log(`  ${key}: ${size} bytes`);

    try {
      const parsed = JSON.parse(value);
      console.log(`    → Valid JSON, keys: ${Object.keys(parsed).join(', ')}`);
    } catch {
      console.log(`    → Not JSON`);
    }
  });
};

// Usage
window._checkLocalStorage();
```

### Verify Data Structure

```javascript
window._verifyDataStructure = () => {
  const data = JSON.parse(localStorage.getItem('seed_data') || '{}');
  const issues = [];

  // Check required fields for projects
  (data.projects || []).forEach((project, idx) => {
    if (!project.id) issues.push(`Project ${idx} missing id`);
    if (!project.name) issues.push(`Project ${idx} missing name`);
    if (!Array.isArray(project.defects)) issues.push(`Project ${idx} defects not array`);
    if (!Array.isArray(project.requirements)) issues.push(`Project ${idx} requirements not array`);
  });

  // Check relationships
  (data.defects || []).forEach((defect, idx) => {
    const hasProject = data.projects.some(p => p.id === defect.projectId);
    if (!hasProject) issues.push(`Defect ${idx} references non-existent projectId ${defect.projectId}`);
  });

  if (issues.length === 0) {
    console.log('✓ Data structure valid');
  } else {
    console.error('✗ Data structure issues:');
    issues.forEach(issue => console.error(`  - ${issue}`));
  }

  return issues;
};

// Usage
window._verifyDataStructure();
```

### Test Seed Initialization

```javascript
window._testSeedReset = async () => {
  console.log('1. Clearing localStorage...');
  localStorage.clear();

  console.log('2. Reloading page...');
  window.location.reload();

  // After page reloads, run this in the console:
  console.log('3. Checking initialized data...');
  window._checkLocalStorage();
};
```

### Verify Data Persistence

```javascript
window._testPersistence = async () => {
  const before = JSON.parse(localStorage.getItem('seed_data') || '{}');
  console.log(`Before reload: ${Object.keys(before).length} top-level keys`);

  // Store a marker
  sessionStorage.setItem('_persistence_check', 'started');
  window.location.reload();

  // After reload, paste this:
  const after = JSON.parse(localStorage.getItem('seed_data') || '{}');
  const wasMarked = sessionStorage.getItem('_persistence_check') === 'started';

  console.log(`After reload: ${Object.keys(after).length} top-level keys`);
  console.log(`Data persisted: ${before.projects?.length === after.projects?.length ? '✓' : '✗'}`);
};
```

---

## 3. UI Injection Testing

### Detect Overlay/Panel Visibility with MutationObserver

Settings overlays and panels often render dynamically. Don't query the DOM directly - observe mutations:

```javascript
window._waitForOverlay = (selector, timeout = 5000) => {
  return new Promise((resolve, reject) => {
    // Check if already visible
    const existing = document.querySelector(selector);
    if (existing) return resolve(existing);

    // Watch for mutations
    const observer = new MutationObserver(() => {
      const element = document.querySelector(selector);
      if (element) {
        observer.disconnect();
        resolve(element);
      }
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true
    });

    setTimeout(() => {
      observer.disconnect();
      reject(new Error(`Overlay ${selector} not found after ${timeout}ms`));
    }, timeout);
  });
};

// Usage
const overlay = await window._waitForOverlay('.settings-panel');
console.log('✓ Settings panel appeared:', overlay);
```

### Query DOM Elements & Verify Theme CSS

```javascript
window._checkThemeCSS = () => {
  const root = document.documentElement;
  const styles = getComputedStyle(root);

  const checks = [
    ['--primary-color', 'primary theme color'],
    ['--bg-color', 'background color'],
    ['--text-color', 'text color']
  ];

  checks.forEach(([varName, desc]) => {
    const value = styles.getPropertyValue(varName).trim();
    const exists = value.length > 0;
    console.log(`${exists ? '✓' : '✗'} ${desc} (${varName}): ${value || 'NOT SET'}`);
  });
};

window._checkThemeCSS();
```

### Check iframe src Attributes

```javascript
window._checkIframes = () => {
  const iframes = document.querySelectorAll('iframe');
  console.log(`Found ${iframes.length} iframes:`);

  iframes.forEach((iframe, idx) => {
    const src = iframe.getAttribute('src');
    console.log(`  [${idx}] ${iframe.id || '(no id)'}`);
    console.log(`      src: ${src}`);
    console.log(`      origin: ${new URL(src, window.location).origin}`);
  });
};

window._checkIframes();
```

### Test Event Handlers

```javascript
window._testEventHandler = async (selector, eventType) => {
  const element = document.querySelector(selector);
  if (!element) throw new Error(`Element not found: ${selector}`);

  console.log(`Triggering ${eventType} on ${selector}`);

  const event = eventType === 'click'
    ? new MouseEvent(eventType, { bubbles: true })
    : new Event(eventType, { bubbles: true });

  element.dispatchEvent(event);

  // Wait for handlers to execute
  await new Promise(r => setTimeout(r, 100));
  console.log('✓ Event dispatched and handlers executed');
};

// Usage
await window._testEventHandler('#theme-toggle-btn', 'click');
```

---

## 4. Theme System Testing

### Verify CSS Custom Properties Exist

```javascript
window._checkThemeVariables = () => {
  const root = document.documentElement;
  const styles = getComputedStyle(root);
  const allProps = Array.from(styles).filter(prop => prop.startsWith('--'));

  console.log(`Found ${allProps.length} CSS custom properties`);

  const themes = ['dark', 'light'];
  const expectedVars = ['primary-color', 'bg-color', 'text-color', 'border-color'];

  themes.forEach(theme => {
    root.setAttribute('data-theme', theme);
    const missing = [];

    expectedVars.forEach(varName => {
      const fullName = `--${theme}-${varName}`;
      if (!allProps.includes(fullName)) {
        missing.push(fullName);
      }
    });

    console.log(`${theme} theme: ${missing.length === 0 ? '✓ all vars present' : '✗ missing: ' + missing.join(', ')}`);
  });
};

window._checkThemeVariables();
```

### Test applyTheme() Function

```javascript
window._testApplyTheme = async () => {
  if (typeof applyTheme !== 'function') {
    console.error('applyTheme function not found');
    return;
  }

  console.log('Testing applyTheme...');

  applyTheme('dark');
  let dataTheme = document.documentElement.getAttribute('data-theme');
  console.log(`After applyTheme('dark'): data-theme=${dataTheme} ${dataTheme === 'dark' ? '✓' : '✗'}`);

  applyTheme('light');
  dataTheme = document.documentElement.getAttribute('data-theme');
  console.log(`After applyTheme('light'): data-theme=${dataTheme} ${dataTheme === 'light' ? '✓' : '✗'}`);
};

await window._testApplyTheme();
```

### Test Theme Persistence

```javascript
window._testThemePersistence = () => {
  const key = 'selectedTheme';
  const theme = 'dark';

  localStorage.setItem(key, theme);
  window.location.reload();

  // After reload, run:
  const stored = localStorage.getItem(key);
  const applied = document.documentElement.getAttribute('data-theme');
  console.log(`Stored theme: ${stored}`);
  console.log(`Applied theme: ${applied}`);
  console.log(`Persistence working: ${stored === applied ? '✓' : '✗'}`);
};
```

### Test postMessage for Portal Integration

```javascript
window._testPostMessage = () => {
  const iframe = document.querySelector('iframe[data-portal="true"]');
  if (!iframe) {
    console.log('No portal iframe found');
    return;
  }

  window.addEventListener('message', (e) => {
    console.log('✓ Received message from portal:', e.data);
  });

  iframe.contentWindow.postMessage({ type: 'THEME_CHANGE', theme: 'dark' }, '*');
  console.log('Sent THEME_CHANGE message to portal');
};

window._testPostMessage();
```

---

## 5. Encoding & UTF-8 Testing

### Detect Mojibake (Double-Encoded UTF-8)

Mojibake occurs when UTF-8 text is decoded as Latin-1 (or vice versa):

```javascript
window._detectMojibake = (text) => {
  // If a character is in the 0x80-0xFF range in Latin-1, it's likely mojibake
  const suspiciousChars = [];

  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x80 && code <= 0xFF) {
      suspiciousChars.push({ pos: i, char: text[i], code: code.toString(16) });
    }
  }

  if (suspiciousChars.length === 0) {
    console.log('✓ No mojibake detected');
    return false;
  }

  console.log(`✗ Potential mojibake found (${suspiciousChars.length} chars):`);
  suspiciousChars.slice(0, 5).forEach(({ char, code }) => {
    console.log(`  0x${code}: ${char}`);
  });

  return true;
};

// Usage
window._detectMojibake(localStorage.getItem('some_data'));
```

### Fix UTF-8 Encoding (Iterative Approach)

```javascript
window._fixEncoding = (text) => {
  let result = text;
  const originalByteCount = new Blob([text]).size;

  // Fix 3-byte UTF-8 sequences
  result = result.replace(/â€[™œ]/g, (match) => {
    const bytes = [];
    for (let i = 0; i < match.length; i++) {
      bytes.push(match.charCodeAt(i) & 0xFF);
    }
    return String.fromCharCode(...bytes);
  });

  // Fix 2-byte UTF-8 sequences (accented chars)
  result = result.replace(/Â[\x80-\xBF]/g, (match) => {
    const byte1 = match.charCodeAt(0) & 0xFF;
    const byte2 = match.charCodeAt(1) & 0xFF;
    return String.fromCharCode((byte1 << 6) | (byte2 & 0x3F));
  });

  const newByteCount = new Blob([result]).size;
  console.log(`Fixed encoding: ${originalByteCount} → ${newByteCount} bytes`);

  return result;
};
```

---

## 6. Common Pitfalls

### Settings Overlays Not in DOM Until Opened

**Problem:** Querying `document.querySelector('.settings-panel')` returns null.

**Solution:** Use MutationObserver to wait for render:

```javascript
// WRONG - overlay doesn't exist yet
const panel = document.querySelector('.settings-panel');

// RIGHT - wait for it to be added to DOM
const panel = await window._waitForOverlay('.settings-panel');
```

---

## 7. Test Template

Reusable JavaScript snippet for common PWA verification tasks:

```javascript
// ====== PWA Console Test Template ======

async function runTests() {
  console.log('=== PWA Test Suite ===\n');

  try {
    // 1. Data layer
    console.log('Test 1: localStorage Integrity');
    window._checkLocalStorage();
    window._verifyDataStructure();

    // 2. UI rendering
    console.log('\nTest 2: UI Components');
    window._checkThemeCSS();
    window._checkIframes();

    // 3. Theme system
    console.log('\nTest 3: Theme System');
    window._checkThemeVariables();
    window._testApplyTheme();

    // 4. Encoding
    console.log('\nTest 4: Encoding Check');
    const data = JSON.stringify(localStorage);
    window._detectMojibake(data);

    console.log('\n✓ Test suite completed');
  } catch (e) {
    console.error('✗ Test failed:', e.message);
  }
}

// Run it
await runTests();
```

---

## Workflow Summary

**Typical testing workflow:**

1. Open PWA in browser (or use `?demo=true` for demo mode)
2. Open DevTools Console (F12)
3. Run data layer tests: `window._checkLocalStorage()`
4. Run UI tests: `window._checkThemeCSS()`
5. Run theme tests: `window._checkThemeVariables()`
6. Run encoding tests: `window._detectMojibake()`
7. Confirm all tests pass

**Key principle:** Test in the app's own runtime environment using its DOM and localStorage directly.
