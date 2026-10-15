"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const security = require("../security");
const catalog = require('../school_catalog');

// Execute the real callable handlers against an isolated transactional datastore.
// This suite never initializes a Firebase app or contacts a deployed project.
function harness(initial = {}, { rejectWritePrefix, enforceAppCheck = false } = {}) {
  const records = new Map(Object.entries(initial));
  records.set(catalog.META, { ready: true, schemaVersion: catalog.VERSION });
  for (const [key, data] of Object.entries(initial)) {
    if (key.startsWith('schools/') && key.split('/').length === 2) {
      const id = key.split('/')[1];
      const entry = catalog.buildCatalogEntry(id, data);
      if (entry) records.set(`${catalog.COLLECTION}/${id}`, entry);
    }
  }
  const reads = [];
  const deleted = Symbol("delete");
  const timestamp = (ms) => ({ toMillis: () => ms });
  const snapshot = (ref) => ({ id: ref.path.split('/').at(-1), exists: records.has(ref.path), data: () => records.get(ref.path), ref });
  let nextId = 0;
  function collection(key, options = {}) {
    const matching = () => [...records.keys()]
      .filter((p) => p.startsWith(`${key}/`) && p.split('/').length === key.split('/').length + 1)
      .filter((p) => (options.filters || []).every(([field, operation, value]) =>
        operation === 'array-contains' ? records.get(p)[field]?.includes(value) :
        operation === 'in' ? value.includes(records.get(p)[field]) :
          (field === '__name__' ? p.split('/').at(-1) : records.get(p)[field]) === value));
    return {
      doc: (id = `synthetic-${++nextId}`) => doc(`${key}/${id}`),
      orderBy: (field, direction) => collection(key, { ...options, field, direction }),
      startAfter: (cursor) => collection(key, { ...options, cursor }),
      limit: (limit) => collection(key, { ...options, limit }),
      where: (field, operation, value) => collection(key, { ...options, filters: [...(options.filters || []), [field, operation, value]] }),
      select: (...fields) => collection(key, { ...options, selected: fields }),
      count: () => ({ get: async () => {
        reads.push({ collection: key, mode: 'count' });
        return { data: () => ({ count: matching().length }) };
      } }),
      aggregate: (spec) => ({ get: async () => {
        reads.push({ collection: key, mode: 'aggregate', fields: Object.values(spec).map((value) => value._field).filter(Boolean) });
        const rows = matching().map((key) => records.get(key));
        return { data: () => Object.fromEntries(Object.entries(spec).map(([key, value]) => [key,
          value.aggregateType === 'count' ? rows.length : rows.reduce((total, row) => total + (row[value._field] ?? 0), 0),
        ])) };
      } }),
      get: async () => {
        reads.push({ collection: key, mode: 'documents', limit: options.limit, selected: options.selected });
        let docs = matching().map((p) => snapshot(doc(p)));
        if (options.field && options.field !== '__name__') docs = docs.filter((d) => d.data()[options.field] != null);
        const value = (d) => options.field === '__name__' ? d.id : d.data()[options.field]?.toMillis?.() ?? d.data()[options.field] ?? '';
        docs.sort((a, b) => (value(a) < value(b) ? -1 : value(a) > value(b) ? 1 : 0) * (options.direction === 'desc' ? -1 : 1));
        if (options.cursor) docs = docs.filter((d) => d.id > options.cursor);
        if (options.limit) docs = docs.slice(0, options.limit);
        if (options.selected) docs = docs.map((d) => ({ ...d,
          data: () => Object.fromEntries(options.selected.filter((key) => Object.hasOwn(d.data(), key)).map((key) => [key, d.data()[key]])),
        }));
        return { docs, size: docs.length };
      },
    };
  }
  const write = (ref, patch, options = {}) => {
    const next = options.merge ? { ...(records.get(ref.path) || {}) } : {};
    for (const [key, value] of Object.entries(patch)) {
      if (value === deleted) delete next[key];
      else if (value && Number.isFinite(value._increment)) next[key] = (Number(next[key]) || 0) + value._increment;
      else next[key] = value;
    }
    records.set(ref.path, next);
  };
  const doc = (key) => ({
    path: key,
    collection: (name) => collection(`${key}/${name}`),
    get: async () => snapshot(doc(key)),
    set: async (value, options) => write(doc(key), value, options),
    update: async (patch) => {
      const next = { ...(records.get(key) || {}) };
      for (const [field, value] of Object.entries(patch)) {
        const parts = field.split(".");
        let target = next;
        for (const part of parts.slice(0, -1)) {
          target[part] = { ...(target[part] || {}) };
          target = target[part];
        }
        target[parts.at(-1)] = value;
      }
      records.set(key, next);
    },
  });
  let queue = Promise.resolve();
  const db = {
    doc,
    collection,
    getAll: async (...args) => {
      const { fieldMask } = args.pop();
      reads.push({ collection: 'schools', mode: 'documents', limit: args.length, selected: fieldMask });
      return args.map((ref) => {
        const original = snapshot(ref);
        const projected = {};
        for (const field of fieldMask) {
          const parts = field.split('.');
          const value = parts.reduce((value, key) => value?.[key], original.data());
          if (value === undefined) continue;
          let target = projected;
          for (const part of parts.slice(0, -1)) target = target[part] ??= {};
          target[parts.at(-1)] = value;
        }
        return { ...original, data: () => projected };
      });
    },
    batch: () => {
      const writes = [];
      return {
        set: (ref, value, options) => writes.push(() => write(ref, value, options)),
        update: (ref, value) => writes.push(() => write(ref, value, { merge: true })),
        commit: async () => { for (const action of writes) action(); },
      };
    },
    runTransaction: (action) => {
      const operation = queue.then(async () => {
        const writes = [];
        const value = await action({
          get: async (ref) => snapshot(ref),
          set: (...args) => {
            if (rejectWritePrefix && args[0].path.startsWith(rejectWritePrefix)) {
              throw new Error('Synthetic transaction write failure');
            }
            writes.push(args);
          },
          update: (ref, value) => writes.push([ref, value, { merge: true }]),
          delete: (ref) => writes.push([ref, null]),
        });
        for (const args of writes) {
          if (args[1] === null) records.delete(args[0].path);
          else write(...args);
        }
        return value;
      });
      queue = operation.catch(() => {});
      return operation;
    },
  };
  const firestore = Object.assign(() => db, {
    Timestamp: { now: () => timestamp(Date.now()), fromMillis: timestamp },
    FieldValue: { serverTimestamp: () => timestamp(Date.now()), delete: () => deleted,
      increment: (amount) => ({ _increment: amount }) },
    FieldPath: { documentId: () => '__name__' },
  });
  const authCalls = [];
  const auth = {
    createCustomToken: async (uid, claims) => { authCalls.push({ method: "createCustomToken", uid, claims }); return "synthetic-custom-token"; },
    getUserByEmail: async () => ({ uid: "target" }),
    createUser: async () => ({ uid: "created" }),
    deleteUser: async () => { authCalls.push("deleteUser"); },
    updateUser: async () => { authCalls.push("updateUser"); },
  };
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const context = {
    exports: {}, Buffer, URL, AbortSignal, Date,
    process: { env: { ENFORCE_APPCHECK: String(enforceAppCheck) } },
    console: { info() {}, warn() {}, error() {} },
    require: (name) => {
      if (name === "firebase-admin") return { initializeApp() {}, firestore, app: { appId: "test-app" }, auth: () => auth };
      if (name === "firebase-functions/v2/https") return { onCall: (_options, handler) => handler, HttpsError };
      if (name === "firebase-functions/v2/firestore") return { onDocumentWritten: (_options, handler) => handler };
      if (name === "firebase-functions/v2") return { setGlobalOptions() {} };
      if (name === "./security") return security;
      if (name === "./team_permissions") return require('../team_permissions');
      if (name === "./school_metrics") return require('../school_metrics');
      if (name === "./school_administrator") return require('../school_administrator');
      if (name === "./school_catalog") return catalog;
      if (name === "./school_registration") return require('../school_registration');
      return require(name);
    },
  };
  const source = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  vm.runInNewContext(source + "\nexports.testHelpers = { isSchoolAdminForSchool, hasInternalSuperAdminAccess, verifyAndRecordTwoFactor, generateTotpCode, hasVerifiedSecondFactor, assertSuperAdmin, requiresSecondFactor, normalizeCurriculoDocs, consumeRequestBudget };", context);
  return { ...context.exports, records, reads, authCalls, authService: auth, timestamp };
}

