'use strict';
// Read-only diagnostics. Never print account tokens, provider secrets or raw logs.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const number = '876132148030';
const appId = '1:876132148030:web:fb552569ce10b7f0a3026f';
const opts = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000, resolveOnHTTPError: true });
async function get(origin, resource) {
  return new Client({ urlPrefix: origin }).get(resource, opts());
}
async function run() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const checks = {
    verificationLogs: async () => {
      const response = await new Client({ urlPrefix: 'https://logging.googleapis.com' }).post('/v2/entries:list', {
        resourceNames: [`projects/${project}`],
        filter: 'resource.type="cloud_run_revision" AND (resource.labels.service_name="geteduprotwofactorstatus" OR resource.labels.service_name="getvalmichtwofactorstatus") AND jsonPayload.verifications:*',
        orderBy: 'timestamp desc', pageSize: 25,
      }, opts());
      return { status: response.status, entries: (response.body.entries || []).map(entry => ({
        timestamp: entry.timestamp, service: entry.resource?.labels?.service_name,
        auth: entry.jsonPayload?.verifications?.auth, app: entry.jsonPayload?.verifications?.app,
      })) };
    },
    callableConfig: async () => {
      const response = await get('https://cloudfunctions.googleapis.com', `/v2/projects/${project}/locations/us-central1/functions/getEduProTwoFactorStatus`);
      const config = response.body;
      return { status: response.status, state: config.state, updatedAt: config.updateTime,
        appCheckEnforced: config.serviceConfig?.environmentVariables?.ENFORCE_APPCHECK === 'true',
        entryPoint: config.buildConfig?.entryPoint };
    },
    webProviders: async () => {
      const providers = {};
      for (const provider of ['recaptchaV3Config', 'recaptchaEnterpriseConfig']) {
        const response = await get('https://firebaseappcheck.googleapis.com', `/v1/projects/${number}/apps/${appId}/${provider}`);
        providers[provider] = { status: response.status, configFound: !!response.body.name,
          siteKey: response.body.siteKey || undefined, tokenTtl: response.body.tokenTtl,
          siteSecretSet: response.body.siteSecretSet, fields: Object.keys(response.body) };
      }
      return providers;
    },
    recaptchaKeys: async () => {
      const response = await get('https://recaptchaenterprise.googleapis.com', `/v1/projects/${project}/keys`);
      return { status: response.status, keys: (response.body.keys || []).map(key => ({
        name: key.name, displayName: key.displayName,
        allowedDomains: key.webSettings?.allowedDomains,
        allowAllDomains: key.webSettings?.allowAllDomains,
        integrationType: key.webSettings?.integrationType,
      })) };
    },
  };
  for (const [name, inspect] of Object.entries(checks)) {
    try { console.log(JSON.stringify({ check: name, result: await inspect() })); }
    catch (error) { console.log(JSON.stringify({ check: name, failed: true, status: error.status || 'unavailable' })); }
  }
}
run().catch(() => { console.error('Could not authenticate diagnostics. No credentials logged.'); process.exitCode = 1; });
