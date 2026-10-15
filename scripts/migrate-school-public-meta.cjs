'use strict';

// Default: read-only inventory. --apply creates missing documents only.
// Existing metadata, school documents and account permissions remain intact.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const cliApi = require(path.join(cli, 'api'));
const { Firestore, FieldPath, FieldValue, Timestamp } = require('../functions/node_modules/@google-cloud/firestore');
const { eligibleSchoolId, createMissingPublicMeta } = require('./lib/school-public-meta-migration.cjs');
const project = 'edupro-8c4fd';
const args = process.argv.slice(2);
const apply = args.includes('--apply');

async function main() {
  if (args.some((arg) => arg !== '--apply')) throw new Error('Unknown option');
  const account = auth.getProjectDefaultAccount(process.cwd());
  await requireAuth({ project, ...account });
  if (!account?.tokens?.refresh_token || (apply && !account.user?.email)) {
    throw new Error('Firebase CLI account unavailable');
  }
  // CLI credentials stay in memory. Do not create a service-account key file.
  const db = new Firestore({ projectId: project, credentials: {
    type: 'authorized_user', client_id: cliApi.clientId(), client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  const result = { project, mode: apply ? 'create-missing-only' : 'read-only',
    schools: 0, existing: 0, missing: 0, created: 0, skipped: 0, sourceMissing: 0, failed: 0 };
  try {
    let cursor;
    while (true) {
      let query = db.collection('schools').orderBy(FieldPath.documentId()).limit(200).select();
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const school of page.docs) {
        if (!eligibleSchoolId(school.id)) { result.skipped++; continue; }
        result.schools++;
        try {
          const target = db.doc(`schools/${school.id}/public/meta`);
          const [meta] = await db.getAll(target, { fieldMask: ['schoolId'] });
          if (meta.exists) { result.existing++; continue; }
          result.missing++;
          if (apply) {
            const outcome = await createMissingPublicMeta(db, school.id, account.user.email, {
              now: () => Timestamp.now(), serverTimestamp: () => FieldValue.serverTimestamp(),
            });
            if (outcome === 'created') result.created++;
            if (outcome === 'existing') result.existing++;
            if (outcome === 'source-missing') result.sourceMissing++;
          }
        } catch { result.failed++; }
      }
      if (page.size < 200) break;
      cursor = page.docs.at(-1).id;
    }
    // Counts only: no school names, identifiers, public links or credentials.
    console.log(JSON.stringify(result));
    if (result.failed) process.exitCode = 1;
  } finally { await db.terminate(); }
}
main().catch(() => {
  console.error('Public metadata migration failed. No credentials or source data logged.');
  process.exitCode = 1;
});