const auth = (uid = "user") => ({ uid, token: { auth_time: Math.floor(Date.now() / 1000), email: "admin@example.test", email_verified: true } });
const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"; // RFC 6238 public test vector.
const rejectCode = (code) => (error) => error.code === code;

test('school metrics converge on current state despite repeated or delayed trigger events', async () => {
  const h = harness({ 'schools/A': { name: 'A' }, 'schools/A/teachers/t': { enabled: true } });
  const event = { params: { schoolId: 'A', recordId: 't' } };
  await Promise.all([h.syncSchoolTeacherMetrics(event), h.syncSchoolTeacherMetrics(event)]);
  assert.equal(h.records.get('schools/A/_operational_teachers/t').activeTeachers, true);
  h.records.set('schools/A/teachers/t', { enabled: false });
  await h.syncSchoolTeacherMetrics(event);
  // An old delivery still reads the current source document, not event.data.
  await h.syncSchoolTeacherMetrics({ ...event, data: { after: { data: () => ({ enabled: true }) } } });
  assert.equal(h.records.get('schools/A/_operational_teachers/t').activeTeachers, false);
  assert.equal(h.records.get('schools/A/_operational_teachers/t').pendingTeachers, true);
  h.records.delete('schools/A/teachers/t');
  await h.syncSchoolTeacherMetrics(event);
  await h.syncSchoolTeacherMetrics(event);
  assert.equal(h.records.has('schools/A/_operational_teachers/t'), false);
});

test('superadmin operational summary uses aggregates and at most four projected documents', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' }, 'schools/A': { name: 'A', adminUid: 'admin' } });
  for (let i = 0; i < 1200; i++) h.records.set(`schools/A/alumnos/student-${i}`, { enabled: true, gradeId: 'grade', privateHealth: 'private' });
  // Before a one-time backfill, unknown coverage must not become a false zero.
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A' } };
  const pending = await h.getTeamSchoolSummary(request);
  assert.equal(pending.totalStudents, 1200);
  assert.equal(pending.activeStudents, null);
  assert.deepEqual([...pending.metricsPending], ['alumnos']);
  for (let i = 0; i < 1200; i++) h.records.set(`schools/A/_operational_alumnos/student-${i}`, { activeStudents: true, studentWithoutGrade: false });
  h.records.set('schools/A/members/admin', { role: 'admin', name: 'School admin', email: 'synthetic@example.test', lastLoginAt: h.timestamp(2000), lastAccessAt: h.timestamp(1000), enabled: true });
  await h.syncSchoolMemberMetrics({ params: { schoolId: 'A', recordId: 'admin' } });
  h.records.set('schools/A/payments/recent', { status: 'verified', createdAt: h.timestamp(3000), receipt: 'private-receipt' });
  const result = await h.getTeamSchoolSummary(request);
  assert.equal(result.activeStudents, 1200);
  assert.equal(result.studentWithoutGrade, 0);
  assert.equal(result.activeUsers, 1);
  assert.equal(result.lastAccessAt, 2000);
  assert.equal(result.lastPaymentAt, 3000);
  assert.equal(result.paymentStatus, 'verified');
  assert.equal(result.adminEmail, 'synthetic@example.test');
  assert.deepEqual([...result.metricsPending], []);
  assert.equal(JSON.stringify(result).includes('private'), false);
  const documents = h.reads.filter((read) => read.mode === 'documents');
  assert.ok(documents.every((read) => read.limit === 1 && read.selected.length > 0));
  assert.equal(documents.some((read) => /alumnos|teachers|subjects|grados|planificaciones/.test(read.collection)), false);
});

test('limited summaries never query or expose payment, activity or access details', async () => {
  for (const role of ['operations_admin', 'support_onboarding']) {
    const h = harness({ 'users/user': { enabled: true, role }, 'schools/A': { name: 'A' } });
    const result = await h.getTeamSchoolSummary({ auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A' } });
    assert.equal(result.paymentStatus, undefined);
    assert.equal(result.lastAccessAt, undefined);
    assert.equal(result.metricsPending, undefined);
    assert.equal(h.reads.length, 6);
    assert.ok(h.reads.every((read) => read.mode === 'count' && !read.collection.includes('_operational_')));
  }
});

test('a newly assigned school administrator is displayed from the school even when its member has no email', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' } });
  const session = { auth: auth(), app: { appId: 'test' } };
  const created = await h.createSchool({ ...session, data: {
    nombre: 'Synthetic school', latitude: 18.5, longitude: -69.9,
    curriculoDocs: [], adminEmail: '  SCHOOL@example.test  ',
  } });
  const member = h.records.get(`schools/${created.schoolId}/members/target`);
  assert.equal(member.email, undefined);
  assert.equal(member.name, undefined);
  for (const role of ['super_admin', 'operations_admin', 'support_onboarding']) {
    h.records.set('users/user', { enabled: true, role });
    const result = await h.getTeamSchoolSummary({ ...session, data: { schoolId: created.schoolId } });
    assert.equal(result.adminEmail, 'school@example.test');
    assert.equal(result.adminAssigned, true);
    assert.equal(result.adminName, 'Administrador asignado');
  }
});

test('principal details use the designated UID and canonical email instead of another administrator', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' },
    'schools/A': { adminUid: 'current', adminEmail: '  CURRENT@example.test  ', adminName: '  ' },
    'schools/A/members/aaa-previous': { role: 'admin_escolar', enabled: false, name: 'Previous administrator', email: 'previous@example.test' },
    'schools/A/members/current': { role: 'admin_escolar', enabled: true, displayName: ' Current administrator ', email: 'outdated@example.test' },
  });
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A' } };
  const result = await h.getTeamSchoolSummary(request);
  assert.equal(result.adminName, 'Current administrator');
  assert.equal(result.adminEmail, 'current@example.test');
  assert.equal(result.adminAssigned, true);
  const limited = h.reads.filter((read) => read.mode === 'documents');
  assert.ok(limited.every((read) => read.limit === 1));
  h.records.set('schools/A', { adminUid: 'current' });
  const legacy = await h.getTeamSchoolSummary(request);
  assert.equal(legacy.adminEmail, 'outdated@example.test');
  assert.equal(legacy.adminName, 'Current administrator');
});

test('missing principal membership or name is distinguished from a school with no assignment', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' },
    'schools/A': { adminEmail: 'school@example.test' },
    'schools/A/members/unrelated': { role: 'admin', enabled: true, name: 'Unrelated administrator', email: 'unrelated@example.test' },
  });
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A' } };
  const assigned = await h.getTeamSchoolSummary(request);
  assert.equal(assigned.adminName, 'Administrador asignado');
  assert.equal(assigned.adminEmail, 'school@example.test');
  assert.equal(assigned.adminAssigned, true);
  h.records.set('schools/A', { adminUid: 'missing', adminEmail: 'school@example.test' });
  assert.equal((await h.getTeamSchoolSummary(request)).adminEmail, 'school@example.test');
  h.records.set('schools/A', { adminUid: 'missing' });
  const incomplete = await h.getTeamSchoolSummary(request);
  assert.equal(incomplete.adminAssigned, true);
  assert.equal(incomplete.adminEmail, '');
  h.records.set('schools/A', { adminEmail: '   ', adminName: 'Stale administrator name' });
  const unassigned = await h.getTeamSchoolSummary(request);
  assert.equal(unassigned.adminAssigned, false);
  assert.equal(unassigned.adminName, 'No asignado');
  assert.equal(unassigned.adminEmail, '');
});

test('team authorization uses the first document, explicit enabled and teamRole over legacy role or claims', async () => {
  const h = harness({
    'users/user': { enabled: true, role: 'superadmin', teamRole: 'support_onboarding' },
    'Users/user': { enabled: true, role: 'superadmin' },
    'EquipoEduPro/user': { enabled: true, role: 'superadmin' },
  });
  const session = auth(); session.token.superadmin = true;
  const request = { app: { appId: 'test' }, auth: session };
  assert.equal((await h.getTeamAccess(request)).role, 'support_onboarding');
  await assert.rejects(h.testHelpers.assertSuperAdmin(request), rejectCode('permission-denied'));
  h.records.set('users/user', { role: 'superadmin', enabled: false });
  assert.equal((await h.getTeamAccess(request)).allowed, false);
  h.records.set('users/user', { role: 'superadmin' });
  assert.equal((await h.getTeamAccess(request)).allowed, false);
  h.records.delete('users/user');
  assert.equal((await h.getTeamAccess(request)).role, 'super_admin');
  h.records.set('EquipoEduPro/user', { enabled: false });
  assert.equal((await h.getTeamAccess(request)).allowed, false);
});

