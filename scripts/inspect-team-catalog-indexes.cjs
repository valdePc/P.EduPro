'use strict';
// Read-only by default. Cleanup is limited to two unused definitions created
// during this migration, and requires proof that no catalog index preexisted.
const fs = require('node:fs');
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
async function main() {
  const args = process.argv.slice(2);
  if (args.some((arg) => arg !== '--cleanup-unused')) throw new Error('Unknown option');
  const project = 'edupro-8c4fd';
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const client = new Client({ urlPrefix: 'https://firestore.googleapis.com' });
  const result = (await client.get(`/v1/projects/${project}/databases/(default)/collectionGroups/team_school_catalog/indexes`,
    { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 })).body;
  const indexes = (result.indexes || []).filter((index) => index.name.split('/').at(-3) === 'team_school_catalog');
  if (args.includes('--cleanup-unused')) {
    const originalLog = fs.readFileSync('audit-catalog-existing-indexes.log', 'utf8');
    const original = JSON.parse(originalLog.slice(originalLog.lastIndexOf('\n{') + 1));
    if (original.indexes.some((index) => index.collectionGroup === 'team_school_catalog')) throw new Error('Catalog indexes preexisted');
    const fields = (index) => index.fields.filter((field) => field.fieldPath !== '__name__').map((field) => field.fieldPath).join(',');
    const required = ['activeCount,draftCount,suspendedCount', 'activeCount,draftCount,locatedCount,suspendedCount', 'provinceKey,searchTokens'];
    if (required.some((definition) => !indexes.some((index) => index.state === 'READY' && fields(index) === definition))) throw new Error('Required indexes unavailable');
    const unused = ['activeCount,suspendedCount,draftCount', 'activeCount,suspendedCount,draftCount,locatedCount'];
    const targets = indexes.filter((index) => unused.includes(fields(index)) && index.fields.every((field) => field.order === 'ASCENDING'));
    for (const index of targets) {
      if (!/^projects\/edupro-8c4fd\/databases\/\(default\)\/collectionGroups\/team_school_catalog\/indexes\/[A-Za-z0-9_-]+$/.test(index.name)) throw new Error('Invalid index target');
      await client.delete(`/v1/${index.name}`, { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 });
    }
    const config = JSON.parse(fs.readFileSync('firestore.indexes.json', 'utf8'));
    config.indexes = config.indexes.filter((index) => index.collectionGroup !== 'team_school_catalog' || !unused.includes(fields(index)));
    fs.writeFileSync('firestore.indexes.json', JSON.stringify(config, null, 2) + '\n');
    console.log(JSON.stringify({ removedUnused: targets.length, retainedCatalogIndexes: required.length }));
    return;
  }
  console.log(JSON.stringify(indexes
    .map((index) => ({ state: index.state,
    fields: index.fields.map((field) => ({ field: field.fieldPath, mode: field.order || field.arrayConfig })) }))));
}
main().catch(() => { console.error('Index inspection failed.'); process.exitCode = 1; });
