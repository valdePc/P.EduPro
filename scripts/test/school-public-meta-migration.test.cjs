'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { SOURCE_FIELDS, eligibleSchoolId, buildMissingPublicMeta, createMissingPublicMeta } =
  require('../lib/school-public-meta-migration.cjs');
const clock = { now: () => 100, serverTimestamp: () => 200 };

function store(initial = {}, failAudit = false) {
  const records = new Map(Object.entries(initial));
  let next = 0;
  const db = {
    doc: (path) => ({ path }),
    collection: (path) => ({ doc: () => ({ path: `${path}/${++next}` }) }),
    runTransaction: async (callback) => {
      const writes = [];
      const result = await callback({
        getAll: async (...args) => {
          const { fieldMask } = args.pop();
          assert.deepEqual(fieldMask, SOURCE_FIELDS);
          return args.map((ref) => ({
            exists: records.has(ref.path),
            data: () => Object.fromEntries(Object.entries(records.get(ref.path) || {})
              .filter(([field]) => fieldMask.includes(field))),
          }));
        },
        create: (ref, data) => {
          if (failAudit && ref.path.startsWith('team_audit/')) throw new Error('Audit unavailable');
          assert.equal(records.has(ref.path), false);
          writes.push([ref.path, data]);
        },
      });
      for (const [path, data] of writes) records.set(path, data);
      return result;
    },
  };
  return { db, records };
}

test('migration publishes only safe public fields and preserves legacy grades', () => {
  const meta = buildMissingPublicMeta({
    name: 'Colegio', grados: [' Primero ', { student: 'private' }],
    adminEmail: 'private@example.test', contact: { phone: 'private' },
    registrationPassword: 'private-secret', billingNextDueAt: 'private-date',
    adminLink: 'https://user:password@example.test/', profLink: 'javascript:alert(1)',
    adminDeepLink: 'https://example.test/?token=private',
    alumLink: 'https://edupro-8c4fd.web.app/#/eduproapp/A/alumnos',
  }, 'A', clock);
  assert.deepEqual(meta.grades, ['Primero']);
  assert.equal(meta.adminLink, '');
  assert.equal(meta.profLink, '');
  assert.equal(meta.adminDeepLink, '');
  assert.ok(meta.alumLink.includes('/A/alumnos'));
  assert.equal(JSON.stringify(meta).includes('private'), false);
  assert.ok(Object.keys(meta).every((key) => SOURCE_FIELDS.includes(key) || key === 'schoolId'));
});

test('missing metadata cannot reactivate a suspended or blocked school', () => {
  for (const status of ['bloqueada', 'suspendida', 'vencida']) {
    assert.equal(buildMissingPublicMeta({ active: true, accountStatus: status }, 'A', clock).active, false);
  }
  assert.equal(buildMissingPublicMeta({ active: false }, 'A', clock).active, false);
  assert.equal(buildMissingPublicMeta({ active: 'false' }, 'A', clock).active, false);
  assert.equal(eligibleSchoolId('ValMichapp_admin_internal'), false);
  assert.equal(eligibleSchoolId('eduproapp_admin_internal'), false);
  assert.equal(eligibleSchoolId('A/other'), false);
});

test('creation is audited, leaves the source intact and is safe to repeat', async () => {
  const school = { name: 'Colegio actual', adminEmail: 'private@example.test', active: true };
  const h = store({ 'schools/A': school });
  assert.equal(await createMissingPublicMeta(h.db, 'A', 'operator@example.test', clock), 'created');
  assert.deepEqual(h.records.get('schools/A'), school);
  assert.equal(h.records.get('schools/A/public/meta').name, school.name);
  const audit = [...h.records].find(([path]) => path.startsWith('team_audit/'))[1];
  assert.equal(audit.actorEmail, 'operator@example.test');
  assert.equal(audit.schoolId, 'A');
  assert.equal(audit.action, 'school.public-meta.created-by-migration');
  const count = h.records.size;
  assert.equal(await createMissingPublicMeta(h.db, 'A', 'operator@example.test', clock), 'existing');
  assert.equal(h.records.size, count);
});

test('a document created after preview is preserved without an audit or overwrite', async () => {
  const existing = { active: false, accountStatus: 'bloqueada', name: 'Existing metadata' };
  const h = store({ 'schools/A': { name: 'Root name', active: true }, 'schools/A/public/meta': existing });
  assert.equal(await createMissingPublicMeta(h.db, 'A', 'operator@example.test', clock), 'existing');
  assert.deepEqual(h.records.get('schools/A/public/meta'), existing);
  assert.equal(h.records.size, 2);
});

test('deleted source and invalid migration contexts cannot create orphaned metadata', async () => {
  const h = store();
  assert.equal(await createMissingPublicMeta(h.db, 'A', 'operator@example.test', clock), 'source-missing');
  assert.equal(h.records.size, 0);
  for (const [id, actor] of [['A/other', 'operator@example.test'], ['eduproapp_admin_x', 'operator@example.test'], ['A', '']]) {
    await assert.rejects(createMissingPublicMeta(h.db, id, actor, clock));
  }
});

test('failed audit prevents metadata creation as part of the same transaction', async () => {
  const h = store({ 'schools/A': { name: 'Colegio' } }, true);
  await assert.rejects(createMissingPublicMeta(h.db, 'A', 'operator@example.test', clock));
  assert.equal(h.records.has('schools/A/public/meta'), false);
  assert.equal(h.records.size, 1);
});