test('all roles use App Check, and restored catalog access requires the current second factor', async () => {
  const h = harness({ 'users/user': { role: 'operations_admin', enabled: true }, 'security_2fa_policy/user': { required: true } });
  await assert.rejects(h.getTeamAccess({ auth: auth() }), rejectCode('failed-precondition'));
  assert.equal((await h.getTeamAccess({ auth: auth(), app: { appId: 'test' } })).role, 'operations_admin');
  await assert.rejects(h.listTeamSchools({ auth: auth(), app: { appId: 'test' }, data: {} }), rejectCode('permission-denied'));
});

test('catalog excludes both internal prefixes before paging and retains every real school', async () => {
  for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
    const ids = ['ValMichapp_admin_A', 'valmichapp_admin_B', 'VALMICHAPP_ADMIN_C',
      'eduproapp_admin_D', 'EduProApp_Admin_E', 'EDUPROAPP_ADMIN_F',
      'ABC-123', 'school_eduproapp_admin_ABC', 'ValMichapp_admin', 'EduPro_SanRafael'];
    const h = harness({ 'users/user': { enabled: true, role },
      ...Object.fromEntries(ids.map((id) => [`schools/${id}`, { name: id }])),
    });
    const visible = [], cursors = new Set();
    let cursor;
    do {
      const page = await h.listTeamSchools({ auth: auth(), app: { appId: 'test' },
        data: { limit: 1, ...(cursor ? { cursor } : {}) },
      });
      visible.push(...page.schools.map((school) => school.id));
      cursor = page.nextCursor;
      if (cursor) {
        assert.equal(cursors.has(cursor), false);
        cursors.add(cursor);
      }
    } while (cursor);
    assert.deepEqual(visible, ['ABC-123', 'EduPro_SanRafael', 'ValMichapp_admin', 'school_eduproapp_admin_ABC']);
    assert.equal(cursors.size, 3);
  }
});

test('catalog and summary allowlists keep billing, individual records and registration secrets isolated', async () => {
  for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
    const h = harness({
      'users/user': { enabled: true, role },
      'schools/A': { name: 'A', adminEmail: 'school@example.test', planPrice: 100, registrationPassword: 'never-return',
        adminUid: 'private-uid', contact: { email: 'contact@example.test', secret: 'never-return' },
        location: { latitude: 18.5, longitude: -69.9, secret: 'never-return' } },
      'schools/B': { name: 'B' },
      'schools/A/alumnos/one': { name: 'private-student' },
      'schools/A/payments/P': { amount: 100, status: 'paid', createdAt: 10, proofUrl: 'never-return' },
    });
    const request = { auth: auth(), app: { appId: 'test' }, data: { limit: 1 } };
    const first = await h.listTeamSchools(request);
    assert.equal(first.schools.length, 1);
    assert.equal(first.nextCursor, 'A');
    const school = first.schools[0].data;
    assert.equal(JSON.stringify(school).includes('never-return'), false);
    assert.equal(school.adminUid, undefined);
    if (role === 'billing_admin') {
      assert.equal(school.contact, undefined); assert.equal(school.location, undefined);
      assert.equal(school.adminEmail, undefined);
      await assert.rejects(h.getTeamSchoolSummary({ ...request, data: { schoolId: 'A' } }), rejectCode('permission-denied'));
    } else {
      const summary = await h.getTeamSchoolSummary({ ...request, data: { schoolId: 'A' } });
      assert.equal(summary.totalStudents, 1);
      assert.equal(JSON.stringify(summary).includes('private-student'), false);
    }
    if (['super_admin', 'billing_admin'].includes(role)) {
      const billing = await h.getTeamSchoolBilling({ ...request, data: { schoolId: 'A' } });
      assert.equal(billing.payments[0].amount, 100);
      assert.equal(billing.payments[0].proofUrl, undefined);
    } else {
      assert.equal(school.planPrice, undefined);
      await assert.rejects(h.getTeamSchoolBilling({ ...request, data: { schoolId: 'A' } }), rejectCode('permission-denied'));
    }
    const second = await h.listTeamSchools({ ...request, data: { limit: 1, cursor: first.nextCursor } });
    assert.equal(second.schools[0].id, 'B');
  }
});

test('catalog reads one bounded page and uses aggregate metrics independent of filters', async () => {
  const schools = Object.fromEntries(Array.from({ length: 280 }, (_, i) => [`schools/S${String(i).padStart(3, '0')}`, {
    name: i === 257 ? 'Colegio Único Águila' : `Colegio ${i}`,
    active: i % 3 !== 0, accountStatus: i % 3 === 0 ? 'suspendida' : 'activa',
    location: { province: i === 257 ? 'Santo Domingo' : 'Azua', latitude: 18.5, longitude: -69.9 },
    registrationPassword: 'do-not-read', privateNotes: 'do-not-read',
  }]));
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' }, ...schools });
  const session = { auth: auth(), app: { appId: 'test' } };
  const first = await h.listTeamSchools({ ...session, data: { limit: 25 } });
  assert.equal(first.schools.length, 25);
  assert.equal(first.nextCursor, 'S024');
  assert.equal(first.metrics.total, 280);
  assert.equal(first.matchingTotal, 280);
  const pageReads = h.reads.filter((read) => read.mode === 'documents');
  assert.equal(pageReads.length, 2);
  assert.equal(pageReads[0].collection, catalog.COLLECTION);
  assert.equal(pageReads[0].limit, 26);
  assert.deepEqual(pageReads[0].selected, []);
  assert.equal(pageReads[1].limit, 25);
  assert.equal(pageReads[1].selected.includes('registrationPassword'), false);
  assert.equal(pageReads[1].selected.includes('privateNotes'), false);
  const second = await h.listTeamSchools({ ...session, data: { limit: 25, cursor: first.nextCursor,
    includeMetrics: false, includeTotal: false } });
  assert.equal(second.schools[0].id, 'S025');
  assert.equal(second.metrics, undefined);
  assert.equal(second.matchingTotal, undefined);
  const searched = await h.listTeamSchools({ ...session, data: { search: 'agui', province: 'Santo Domingo' } });
  assert.deepEqual(Array.from(searched.schools, (row) => row.id), ['S257']);
  assert.equal(searched.matchingTotal, 1);
  assert.equal(searched.metrics.total, 280);
  assert.equal(searched.metrics.located, 280);
});

test('catalog validates query inputs and cannot expose geography to billing or bypass server guards', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'billing_admin' },
    'schools/A': { name: 'A', location: { province: 'Azua', latitude: 18.5, longitude: -69.9 }, contact: { email: 'private-contact' } },
  });
  const session = { auth: auth(), app: { appId: 'test' } };
  for (const data of [{ limit: 0 }, { limit: 101 }, { cursor: '../A' }, { cursor: {} },
    { search: 'a'.repeat(81) }, { province: 5 }, { includeMetrics: 'yes' }, { includeTotal: [] }]) {
    await assert.rejects(h.listTeamSchools({ ...session, data }), rejectCode('invalid-argument'));
  }
  await assert.rejects(h.listTeamSchools({ ...session, data: { province: 'Azua' } }), rejectCode('permission-denied'));
  const page = await h.listTeamSchools({ ...session, data: {} });
  assert.equal(page.metrics.located, undefined);
  assert.equal(page.schools[0].data.location, undefined);
  assert.equal(page.schools[0].data.contact, undefined);
  const rootRead = h.reads.find((read) => read.collection === 'schools');
  assert.equal(rootRead.selected.some((field) => field.startsWith('location') || field.startsWith('contact')), false);
  await assert.rejects(h.listTeamSchools({ auth: auth(), data: {} }), rejectCode('failed-precondition'));
  await assert.rejects(h.listTeamSchools({ app: { appId: 'test' }, data: {} }), rejectCode('unauthenticated'));
  h.records.set('users/user', { enabled: false, role: 'billing_admin' });
  await assert.rejects(h.listTeamSchools({ ...session, data: {} }), rejectCode('permission-denied'));
});

