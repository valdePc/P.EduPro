'use strict';
// Read-only, only npm lockfile mismatch lines from recent function operations.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://cloudfunctions.googleapis.com' });
  const opts = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };
  const body = (await api.get(`/v2/projects/${project}/locations/us-central1/operations`, { ...opts, queryParams: { pageSize: 100 } })).body;
  const rows = (body.operations || []).filter(op => op.error && String(op.metadata?.target || '').includes('getEduProTwoFactorStatus'));
  console.log(JSON.stringify(rows.slice(0, 1).map(op => ({
    target: 'getEduProTwoFactorStatus',
    lines: String(op.error.message || '').split(/\r?\n/).filter(line => /npm error (Missing|Invalid|code EUSAGE|`npm ci`)/.test(line)).map(line => line.slice(0, 300)).slice(0, 30),
  }))));
}
run().catch(() => { console.error('Function operation inspection failed.'); process.exitCode = 1; });
