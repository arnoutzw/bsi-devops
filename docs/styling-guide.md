# Styling Guide — BSI Portal Apps

> Last updated: 2026-02-25

All apps are single HTML files with no build step. Load dependencies from CDN only. Apps support **dark** and **light** themes, with portal-driven theme switching via postMessage.

---

## CDN Stack

```html
<script src="https://cdn.tailwindcss.com"></script>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
```

Configure Tailwind inline:
```html
<script>
tailwind.config = {
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace']
      }
    }
  }
}
</script>
```

---

## Themes

### Available Themes

| Theme | Attribute | Background | Accent | Notes |
|-------|-----------|------------|--------|-------|
| **Dark** | `data-theme="dark"` | Zinc #09090b | Amber #f59e0b | Default for all apps |
| **Light** | `data-theme="light"` | White #ffffff | ASML blue #10069f | Corporate light mode |
| **E-ink** | `data-theme="eink"` | White #ffffff | Black #000000 | ForgeBoard only, high-contrast monochrome |

Legacy: The value `asml` is mapped to `light` via `mapTheme()`.

### CSS Custom Properties

All apps define semantic CSS variables that change with the theme:

**Dark theme** (`:root, [data-theme="dark"]`):
```css
--bg-body:       #09090b;
--bg-primary:    #18181b;
--bg-secondary:  #27272a;
--bg-hover:      #3f3f46;
--text-primary:  #f4f4f5;
--text-secondary:#d4d4d8;
--text-muted:    #71717a;
--text-dim:      #52525b;
--accent:        #f59e0b;
--accent-hover:  #fbbf24;
--accent-bg:     rgba(245,158,11,0.10);
--border:        #3f3f46;
--border-light:  #27272a;
```

**Light theme** (`[data-theme="light"]`):
```css
--bg-body:       #ffffff;
--bg-primary:    #ffffff;
--bg-secondary:  #f8f9fb;
--bg-hover:      #f0f2f5;
--text-primary:  #081249;
--text-secondary:#2b2a3e;
--text-muted:    #555570;
--accent:        #10069f;
--accent-hover:  #1297e4;
--border:        #e2e5f0;
```

**ForgeBoard e-ink** (`[data-theme="eink"]`):
```css
--bg: #ffffff;  --bg2: #f5f5f5;  --bg3: #e0e0e0;
--fg: #000000;  --accent: #000000;
/* No shadows, maximum contrast */
```

### Tailwind Class Overrides for Light Theme

Since apps are designed dark-first with Tailwind, the light theme remaps utility classes via CSS overrides:

```css
[data-theme="light"] .bg-zinc-950 { background-color: var(--bg-body) !important; }
[data-theme="light"] .bg-zinc-900 { background-color: var(--bg-primary) !important; }
[data-theme="light"] .bg-zinc-800 { background-color: var(--bg-secondary) !important; }
[data-theme="light"] .text-zinc-100 { color: var(--text-primary) !important; }
[data-theme="light"] .text-zinc-300 { color: var(--text-secondary) !important; }
[data-theme="light"] .text-zinc-400 { color: var(--text-muted) !important; }
[data-theme="light"] .text-amber-500 { color: var(--accent) !important; }
[data-theme="light"] .border-zinc-700 { border-color: var(--border) !important; }
```

This means all apps can use standard Tailwind dark-mode classes and the light theme "just works".

---

## Theme Bridge v1.1

The portal broadcasts the active theme to all child iframes via postMessage.

### Portal Side (home/index.html)

```javascript
// Store theme
window._portalTheme = localStorage.getItem('portal_theme') || 'dark';

// Broadcast to all iframes on theme change
function broadcastTheme(theme) {
  document.querySelectorAll('iframe').forEach(iframe => {
    iframe.contentWindow.postMessage({ type: 'theme-change', theme: theme }, '*');
  });
}

// Respond to child theme-request (handles race conditions)
window.addEventListener('message', function(e) {
  if (e.data && e.data.type === 'theme-request' && e.source) {
    e.source.postMessage({ type: 'theme-change', theme: window._portalTheme }, '*');
  }
});
```