test('uninitialized catalog fails explicitly instead of returning a misleading empty list', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' } });
  h.records.delete(catalog.META);
  await assert.rejects(h.listTeamSchools({ auth: auth(), app: { appId: 'test' }, data: {} }), rejectCode('failed-precondition'));
  assert.equal(h.reads.filter((read) => read.mode === 'documents').length, 0);
});

test('catalog triggers converge on current roots without indexing secrets or resurrecting deleted schools', async () => {
  const h = harness({ 'schools/A': { name: 'Old name', active: true }, 'schools/EduProApp_Admin_Z': { name: 'Internal' } });
  h.records.set('schools/A', { name: 'New name', active: false,
    location: { province: 'Azua', lat: '18.5', lng: '-69.9' }, contact: { email: 'private-email' }, registrationPassword: 'private-password' });
  const event = { params: { schoolId: 'A' }, data: { after: { data: () => ({ name: 'Obsolete event data' }) } } };
  await h.syncTeamSchoolCatalog(event);
  await h.syncTeamSchoolCatalog(event);
  const entry = h.records.get(`${catalog.COLLECTION}/A`);
  assert.equal(entry.status, 'suspended');
  assert.equal(entry.hasCoordinates, true);
  assert.equal(entry.searchTokens.includes('new'), true);
  assert.equal(entry.searchTokens.includes('old'), false);
  assert.equal(JSON.stringify(entry).includes('private-'), false);
  h.records.delete('schools/A');
  await h.syncTeamSchoolCatalog(event);
  await h.syncTeamSchoolCatalog(event);
  assert.equal(h.records.has(`${catalog.COLLECTION}/A`), false);
  h.records.set(`${catalog.COLLECTION}/EduProApp_Admin_Z`, { status: 'active' });
  await h.syncTeamSchoolCatalog({ params: { schoolId: 'EduProApp_Admin_Z' } });
  assert.equal(h.records.has(`${catalog.COLLECTION}/EduProApp_Admin_Z`), false);
});

test('operations can create Base schools and set locations but cannot change plans, administrators or IP blocks', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'operations_admin' }, 'schools/A': { name: 'A' } });
  const request = { auth: auth(), app: { appId: 'test' }, data: { nombre: 'New school', latitude: 18.5, longitude: -69.9, curriculoDocs: [] } };
  const created = await h.createSchool(request);
  assert.equal(h.records.get(`schools/${created.schoolId}`).studentsLimit, 150);
  await assert.rejects(h.createSchool({ ...request, data: { ...request.data, planTier: 'premium' } }), rejectCode('invalid-argument'));
  await assert.rejects(h.createSchool({ ...request, data: { ...request.data, adminsLimit: 999 } }), rejectCode('invalid-argument'));
  const updated = await h.updateSchoolLocation({ ...request, data: { schoolId: 'A', latitude: 18.6, longitude: -69.8 } });
  assert.equal(updated.success, true);
  // An invalid query reaches input validation for operations, while support
  // must be rejected at authorization before calling any external map service.
  await assert.rejects(h.searchSchoolPlaces({ ...request, data: { query: '' } }), rejectCode('invalid-argument'));
  for (const endpoint of ['assignSchoolAdmin', 'upsertSchoolAdmin', 'updateSchoolPlanLimits', 'listSchoolAccessIps', 'unlockSchoolAccessIp']) {
    await assert.rejects(h[endpoint]({ ...request, data: { schoolId: 'A' } }), rejectCode('permission-denied'), endpoint);
  }
  for (const role of ['support_onboarding', 'billing_admin']) {
    h.records.set('users/user', { enabled: true, role });
    await assert.rejects(h.createSchool(request), rejectCode('permission-denied'));
    await assert.rejects(h.updateSchoolLocation({ ...request, data: { schoolId: 'A' } }), rejectCode('permission-denied'));
    await assert.rejects(h.searchSchoolPlaces({ ...request, data: { query: '' } }), rejectCode('permission-denied'));
  }
});

test('operations creation appears in the safe catalog, location edits persist, and revocation blocks the next request', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'operations_admin' } });
  const session = { auth: auth(), app: { appId: 'test' } };
  const input = {
    nombre: 'Colegio de prueba operativa', planTier: 'base',
    adminsLimit: 1, teachersLimit: 10, studentsLimit: 150,
    latitude: 18.5, longitude: -69.9, province: 'Santo Domingo',
    contactEmail: 'synthetic@example.test', curriculoDocs: [],
  };
  const created = await h.createSchool({ ...session, data: input });
  const schoolPath = `schools/${created.schoolId}`;
  // Sensitive synthetic data must never escape through the role's catalog.
  h.records.get(schoolPath).privateNotes = 'synthetic-private-note';
  h.records.set(`${schoolPath}/alumnos/student`, { name: 'synthetic-private-student' });
  const first = await h.listTeamSchools({ ...session, data: { limit: 100 } });
  const visible = first.schools.find((school) => school.id === created.schoolId);
  assert.ok(visible, 'The newly created school must be visible to its operations creator');
  assert.equal(visible.data.planTier, 'base');
  assert.equal(visible.data.contact.email, input.contactEmail);
  assert.equal(visible.data.privateNotes, undefined);
  assert.equal(JSON.stringify(first).includes(created.password), false);
  assert.equal(JSON.stringify(first).includes('synthetic-private-student'), false);
  const summary = await h.getTeamSchoolSummary({ ...session, data: { schoolId: created.schoolId } });
  assert.equal(summary.totalStudents, 1);
  assert.equal(JSON.stringify(summary).includes('synthetic-private-student'), false);
  await h.updateSchoolLocation({ ...session, data: { schoolId: created.schoolId, latitude: 18.6, longitude: -69.8 } });
  const refreshed = await h.listTeamSchools({ ...session, data: {} });
  const updated = refreshed.schools.find((school) => school.id === created.schoolId);
  assert.equal(updated.data.location.latitude, 18.6);
  assert.equal(updated.data.location.longitude, -69.8);
  assert.equal(updated.data.studentsLimit, 150);
  assert.equal(h.records.get(`${catalog.COLLECTION}/${created.schoolId}`).hasCoordinates, true);
  h.records.set('users/user', { enabled: false, role: 'operations_admin' });
  await assert.rejects(h.listTeamSchools({ ...session, data: {} }), rejectCode('permission-denied'));
  await assert.rejects(h.createSchool({ ...session, data: input }), rejectCode('permission-denied'));
  await assert.rejects(h.updateSchoolLocation({ ...session, data: { schoolId: created.schoolId, latitude: 18.7, longitude: -69.7 } }), rejectCode('permission-denied'));
  assert.equal(h.records.get(schoolPath).location.latitude, 18.6);
});

test('location updates and their aggregate index are committed atomically', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'operations_admin' },
    'schools/A': { name: 'A', location: { province: 'Azua', addressLine: 'Existing address' } },
  }, { rejectWritePrefix: `${catalog.COLLECTION}/` });
  await assert.rejects(h.updateSchoolLocation({ auth: auth(), app: { appId: 'test' },
    data: { schoolId: 'A', latitude: 18.5, longitude: -69.9 } }), /Synthetic transaction write failure/);
  assert.equal(h.records.get('schools/A').location.latitude, undefined);
  assert.equal(h.records.get(`${catalog.COLLECTION}/A`).hasCoordinates, false);
});

test('school creation cannot bypass the administrator assignment permission', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'operations_admin' } });
  h.authService.getUserByEmail = async () => { throw new Error('Authorization must reject before reading Auth'); };
  h.authService.createUser = async () => { throw new Error('Authorization must reject before creating an account'); };
  const request = {
    auth: auth(), app: { appId: 'test' },
    data: { nombre: 'New school', latitude: 18.5, longitude: -69.9, curriculoDocs: [], contactEmail: 'contact@example.test' },
  };
  await assert.rejects(h.createSchool({ ...request, data: { ...request.data, adminEmail: 'contact@example.test' } }), rejectCode('permission-denied'));
  assert.equal([...h.records.keys()].some((key) => key.startsWith('schools/')), false);
  const created = await h.createSchool(request);
  const school = h.records.get(`schools/${created.schoolId}`);
  assert.equal(school.contact.email, 'contact@example.test');
  assert.equal(school.adminUid, undefined);
  assert.equal(created.adminEmail, null);
});

