'use strict';
// Read only: report MFA policy/enrollment without retrieving a TOTP secret.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const email = (process.argv[2] || '').trim().toLowerCase();
const options = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000, resolveOnHTTPError: true });

async function run() {
  if (process.argv.length !== 3 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Invalid account argument');
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const identity = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com' });
  const users = await identity.post(`/v1/projects/${project}/accounts:lookup`, { email: [email] }, {
    ...options(), queryParams: { fields: 'users(localId,email,disabled)' },
  });
  if (users.status !== 200 || users.body.users?.length !== 1 || users.body.users[0].email?.toLowerCase() !== email) throw new Error('Account lookup failed');
  const uid = users.body.users[0].localId;
  if (!/^[A-Za-z0-9_-]+$/.test(uid)) throw new Error('Invalid account UID');

  const db = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
  async function get(path, fields) {
    const queryParams = new URLSearchParams();
    for (const field of fields) queryParams.append('mask.fieldPaths', field);
    const response = await db.get(`/v1/projects/${project}/databases/(default)/documents/${path}`, { ...options(), queryParams });
    if (response.status === 404) return null;
    if (response.status !== 200) throw new Error(`Document read failed: ${response.status}`);
    return response.body.fields || {};
  }
  const config = await get('app_config/security', ['twoFAEnabled']);
  const policy = await get(`security_2fa_policy/${uid}`, ['required']);
  const state = await get(`security_2fa_users/${uid}`, ['enabled']);
  console.log(JSON.stringify({
    accountEnabled: users.body.users[0].disabled !== true,
    twoFactorRequiredByPolicy: config?.twoFAEnabled?.booleanValue === true || policy?.required?.booleanValue === true,
    globalTwoFactorPolicyEnabled: config?.twoFAEnabled?.booleanValue === true,
    accountTwoFactorPolicyEnabled: policy?.required?.booleanValue === true,
    twoFactorEnrollmentPresent: state !== null,
    twoFactorEnrollmentEnabled: state?.enabled?.booleanValue === true,
    secretRead: false,
    mode: 'read-only',
  }));
}

run().catch(() => { console.error('MFA status inspection failed; no secret or credentials logged.'); process.exitCode = 1; });
