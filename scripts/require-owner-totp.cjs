'use strict';
// Scoped, create-only policy for the existing principal account. Dry-run by default.
// The TOTP secret and user credentials are never read or written here.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const ownerEmail = 'valdeymse@gmail.com';
const functions = [
  'getEduProTwoFactorStatus', 'startEduProTwoFactorEnrollment',
  'confirmEduProTwoFactorEnrollment', 'verifyEduProTwoFactorCode',
  'upsertSchoolAdmin', 'assignSchoolAdmin', 'createSchool',
  'setSchoolRegistroConfig', 'listSchoolAccessIps',
  'unlockSchoolAccessIp', 'searchSchoolPlaces',
];
const opts = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000, resolveOnHTTPError: true });
async function run() {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--apply')) throw new Error('Unexpected argument');
  const apply = args[0] === '--apply';
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const identity = new Client({ urlPrefix: 'https://identitytoolkit.googleapis.com' });
  const found = await identity.post(`/v1/projects/${project}/accounts:lookup`, { email: [ownerEmail] }, {
    ...opts(), queryParams: { fields: 'users(localId,email,disabled,emailVerified)' },
  });
  const user = found.body?.users?.[0];
  if (found.status !== 200 || found.body.users?.length !== 1 ||
      user.email?.toLowerCase() !== ownerEmail || user.disabled === true || user.emailVerified !== true ||
      !/^[A-Za-z0-9_-]+$/.test(user.localId || '')) throw new Error('Owner account verification failed');
  const uid = user.localId;
  const cloud = new Client({ urlPrefix: 'https://cloudfunctions.googleapis.com' });
  for (const name of functions) {
    const response = await cloud.get(`/v2/projects/${project}/locations/us-central1/functions/${name}`, opts());
    const generation = Number(response.body?.buildConfig?.source?.storageSource?.generation || 0);
    if (response.status !== 200 || response.body.state !== 'ACTIVE' || generation < 1791332700000000) {
      throw new Error(`Function ${name} is not verified as updated`);
    }
  }
  const firestore = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
  const root = `/v1/projects/${project}/databases/(default)/documents`;
  const userMask = new URLSearchParams();
  userMask.append('mask.fieldPaths', 'enabled');
  userMask.append('mask.fieldPaths', 'role');
  const userDoc = await firestore.get(`${root}/users/${uid}`, { ...opts(), queryParams: userMask });
  if (userDoc.status !== 200 || userDoc.body?.fields?.enabled?.booleanValue !== true ||
      !['superadmin', 'super_admin'].includes(userDoc.body?.fields?.role?.stringValue?.toLowerCase())) {
    throw new Error('Internal superadmin record verification failed');
  }
  const policy = await firestore.get(`${root}/security_2fa_policy/${uid}`, { ...opts(), queryParams: { 'mask.fieldPaths': 'required' } });
  if (policy.status === 200) {
    if (policy.body?.fields?.required?.booleanValue !== true) throw new Error('Existing policy differs; refusing to overwrite');
    console.log(JSON.stringify({ mode: 'already-enabled', account: ownerEmail, functionsVerified: functions.length, required: true, secretRead: false }));
    return;
  }
  if (policy.status !== 404) throw new Error('Policy state could not be confirmed');
  if (!apply) {
    console.log(JSON.stringify({ mode: 'dry-run', account: ownerEmail, functionsVerified: functions.length, proposed: 'require TOTP for this UID only', secretRead: false }));
    return;
  }
  const created = await firestore.post(`${root}/security_2fa_policy`, {
    fields: { required: { booleanValue: true } },
  }, { ...opts(), queryParams: { documentId: uid } });
  if (created.status !== 200 || created.body?.fields?.required?.booleanValue !== true) throw new Error('Policy creation not confirmed');
  console.log(JSON.stringify({ mode: 'applied', account: ownerEmail, functionsVerified: functions.length, required: true, secretRead: false }));
}
run().catch(error => {
  const message = String(error?.message || '');
  const safe = /^(Owner account verification failed|Function [A-Za-z]+ is not verified as updated|Internal superadmin record verification failed|Existing policy differs; refusing to overwrite|Policy state could not be confirmed|Policy creation not confirmed)$/.test(message);
  console.error(safe ? message : 'Owner TOTP policy was not activated. No secret logged.');
  process.exitCode = 1;
});