test('superadmin plan edits validate bounds and atomically record an audit event', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' }, 'schools/A': {
    name: 'A', planTier: 'base', adminsLimit: 1, teachersLimit: 10, studentsLimit: 150,
    planLimits: { admins: 1, teachers: 10, students: 150 }, maxUsers: 161,
    privateNotes: 'synthetic-sensitive-data',
  } });
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A', planTier: 'plus', adminsLimit: 3, teachersLimit: 25, studentsLimit: 300, reason: '  Ampliación aprobada para el próximo curso  ' } };
  await h.updateSchoolPlanLimits(request);
  assert.equal(h.records.get('schools/A').maxUsers, 328);
  const events = [...h.records.entries()].filter(([key]) => key.startsWith('team_audit/'));
  assert.equal(events.length, 1);
  const event = events[0][1];
  assert.equal(event.actorUid, 'user');
  assert.equal(event.actorRole, 'super_admin');
  assert.equal(event.schoolId, 'A');
  assert.equal(event.action, 'school.plan-limits.updated');
  assert.equal(event.reason, request.data.reason.trim());
  assert.equal(event.before.planTier, 'base');
  assert.equal(event.before.studentsLimit, 150);
  assert.equal(event.after.planTier, 'plus');
  assert.equal(event.after.studentsLimit, 300);
  assert.equal(event.after.planLimits.students, 300);
  assert.equal(event.after.maxUsers, 328);
  assert.equal(event.before.privateNotes, undefined);
  assert.equal(event.createdAt.toMillis(), h.records.get('schools/A').updatedAt.toMillis());
  await assert.rejects(h.updateSchoolPlanLimits({ ...request, data: { ...request.data, studentsLimit: 1000001 } }), rejectCode('invalid-argument'));
  assert.equal([...h.records.keys()].filter((key) => key.startsWith('team_audit/')).length, 1);
  assert.equal(h.records.get('schools/A').studentsLimit, 300);
});

test('plan edits reject missing, malformed or oversized reasons without changing a school', async () => {
  const initial = { name: 'A', studentsLimit: 150 };
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' }, 'schools/A': initial });
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A', planTier: 'plus', adminsLimit: 3, teachersLimit: 25, studentsLimit: 300 } };
  for (const reason of [undefined, null, 1234567890, {}, '', '         ', 'corto', 'x'.repeat(501)]) {
    await assert.rejects(h.updateSchoolPlanLimits({ ...request, data: { ...request.data, reason } }), rejectCode('invalid-argument'));
    assert.equal(h.records.get('schools/A'), initial);
    assert.equal([...h.records.keys()].some((key) => key.startsWith('team_audit/')), false);
  }
  await assert.rejects(h.updateSchoolPlanLimits({ ...request, data: { ...request.data, schoolId: 'missing', reason: 'Cambio autorizado del plan' } }), rejectCode('not-found'));
  assert.equal([...h.records.keys()].some((key) => key.startsWith('team_audit/')), false);
});

test('sensitive plan edits require App Check, current superadmin permission and recent authentication', async () => {
  const h = harness({ 'users/user': { enabled: true, role: 'super_admin' }, 'schools/A': { name: 'A', studentsLimit: 150 } });
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A', planTier: 'plus', adminsLimit: 3, teachersLimit: 25, studentsLimit: 300, reason: 'Cambio autorizado del plan' } };
  await assert.rejects(h.updateSchoolPlanLimits({ ...request, app: null }), rejectCode('failed-precondition'));
  await assert.rejects(h.updateSchoolPlanLimits({ ...request, auth: { ...request.auth, token: { ...request.auth.token, auth_time: Math.floor(Date.now() / 1000) - 600 } } }), rejectCode('unauthenticated'));
  for (const role of ['operations_admin', 'support_onboarding', 'billing_admin']) {
    h.records.set('users/user', { enabled: true, role });
    await assert.rejects(h.updateSchoolPlanLimits(request), rejectCode('permission-denied'));
  }
  h.records.set('users/user', { enabled: false, role: 'super_admin' });
  await assert.rejects(h.updateSchoolPlanLimits(request), rejectCode('permission-denied'));
  assert.equal(h.records.get('schools/A').studentsLimit, 150);
  assert.equal([...h.records.keys()].some((key) => key.startsWith('team_audit/')), false);
});

test('plan edits cannot bypass required MFA or commit without their audit entry', async () => {
  const initial = { name: 'A', studentsLimit: 150 };
  const fixtures = { 'users/user': { enabled: true, role: 'super_admin' }, 'schools/A': initial };
  const request = { auth: auth(), app: { appId: 'test' }, data: { schoolId: 'A', planTier: 'plus', adminsLimit: 3, teachersLimit: 25, studentsLimit: 300, reason: 'Cambio autorizado del plan' } };
  const h = harness({ ...fixtures, 'security_2fa_policy/user': { required: true } });
  await assert.rejects(h.updateSchoolPlanLimits(request), rejectCode('permission-denied'));
  assert.equal(h.records.get('schools/A'), initial);
  h.records.set('security_2fa_users/user', {
    enabled: true, lastVerifiedAt: h.timestamp(Date.now()), lastVerifiedAuthTime: request.auth.token.auth_time,
  });
  await h.updateSchoolPlanLimits(request);
  assert.equal(h.records.get('schools/A').studentsLimit, 300);
  const broken = harness(fixtures, { rejectWritePrefix: 'team_audit/' });
  await assert.rejects(broken.updateSchoolPlanLimits(request), /Synthetic transaction write failure/);
  assert.equal(broken.records.get('schools/A'), initial);
  assert.equal([...broken.records.keys()].some((key) => key.startsWith('team_audit/')), false);
});

test('Dominican schedules are independent of browser time and principal access remains 24/7 unless disabled', () => {
  const { teamScheduleAllows } = require('../team_permissions');
  const hours = { enabled: true, allowedWeekdays: [1], startMinute: 480, endMinute: 1080 };
  assert.equal(teamScheduleAllows('operations_admin', hours, new Date('2026-10-05T11:59:00Z')), false);
  assert.equal(teamScheduleAllows('operations_admin', hours, new Date('2026-10-05T12:00:00Z')), true);
  assert.equal(teamScheduleAllows('operations_admin', hours, new Date('2026-10-06T12:00:00Z')), false);
  assert.equal(teamScheduleAllows('super_admin', hours, new Date('2026-10-06T01:00:00Z')), true);
  assert.equal(teamScheduleAllows('super_admin', { ...hours, enabled: false }), false);
});

test("assigning a new school administrator requires an explicit create request", async () => {
  const h = harness({
    "users/user": { role: "superadmin", enabled: true },
    "schools/A": { name: "Escuela A" },
  });
  h.authService.getUserByEmail = async () => {
    const error = new Error("missing");
    error.code = "auth/user-not-found";
    throw error;
  };
  let createdPassword;
  h.authService.createUser = async (value) => {
    createdPassword = value.password;
    return { uid: "created" };
  };
  await assert.rejects(
    h.assignSchoolAdmin({ app: { appId: "test-app" }, auth: auth(), data: { schoolCode: "A", email: "school@example.test" } }),
    rejectCode("not-found"),
  );
  assert.equal(createdPassword, undefined);

  const result = await h.assignSchoolAdmin({
    app: { appId: "test-app" }, auth: auth(),
    data: { schoolCode: "A", email: "SCHOOL@example.test", createIfMissing: true },
  });
  assert.equal(result.created, true);
  assert.equal(result.email, "school@example.test");
  assert.ok(createdPassword.length >= 32);
  assert.equal(h.records.get("schools/A").adminUid, "created");
  assert.equal(h.records.get("schools/A/members/created").enabled, true);
  assert.equal(JSON.stringify([...h.records.values()]).includes(createdPassword), false);
});

