// Preload patch for n8n: relax inbound server timeouts AND outbound fetch (undici) timeouts.
(function () {
  const toNum = (v, d) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : d;
  };

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
    const { Agent, setGlobalDispatcher } = require('undici');

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
    console.warn('[patch] undici not available or failed to set dispatcher', e?.message || e);
  }
})();
