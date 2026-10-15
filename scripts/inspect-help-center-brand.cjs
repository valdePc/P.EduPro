'use strict';
// Read-only check. Never prints the document or private content.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';

function countOldName(value) {
  if (typeof value === 'string') return (value.match(/valmich/gi) || []).length;
  if (Array.isArray(value)) return value.reduce((count, item) => count + countOldName(item), 0);
  if (value && typeof value === 'object') return Object.values(value).reduce((count, item) => count + countOldName(item), 0);
  return 0;
}

async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
  const response = await api.get(`/v1/projects/${project}/databases/(default)/documents/app_config/help_center`, {
    skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000, resolveOnHTTPError: true,
  });
  if (response.status === 404) {
    console.log(JSON.stringify({ exists: false, oldBrandOccurrences: 0, mode: 'read-only' }));
    return;
  }
  if (response.status !== 200) throw new Error('Read failed');
  console.log(JSON.stringify({ exists: true, oldBrandOccurrences: countOldName(response.body.fields), mode: 'read-only' }));
}

run().catch(() => { console.error('Help center brand inspection failed; no content logged.'); process.exitCode = 1; });