### Child App Side (BSI Theme Bridge IIFE)

Every child app includes this self-executing function:

```javascript
(function() {
  var isEmbedded = (window.parent !== window);

  function applyBsiTheme(theme) {
    if (theme !== 'dark' && theme !== 'light') theme = 'dark';
    var html = document.documentElement;
    html.setAttribute('data-theme', theme);
    html.style.colorScheme = theme;

    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = (theme === 'light') ? '#ffffff' : '#09090b';

    // Fire event so app-specific code can react (e.g., re-render charts)
    document.dispatchEvent(new CustomEvent('bsi-theme-applied', { detail: { theme } }));
  }

  function mapTheme(raw) {
    return (raw === 'asml' || raw === 'light') ? 'light' : 'dark';
  }

  if (isEmbedded) {
    // Hide theme toggle when running inside portal iframe
    var s = document.createElement('style');
    s.textContent = '[data-theme-toggle]{display:none!important}';
    document.head.appendChild(s);

    // Listen for parent theme broadcasts
    window.addEventListener('message', function(e) {
      if (e.data && e.data.type === 'theme-change') {
        applyBsiTheme(mapTheme(e.data.theme));
      }
    });

    // Request current theme on load (covers race conditions)
    window.parent.postMessage({ type: 'theme-request' }, '*');
  }

  window._bsiIsEmbedded = isEmbedded;
  window._bsiApplyTheme = applyBsiTheme;
})();
```

### Key Features

- **Handshake protocol**: Child sends `theme-request`, portal responds with `theme-change` — handles iframe loading after portal theme is already set
- **Toggle hiding**: `[data-theme-toggle]{display:none!important}` hides the app's own theme picker when embedded
- **Event system**: `bsi-theme-applied` CustomEvent lets app code react to theme changes (e.g., re-render Plotly charts, update SVG fills)
- **Legacy mapping**: `asml` → `light` for backward compatibility
- **Storage isolation**: Each app stores standalone preference in its own localStorage key (`fb_theme`, `erp_theme`, `reqforge_theme`, etc.)

### App-Specific Notes

| App | Storage Key | Themes | Notes |
|-----|------------|--------|-------|
| scrum-app | `scrum_theme` | dark, light | Re-renders charts on `bsi-theme-applied` |
| erp-app | `erp_theme` | dark, light | Forwards theme to nested child iframes (lab-inventory, filaments) |
| req-management | `reqforge_theme` | dark, light | Re-renders dashboard charts on theme change |
| forgeboard | `fb_theme` | dark, light, eink | 3-theme cycle; uses `_themeAccent()` / `_themeBg2()` for SVG rendering |
| alm-app (RCA Studio) | — | dark, light | Uses alternative `theme-sync` protocol + direct DOM inspection of parent |

---

## Color Palette (Dark Theme — Tailwind Classes)

| Role | Tailwind Class | Hex |
|------|---------------|-----|
| Page background | `bg-zinc-950` | `#09090b` |
| Card / panel bg | `bg-zinc-900` | `#18181b` |
| Inset / input bg | `bg-zinc-800` | `#27272a` |
| Border default | `border-zinc-700` | `#3f3f46` |
| Border accent | `border-amber-500/50` | — |
| Text primary | `text-zinc-100` | `#f4f4f5` |
| Text secondary | `text-zinc-400` | `#a1a1aa` |
| Text muted | `text-zinc-500` | `#71717a` |
| Accent primary | `text-amber-500` / `bg-amber-500` | `#f59e0b` |
| Accent hover | `text-amber-400` / `bg-amber-400` | `#fbbf24` |
| Accent subtle bg | `bg-amber-500/10` | — |
| Danger | `text-red-400` / `bg-red-500/20` | — |
| Success | `text-green-400` | — |

