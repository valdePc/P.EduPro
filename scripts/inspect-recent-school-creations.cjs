'use strict';
// Read-only duplicate check. Prints counts only; never prints school documents.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));

const project = 'edupro-8c4fd';
const ownerEmail = 'valdeymse@gmail.com';

async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
  const response = await api.post(`/v1/projects/${project}/databases/(default)/documents:runQuery`, {
    structuredQuery: {
      from: [{ collectionId: 'schools' }],
      where: { fieldFilter: {
        field: { fieldPath: 'createdByEmail' },
        op: 'EQUAL',
        value: { stringValue: ownerEmail },
      } },
      limit: 100,
    },
  }, { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000, resolveOnHTTPError: true });
  if (response.status !== 200) throw new Error('Read failed');
  const rows = Array.isArray(response.body) ? response.body : [];
  const since = Date.now() - 2 * 60 * 60 * 1000;
  const recentCount = rows.filter((row) => {
    const value = row.document?.fields?.createdAt?.timestampValue;
    return value && Date.parse(value) >= since;
  }).length;
  console.log(JSON.stringify({ project, recentSchoolCreationsByOwnerLastTwoHours: recentCount, mode: 'read-only' }));
}

run().catch(() => { console.error('Recent school inspection failed; no document content logged.'); process.exitCode = 1; });
