'use strict';
// Read-only control-plane inspection. Never reads student records or key values.
// Reuses Firebase CLI authentication; outputs only an explicit metadata allowlist.
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const rules = require(path.join(cli, 'gcp/rules'));
const project = 'edupro-8c4fd';
const projectNumber = '876132148030';
const digest = value => crypto.createHash('sha256').update(value.replace(/\r\n/g, '\n')).digest('hex');
async function get(origin, resource) {
  const response = await new Client({ urlPrefix: origin }).get(resource, { skipLog: { resBody: true } });
  return response.body;
}
async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const report = { inspectedAt: new Date().toISOString(), project, scope: 'Control-plane metadata only; no school/user documents or API key strings.' };
  const checks = {
    rules: async () => {
      const releases = await rules.listAllReleases(project);
      const result = [];
      for (const release of releases) {
        const files = await rules.getRulesetContent(release.rulesetName);
        result.push({
          release: release.name, updatedAt: release.updateTime,
          files: files.map(file => {
            const local = release.name.includes('cloud.firestore') ? 'firestore.rules' : 'storage.rules';
            return { name: file.name, sha256: digest(file.content), matchesLocal: fs.existsSync(local) && digest(fs.readFileSync(local, 'utf8')) === digest(file.content), changedKeysOccurrences: (file.content.match(/\.changedKeys\(/g) || []).length, unconditionalAllow: /allow\s+[^;]+:\s*if\s+true\s*;/.test(file.content) };
          }),
        });
      }
      return result;
    },
    apiKeyRestrictions: async () => {
      const data = await get('https://apikeys.googleapis.com', `/v2/projects/${project}/locations/global/keys`);
      return (data.keys || []).map(key => ({ name: key.name, displayName: key.displayName, restrictions: key.restrictions || {}, hasAdditionalPage: !!data.nextPageToken }));
    },
    appCheck: async () => {
      const data = await get('https://firebaseappcheck.googleapis.com', `/v1/projects/${projectNumber}/services`);
      return (data.services || []).map(service => ({ name: service.name, enforcementMode: service.enforcementMode }));
    },
    authentication: async () => {
      const data = await get('https://identitytoolkit.googleapis.com', `/admin/v2/projects/${project}/config`);
      return { authorizedDomains: data.authorizedDomains, signIn: { email: data.signIn?.email, anonymous: data.signIn?.anonymous, phoneNumberEnabled: data.signIn?.phoneNumber?.enabled }, mfa: data.mfa, passwordPolicy: data.passwordPolicyConfig, emailPrivacy: data.emailPrivacyConfig };
    },
    functions: async () => {
      const data = await get('https://cloudfunctions.googleapis.com', `/v2/projects/${project}/locations/us-central1/functions`);
      return (data.functions || []).map(fn => ({ name: fn.name.split('/').pop(), state: fn.state, runtime: fn.buildConfig?.runtime, updateTime: fn.updateTime, maxInstanceCount: fn.serviceConfig?.maxInstanceCount, ingressSettings: fn.serviceConfig?.ingressSettings, appCheckConfigured: fn.serviceConfig?.environmentVariables?.ENFORCE_APPCHECK === 'true', legacyMfaBypassConfigured: fn.serviceConfig?.environmentVariables?.DISABLE_TWO_FACTOR === 'true' }));
    },
  };
  for (const [name, check] of Object.entries(checks)) {
    try { report[name] = await check(); }
    catch (error) { report[name] = { verified: false, status: error.status || error.context?.response?.statusCode || 'request-failed' }; }
  }
  console.log(JSON.stringify(report, null, 2));
}
run().catch(() => { console.error('Read-only cloud inspection could not authenticate; no credentials logged.'); process.exitCode = 1; });