---

## Typography

- **Body / UI**: `font-sans text-sm text-zinc-300`
- **Headings**: `font-mono font-bold text-zinc-100` (use `text-amber-500` for h1)
- **Labels / small text**: `text-xs text-zinc-500 font-mono`
- **Monospace data**: `font-mono` (values, code, IDs, hashes)

---

## Common Components

### Buttons
```
Primary:   bg-amber-500 hover:bg-amber-400 text-zinc-900 font-mono font-bold px-4 py-2.5 rounded-lg
Secondary: bg-zinc-700 hover:bg-zinc-600 text-zinc-300 text-xs font-mono px-3 py-1.5 rounded-lg
Ghost:     text-zinc-400 hover:text-amber-400 hover:bg-zinc-800 px-2 py-1.5 rounded-lg
```

### Inputs
```
bg-zinc-800 border border-zinc-700 rounded-lg px-4 py-2.5
font-mono text-sm text-zinc-100 placeholder:text-zinc-600
focus:border-amber-500 focus:outline-none
```

### Cards / Panels
```
bg-zinc-900 border border-zinc-700 rounded-lg p-5
hover:border-amber-500/50 hover:bg-zinc-800/80 hover:shadow-lg hover:shadow-amber-500/10
transition-all duration-300
```

### Terminal Window Header (decorative)
```html
<div class="flex gap-1.5 mb-3">
  <div class="w-3 h-3 rounded-full bg-red-500"></div>
  <div class="w-3 h-3 rounded-full bg-yellow-500"></div>
  <div class="w-3 h-3 rounded-full bg-green-500"></div>
</div>
```

### Tags / Badges
```
text-xs px-2 py-0.5 bg-amber-500/10 text-amber-400 rounded font-mono
```

### Toggle Switch
```
Container: w-8 h-5 rounded-full (bg-amber-500 when on, bg-zinc-700 when off)
Dot:       w-4 h-4 rounded-full bg-white (left-3.5 when on, left-0.5 when off)
transition-all
```

---

## Layout

- Max content width: `max-w-7xl mx-auto`
- Grid: `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6`
- Sticky header: `sticky top-0 z-40 bg-zinc-900/80 backdrop-blur-sm border-b border-zinc-800`
- Standard padding: `p-4` to `p-6` for sections, `p-5` for cards

---

## Scrollbars (add to `<style>`)

```css
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: #18181b; }
::-webkit-scrollbar-thumb { background: #3f3f46; border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: #52525b; }
```

---

## Hover & Transitions

- Cards: `hover:-translate-y-1 transition-all duration-300`
- Buttons: `transition-colors`
- Accent glow on hover: `hover:shadow-lg hover:shadow-amber-500/10`
- Bottom bar reveal: `h-0.5 bg-gradient-to-r from-amber-500 to-orange-500 scale-x-0 group-hover:scale-x-100 transition-transform duration-300`

---

## Icons

Use Lucide icons via CDN (`lucide-react` for React apps, `lucide` for vanilla).
Standard sizes: 14-16px for inline, 18-20px for buttons, 32-48px for empty states.
Color: match surrounding text color (`text-zinc-400` default, `text-amber-500` for accent).

---

## Key Rules

1. Single HTML file — all CSS/JS inline
2. No npm, no build step — CDN only
3. `font-sans` (Inter) for UI, `font-mono` (JetBrains Mono) for data/code/headings
4. Zinc for neutrals, amber for accents — no other hue families except status colors (red/green/yellow)
5. Always include custom scrollbar styles
6. Backdrop blur on overlays: `bg-black/90 backdrop-blur-sm`
7. Rounded corners: `rounded-lg` (default), `rounded-xl` (modals)
8. Include the BSI Theme Bridge IIFE in every app for portal integration
9. Use CSS custom properties (`--bg-body`, `--accent`, etc.) for theme-aware styling
10. Light theme Tailwind overrides use `[data-theme="light"]` selector with `!important`
