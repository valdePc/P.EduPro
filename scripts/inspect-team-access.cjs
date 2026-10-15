'use strict';
// Read-only administrative inspection, never shipped to the client.
// Usage: node scripts/inspect-team-access.cjs account@example.org
// Uses the existing Firebase CLI login; never prints tokens or password material.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const email = (process.argv[2] || '').trim().toLowerCase();
const skipLog = { body: true, resBody: true, queryParams: true };
const options = () => ({ skipLog, timeout: 30000 });
const identity = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com' });
const database = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
const scheduleFields = ['allowedWeekdays', 'allowedDayLabels', 'startMinute', 'endMinute', 'startLabel', 'endLabel'];
const inspectedFields = ['email', 'uid', 'enabled', 'role', 'teamRole', ...scheduleFields];

function decode(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  return null;
}

async function lookupAccount() {
  const response = await identity.post(`/v1/projects/${project}/accounts:lookup`, { email: [email] }, {
    ...options(), queryParams: { fields: 'users(localId,email,emailVerified,disabled)' },
  });
  const users = response.body.users || [];
  if (users.length !== 1 || users[0].email?.toLowerCase() !== email) {
    throw new Error('Expected exactly one matching Auth account.');
  }
  const account = users[0];
  if (!/^[A-Za-z0-9_-]+$/.test(account.localId)) throw new Error('Unexpected UID format.');
  return account;
}

async function readProfile(collection, uid) {
  const queryParams = new URLSearchParams();
  inspectedFields.forEach(field => queryParams.append('mask.fieldPaths', field));
  const response = await database.get(`/v1/projects/${project}/databases/(default)/documents/${collection}/${uid}`, {
    ...options(), queryParams, resolveOnHTTPError: true,
  });
  if (response.status === 404) return null;
  if (response.status !== 200) throw new Error(`Profile read failed (HTTP ${response.status}).`);
  return response.body;
}

function summary(doc) {
  return doc ? Object.fromEntries(Object.entries(doc.fields || {}).map(([key, value]) => [key, decode(value)])) : null;
}

async function run() {
  if (process.argv.length !== 3 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    console.error('Usage: node scripts/inspect-team-access.cjs account@example.org');
    process.exitCode = 1;
    return;
  }
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const account = await lookupAccount();
  const profiles = {};
  for (const collection of ['users', 'Users', 'EquipoEduPro', 'EquipoValMich']) {
    profiles[collection] = await readProfile(collection, account.localId);
  }
  console.log(JSON.stringify({
    project, email, uid: account.localId,
    authEnabled: account.disabled !== true, emailVerified: account.emailVerified === true,
    profiles: Object.fromEntries(Object.entries(profiles).map(([key, doc]) => [key, summary(doc)])),
    mode: 'read-only',
  }, null, 2));
}

run().catch(error => {
  // Deliberately do not log upstream error objects, requests, or response bodies.
  console.error(`Account schedule operation failed; HTTP status: ${error.status || error.context?.response?.statusCode || 'unavailable'}. No credentials logged.`);
  process.exitCode = 1;
});
