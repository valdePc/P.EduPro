'use strict';
// Scoped maintenance for this project's existing web app and local Flutter browser.
// Dry-run unless --apply is supplied. No Auth, MFA, IAM or enforcement writes.
const path = require('node:path');
const crypto = require('node:crypto');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const number = '876132148030';
const appId = '1:876132148030:web:fb552569ce10b7f0a3026f';
// Public site key, already restricted to this project's production domain.
const siteKey = '6LefmKosAAAAABHcoFFbE_ekwlbP9nRY8rTV-jCx';
const appPath = `projects/${number}/apps/${appId}`;
const configPath = `${appPath}/recaptchaEnterpriseConfig`;
const api = new Client({ urlPrefix: 'https://firebaseappcheck.googleapis.com' });
const opts = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 });

async function connectLocalBrowser(port) {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid debug port');
  const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json());
  const pagesLocal = pages.filter(p => p.type === 'page' && /^http:\/\/(localhost|127\.0\.0\.1):/.test(p.url));
  if (pagesLocal.length !== 1) throw new Error('Expected one local Flutter page');
  const page = pagesLocal[0];
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let nextId = 1;
  const pending = new Map();
  socket.onmessage = ({ data }) => {
    const response = JSON.parse(data);
    if (pending.has(response.id)) {
      pending.get(response.id)(response);
      pending.delete(response.id);
    }
  };
  async function evaluate(expression) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error('Browser operation timed out')); }, 30000);
      pending.set(id, response => {
        clearTimeout(timer);
        if (response.error || response.result?.exceptionDetails) reject(new Error('Browser operation failed'));
        else resolve(response.result?.result?.value);
      });
      socket.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, returnByValue: true, awaitPromise: true } }));
    });
  }
  return { evaluate, close: () => socket.close(), origin: new URL(page.url).origin };
}

