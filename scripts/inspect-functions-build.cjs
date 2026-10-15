'use strict';
// Read only. Emits selected npm dependency errors, never full build logs.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
async function run() {
  const id = process.argv[2];
  if (!/^[0-9a-f-]{36}$/.test(id || '')) throw new Error('Invalid build ID');
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://cloudbuild.googleapis.com' });
  const opts = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };
  const build = (await api.get(`/v1/projects/${project}/locations/us-central1/builds/${id}`, opts)).body;
  const result = { status: build.status, failureType: build.failureInfo?.type || null, bucket: build.logsBucket || null, loggingMode: build.options?.logging || null, logUrlHost: build.logUrl ? new URL(build.logUrl).host : null };
  result.failureDetail = String(build.failureInfo?.detail || '').slice(0, 600);
  if (build.logsBucket) {
    const storage = new Client({ urlPrefix: 'https://storage.googleapis.com' });
    const bucket = build.logsBucket.replace(/^gs:\/\//, '');
    const object = `log-${id}.txt`;
    const response = await storage.get(`/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(object)}`, { ...opts, queryParams: { alt: 'media' }, resolveOnHTTPError: true });
    const source = typeof response.body === 'string' ? response.body : '';
    result.logAvailable = response.status === 200;
    result.npmErrors = source.split(/\r?\n/).filter(line => /npm error (Missing|Invalid|code EUSAGE|`npm ci`)/.test(line)).map(line => line.replace(/^.*?npm error /, 'npm error ').slice(0, 300)).slice(0, 25);
  }
  if (!result.logAvailable) {
    const logging = new Client({ urlPrefix: 'https://logging.googleapis.com' });
    const entries = (await logging.post('/v2/entries:list', {
      resourceNames: [`projects/${project}`],
      filter: `resource.type="build" AND resource.labels.build_id="${id}"`,
      orderBy: 'timestamp asc',
      pageSize: 1000,
    }, opts)).body.entries || [];
    const lines = entries.flatMap(entry => String(entry.textPayload || entry.jsonPayload?.message || '').split(/\r?\n/));
    result.logAvailable = entries.length > 0;
    result.npmErrors = lines.filter(line => /npm error (Missing|Invalid|code EUSAGE|`npm ci`)/.test(line)).map(line => line.replace(/^.*?npm error /, 'npm error ').slice(0, 300)).slice(0, 25);
  }
  console.log(JSON.stringify(result));
}
run().catch(() => { console.error('Build inspection failed.'); process.exitCode = 1; });
