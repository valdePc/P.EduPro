'use strict';

// Read-only deployment diagnostics. Never print environment values or tokens.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const options = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };

async function main() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const functions = new Client({ urlPrefix: 'https://cloudfunctions.googleapis.com' });
  const result = (await functions.get(`/v2/projects/${project}/locations/us-central1/functions`, options)).body;
  console.log(JSON.stringify((result.functions || []).map((f) => ({
    name: f.name.split('/').at(-1), state: f.state,
    cpu: f.serviceConfig?.availableCpu, memory: f.serviceConfig?.availableMemory,
    min: f.serviceConfig?.minInstanceCount, max: f.serviceConfig?.maxInstanceCount,
    concurrency: f.serviceConfig?.maxInstanceRequestConcurrency,
    updateTime: f.updateTime,
  })), null, 2));
  const metrics = ['getTeamSchoolSummary', 'syncSchoolTeacherMetrics', 'syncSchoolStudentMetrics',
    'syncSchoolMemberMetrics', 'syncSchoolSubjectMetrics', 'syncSchoolPlanMetrics', 'syncTeamSchoolCatalog'];
  const events = new Client({ urlPrefix: 'https://eventarc.googleapis.com' });
  for (const name of metrics) {
    const deployed = (result.functions || []).find((f) => f.name.split('/').at(-1) === name);
    if (deployed?.state !== 'ACTIVE') throw new Error('Operational metric function is not active.');
    if (name.startsWith('sync')) {
      if (!deployed.eventTrigger?.trigger) throw new Error('Missing metric event trigger.');
      const event = (await events.get(`/v1/${deployed.eventTrigger.trigger}`, options)).body;
      console.log(JSON.stringify({ function: name, eventTriggerPresent: !!event.name }));
    }
  }
  const run = new Client({ urlPrefix: 'https://run.googleapis.com' });
  for (const name of ['unlockschoolaccessip', 'searchschoolplaces', 'createschool', 'listteamschools', 'updateschoollocation', 'updateschoolplanlimits',
    'getteamschoolsummary', 'syncschoolteachermetrics', 'syncschoolstudentmetrics', 'syncschoolmembermetrics',
    'syncschoolsubjectmetrics', 'syncschoolplanmetrics', 'syncteamschoolcatalog']) {
    const service = (await run.get(`/v2/projects/${project}/locations/us-central1/services/${name}`, options)).body;
    const ready = !!service.latestCreatedRevision && service.latestCreatedRevision === service.latestReadyRevision &&
      (service.conditions || []).every((c) => c.state === 'CONDITION_SUCCEEDED');
    console.log(JSON.stringify({ name, latestCreated: service.latestCreatedRevision,
      latestReady: service.latestReadyRevision, ready, conditions: (service.conditions || []).map((c) => ({ type: c.type, state: c.state, reason: c.reason })),
      traffic: service.trafficStatuses, scaling: service.template?.scaling,
      resources: service.template?.containers?.map((c) => c.resources),
    }, null, 2));
    if (!ready) throw new Error('Latest revision is not ready.');
  }
  const quotas = new Client({ urlPrefix: 'https://serviceusage.googleapis.com' });
  const quotaResult = (await quotas.get(`/v1beta1/projects/876132148030/services/run.googleapis.com/consumerQuotaMetrics`, {
    ...options, queryParams: { view: 'FULL', pageSize: 200 },
  })).body;
  console.log(JSON.stringify((quotaResult.metrics || []).filter((m) => /cpu/i.test(m.metric)).map((m) => ({
    metric: m.metric,
    limits: (m.consumerQuotaLimits || []).map((limit) => ({
      unit: limit.unit,
      buckets: (limit.quotaBuckets || []).filter((b) => !b.dimensions?.region || b.dimensions.region === 'us-central1')
        .map((b) => ({ dimensions: b.dimensions, effectiveLimit: b.effectiveLimit })),
    })),
  })), null, 2));
}
main().catch((error) => { console.error(`Deployment inspection failed (${error.status || 'request'}).`); process.exitCode = 1; });