async function run() {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const refreshDebugToken = args.includes('--refresh-debug-token');
  const retireId = args.find(arg => /^--retire-debug-token=[A-Za-z0-9_-]+$/.test(arg))?.split('=')[1];
  const port = Number(args.find(arg => /^--debug-port=\d+$/.test(arg))?.split('=')[1]);
  if (args.some(arg => arg !== '--apply' && arg !== '--refresh-debug-token' && !/^--retire-debug-token=[A-Za-z0-9_-]+$/.test(arg) && !/^--debug-port=\d+$/.test(arg))) throw new Error('Unexpected argument');
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const config = (await api.get(`/v1/${configPath}`, opts())).body;
  if (config.siteKey && config.siteKey !== siteKey) throw new Error('An existing provider uses a different key; refusing to replace it');
  const recaptcha = new Client({ urlPrefix: 'https://recaptchaenterprise.googleapis.com' });
  const key = (await recaptcha.get(`/v1/projects/${number}/keys/${siteKey}`, opts())).body;
  if (key.webSettings?.integrationType !== 'SCORE' || key.webSettings.allowAllDomains === true ||
      JSON.stringify(key.webSettings.allowedDomains) !== JSON.stringify([`${project}.web.app`])) {
    throw new Error('Unexpected site key restrictions');
  }
  const browser = await connectLocalBrowser(port);
  try {
    const correctApp = await browser.evaluate(`typeof firebase_core !== 'undefined' && typeof firebase_app_check !== 'undefined' && firebase_core.getApp().options.projectId === ${JSON.stringify(project)} && firebase_core.getApp().options.appId === ${JSON.stringify(appId)}`);
    if (correctApp !== true) throw new Error('Local page is not the expected Firebase app');
    if (!apply) {
      console.log(JSON.stringify({ mode: 'dry-run', project, origin: browser.origin,
        changes: ['Associate the existing domain-restricted Enterprise site key', 'Register one private App Check debug token for this local browser', 'Activate App Check in this browser and verify token issuance'],
        authAndMfaUnchanged: true, enforcementUnchanged: true }));
      return;
    }
    if (!config.siteKey) {
      await api.patch(`/v1/${configPath}`, { name: configPath, siteKey }, { ...opts(), queryParams: { updateMask: 'siteKey' } });
    }
    const verified = (await api.get(`/v1/${configPath}`, opts())).body;
    if (verified.siteKey !== siteKey) throw new Error('Provider verification failed');

    // Reuse only the App Check SDK's local debug secret. Never inspect Auth storage.
    const debugToken = refreshDebugToken ? crypto.randomUUID() : await browser.evaluate(`(async () => {
      const names = await indexedDB.databases();
      if (!names.some(db => db.name === 'firebase-app-check-database')) return crypto.randomUUID();
      return new Promise((resolve, reject) => {
        const open = indexedDB.open('firebase-app-check-database', 1);
        open.onerror = reject;
        open.onsuccess = () => {
          const db = open.result;
          const read = db.transaction('firebase-app-check-store', 'readonly').objectStore('firebase-app-check-store').get('debug-token');
          read.onerror = reject;
          read.onsuccess = () => { db.close(); resolve(read.result?.value || crypto.randomUUID()); };
        };
      });
    })()`);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(debugToken)) throw new Error('Unexpected debug secret format');
    const suffix = crypto.createHash('sha256').update(debugToken).digest('hex').slice(0, 12);
    const displayName = `Local Flutter browser ${suffix}`;
    const existing = (await api.get(`/v1/${appPath}/debugTokens`, opts())).body;
    if (existing.nextPageToken) throw new Error('Debug token list requires review');
    let registration = (existing.debugTokens || []).find(token => token.displayName === displayName);
    if (!registration) registration = (await api.post(`/v1/${appPath}/debugTokens`, { displayName, token: debugToken }, opts())).body;
    console.log(JSON.stringify({ providerVerified: true, debugTokenResource: registration.name, secretPrinted: false }));

    // Persist through page reloads in the SDK's own store, never in source/builds.
    await browser.evaluate(`new Promise((resolve, reject) => {
      const open = indexedDB.open('firebase-app-check-database', 1);
      open.onupgradeneeded = () => open.result.createObjectStore('firebase-app-check-store', { keyPath: 'compositeKey' });
      open.onerror = reject;
      open.onsuccess = () => {
        const db = open.result;
        const tx = db.transaction('firebase-app-check-store', 'readwrite');
        tx.objectStore('firebase-app-check-store').put({ compositeKey: 'debug-token', value: ${JSON.stringify(debugToken)} });
        tx.onerror = reject;
        tx.oncomplete = () => { db.close(); resolve(true); };
      };
    })`);
    if (refreshDebugToken) {
      await browser.evaluate('setTimeout(() => location.reload(), 50); true');
      await new Promise(resolve => setTimeout(resolve, 1000));
      let ready = false;
      for (let attempt = 0; attempt < 25 && !ready; attempt++) {
        try {
          ready = await browser.evaluate(`typeof firebase_core !== 'undefined' && typeof firebase_app_check !== 'undefined' && firebase_core.getApps().some(app => app.options.appId === ${JSON.stringify(appId)})`);
        } catch (_) { /* The expected reload briefly replaces the JS context. */ }
        if (!ready) await new Promise(resolve => setTimeout(resolve, 500));
      }
      if (!ready) throw new Error('Reload did not initialize the expected app');
    }
    const tokenIssued = await browser.evaluate(`(async () => {
      self.FIREBASE_APPCHECK_DEBUG_TOKEN = true;
      const appCheck = firebase_app_check.initializeAppCheck(firebase_core.getApp(), {
        provider: new firebase_app_check.ReCaptchaEnterpriseProvider(${JSON.stringify(siteKey)})
      });
      firebase_app_check.setTokenAutoRefreshEnabled(appCheck, true);
      const result = await firebase_app_check.getToken(appCheck, true);
      return typeof result.token === 'string' && result.token.length > 0;
    })()`);
    if (!tokenIssued) throw new Error('App Check did not issue a token');
    if (retireId) {
      const retirePath = `${appPath}/debugTokens/${retireId}`;
      if (retirePath === registration.name) throw new Error('Cannot retire the active token');
      const retired = (await api.get(`/v1/${retirePath}`, opts())).body;
      if (!retired.displayName?.startsWith('Local Flutter browser ')) throw new Error('Refusing to retire an unrelated registration');
      await api.delete(`/v1/${retirePath}`, { ...opts(), queryParams: { etag: retired.etag } });
      console.log(JSON.stringify({ previousDevelopmentTokenRetired: true }));
    }
    console.log(JSON.stringify({ mode: 'applied', origin: browser.origin, appCheckTokenIssued: true,
      authAndMfaUnchanged: true, enforcementUnchanged: true }));
  } finally { browser.close(); }
}
run().catch(() => { console.error('App Check configuration did not complete. No secrets logged; inspect the completed stages before retrying.'); process.exitCode = 1; });
