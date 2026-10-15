'use strict';

// Read-only control-plane inspection. No school documents, stored objects,
// credentials, IAM member identities or notification addresses are printed.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const rules = require(path.join(cli, 'gcp/rules'));
const project = 'edupro-8c4fd';
const requestOptions = () => ({ skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 });
// Firebase CLI's Client mutates options; independent calls need separate objects.
const get = async (origin, resource) => (await new Client({ urlPrefix: origin }).get(resource, requestOptions())).body;

async function main() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const report = { inspectedAt: new Date().toISOString(), project, scope: 'control-plane-read-only' };
  const checks = {
    database: async () => {
      const data = await get('https://firestore.googleapis.com', `/v1/projects/${project}/databases/(default)`);
      return { location: data.locationId, type: data.type,
        pointInTimeRecovery: data.pointInTimeRecoveryEnablement,
        deleteProtection: data.deleteProtectionState, versionRetentionPeriod: data.versionRetentionPeriod };
    },
    backups: async () => {
      const data = await get('https://firestore.googleapis.com', `/v1/projects/${project}/databases/(default)/backupSchedules`);
      return { count: (data.backupSchedules || []).length, additionalPage: !!data.nextPageToken,
        schedules: (data.backupSchedules || []).map(row => ({ retention: row.retention,
          daily: !!row.dailyRecurrence, weekly: !!row.weeklyRecurrence })) };
    },
    storage: async () => {
      const data = await get('https://storage.googleapis.com', `/storage/v1/b/${project}.firebasestorage.app`);
      return { location: data.location, uniformBucketLevelAccess: data.iamConfiguration?.uniformBucketLevelAccess?.enabled,
        publicAccessPrevention: data.iamConfiguration?.publicAccessPrevention,
        versioningEnabled: data.versioning?.enabled === true,
        softDeleteRetentionSeconds: data.softDeletePolicy?.retentionDurationSeconds,
        retentionPeriod: data.retentionPolicy?.retentionPeriod,
        lifecycleRuleCount: (data.lifecycle?.rule || []).length };
    },
    storageRulesReview: async () => {
      const releases = await rules.listAllReleases(project);
      const release = releases.find(row => row.name.includes('firebase.storage/'));
      if (!release) return { releasePresent: false };
      const files = await rules.getRulesetContent(release.rulesetName);
      const source = files.map(row => row.content || '').join('\n');
      return { releasePresent: true, updatedAt: release.updateTime,
        chatReadPermitsSchoolAccessHelper: /match\s+\/schools\/\{schoolId\}\/chat_uploads\/[\s\S]*?allow\s+read\s*:\s*if\s+canAccessSchoolStorage\(schoolId\)/.test(source),
        chatWriteUsesSchoolAccessHelper: /match\s+\/schools\/\{schoolId\}\/chat_uploads\/[\s\S]*?allow\s+write\s*:\s*if\s+canAccessSchoolStorage\(schoolId\)/.test(source),
        chatUpdatesExplicitlyDenied: /allow\s+update\s*,\s*delete\s*:\s*if\s+false/.test(source),
        secondFactorStateMentioned: /security_2fa_users|sign_in_second_factor|lastVerifiedAuthTime/.test(source) };
    },
    monitoring: async () => {
      const data = await get('https://monitoring.googleapis.com', `/v3/projects/${project}/alertPolicies?pageSize=100`);
      const rows = data.alertPolicies || [];
      return { count: rows.length, enabled: rows.filter(row => row.enabled !== false).length,
        withNotificationChannels: rows.filter(row => (row.notificationChannels || []).length > 0).length,
        additionalPage: !!data.nextPageToken };
    },
    publicHosting: async () => {
      const rows = await Promise.all(['/acerca.html', '/aviso-legal.html', '/privacidad.html', '/cookies.html', '/sitemap.xml', '/robots.txt', '/404.html']
        .map(async resource => {
          const response = await fetch(`https://${project}.web.app${resource}`, {
            signal: AbortSignal.timeout(15000), redirect: 'follow',
          });
          const body = await response.text();
          return { path: resource, status: response.status,
            hsts: response.headers.get('strict-transport-security'),
            csp: response.headers.get('content-security-policy'),
            appearsToBeFlutterShell: body.includes('flutter_bootstrap.js'),
            hasEduProBrand: body.includes('EduPro'),
          };
        }));
      return rows;
    },
    budgets: async () => {
      const info = await get('https://cloudbilling.googleapis.com', `/v1/projects/${project}/billingInfo`);
      if (!info.billingAccountName) return { billingEnabled: info.billingEnabled, linkedAccount: false };
      const data = await get('https://billingbudgets.googleapis.com', `/v1/${info.billingAccountName}/budgets?pageSize=100`);
      const rows = data.budgets || [];
      const relevant = rows.filter(row => !row.budgetFilter?.projects?.length ||
        row.budgetFilter.projects.some(value => value === `projects/${project}` || value === 'projects/876132148030'));
      return { billingEnabled: info.billingEnabled, applicableBudgets: relevant.length,
        withThresholds: relevant.filter(row => (row.thresholdRules || []).length > 0).length,
        additionalPage: !!data.nextPageToken };
    },
    projectIam: async () => {
      // getIamPolicy is a read-only RPC even though its transport is POST.
      const client = new Client({ urlPrefix: 'https://cloudresourcemanager.googleapis.com' });
      const data = (await client.post(`/v1/projects/${project}:getIamPolicy`, {}, requestOptions())).body;
      const bindings = data.bindings || [];
      return { bindings: bindings.length,
        broadRoles: bindings.filter(row => ['roles/owner', 'roles/editor'].includes(row.role))
          .map(row => ({ role: row.role, memberCount: (row.members || []).length })),
        publicBindings: bindings.filter(row => (row.members || []).some(value =>
          value === 'allUsers' || value === 'allAuthenticatedUsers')).map(row => ({ role: row.role })) };
    },
  };
  const results = await Promise.allSettled(Object.entries(checks).map(async ([name, check]) => [name, await check()]));
  Object.keys(checks).forEach((name, index) => {
    const result = results[index];
    report[name] = result.status === 'fulfilled' ? result.value[1] : {
      verified: false, status: result.reason?.status || result.reason?.context?.response?.statusCode || 'request-failed',
    };
  });
  console.log(JSON.stringify(report, null, 2));
}
main().catch(() => { console.error('Read-only readiness inspection failed; no credentials logged.'); process.exitCode = 1; });
