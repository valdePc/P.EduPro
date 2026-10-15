'use strict';
// Read-only inspection. Never prints rule source or account secrets.
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://firebaserules.googleapis.com' });
  const opts = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };
  const release = (await api.get(`/v1/projects/${project}/releases/cloud.firestore`, opts)).body;
  const ruleset = (await api.get(`/v1/${release.rulesetName}`, opts)).body;
  const source = (ruleset.source?.files || []).map(file => file.content || '').join('');
  const local = fs.readFileSync(path.join(process.cwd(), 'firestore.rules'), 'utf8');
  const hash = value => crypto.createHash('sha256').update(value.replace(/\r\n/g, '\n')).digest('hex');
  console.log(JSON.stringify({
    releasePresent: !!release.rulesetName,
    rulesBytes: source.length,
    policyPathExplicitlyGranted: source.includes('security_2fa_policy'),
    recursiveWildcardPresent: source.includes('match /{document=**}'),
    localMatchesDeployed: hash(source) === hash(local),
  }));
}
run().catch(() => { console.error('Rules inspection failed.'); process.exitCode = 1; });
