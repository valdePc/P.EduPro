'use strict';
// One-time loopback registrar for the local setup page. No token is printed,
// written to the repository, accepted from chat, or shared across profiles.
const http = require('node:http');
const path = require('node:path');
const crypto = require('node:crypto');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const number = '876132148030';
const appId = '1:876132148030:web:fb552569ce10b7f0a3026f';
const siteKey = '6LefmKosAAAAABHcoFFbE_ekwlbP9nRY8rTV-jCx';
const appPath = `projects/${number}/apps/${appId}`;
const origin = 'http://localhost:55595';
const port = 52611;

async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://firebaseappcheck.googleapis.com' });
  const opts = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 });
  const config = (await api.get(`/v1/${appPath}/recaptchaEnterpriseConfig`, opts())).body;
  if (config.siteKey !== siteKey) throw new Error('App Check provider mismatch');
  let completed = false;
  let attempts = 0;
  const server = http.createServer(async (request, response) => {
    const allowed = request.socket.remoteAddress === '127.0.0.1' &&
      request.headers.host === `127.0.0.1:${port}` && request.headers.origin === origin;
    if (!allowed || request.url !== '/register') {
      response.writeHead(403); response.end(); return;
    }
    response.setHeader('Access-Control-Allow-Origin', origin);
    response.setHeader('Vary', 'Origin');
    response.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    response.setHeader('Cache-Control', 'no-store');
    if (request.method === 'OPTIONS') {
      response.writeHead(204); response.end(); return;
    }
    if (request.method !== 'POST' || completed || ++attempts > 3 ||
        request.headers['content-type'] !== 'application/json') {
      response.writeHead(400); response.end(); return;
    }
    try {
      let body = '';
      for await (const chunk of request) {
        body += chunk;
        if (body.length > 128) throw new Error('Payload too large');
      }
      const parsed = JSON.parse(body);
      const token = parsed?.token;
      if (Object.keys(parsed).length !== 1 ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token || '')) {
        throw new Error('Unexpected request');
      }
      const suffix = crypto.createHash('sha256').update(token).digest('hex').slice(0, 12);
      await api.post(`/v1/${appPath}/debugTokens`, { displayName: `Local personal browser ${suffix}`, token }, opts());
      completed = true;
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end('{"ok":true}');
      console.log(JSON.stringify({ browserAuthorized: true, tokenPrinted: false, profile: 'personal Chrome' }));
      server.close();
    } catch (_) {
      response.writeHead(400); response.end();
    }
  });
  server.listen(port, '127.0.0.1', () => {
    console.log(JSON.stringify({ ready: true, setupPage: `${origin}/appcheck-local-setup.html`, tokenPrinted: false }));
  });
  setTimeout(() => {
    if (!completed) console.error('Local browser authorization timed out; no token registered.');
    server.close();
  }, 5 * 60 * 1000).unref();
}
run().catch(() => { console.error('Local App Check setup could not start. No token logged.'); process.exitCode = 1; });
