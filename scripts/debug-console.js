/**
 * BSI Debug Console — in-app overlay for iframe debugging
 *
 * Activates when URL has ?debug=true OR parent sends postMessage { type: 'enable-debug' }
 * Intercepts console.log/warn/error/info and renders in a floating panel.
 * Also forwards all messages to parent window via postMessage for portal-level visibility.
 *
 * Usage in any BSI single-file app — add before </head>:
 *   <script src="https://bsi-devops.pages.dev/scripts/debug-console.js"></script>
 *
 * Or inline the IIFE directly.
 */
(function () {
  'use strict';

  const params = new URLSearchParams(window.location.search);
  let enabled = params.get('debug') === 'true';

  // Allow parent to enable debug dynamically
  window.addEventListener('message', function (e) {
    if (e.data && e.data.type === 'enable-debug') {
      enabled = true;
      init();
    }
  });

  if (enabled) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  }

  let initialized = false;
  const buffer = []; // buffer messages before DOM ready

  // Patch console immediately so we capture early messages
  const original = {
    log: console.log,
    warn: console.warn,
    error: console.error,
    info: console.info,
    debug: console.debug,
  };

  function timestamp() {
    const d = new Date();
    return (
      String(d.getHours()).padStart(2, '0') + ':' +
      String(d.getMinutes()).padStart(2, '0') + ':' +
      String(d.getSeconds()).padStart(2, '0') + '.' +
      String(d.getMilliseconds()).padStart(3, '0')
    );
  }

  function serialize(args) {
    return Array.from(args).map(function (a) {
      if (a === null) return 'null';
      if (a === undefined) return 'undefined';
      if (typeof a === 'string') return a;
      try { return JSON.stringify(a, null, 1); } catch (_) { return String(a); }
    }).join(' ');
  }

  function capture(level, args) {
    const entry = { level: level, time: timestamp(), text: serialize(args) };

    // Forward to parent
    try {
      if (window.parent !== window) {
        window.parent.postMessage({
          type: 'debug-console',
          appUrl: window.location.href,
          entry: entry,
        }, '*');
      }
    } catch (_) {}

    if (!enabled) return;

    if (initialized) {
      appendEntry(entry);
    } else {
      buffer.push(entry);
    }
  }

  // Patch all levels
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    console[level] = function () {
      capture(level, arguments);
      original[level].apply(console, arguments);
    };
  });

  // Catch unhandled errors
  window.addEventListener('error', function (ev) {
    capture('error', [ev.message + ' at ' + (ev.filename || '') + ':' + ev.lineno]);
  });
  window.addEventListener('unhandledrejection', function (ev) {
    capture('error', ['Unhandled promise: ' + (ev.reason && ev.reason.message || ev.reason || 'unknown')]);
  });

  // --- UI ---
  let panel, logContainer, badge;
  const COLORS = {
    log: '#a1a1aa',    // zinc-400
    info: '#60a5fa',   // blue-400
    warn: '#fbbf24',   // amber-400
    error: '#f87171',  // red-400
    debug: '#818cf8',  // indigo-400
  };

  function init() {
    if (initialized) return;
    initialized = true;

    panel = document.createElement('div');
    panel.id = 'bsi-debug-console';
    panel.innerHTML = `
      <div id="bsi-dbg-header">
        <span style="font-weight:600;font-size:11px;letter-spacing:0.5px;">DEBUG CONSOLE</span>
        <span id="bsi-dbg-badge" style="background:#f59e0b;color:#000;border-radius:9px;padding:0 6px;font-size:10px;font-weight:700;min-width:16px;text-align:center;display:none;">0</span>
        <span style="flex:1"></span>
        <button id="bsi-dbg-clear" title="Clear" style="background:none;border:none;color:#a1a1aa;cursor:pointer;font-size:14px;padding:2px 4px;">CLR</button>
        <button id="bsi-dbg-min" title="Minimize" style="background:none;border:none;color:#a1a1aa;cursor:pointer;font-size:16px;padding:2px 4px;">_</button>
        <button id="bsi-dbg-close" title="Close" style="background:none;border:none;color:#a1a1aa;cursor:pointer;font-size:14px;padding:2px 4px;">X</button>
      </div>
      <div id="bsi-dbg-logs"></div>
      <div id="bsi-dbg-input-row">
        <input id="bsi-dbg-input" type="text" placeholder="eval JS..." />
      </div>
    `;

    const style = document.createElement('style');
    style.textContent = `
      #bsi-debug-console {
        position: fixed; bottom: 8px; right: 8px; width: 420px; max-height: 320px;
        background: #18181bee; border: 1px solid #3f3f46; border-radius: 8px;
        font-family: 'JetBrains Mono', monospace; font-size: 11px; color: #d4d4d8;
        z-index: 999999; display: flex; flex-direction: column; box-shadow: 0 4px 24px #0008;
      }
      #bsi-debug-console.minimized #bsi-dbg-logs,
      #bsi-debug-console.minimized #bsi-dbg-input-row { display: none; }
      #bsi-debug-console.minimized { max-height: none; width: auto; }
      #bsi-dbg-header {
        display: flex; align-items: center; gap: 6px; padding: 6px 10px;
        border-bottom: 1px solid #3f3f46; cursor: move; user-select: none;
      }
      #bsi-dbg-logs {
        flex: 1; overflow-y: auto; padding: 4px 0; max-height: 230px;
      }
      #bsi-dbg-logs::-webkit-scrollbar { width: 4px; }
      #bsi-dbg-logs::-webkit-scrollbar-thumb { background: #52525b; border-radius: 2px; }
      .bsi-dbg-entry {
        padding: 2px 10px; border-bottom: 1px solid #27272a; white-space: pre-wrap;
        word-break: break-all; line-height: 1.4;
      }
      .bsi-dbg-entry:hover { background: #27272a; }
      .bsi-dbg-time { color: #71717a; margin-right: 6px; }
      .bsi-dbg-level { font-weight: 600; margin-right: 6px; text-transform: uppercase; min-width: 36px; display: inline-block; }
      #bsi-dbg-input-row { padding: 4px 8px; border-top: 1px solid #3f3f46; }
      #bsi-dbg-input {
        width: 100%; background: #27272a; border: 1px solid #3f3f46; border-radius: 4px;
        color: #d4d4d8; font-family: inherit; font-size: 11px; padding: 4px 8px; outline: none;
      }
      #bsi-dbg-input:focus { border-color: #f59e0b; }
    `;
    document.head.appendChild(style);
    document.body.appendChild(panel);

    logContainer = document.getElementById('bsi-dbg-logs');
    badge = document.getElementById('bsi-dbg-badge');

    // Drag
    let dragging = false, dx = 0, dy = 0;
    const header = document.getElementById('bsi-dbg-header');
    header.addEventListener('mousedown', function (e) {
      if (e.target.tagName === 'BUTTON') return;
      dragging = true;
      dx = e.clientX - panel.getBoundingClientRect().left;
      dy = e.clientY - panel.getBoundingClientRect().top;
      panel.style.transition = 'none';
    });
    document.addEventListener('mousemove', function (e) {
      if (!dragging) return;
      panel.style.left = (e.clientX - dx) + 'px';
      panel.style.top = (e.clientY - dy) + 'px';
      panel.style.right = 'auto';
      panel.style.bottom = 'auto';
    });
    document.addEventListener('mouseup', function () { dragging = false; });

    // Buttons
    document.getElementById('bsi-dbg-close').onclick = function () {
      panel.style.display = 'none';
    };
    document.getElementById('bsi-dbg-min').onclick = function () {
      panel.classList.toggle('minimized');
    };
    document.getElementById('bsi-dbg-clear').onclick = function () {
      logContainer.innerHTML = '';
    };

    // Eval input
    const input = document.getElementById('bsi-dbg-input');
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        const code = input.value.trim();
        if (!code) return;
        capture('info', ['> ' + code]);
        try {
          const result = eval(code);
          capture('log', [result]);
        } catch (err) {
          capture('error', [err.message]);
        }
        input.value = '';
      }
    });

    // Flush buffer
    buffer.forEach(appendEntry);
    buffer.length = 0;
  }

  function appendEntry(entry) {
    if (!logContainer) return;
    const div = document.createElement('div');
    div.className = 'bsi-dbg-entry';
    const color = COLORS[entry.level] || COLORS.log;
    div.innerHTML =
      '<span class="bsi-dbg-time">' + entry.time + '</span>' +
      '<span class="bsi-dbg-level" style="color:' + color + '">' + entry.level + '</span>' +
      '<span>' + escapeHtml(entry.text) + '</span>';
    logContainer.appendChild(div);
    logContainer.scrollTop = logContainer.scrollHeight;

    // Badge count when minimized
    if (panel.classList.contains('minimized') && (entry.level === 'error' || entry.level === 'warn')) {
      const count = parseInt(badge.textContent || '0', 10) + 1;
      badge.textContent = count;
      badge.style.display = 'inline-block';
    }
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
})();
