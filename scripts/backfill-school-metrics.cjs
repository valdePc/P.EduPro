'use strict';

// One-time, resumable derived-counter initialization. Never modifies source
// schools, students, members, teachers, subjects or plans. No personal output.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Firestore, FieldPath } = require('../functions/node_modules/@google-cloud/firestore');
const cliApi = require(path.join(cli, 'api'));
const { METRICS, metricCollection, syncMetrics, readDerivedMetrics } = require('../functions/school_metrics');
const { principalUid } = require('../functions/school_administrator');
const project = 'edupro-8c4fd';
const apply = process.argv.includes('--apply');

async function* ids(collection) {
  let cursor;
  while (true) {
    let query = collection.orderBy(FieldPath.documentId()).limit(200).select();
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const document of page.docs) yield document.id;
    if (page.size < 200) return;
    cursor = page.docs.at(-1).id;
  }
}

async function main() {
  const account = auth.getProjectDefaultAccount(process.cwd());
  await requireAuth({ project, ...account });
  if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI account unavailable');
  // Reuse CLI OAuth credentials in memory; never create a service-account key
  // or persist a credential file for this maintenance operation.
  const db = new Firestore({ projectId: project, credentials: {
    type: 'authorized_user', client_id: cliApi.clientId(), client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  let schools = 0, sourceRows = 0, derivedRows = 0, incomplete = 0;
  for await (const schoolId of ids(db.collection('schools'))) {
    if (/^(valmichapp|eduproapp)_admin_/i.test(schoolId)) continue;
    schools++;
    const school = db.doc(`schools/${schoolId}`);
    const totals = {};
    for (const collection of Object.keys(METRICS)) {
      totals[collection] = (await school.collection(collection).count().get()).data().count;
      for await (const recordId of ids(school.collection(collection))) {
        sourceRows++;
        if (apply) await syncMetrics(db, schoolId, collection, recordId);
      }
      // Also reconcile removed source rows after an interrupted older backfill.
      for await (const recordId of ids(school.collection(metricCollection(collection)))) {
        derivedRows++;
        if (apply) await syncMetrics(db, schoolId, collection, recordId);
      }
    }
    const state = await readDerivedMetrics(school, totals);
    if (state.metricsPending.length) incomplete++;
    if (process.argv.includes('--verify-queries')) {
      const principal = await db.collection('schools').where(FieldPath.documentId(), '==', schoolId)
        .limit(1).select('adminUid').get();
      const assignedUid = principalUid(principal.docs[0]?.data() || {});
      await Promise.all([
        school.collection('members').orderBy('lastAccessAt', 'desc').limit(1).select('lastAccessAt').get(),
        school.collection('members').orderBy('lastLoginAt', 'desc').limit(1).select('lastLoginAt').get(),
        assignedUid ? school.collection('members').where(FieldPath.documentId(), '==', assignedUid).limit(1)
          .select('name', 'displayName', 'nombre', 'email').get() : Promise.resolve(null),
        school.collection('payments').orderBy('createdAt', 'desc').limit(1).select('status', 'estado', 'createdAt').get(),
      ]);
    }
  }
  console.log(JSON.stringify({ project, mode: apply ? 'derived-counters-only' : 'read-only',
    schools, sourceRows, derivedRows, schoolsWithIncompleteCoverage: incomplete,
    boundedQueriesVerified: process.argv.includes('--verify-queries') }));
  if (apply && incomplete) process.exitCode = 1;
  await db.terminate();
}
main().catch(() => {
  console.error('Metric initialization failed. No credentials or source data logged.');
  process.exitCode = 1;
});