test("replacing a primary administrator disables the previous school membership", async () => {
  const h = harness({
    "users/user": { role: "superadmin", enabled: true },
    "schools/A": { adminUid: "old", adminEmail: "old@example.test" },
    "schools/A/members/old": { role: "admin_escolar", enabled: true },
  });
  const result = await h.assignSchoolAdmin({
    app: { appId: "test-app" }, auth: auth(), data: { schoolCode: "A", email: "new@example.test" },
  });
  assert.equal(result.created, false);
  assert.equal(h.records.get("schools/A/members/old").enabled, false);
  assert.equal(h.records.get("schools/A/members/target").enabled, true);
});

test("creating a school with an administrator email links Auth, school, and membership", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true } });
  h.authService.getUserByEmail = async () => {
    const error = new Error("missing");
    error.code = "auth/user-not-found";
    throw error;
  };
  let createdPassword;
  h.authService.createUser = async (value) => {
    createdPassword = value.password;
    return { uid: "new-school-admin" };
  };
  const result = await h.createSchool({
    app: { appId: "test-app" }, auth: auth(),
    data: {
      nombre: "Colegio Prueba",
      contactEmail: "school@example.test",
      adminEmail: "SCHOOL@example.test",
      latitude: 18.481234,
      longitude: -69.901234,
      curriculoDocs: [],
    },
  });
  const school = h.records.get(`schools/${result.schoolId}`);
  const member = h.records.get(`schools/${result.schoolId}/members/new-school-admin`);
  assert.equal(school.adminEmail, "school@example.test");
  assert.equal(school.adminUid, "new-school-admin");
  assert.equal(school.contact.email, "school@example.test");
  assert.equal(school.location.latitude, 18.481234);
  assert.equal(school.location.longitude, -69.901234);
  assert.equal(school.location.source, "manual_pin");
  assert.equal(member.role, "admin_escolar");
  assert.equal(member.enabled, true);
  assert.equal(result.adminAccountCreated, true);
  assert.ok(createdPassword.length >= 32);
  assert.equal(JSON.stringify([...h.records.values()]).includes(createdPassword), false);
});

test('school creation writes public metadata without contacts, billing or registration secrets', async () => {
  const h = harness({ 'users/user': { role: 'superadmin', enabled: true } });
  const created = await h.createSchool({ app: { appId: 'test' }, auth: auth(), data: {
    nombre: 'Colegio público', officialName: 'Nombre oficial', contactEmail: 'private@example.test',
    contactPhone: 'private-phone', latitude: 18.48, longitude: -69.9, curriculoDocs: [],
  } });
  const school = h.records.get(`schools/${created.schoolId}`);
  const meta = h.records.get(`schools/${created.schoolId}/public/meta`);
  assert.equal(meta.schoolId, created.schoolId);
  assert.equal(meta.name, school.name);
  assert.equal(meta.officialName, school.officialName);
  assert.equal(meta.accountStatus, 'activa');
  assert.equal(meta.active, true);
  assert.equal(meta.adminLink, school.adminLink);
  for (const key of ['adminEmail', 'adminUid', 'contact', 'location', 'planPrice', 'renewalAt', 'createdByEmail', 'password']) {
    assert.equal(Object.hasOwn(meta, key), false);
  }
  assert.equal(JSON.stringify(meta).includes(created.password), false);
  assert.equal(JSON.stringify(meta).includes('private'), false);
});

test("contact-only email does not silently create school admin access", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true } });
  const result = await h.createSchool({
    app: { appId: "test-app" }, auth: auth(), data: { nombre: "Colegio Contacto", contactEmail: "contact@example.test", latitude: 18.48, longitude: -69.9, curriculoDocs: [] },
  });
  const school = h.records.get(`schools/${result.schoolId}`);
  assert.equal(school.contact.email, "contact@example.test");
  assert.equal(school.adminUid, undefined);
  assert.equal(result.adminAccountCreated, false);
});

test("school location is required and validated before creating a school", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true } });
  for (const coordinates of [{}, { latitude: 0, longitude: 0 }, { latitude: "18.48", longitude: -69.9 }]) {
    await assert.rejects(
      h.createSchool({ app: { appId: "test-app" }, auth: auth(), data: { nombre: "Sin ubicación", curriculoDocs: [], ...coordinates } }),
      rejectCode("invalid-argument"),
    );
  }
  assert.equal([...h.records.keys()].some((key) => key.startsWith("schools/")), false);
});

test("authorized operations can set a stored location; outsiders cannot", async () => {
  const h = harness({
    "users/user": { role: "superadmin", enabled: true },
    "schools/A": { name: "Colegio A", location: { province: "Santo Domingo" } },
  });
  await assert.rejects(
    h.updateSchoolLocation({ app: { appId: "test-app" }, auth: auth("other"), data: { schoolId: "A", latitude: 18.48, longitude: -69.9 } }),
    rejectCode("permission-denied"),
  );
  await assert.rejects(
    h.updateSchoolLocation({ app: { appId: "test-app" }, auth: auth(), data: { schoolId: "missing", latitude: 18.48, longitude: -69.9 } }),
    rejectCode("not-found"),
  );
  const result = await h.updateSchoolLocation({
    app: { appId: "test-app" }, auth: auth(), data: { schoolId: "A", latitude: 18.48123449, longitude: -69.90123449 },
  });
  assert.equal(result.success, true);
  assert.equal(h.records.get("schools/A").location.province, "Santo Domingo");
  assert.equal(h.records.get("schools/A").location.latitude, 18.481234);
  assert.equal(h.records.get("schools/A").location.longitude, -69.901234);
});

test("school IDs reject path injection and non-string input", () => {
  assert.equal(security.normalizeSchoolId(" eduproapp_admin_ABC-123 "), "ABC-123");
  for (const value of ["../other", "ABC/config/registro", "a/b/c", "a\\b", "", {}, "x".repeat(129)]) {
    assert.equal(security.normalizeSchoolId(value), "");
  }
});

test("client prefixes and unrelated CDN headers cannot replace the trusted final hop", () => {
  const request = { headers: { "fastly-client-ip": "192.0.2.1", "cf-connecting-ip": "192.0.2.2", "x-forwarded-for": "192.0.2.3, 203.0.113.4" } };
  assert.equal(security.resolveClientIp(request), "203.0.113.4");
  request.headers["x-forwarded-for"] = "198.51.100.1, 203.0.113.4";
  assert.equal(security.resolveClientIp(request), "203.0.113.4");
  request.headers["x-forwarded-for"] = "192.0.2.1, invalid";
  assert.equal(security.resolveClientIp(request), "");
  assert.equal(security.resolveClientIp({ socket: { remoteAddress: "::ffff:127.0.0.1" } }), "127.0.0.1");
});

test("codes use the cryptographic generator instead of Math.random", () => {
  const original = Math.random;
  Math.random = () => { throw new Error("insecure PRNG used"); };
  try { assert.match(security.randomAlphaNumCode(16), /^[A-Z0-9]{16}$/); }
  finally { Math.random = original; }
});

test("curriculum accepts only bounded built-in Storage PDFs or credential-free HTTPS links", () => {
  const normalize = harness().testHelpers.normalizeCurriculoDocs;
  const row = (url) => [{ title: "Curriculo", category: "Base", url }];
  assert.equal(normalize(row("curriculo/base/1Z1p-adecuacion-curricular-nivel-inicial-final-2023pdf.pdf"))[0].url,
    "curriculo/base/1Z1p-adecuacion-curricular-nivel-inicial-final-2023pdf.pdf");
  assert.equal(normalize(row("https://example.org/documento.pdf"))[0].url, "https://example.org/documento.pdf");
  for (const url of [
    "curriculo/base/../secret.pdf",
    "curriculo/base/secret.pdf?token=abc",
    "curriculo/other/secret.pdf",
    "http://example.org/documento.pdf",
    "https://user:password@example.org/documento.pdf",
  ]) {
    assert.throws(() => normalize(row(url)), rejectCode("invalid-argument"));
  }
});

test("unverified matching email is not school administration; disabled member takes precedence", async () => {
  const h = harness({ "schools/A": { adminEmail: "admin@example.test" } });
  assert.equal(await h.testHelpers.isSchoolAdminForSchool("user", "A", { email: "admin@example.test" }), false);
  assert.equal(await h.testHelpers.isSchoolAdminForSchool("user", "A", auth().token), true);
  h.records.set("schools/A/members/user", { role: "admin_escolar", enabled: false });
  assert.equal(await h.testHelpers.isSchoolAdminForSchool("user", "A", auth().token), false);
  assert.equal(await h.testHelpers.isSchoolAdminForSchool("user", "B", auth().token), false);
});

