'use strict';

// Read-only staff identity audit. Prints counts, never emails, UIDs or secrets.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const { canonicalTeamRole, normalizeTeamRole } = require('../functions/team_permissions');
const project = 'edupro-8c4fd';
const prefix = `/v1/projects/${project}/databases/(default)/documents`;
const api = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
const opts = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };
function mask() {
  const params = new URLSearchParams();
  for (const field of ['role', 'teamRole', 'enabled']) params.append('mask.fieldPaths', field);
  return params;
}
function decode(doc) {
  if (!doc) return null;
  return Object.fromEntries(Object.entries(doc.fields || {}).map(([key, value]) => [key, value.stringValue ?? value.booleanValue ?? null]));
}
async function list(collection) {
  const result = new Map();
  let token;
  do {
    const params = mask(); params.set('pageSize', '100');
    if (token) params.set('pageToken', token);
    const body = (await api.get(`${prefix}/${collection}`, { ...opts, queryParams: params })).body;
    for (const doc of body.documents || []) result.set(doc.name.split('/').at(-1), decode(doc));
    token = body.nextPageToken;
  } while (token);
  return result;
}
async function read(collection, uid) {
  const response = await api.get(`${prefix}/${collection}/${encodeURIComponent(uid)}`, { ...opts, queryParams: mask(), resolveOnHTTPError: true });
  if (response.status === 404) return null;
  if (response.status !== 200) throw new Error('Identity inspection failed.');
  return decode(response.body);
}
async function main() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const [team, legacy] = await Promise.all([list('EquipoEduPro'), list('EquipoValMich')]);
  const uids = new Set([...team.keys(), ...legacy.keys()]);
  let differentRoles = 0;
  let blocked = 0;
  for (const uid of uids) {
    const [primary, historic] = await Promise.all([read('users', uid), read('Users', uid)]);
    const identity = primary ?? historic ?? team.get(uid) ?? legacy.get(uid);
    const schedule = team.get(uid) ?? legacy.get(uid);
    const effective = canonicalTeamRole(identity);
    const declared = normalizeTeamRole(schedule?.teamRole ?? schedule?.role);
    if (effective !== 'denied' && declared !== effective) differentRoles++;
    if (effective === 'denied' || schedule?.enabled === false) blocked++;
  }
  console.log(JSON.stringify({ staffIdentities: uids.size, differentRoles, blocked }, null, 2));
  if (differentRoles) process.exitCode = 2;
}
main().catch(() => { console.error('Staff consistency inspection failed.'); process.exitCode = 1; });
