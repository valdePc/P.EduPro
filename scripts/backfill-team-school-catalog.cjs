'use strict';

// Read-only by default. --apply reconciles derived search rows; it never writes
// school source records, credentials, roles or individual school collections.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const cliApi = require(path.join(cli, 'api'));
const { Firestore, FieldPath, FieldValue } = require('../functions/node_modules/@google-cloud/firestore');
const { COLLECTION, META, VERSION, eligible, syncCatalog, buildCatalogEntry, validateCatalogQuery,
  readCatalogPage } = require('../functions/school_catalog');
const project = 'edupro-8c4fd';
const args = process.argv.slice(2);
const apply = args.includes('--apply');
const verify = args.includes('--verify-queries');
let phase = 'authorize';

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
  if (args.some((arg) => !['--apply', '--verify-queries'].includes(arg))) throw new Error('Unknown option');
  const account = auth.getProjectDefaultAccount(process.cwd());
  await requireAuth({ project, ...account });
  if (!account?.tokens?.refresh_token || apply && !account.user?.email) throw new Error('Firebase CLI account unavailable');
  const db = new Firestore({ projectId: project, credentials: {
    type: 'authorized_user', client_id: cliApi.clientId(), client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  const summary = { project, mode: apply ? 'derived-index-only' : 'read-only',
    schools: 0, indexed: 0, missing: 0, outdated: 0, orphaned: 0, failed: 0, ready: false, queriesVerified: 0 };
  const fields = ['name', 'nombre', 'officialName', 'code', 'institutionCode', 'active', 'accountStatus', 'status',
    'location.latitude', 'location.longitude', 'location.province', 'location.municipality',
    'location.lat', 'location.lng', 'location.lon', 'location.x', 'location.y',
    'latitude', 'longitude', 'lat', 'lng', 'lon', 'geo.latitude', 'geo.longitude', 'geo.lat', 'geo.lng', 'geo.lon'];
  try {
    phase = 'derive';
    for await (const id of ids(db.collection('schools'))) {
      if (!eligible(id)) continue;
      summary.schools++;
      try {
        const [root] = await db.getAll(db.doc(`schools/${id}`), { fieldMask: fields });
        const index = await db.doc(`${COLLECTION}/${id}`).get();
        if (!index.exists) summary.missing++;
        else if (!require('node:util').isDeepStrictEqual(index.data(), buildCatalogEntry(id, root.data()))) summary.outdated++;
        if (apply) await syncCatalog(db, id);
      } catch { summary.failed++; }
    }
    // Also reconcile deleted schools after an interrupted previous migration.
    for await (const id of ids(db.collection(COLLECTION))) {
      summary.indexed++;
      try {
        const [root] = await db.getAll(db.doc(`schools/${id}`), { fieldMask: [] });
        if (!eligible(id) || !root.exists) {
          summary.orphaned++;
          if (apply) await syncCatalog(db, id);
        }
      } catch { summary.failed++; }
    }
    if (verify && !summary.failed) {
      for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
        for (const filters of [{}, { search: 'san' }, ...(role !== 'billing_admin' ?
          [{ province: 'Santo Domingo' }, { search: 'san', province: 'Santo Domingo' }] : [])]) {
          phase = `verify-${role}-${filters.search ? 'search' : 'all'}${filters.province ? '-province' : ''}`;
          const first = await readCatalogPage(db, role, validateCatalogQuery({ ...filters, limit: 1 }), FieldPath.documentId());
          if (first.schools.length > 1 || !first.metrics || first.matchingTotal == null) throw new Error('Invalid page');
          if (first.nextCursor) {
            await readCatalogPage(db, role, validateCatalogQuery({ ...filters, limit: 1,
              cursor: first.nextCursor, includeMetrics: false, includeTotal: false }), FieldPath.documentId());
          }
          if (role === 'billing_admin' && (first.metrics.located != null || first.schools.some((row) => row.data.location))) throw new Error('Role projection failed');
          summary.queriesVerified++;
        }
      }
    }
    if (apply && !summary.failed) {
      phase = 'ready';
      const audit = db.collection('team_audit').doc();
      await db.runTransaction(async (transaction) => {
        transaction.set(db.doc(META), { ready: true, schemaVersion: VERSION,
          initializedAt: FieldValue.serverTimestamp() });
        transaction.set(audit, { action: 'school.catalog.initialized', actorEmail: account.user.email,
          createdAt: FieldValue.serverTimestamp(), sourceCount: summary.schools, derivedOnly: true });
      });
    }
    const state = await db.doc(META).get();
    summary.ready = state.data()?.ready === true && state.data()?.schemaVersion === VERSION;
    console.log(JSON.stringify(summary));
    if (summary.failed) process.exitCode = 1;
  } finally { await db.terminate(); }
}
main().catch((error) => {
  const code = typeof error.code === 'number' ? error.code : 'request';
  const reason = /index/i.test(error.message || '') ? 'index' : 'request';
  const suggestion = /create_composite=([A-Za-z0-9_=-]+)/.exec(error.message || '');
  const suggestedFields = suggestion ? Buffer.from(suggestion[1], 'base64').toString('utf8')
    .match(/activeCount|draftCount|locatedCount|suspendedCount|provinceKey|searchTokens|__name__/g) : null;
  console.error(JSON.stringify({ failed: true, phase, code, reason, suggestedFields }));
  process.exitCode = 1;
});
