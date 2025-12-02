// Preload patch for n8n: relax inbound server timeouts AND outbound fetch (undici) timeouts.
(function () {
  const path = require('path');

  const toNum = (v, d) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : d;
  };

  // Helper function to try loading undici from various locations
  function tryRequireUndici() {
    // List of possible paths where undici might be located
    const possiblePaths = [
      'undici', // Standard require (if installed globally or in current node_modules)
    ];

    // Add n8n-specific paths that might exist in Docker container
    const n8nPaths = [
      '/usr/local/lib/node_modules/n8n/node_modules/undici',
      '/usr/lib/node_modules/n8n/node_modules/undici',
      '/home/node/.npm-global/lib/node_modules/n8n/node_modules/undici',
      path.join(process.cwd(), 'node_modules', 'undici'),
      path.join(process.cwd(), 'node_modules', 'n8n', 'node_modules', 'undici'),
    ];

    possiblePaths.push(...n8nPaths);

    for (const modulePath of possiblePaths) {
      try {
        return require(modulePath);
      } catch {
        // Continue to next path
      }
    }
    return null;
  }

  // Inbound: Node HTTP(S) server timeouts (affects browser -> n8n)
  const inboundRequestTimeout = toNum(process.env.N8N_HTTP_REQUEST_TIMEOUT, 0);          // 0 = disable per-request timeout
  const inboundHeadersTimeout = toNum(process.env.N8N_HTTP_HEADERS_TIMEOUT, 120_000);    // must be > keepAlive
  const inboundKeepAliveTimeout = toNum(process.env.N8N_HTTP_KEEPALIVE_TIMEOUT, 65_000);

  function patchServer(modName) {
    try {
      const mod = require(modName);
      if (!mod || typeof mod.createServer !== 'function') return;
      const orig = mod.createServer;
      mod.createServer = function patchedCreateServer(...args) {
        const srv = orig.apply(this, args);
        try {
          srv.requestTimeout = inboundRequestTimeout;
          // Ensure headersTimeout > keepAliveTimeout by at least 1000ms
          srv.keepAliveTimeout = inboundKeepAliveTimeout;
          srv.headersTimeout = Math.max(inboundHeadersTimeout, inboundKeepAliveTimeout + 1000);
          console.log(
            `[patch] ${modName} server timeouts: request=${srv.requestTimeout}ms, ` +
            `headers=${srv.headersTimeout}ms, keepAlive=${srv.keepAliveTimeout}ms`
          );
        } catch (e) {
          console.warn('[patch] failed to set server timeouts on', modName, e?.message || e);
        }
        return srv;
      };
    } catch (e) {
      console.warn('[patch] failed to patch module', modName, e?.message || e);
    }
  }

  patchServer('http');
  patchServer('https');

  // Outbound: undici (Node fetch) timeouts (affects n8n -> LLM/API)
  // If your model/API takes >30s to send first byte (headers), default undici will throw "Headers Timeout Error".
  try {
    const undici = tryRequireUndici();

    if (!undici) {
      // This is expected in some environments - undici patching is optional
      // Inbound server timeout patching (above) will still work
      console.log('[patch] undici module not found - outbound fetch timeout patching skipped (inbound server timeouts still applied)');
      return;
    }

    const { Agent, setGlobalDispatcher } = undici;

    const headersTimeout = toNum(process.env.FETCH_HEADERS_TIMEOUT, 180_000); // 3 min for first byte/headers
    const bodyTimeout = toNum(process.env.FETCH_BODY_TIMEOUT, 1_200_000);     // 20 min for full body/stream
    const connectTimeout = toNum(process.env.FETCH_CONNECT_TIMEOUT, 60_000);  // 60s TCP/TLS connect
    const keepAliveTimeout = toNum(process.env.FETCH_KEEPALIVE_TIMEOUT, 65_000);

    const dispatcher = new Agent({
      headersTimeout,
      bodyTimeout,
      connectTimeout,
      keepAliveTimeout,
      // keepAliveMaxTimeout can be set if your Node/undici version supports it; keep defaults otherwise.
    });

    setGlobalDispatcher(dispatcher);
    console.log(
      `[patch] undici dispatcher set: headersTimeout=${headersTimeout}ms, ` +
      `bodyTimeout=${bodyTimeout}ms, connectTimeout=${connectTimeout}ms, ` +
      `keepAliveTimeout=${keepAliveTimeout}ms`
    );
  } catch (e) {
    console.warn('[patch] undici patching failed:', e?.message || e);
  }
})();
