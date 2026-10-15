'use strict';
// Inspect only a localhost Flutter page in its dedicated debug browser.
async function run() {
  const port = Number(process.argv[2]);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid port');
  const pages = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json());
  const page = pages.find(page => page.type === 'page' && /^http:\/\/(localhost|127\.0\.0\.1):/.test(page.url));
  if (!page) throw new Error('No local Flutter page');
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  const probe = process.argv[3] === '--probe';
  const expression = probe ? `(async () => {
    const app = firebase_core.getApp();
    if (app.options.projectId !== 'edupro-8c4fd' || app.options.appId !== '1:876132148030:web:fb552569ce10b7f0a3026f') throw new Error('Unexpected app');
    const user = firebase_auth.getAuth(app).currentUser;
    if (user && user.email?.toLowerCase() !== 'valdeymse@gmail.com') throw new Error('Unexpected account');
    try {
      const response = await firebase_functions.httpsCallable(firebase_functions.getFunctions(app, 'us-central1'), 'getEduProTwoFactorStatus')({ audience: 'admin_general' });
      return JSON.stringify({ authenticatedTargetAccount: !!user, callableSucceeded: true, required: response.data.required, enrolled: response.data.enrolled, verified: response.data.verified });
    } catch (error) {
      const knownMessages = ['Unauthenticated', 'Debes iniciar sesión.', 'Debes iniciar sesion.', 'No autenticado'];
      return JSON.stringify({ authenticatedTargetAccount: !!user, callableSucceeded: false, errorCode: String(error.code).slice(0, 80), knownMessage: knownMessages.includes(error.message) ? error.message : 'other' });
    }
  })()` : `JSON.stringify({ origin: location.origin, firebase: typeof firebase_core, appCheck: typeof firebase_app_check, functions: typeof firebase_functions, debugTokenMode: self.FIREBASE_APPCHECK_DEBUG_TOKEN === true ? 'auto' : typeof self.FIREBASE_APPCHECK_DEBUG_TOKEN, apps: typeof firebase_core !== 'undefined' ? firebase_core.getApps().map(app => ({ name: app.name, appId: app.options.appId, projectId: app.options.projectId })) : [] })`;
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Browser operation timed out')), 30000);
    socket.onmessage = ({ data }) => {
      const response = JSON.parse(data);
      if (response.id === 1) { clearTimeout(timer); resolve(response.result); }
    };
    socket.onerror = reject;
    if (process.argv[3] === '--close') {
      socket.send(JSON.stringify({ id: 1, method: 'Browser.close' }));
      return;
    }
    socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
      expression, returnByValue: true, awaitPromise: true,
    }}));
  });
  socket.close();
  console.log(result.result?.value || 'No public configuration available');
}
run().catch(() => { console.error('Local browser inspection failed; no page content or credentials logged.'); process.exitCode = 1; });