test("disabled internal users cannot reuse stale superadmin claims", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: false } });
  assert.equal(await h.testHelpers.hasInternalSuperAdminAccess({ uid: "user", token: { superadmin: true } }), false);
});

test("anonymous and cross-school callers cannot reset the login limiter", async () => {
  const h = harness({ "schools/B/members/user": { role: "admin_escolar", enabled: true } });
  const initialSize = h.records.size;
  await assert.rejects(h.adminSchoolLoginRateLimit({ data: { operation: "success", schoolId: "A" } }), rejectCode("unauthenticated"));
  await assert.rejects(h.adminSchoolLoginRateLimit({ app: { appId: "test-app" }, auth: auth(), data: { operation: "success", schoolId: "A" } }), rejectCode("permission-denied"));
  await assert.rejects(h.schoolAccessIpPing({ data: { operation: "success", schoolId: "A", audience: "docentes" } }), rejectCode("unauthenticated"));
  assert.equal(h.records.size, initialSize);
});

test("TOTP calculation matches the published RFC vector", () => {
  const h = harness();
  assert.equal(h.testHelpers.generateTotpCode(secret, 1), "287082");
  assert.equal(security.totpCounter(secret, "287082", 59000, h.testHelpers.generateTotpCode), 1);
});

test("five incorrect TOTP guesses lock the account and retain the failures", async () => {
  const h = harness({ "security_2fa_users/user": { secret, enabled: true } });
  const params = { app: { appId: "test-app" }, auth: auth(), audience: "admin_general", schoolId: "", code: "invalid", enrollment: false };
  for (let n = 0; n < 4; n += 1) await assert.rejects(h.testHelpers.verifyAndRecordTwoFactor(params), rejectCode("permission-denied"));
  await assert.rejects(h.testHelpers.verifyAndRecordTwoFactor(params), rejectCode("resource-exhausted"));
  assert.equal(h.records.get("security_2fa_users/user").failedAttempts, 5);
  params.code = h.testHelpers.generateTotpCode(secret, Math.floor(Date.now() / 30000));
  await assert.rejects(h.testHelpers.verifyAndRecordTwoFactor(params), rejectCode("resource-exhausted"));
});

test("parallel reuse of a valid TOTP yields only one verified session", async () => {
  const h = harness({ "security_2fa_users/user": { secret, enabled: true } });
  const session = auth();
  const params = { app: { appId: "test-app" }, auth: session, audience: "admin_general", schoolId: "", code: h.testHelpers.generateTotpCode(secret, Math.floor(Date.now() / 30000)), enrollment: false };
  const results = await Promise.allSettled([h.testHelpers.verifyAndRecordTwoFactor(params), h.testHelpers.verifyAndRecordTwoFactor(params)]);
  assert.equal(results.filter((row) => row.status === "fulfilled").length, 1);
  const state = h.records.get("security_2fa_users/user");
  assert.equal(h.testHelpers.hasVerifiedSecondFactor(session, state), true);
  assert.equal(h.testHelpers.hasVerifiedSecondFactor({ ...session, token: { auth_time: session.token.auth_time + 1 } }, state), false);
});

test("pending enrollment expires and cannot be confirmed for a different school", async () => {
  const h = harness();
  const params = { app: { appId: "test-app" }, auth: auth(), audience: "admin_escolar", schoolId: "B", code: h.testHelpers.generateTotpCode(secret, Math.floor(Date.now() / 30000)), enrollment: true };
  h.records.set("security_2fa_users/user", { pendingSecret: secret, pendingCreatedAt: h.timestamp(Date.now()), pendingAudience: "admin_escolar", pendingSchoolId: "A" });
  await assert.rejects(h.testHelpers.verifyAndRecordTwoFactor(params), rejectCode("failed-precondition"));
  h.records.set("security_2fa_users/user", { pendingSecret: secret, pendingCreatedAt: h.timestamp(Date.now() - 600001), pendingAudience: "admin_escolar", pendingSchoolId: "B" });
  await assert.rejects(h.testHelpers.verifyAndRecordTwoFactor(params), rejectCode("failed-precondition"));
});

test("an enrolled factor cannot be replaced with password authentication alone", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "app_config/security": { twoFAEnabled: true }, "security_2fa_users/user": { enabled: true, secret } });
  await assert.rejects(h.startEduProTwoFactorEnrollment({ app: { appId: "test-app" }, auth: auth(), data: { audience: "admin_general" } }), rejectCode("failed-precondition"));
  assert.equal(h.records.get("security_2fa_users/user").secret, secret);
  assert.equal(h.records.get("security_2fa_users/user").pendingSecret, undefined);
});

test("privileged callable guard requires a verified factor when policy enables it", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "app_config/security": { twoFAEnabled: true } });
  await assert.rejects(h.testHelpers.assertSuperAdmin({ app: { appId: "test-app" }, auth: auth() }), rejectCode("permission-denied"));
  const session = auth();
  h.records.set("security_2fa_users/user", { enabled: true, lastVerifiedAt: h.timestamp(Date.now()), lastVerifiedAuthTime: session.token.auth_time });
  await h.testHelpers.assertSuperAdmin({ app: { appId: "test-app" }, auth: session });
});

test("school creation rejects a stale session before writing any school data", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true } });
  const session = auth();
  session.token.auth_time = Math.floor(Date.now() / 1000) - 301;
  await assert.rejects(
    h.createSchool({ app: { appId: "test-app" }, auth: session, data: { nombre: "Colegio de prueba" } }),
    rejectCode("unauthenticated")
  );
  assert.equal([...h.records.keys()].some((key) => key.startsWith("schools/")), false);
});

test("per-account policy requires TOTP only for the selected superadmin", async () => {
  const h = harness({
    "users/user": { role: "superadmin", enabled: true },
    "users/other": { role: "superadmin", enabled: true },
    "app_config/security": { twoFAEnabled: false },
    "security_2fa_policy/user": { required: true },
  });
  const first = auth("user");
  const other = auth("other");
  assert.equal((await h.getEduProTwoFactorStatus({ app: { appId: "test-app" }, auth: first, data: { audience: "admin_general" } })).required, true);
  assert.equal((await h.getEduProTwoFactorStatus({ app: { appId: "test-app" }, auth: other, data: { audience: "admin_general" } })).required, false);
  await assert.rejects(h.testHelpers.assertSuperAdmin({ app: { appId: "test-app" }, auth: first }), rejectCode("permission-denied"));
  await h.testHelpers.assertSuperAdmin({ app: { appId: "test-app" }, auth: other });
  h.records.set("security_2fa_users/user", { enabled: true, lastVerifiedAt: h.timestamp(Date.now()), lastVerifiedAuthTime: first.token.auth_time });
  await h.testHelpers.assertSuperAdmin({ app: { appId: "test-app" }, auth: first });
});

test("staff identity is rejected before upsertSchoolAdmin can change its password", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "Users/target": { role: "operations_admin", enabled: true }, "schools/A": {} });
  await assert.rejects(h.upsertSchoolAdmin({ app: { appId: "test-app" }, auth: auth(), data: { schoolId: "A", email: "admin@example.test", password: "test-fixture-password", allowPasswordUpdate: true } }), rejectCode("permission-denied"));
  assert.deepEqual(h.authCalls, []);
});

test("server rejects malformed credential payloads before mutating Auth", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "schools/A": {} });
  let calls = 0;
  h.authService.getUserByEmail = async () => { calls++; return { uid: "target" }; };
  for (const patch of [
    { password: 123456789012 }, { password: { secret: "not-a-string" } },
    { password: "x".repeat(129) }, { email: ["admin@example.test"] },
    { email: "invalid" }, { email: "a".repeat(250) + "@example.test" },
    { allowPasswordUpdate: "true" }, { schoolId: "A\n" },
  ]) {
    await assert.rejects(h.upsertSchoolAdmin({ app: { appId: "test-app" }, auth: auth(), data: {
      schoolId: "A", email: "admin@example.test", ...patch,
    } }), rejectCode("invalid-argument"));
  }
  assert.equal(calls, 0);
  assert.deepEqual(h.authCalls, []);
});

test("school administrator password retains whitespace and Unicode at the Auth boundary", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "schools/A": {} });
  const password = "  synthetic-á-secret\t  ";
  let received;
  h.authService.updateUser = async (_uid, patch) => { received = patch.password; };
  await h.upsertSchoolAdmin({ app: { appId: "test-app" }, auth: auth(), data: {
    schoolId: "A", email: "admin@example.test", password, allowPasswordUpdate: true,
  } });
  assert.equal(received, password);
  assert.equal(JSON.stringify([...h.records.values()]).includes(password), false);
});

test("new registro secrets are salted, never stored in plaintext and preserve their exact value", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "schools/A": { active: true } });
  const password = "  synthetic-á-registro  ";
  const request = { auth: auth(), data: { schoolId: "A", password } };
  await h.setSchoolRegistroConfig(request);
  const first = { ...h.records.get("schools/A/config/registro") };
  await h.setSchoolRegistroConfig(request);
  const second = h.records.get("schools/A/config/registro");
  assert.equal(second.password, undefined);
  assert.notEqual(second.passwordSalt, first.passwordSalt);
  assert.notEqual(second.passwordHash, first.passwordHash);
  const rawRequest = { socket: { remoteAddress: "192.0.2.10" } };
  const correct = await h.validateSchoolRegistroAccess({ rawRequest, data: { schoolId: "A", code: password } });
  assert.equal(correct.ok, true);
  assert.equal(correct.customToken, "synthetic-custom-token");
  const issued = h.authCalls.find((call) => call.method === "createCustomToken");
  assert.match(issued.uid, /^reg_[a-f0-9]{32}$/);
  assert.deepEqual(issued.claims, { eduproRegistro: true, registroSchoolId: "A" });
  assert.notEqual(second.accessVersion, first.accessVersion);
  const altered = await h.validateSchoolRegistroAccess({ rawRequest, data: { schoolId: "A", code: password.trim() } });
  assert.equal(altered.ok, false);
  assert.equal(JSON.stringify([...h.records.values()]).includes(password), false);
});

test("legacy registro migration preserves the stored secret and succeeds again after migration", async () => {
  const password = " synthetic-legacy ";
  const h = harness({ "schools/A": { active: true }, "schools/A/config/registro": { password } });
  const request = { rawRequest: { socket: { remoteAddress: "192.0.2.11" } }, data: { schoolId: "A", code: password } };
  assert.equal((await h.validateSchoolRegistroAccess(request)).ok, true);
  assert.equal(h.records.get("schools/A/config/registro").password, undefined);
  assert.equal((await h.validateSchoolRegistroAccess(request)).ok, true);
});

test("malformed verification inputs are rejected before request counters or secrets are read", async () => {
  const h = harness();
  const before = h.records.size;
  for (const code of [123456, {}, [], "x".repeat(129)]) {
    await assert.rejects(h.validateSchoolRegistroAccess({ data: { schoolId: "A", code } }), rejectCode("invalid-argument"));
  }
  await assert.rejects(h.verifyEduProTwoFactorCode({ data: { code: {}, audience: "admin_general" } }), rejectCode("invalid-argument"));
  await assert.rejects(h.precheckTeacherSignup({ data: { schoolId: "A", emailLower: "a@example.test", phoneHash: "x".repeat(64) } }), rejectCode("invalid-argument"));
  assert.equal(h.records.size, before);
});

test("registration callable guards require authentication and configured App Check", async () => {
  const names = ["registerSchoolStudent", "createSchoolRegistroGrade", "uploadSchoolRegistroPhoto", "endSchoolRegistroSession"];
  for (const name of names) {
    const h = harness();
    await assert.rejects(h[name]({ data: { schoolId: "A" } }), rejectCode("unauthenticated"));
    const protectedHarness = harness({}, { enforceAppCheck: true });
    await assert.rejects(protectedHarness[name]({ auth: auth(), data: { schoolId: "A" } }), rejectCode("failed-precondition"));
  }
});

test("invalid registration code cannot issue a token and successful code config rotation revokes the session", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true }, "schools/A": { active: true },
    "schools/A/config/registro": { password: "synthetic-legacy-code" } });
  const rawRequest = { socket: { remoteAddress: "192.0.2.15" } };
  const invalid = await h.validateSchoolRegistroAccess({ rawRequest, data: { schoolId: "A", code: "wrong-code" } });
  assert.equal(invalid.ok, false);
  assert.equal(h.authCalls.some((call) => call.method === "createCustomToken"), false);
  await h.validateSchoolRegistroAccess({ rawRequest, data: { schoolId: "A", code: "synthetic-legacy-code" } });
  const issued = h.authCalls.find((call) => call.method === "createCustomToken");
  const issuedVersion = h.records.get(`registro_sessions/${issued.uid}`).version;
  await h.setSchoolRegistroConfig({ auth: auth(), data: { schoolId: "A", permitirFotoAlumno: false } });
  assert.notEqual(h.records.get("schools/A/config/registro").accessVersion, issuedVersion);
});

test("parallel requests cannot bypass a per-account budget by changing IP", async () => {
  const h = harness();
  const calls = Array.from({ length: 20 }, (_, i) => h.testHelpers.consumeRequestBudget({
    auth: auth(), rawRequest: { socket: { remoteAddress: `192.0.2.${i + 1}` } },
  }, "two-factor-code", 5, 60000));
  const results = await Promise.allSettled(calls);
  assert.equal(results.filter(row => row.status === "fulfilled").length, 5);
  for (const row of results.filter(row => row.status === "rejected")) assert.equal(row.reason.code, "resource-exhausted");
});

test("rotating accounts still consumes the aggregate IP budget; rejection does not prolong it", async () => {
  const h = harness();
  const rawRequest = { socket: { remoteAddress: "192.0.2.22" } };
  for (let i = 0; i < 120; i++) {
    await h.testHelpers.consumeRequestBudget({ auth: auth(`user-${i}`), rawRequest }, "two-factor-code", 1, 60000);
  }
  const aggregate = [...h.records.values()].find(row => row.count === 120);
  const expires = aggregate.expiresAt.toMillis();
  const before = h.records.size;
  await assert.rejects(h.testHelpers.consumeRequestBudget({ auth: auth("another"), rawRequest }, "two-factor-code", 1, 60000), rejectCode("resource-exhausted"));
  assert.equal(h.records.size, before);
  assert.equal(aggregate.expiresAt.toMillis(), expires);
  for (const row of h.records.values()) if (row.expiresAt) row.expiresAt = h.timestamp(Date.now() - 1);
  await h.testHelpers.consumeRequestBudget({ auth: auth("another"), rawRequest }, "two-factor-code", 1, 60000);
});

test("unauthenticated budgets require a resolvable origin; account and IP are not persisted in plaintext", async () => {
  const h = harness();
  await assert.rejects(h.testHelpers.consumeRequestBudget({}, "registro-code"), rejectCode("failed-precondition"));
  await h.testHelpers.consumeRequestBudget({ auth: auth("synthetic-user"), rawRequest: { socket: { remoteAddress: "192.0.2.23" } } }, "two-factor-code");
  const serialized = JSON.stringify([...h.records.entries()]);
  assert.equal(serialized.includes("synthetic-user"), false);
  assert.equal(serialized.includes("192.0.2.23"), false);
});

test("school identity and contact fields are validated before creating school or Auth records", async () => {
  const h = harness({ "users/user": { role: "superadmin", enabled: true } });
  const before = h.records.size;
  for (const patch of [
    { nombre: {} }, { nombre: "x".repeat(201) }, { nombre: "A\nB" },
    { contactName: [] }, { contactEmail: "invalid" }, { contactPhone: "x".repeat(41) },
    { addressLine: "x".repeat(1001) },
  ]) {
    await assert.rejects(h.createSchool({ app: { appId: "test-app" }, auth: auth(), data: {
      nombre: "Escuela sintética", ...patch,
    } }), rejectCode("invalid-argument"));
  }
  assert.equal(h.records.size, before);
  assert.deepEqual(h.authCalls, []);
  // Optional empty metadata remains compatible and human names stay intact.
  const payload = { nombre: "Escuela O'Hara & Niño", contactName: null };
  assert.equal(security.validateAuthInput(payload, {
    nombre: { max: 200, required: true }, contactName: { max: 200, nullable: true },
  }), payload);
});
