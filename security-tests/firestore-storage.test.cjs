'use strict';

// Synthetic fixtures only. Refuse to run against any non-local project/service.
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { before, beforeEach, after, test } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, deleteField, writeBatch, Timestamp, serverTimestamp, query, where, limit, orderBy } = require('firebase/firestore');
const { ref, uploadBytes, getBytes, deleteObject } = require('firebase/storage');

const projectId = 'demo-edupro-security';
// Emulator/runtime faults can otherwise keep the SDK retrying forever,
// including during cleanup. A watchdog failure can never count as a pass.
const watchdog = setTimeout(() => {
  console.error('[security-tests] TIMEOUT after 90 seconds; emulator or SDK did not complete.');
  process.exit(1);
}, 90_000);
function localEndpoint(name, fallback) {
  const value = process.env[name] || fallback;
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(value)) {
    throw new Error(`${name} must point at a loopback emulator`);
  }
  const [host, port] = value.split(':');
  return { host, port: Number(port) };
}
if (process.env.GCLOUD_PROJECT && process.env.GCLOUD_PROJECT !== projectId) {
  throw new Error('These tests are restricted to demo-edupro-security');
}
const now = Timestamp.fromDate(new Date());
let env;
const profile = (uid, role = 'student', schoolId = 'school-a') => ({
  uid, role, teamRole: '', enabled: true, schoolId, schoolIds: [schoolId],
  teacherDocId: role === 'teacher' ? 'teacher-a' : '',
  displayName: 'Synthetic User', updatedAt: now,
});
const membership = (uid, role = 'teacher', enabled = true) => ({
  uid, role, audience: 'teachers', enabled, teacherDocId: 'teacher-a',
  tokens: [], updatedAt: now, lastTokenAt: now,
});
function context(uid, verified = true, email = `${uid}@example.test`) {
  return env.authenticatedContext(uid, { email, email_verified: verified });
}
function db(uid, verified = true, email) { return context(uid, verified, email).firestore(); }
function storage(uid) { return context(uid).storage(); }
const path = (suffix) => `schools/school-a/${suffix}`;
const registroUid = 'reg_00000000000000000000000000000001';
const registroVersion = 'synthetic-access-version-a';
function registroContext(uid = registroUid, extraClaims = {}) {
  return env.authenticatedContext(uid, {
    eduproRegistro: true, registroSchoolId: 'school-a', firebase: { sign_in_provider: 'custom' }, ...extraClaims,
  });
}
const registroSession = () => ({
  schoolId: 'school-a', enabled: true, version: registroVersion,
  expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { ...localEndpoint('FIRESTORE_EMULATOR_HOST', '127.0.0.1:8088'), rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8') },
    storage: { ...localEndpoint('FIREBASE_STORAGE_EMULATOR_HOST', '127.0.0.1:9198'), rules: readFileSync(resolve(__dirname, '../storage.rules'), 'utf8') },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (adminContext) => {
    const adminDb = adminContext.firestore();
    const batch = writeBatch(adminDb);
    const fixtures = {
      'schools/school-a': { active: true, accountStatus: 'active' },
      'schools/school-b': { active: true, accountStatus: 'active' },
      [`registro_sessions/${registroUid}`]: registroSession(),
      [path('config/registro')]: { accessVersion: registroVersion, permitirFotoAlumno: true, permitirEditarEstudiantes: true },
      [path('grados/grade-a')]: { name: 'Grade A', nivel: 'primaria', gradoKey: 'grade-a' },
      'schools/school-b/grados/grade-b': { name: 'Grade B', nivel: 'primaria' },
      [path('public/meta')]: { active: true, accountStatus: 'active' },
      'users/admin-a': profile('admin-a', 'admin'),
      'users/admin-b': profile('admin-b', 'admin', 'school-b'),
      'users/student-a': profile('student-a'),
      'users/teacher-a': profile('teacher-a', 'teacher'),
      'users/outsider': profile('outsider', 'student', 'school-b'),
      'users/new-user': { uid: 'new-user', role: 'student', enabled: true },
      'Users/legacy-user': { uid: 'legacy-user', role: 'student', enabled: true },
      [path('members/admin-a')]: membership('admin-a', 'admin'),
      'schools/school-b/members/admin-b': membership('admin-b', 'admin'),
      [path('members/teacher-a')]: membership('teacher-a'),
      [path('members/disabled-teacher')]: membership('disabled-teacher', 'teacher', false),
      [path('teachers/teacher-a')]: { authUid: 'teacher-a', emailLower: 'teacher-a@example.test', statusLower: 'active', enabled: true, gradeIds: ['grade-a'], subjectIds: ['math'] },
      [path('teachers/pending')]: { authUid: 'pending', emailLower: 'pending@example.test', statusLower: 'pending', enabled: true },
      [path('teacher_directory/pending')]: { authUid: 'pending', emailLower: 'pending@example.test', statusLower: 'pending', enabled: true },
      [path('teachers_uid/teacher-a')]: { schoolId: 'school-a', teacherDocId: 'teacher-a', updatedAt: now },
      [path('teachers_public/outsider')]: { teacherId: 'outsider', emailLower: 'outsider@example.test', statusLower: 'pending' },
      [path('teachers_public/teacher-a')]: { teacherId: 'teacher-a', emailLower: 'teacher-a@example.test', statusLower: 'active', name: 'Synthetic teacher' },
      [path('alumnos_login/student-a')]: { enabled: true, schoolId: 'school-a', studentIds: ['student-record-a'], selectedAlumnoId: 'student-record-a', updatedAt: now },
      [path('alumnos_login/parent@example.test')]: { enabled: true, schoolId: 'school-a', studentIds: ['student-record-a'] },
      [path('alumnos/student-record-a')]: { enabled: true, authUid: 'student-a', emailLower: 'student-a@example.test', accesosEmails: ['parent@example.test'], gradoKey: 'grade-a', grado: 'Grade A' },
      [path('alumnos/student-record-a2')]: { enabled: true, authUid: 'student-a2', emailLower: 'student-a2@example.test', accesosEmails: [], gradoKey: 'grade-a', grado: 'Grade A' },
      [path('alumnos/student-record-b')]: { enabled: true, authUid: 'another-student', emailLower: 'another@example.test', accesosEmails: [], gradoKey: 'grade-b', grado: 'Grade B' },
      [path('estudiantes/student-record-b')]: { name: 'Synthetic other student', schoolId: 'school-a' },
      [path('tareas_docentes/task-a')]: { schoolId: 'school-a', createdByUid: 'teacher-a', gradeId: 'grade-a' },
      [path('appointments/admin-only')]: { audience: 'adminOnly', createdByUid: 'admin-a', canceled: false },
      'alumnos_global/student-b': { schoolId: 'school-b', name: 'Synthetic B' },
      'estudiantes_global/student-b': { schoolId: 'school-b', name: 'Synthetic B' },
    };
    for (const [documentPath, data] of Object.entries(fixtures)) batch.set(doc(adminDb, documentPath), data);
    await batch.commit();
  });
});
after(async () => {
  if (env) await env.cleanup();
  clearTimeout(watchdog);
});

test('anonymous requests cannot read private school or student records', async () => {
  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, 'schools/school-a')));
  await assertFails(getDoc(doc(anonymous, path('alumnos/student-record-a'))));
});

test('limited registration can read its school grades and students for the form, roster and duplicate checks', async () => {
  const client = registroContext().firestore();
  await assertSucceeds(getDoc(doc(client, path('grados/grade-a'))));
  await assertSucceeds(getDocs(query(collection(client, path('grados')), orderBy('name'))));
  await assertSucceeds(getDoc(doc(client, path('alumnos/student-record-a'))));
  await assertSucceeds(getDocs(query(collection(client, path('alumnos')), where('grado', '==', 'Grade A'))));
  await assertSucceeds(getDocs(query(collection(client, path('alumnos')),
    where('matricula', '==', 'SYNTHETIC-001'), where('gradoKey', '==', 'grade-a'),
    where('tanda', '==', 'manana'), where('nivel', '==', 'primaria'), limit(1))));
  await assertSucceeds(getDocs(query(collection(client, path('alumnos')),
    where('nombresKey', '==', 'synthetic'), where('apellidosKey', '==', 'example'), limit(8))));
  await assertFails(getDoc(doc(client, 'schools/school-a')));
  await assertFails(getDoc(doc(client, path('public/meta'))));
  await assertFails(getDocs(collection(client, path('subjects'))));
  await assertFails(getDocs(collection(client, 'schools/school-b/grados')));
  await assertFails(getDoc(doc(client, 'schools/school-b/alumnos/student-record-b')));
  await assertFails(getDocs(collection(client, path('alumnos/student-record-a/tutores'))));
});

test('registration reads require a genuine school-scoped token and an enabled, current server session', async () => {
  const target = (client) => doc(client, path('alumnos/student-record-a'));
  for (const client of [
    registroContext(registroUid, { eduproRegistro: false }).firestore(),
    registroContext(registroUid, { registroSchoolId: 'school-b' }).firestore(),
    registroContext(registroUid, { firebase: { sign_in_provider: 'google.com' } }).firestore(),
    registroContext('outsider').firestore(),
    env.authenticatedContext(registroUid).firestore(),
  ]) await assertFails(getDoc(target(client)));
  const client = registroContext().firestore();
  for (const patch of [
    { enabled: false }, { enabled: 'true' }, { schoolId: 'school-b' },
    { expiresAt: Timestamp.fromMillis(Date.now() - 60_000) }, { expiresAt: 'future' },
    { expiresAt: Timestamp.fromMillis(Date.now() + 3 * 60 * 60 * 1000) },
    { version: '' }, { version: 'different-version' },
  ]) {
    await env.withSecurityRulesDisabled((admin) => setDoc(doc(admin.firestore(), `registro_sessions/${registroUid}`), { ...registroSession(), ...patch }));
    await assertFails(getDoc(target(client)));
    await assertFails(getDocs(collection(client, path('grados'))));
  }
  await env.withSecurityRulesDisabled((admin) => deleteDoc(doc(admin.firestore(), `registro_sessions/${registroUid}`)));
  await assertFails(getDoc(target(client)));
});

test('rotated or missing access version revokes reads, and disabled schools fail closed', async () => {
  const client = registroContext().firestore();
  const check = () => getDoc(doc(client, path('alumnos/student-record-a')));
  for (const accessVersion of ['rotated-version', '', null]) {
    await env.withSecurityRulesDisabled((admin) => updateDoc(doc(admin.firestore(), path('config/registro')), { accessVersion }));
    await assertFails(check());
    await assertFails(getDocs(collection(client, path('grados'))));
  }
  await env.withSecurityRulesDisabled(async (admin) => {
    await updateDoc(doc(admin.firestore(), path('config/registro')), { accessVersion: deleteField() });
  });
  await assertFails(check());
  await env.withSecurityRulesDisabled((admin) => updateDoc(doc(admin.firestore(), path('config/registro')), { accessVersion: registroVersion }));
  for (const school of [
    { active: false, accountStatus: 'active' }, { active: true, enabled: false, accountStatus: 'active' },
    { active: true, accountStatus: 'suspendida' }, { active: true, accountStatus: 'blocked' },
    { active: true, accountStatus: 'vencida' }, { active: true, accountStatus: 'unknown' },
    { active: true, status: 'suspendida' }, { active: true, accountStatus: null, status: 'blocked' },
    {},
  ]) {
    await env.withSecurityRulesDisabled((admin) => setDoc(doc(admin.firestore(), 'schools/school-a'), school));
    await assertFails(check());
  }
  for (const school of [{ active: true }, { active: true, accountStatus: 'activa' }, { active: true, accountStatus: 'activo' }]) {
    await env.withSecurityRulesDisabled((admin) => setDoc(doc(admin.firestore(), 'schools/school-a'), school));
    await assertSucceeds(check());
  }
  await env.withSecurityRulesDisabled((admin) => deleteDoc(doc(admin.firestore(), 'schools/school-a')));
  await assertFails(check());
});

test('registration cannot inspect secrets, identity records or turn itself into an administrator', async () => {
  const client = registroContext().firestore();
  for (const documentPath of [
    `registro_sessions/${registroUid}`, path('config/registro'), `users/${registroUid}`,
    `Users/${registroUid}`, path(`members/${registroUid}`), `EquipoEduPro/${registroUid}`,
    'users/admin-a', path('alumnos_login/student-a'), 'alumnos_global/student-b',
  ]) {
    await assertFails(getDoc(doc(client, documentPath)));
    await assertFails(setDoc(doc(client, documentPath), { enabled: true, role: 'admin', schoolId: 'school-a' }));
  }
  await assertFails(setDoc(doc(client, `users/${registroUid}`), {
    uid: registroUid, role: 'student', schoolId: 'school-a', enabled: true,
  }));
  await assertFails(setDoc(doc(client, path('grados/forged')), { name: 'Forged' }));
  await assertFails(updateDoc(doc(client, path('alumnos/student-record-a')), { authUid: registroUid }));
  await assertFails(deleteDoc(doc(client, path('alumnos/student-record-a'))));
  // Even a stale/spoofed backing identity must not upgrade this token class.
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), `users/${registroUid}`), profile(registroUid, 'super_admin'));
    await setDoc(doc(admin.firestore(), path(`members/${registroUid}`)), membership(registroUid, 'admin'));
  });
  await assertFails(getDocs(collection(client, 'schools')));
  await assertFails(updateDoc(doc(client, path('config/registro')), { accessVersion: 'forged' }));
  await assertFails(setDoc(doc(client, path('alumnos/forged')), { schoolId: 'school-a' }));
});

test('the original client registration batch denies anonymous and registrar writes but preserves school admin access', async () => {
  const commit = (client) => {
    const batch = writeBatch(client);
    const student = { schoolId: 'school-a', nombres: 'Synthetic', apellidos: 'Example', accesosEmails: ['synthetic-parent@example.test'] };
    batch.set(doc(client, path('alumnos/synthetic-batch-student')), student);
    batch.set(doc(client, 'alumnos_global/synthetic-batch-student'), student);
    batch.set(doc(client, path('alumnos_login/synthetic-parent@example.test')), {
      schoolId: 'school-a', enabled: true, studentIds: ['synthetic-batch-student'],
    });
    return batch.commit();
  };
  await assertFails(commit(env.unauthenticatedContext().firestore()));
  await assertFails(commit(registroContext().firestore()));
  await assertSucceeds(commit(db('admin-a')));
  await assertSucceeds(getDoc(doc(db('admin-a'), path('alumnos/synthetic-batch-student'))));
});

test('registration config preserves admin flag edits but reserves access-version and credential rotation for the server', async () => {
  const target = doc(db('admin-a'), path('config/registro'));
  await assertSucceeds(updateDoc(target, { permitirFotoAlumno: false }));
  await assertSucceeds(setDoc(target, { permitirFotoAlumno: true }, { merge: true }));
  await assertFails(updateDoc(target, { accessVersion: 'forged' }));
  await assertFails(updateDoc(target, { accessVersion: deleteField() }));
  await assertFails(updateDoc(target, { passwordHash: 'a'.repeat(64), passwordSalt: 'b'.repeat(32), passwordAlgo: 'scrypt_v1' }));
  await assertFails(updateDoc(target, { arbitraryGrant: true }));
  await assertFails(updateDoc(target, { permitirFotoAlumno: 'true' }));
});

test('derived catalog and readiness reject all client roles including the superadmin', async () => {
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'team_school_catalog/school-a'), {
      schemaVersion: 1, status: 'active', searchTokens: ['school'], provinceKey: 'azua', hasCoordinates: true,
    });
    await setDoc(doc(admin.firestore(), 'team_catalog_meta/state'), { ready: true, schemaVersion: 1 });
    for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
      await setDoc(doc(admin.firestore(), `users/${role}`), { enabled: true, role: 'superadmin', teamRole: role });
      await setDoc(doc(admin.firestore(), `EquipoEduPro/${role}`), { enabled: true, teamRole: role });
    }
  });
  for (const client of [env.unauthenticatedContext().firestore(), db('admin-a'), db('teacher-a'), db('student-a'),
    ...['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin'].map((role) => db(role))]) {
    await assertFails(getDoc(doc(client, 'team_school_catalog/school-a')));
    await assertFails(getDocs(collection(client, 'team_school_catalog')));
    await assertFails(setDoc(doc(client, 'team_school_catalog/forged'), { status: 'active' }));
    await assertFails(getDoc(doc(client, 'team_catalog_meta/state')));
    await assertFails(updateDoc(doc(client, 'team_catalog_meta/state'), { ready: false }));
  }
});

test('internal roles cannot read raw school catalogs, students or payments except the superadmin', async () => {
  for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), `users/${role}`), { enabled: true, role: 'superadmin', teamRole: role });
      await setDoc(doc(admin.firestore(), `EquipoEduPro/${role}`), { enabled: true, teamRole: role });
    });
    const client = db(role);
    const check = role === 'super_admin' ? assertSucceeds : assertFails;
    await check(getDocs(collection(client, 'schools')));
    await check(getDoc(doc(client, path('alumnos/student-record-a'))));
    await check(getDocs(collection(client, path('payments'))));
    // Operational catalog/creation/location changes must use the authorized
    // callables, never bypass their restrictions with raw Firestore writes.
    await check(setDoc(doc(client, `schools/direct-create-${role}`), { name: 'Synthetic school', active: true }));
    await check(updateDoc(doc(client, 'schools/school-a'), { 'location.latitude': 18.5, 'location.longitude': -69.9 }));
    await assertFails(updateDoc(doc(client, 'schools/school-a'), { adminsLimit: 99 }));
    await check(updateDoc(doc(client, `users/${role}`), { teamRole: 'super_admin' }));
    await assertSucceeds(getDoc(doc(client, `EquipoEduPro/${role}`)));
    if (role !== 'super_admin') {
      await assertFails(getDocs(collection(client, 'EquipoEduPro')));
      await assertFails(setDoc(doc(client, 'EquipoValMich/other'), { enabled: true, role: 'superadmin' }));
      await assertSucceeds(updateDoc(doc(client, `EquipoEduPro/${role}`), {
        lastLoginAt: serverTimestamp(), updatedAt: serverTimestamp(), lastLoginContext: { platform: 'web' },
      }));
      await assertFails(updateDoc(doc(client, `EquipoEduPro/${role}`), { enabled: true, teamRole: 'superadmin' }));
      await assertFails(uploadBytes(ref(storage(role), 'schools/school-a/private/blocked.pdf'), new Uint8Array([1]), { contentType: 'application/pdf' }));
    }
  }
});

test('plan and limit updates require the audited callable even for a superadmin', async () => {
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users/plan-owner'), { enabled: true, role: 'super_admin' });
  });
  const client = db('plan-owner');
  const school = doc(client, 'schools/school-a');
  for (const patch of [
    { planTier: 'premium' }, { adminsLimit: 5 }, { teachersLimit: 60 },
    { studentsLimit: 900 }, { planLimits: { admins: 5, teachers: 60, students: 900 } },
    { maxUsers: 965 },
  ]) {
    await assertFails(updateDoc(school, patch));
    await assertFails(setDoc(school, patch, { merge: true }));
  }
  await assertFails(updateDoc(school, { 'planLimits.students': 900 }));
  await assertSucceeds(updateDoc(school, { name: 'Synthetic name change' }));
  await assertSucceeds(getDoc(school));
});

test('only superadmin can atomically change staff role and disable all identity copies', async () => {
  await env.withSecurityRulesDisabled(async (admin) => {
    const adminDb = admin.firestore();
    await setDoc(doc(adminDb, 'users/owner'), { enabled: true, role: 'superadmin' });
    for (const name of ['users', 'Users', 'EquipoEduPro', 'EquipoValMich']) {
      await setDoc(doc(adminDb, `${name}/staff`), { enabled: true, role: 'support_onboarding', teamRole: 'support_onboarding' });
    }
  });
  const change = (client, patch) => {
    const batch = writeBatch(client);
    for (const name of ['users', 'Users', 'EquipoEduPro', 'EquipoValMich']) {
      batch.set(doc(client, `${name}/staff`), patch, { merge: true });
    }
    return batch.commit();
  };
  const rolePatch = {
    role: 'operations_admin', teamRole: 'operations_admin',
    teamRoleLabel: 'Administrador operativo', teamRoleSummary: 'Synthetic role summary',
    updatedAt: serverTimestamp(),
  };
  await assertFails(change(db('staff'), rolePatch));
  await assertSucceeds(change(db('owner'), rolePatch));
  for (const name of ['users', 'Users', 'EquipoEduPro', 'EquipoValMich']) {
    const saved = await getDoc(doc(db('owner'), `${name}/staff`));
    if (saved.data().teamRole !== 'operations_admin') throw new Error(`Role was not saved in ${name}`);
  }
  await assertFails(updateDoc(doc(db('staff'), 'users/staff'), { teamRole: 'super_admin', role: 'super_admin' }));
  await assertSucceeds(change(db('owner'), { enabled: false, updatedAt: serverTimestamp() }));
  await assertFails(change(db('staff'), { enabled: true, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('staff'), 'EquipoEduPro/staff'), {
    lastLoginAt: serverTimestamp(), updatedAt: serverTimestamp(), lastLoginContext: { platform: 'web' },
  }));
});

test('derived operational counters are server-only, even for a superadmin', async () => {
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users/metrics-owner'), { enabled: true, role: 'super_admin' });
    for (const collection of ['teachers', 'alumnos', 'members', 'subjects', 'planificaciones_anuales']) {
      await setDoc(doc(admin.firestore(), `schools/school-a/_operational_${collection}/record`), { active: true });
    }
  });
  for (const uid of ['metrics-owner', 'admin-a', 'teacher-a', 'outsider']) {
    for (const collection of ['teachers', 'alumnos', 'members', 'subjects', 'planificaciones_anuales']) {
      const target = doc(db(uid), `schools/school-a/_operational_${collection}/record`);
      await assertFails(getDoc(target));
      await assertFails(updateDoc(target, { active: false }));
      await assertFails(setDoc(target, { forged: true }));
    }
  }
});

test('canonical role precedence and explicit revocation defeat stale superadmin identities and claims', async () => {
  const identity = env.authenticatedContext('conflict', { superadmin: true, role: 'superadmin', email: 'conflict@example.test' }).firestore();
  const cases = [
    { role: 'superadmin', enabled: false },
    { role: 'superadmin' },
    { role: 'superadmin', teamRole: 'billing_admin', enabled: true },
    { role: 'superadmin', teamRole: '', enabled: true },
  ];
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'Users/conflict'), { role: 'superadmin', enabled: true });
    await setDoc(doc(admin.firestore(), 'EquipoEduPro/conflict'), { role: 'superadmin', enabled: true });
  });
  for (const value of cases) {
    await env.withSecurityRulesDisabled((admin) => setDoc(doc(admin.firestore(), 'users/conflict'), value));
    await assertFails(getDocs(collection(identity, 'schools')));
    await assertFails(updateDoc(doc(identity, 'schools/school-a'), { name: 'unauthorized' }));
  }
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users/conflict'), { role: 'super_admin', enabled: true });
    await setDoc(doc(admin.firestore(), 'EquipoEduPro/conflict'), { enabled: false });
  });
  await assertFails(getDocs(collection(identity, 'schools')));
});

test('legacy superadmin alias and team-only identity retain access; missing own team document can be read', async () => {
  await env.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users/primary'), { role: 'superadmin', enabled: true });
    await setDoc(doc(admin.firestore(), 'EquipoEduPro/team-only'), { teamRole: 'super_admin', enabled: true });
    await setDoc(doc(admin.firestore(), 'EquipoValMich/legacy-team'), { teamRole: 'super_admin', enabled: true });
  });
  for (const uid of ['primary', 'team-only', 'legacy-team']) {
    await assertSucceeds(getDocs(collection(db(uid), 'schools')));
  }
  await assertSucceeds(getDoc(doc(db('new-user'), 'EquipoEduPro/new-user')));
  await assertFails(setDoc(doc(db('new-user'), 'EquipoEduPro/new-user'), { enabled: true, teamRole: 'super_admin' }));
});
test('legitimate profile updates succeed but adding or deleting authorization fields fails', async () => {
  await assertSucceeds(updateDoc(doc(db('new-user'), 'users/new-user'), { displayName: 'Updated synthetic name' }));
  await assertFails(updateDoc(doc(db('new-user'), 'users/new-user'), { teamRole: 'superadmin' }));
  await assertFails(updateDoc(doc(db('new-user'), 'users/new-user'), { enabled: deleteField() }));
  await assertFails(updateDoc(doc(db('legacy-user'), 'Users/legacy-user'), { teamRole: 'superadmin' }));
});
test('school administrator can read own school but not another school', async () => {
  await assertSucceeds(getDoc(doc(db('admin-a'), 'schools/school-a')));
  await assertFails(getDoc(doc(db('admin-a'), 'schools/school-b')));
});
test('school administrator cannot take over another school global student index', async () => {
  for (const index of ['alumnos_global', 'estudiantes_global']) {
    console.info(`[authorization-case] ${index}: reject foreign administrator`);
    await assertFails(updateDoc(doc(db('admin-a'), `${index}/student-b`), { schoolId: 'school-a', name: 'Hijacked' }));
    console.info(`[authorization-case] ${index}: permit owning administrator`);
    await assertSucceeds(updateDoc(doc(db('admin-b'), `${index}/student-b`), { name: 'Authorized edit' }));
  }
});
test('pending public directory records do not confer teacher permissions', async () => {
  await assertFails(getDoc(doc(db('outsider'), path('alumnos/student-record-a'))));
  await assertFails(getDocs(collection(db('outsider'), path('alumnos'))));
});
test('pending teacher cannot bootstrap a membership or UID mapping', async () => {
  await assertFails(setDoc(doc(db('pending'), path('members/pending')), membership('pending')));
  await assertFails(setDoc(doc(db('pending'), path('teachers_uid/pending')), { schoolId: 'school-a', teacherDocId: 'pending', updatedAt: now }));
});
test('approved teacher can bootstrap a membership through verified identity', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    // Initial approved registration has no authUid until first verified login.
    await setDoc(doc(c.firestore(), path('teacher_directory/approved')), { emailLower: 'approved@example.test', statusLower: 'active', enabled: true });
  });
  await assertSucceeds(setDoc(doc(db('approved'), path('members/approved')), { ...membership('approved'), teacherDocId: 'approved' }));
});
test('disabled teacher cannot re-enable their own membership', async () => {
  await assertFails(updateDoc(doc(db('disabled-teacher'), path('members/disabled-teacher')), { enabled: true }));
  await assertFails(getDoc(doc(db('disabled-teacher'), path('tareas_docentes/task-a'))));
});
test('school administrator can revoke a teacher membership', async () => {
  await assertSucceeds(updateDoc(doc(db('admin-a'), path('members/teacher-a')), { enabled: false, updatedAt: now }));
  await assertFails(getDoc(doc(db('teacher-a'), path('tareas_docentes/task-a'))));
});
test('student can read own linked record but not another student or the legacy roster', async () => {
  await assertSucceeds(getDoc(doc(db('student-a'), path('alumnos/student-record-a'))));
  await assertFails(getDoc(doc(db('student-a'), path('alumnos/student-record-b'))));
  await assertFails(getDocs(collection(db('student-a'), path('estudiantes'))));
});
test('unverified email cannot impersonate a parent; verified parent retains access', async () => {
  const student = path('alumnos/student-record-a');
  await assertFails(getDoc(doc(db('email-attacker', false, 'parent@example.test'), student)));
  await assertSucceeds(getDoc(doc(db('verified-parent', true, 'parent@example.test'), student)));
});
test('teacher directory cannot be enumerated by an unrelated account', async () => {
  await assertFails(getDocs(collection(db('outsider'), path('teachers_public'))));
  await assertSucceeds(getDoc(doc(db('teacher-a'), path('teachers_public/teacher-a'))));
});
test('student cannot add arbitrary linked students to login metadata', async () => {
  await assertFails(updateDoc(doc(db('student-a'), path('alumnos_login/student-a')), { studentIds: ['student-record-a', 'student-record-b'] }));
  await assertFails(updateDoc(doc(db('student-a'), path('alumnos_login/student-a')), { authUid: 'another-student' }));
});
test('student submissions accept answers but reject self-awarded grades', async () => {
  const target = doc(db('student-a'), path('tareas_docentes/task-a/submissions/student-record-a'));
  await assertFails(setDoc(target, { studentId: 'student-record-a', finalPoints: 100, gradeApproved: true }));
  await assertSucceeds(setDoc(target, { studentId: 'student-record-a', studentName: 'Synthetic student', answers: [], attachments: [], submittedAt: now, updatedAt: now, status: 'submitted' }));
  await assertFails(updateDoc(target, { finalPoints: 100 }));
});
test('calendar audiences are enforced for teacher reads and cancellation', async () => {
  await assertFails(getDoc(doc(db('teacher-a'), path('appointments/admin-only'))));
  await assertFails(updateDoc(doc(db('teacher-a'), path('appointments/admin-only')), { canceled: true }));
  await assertSucceeds(getDoc(doc(db('admin-a'), path('appointments/admin-only'))));
});
test('grades require assigned subject and preserve student identity', async () => {
  const target = doc(db('teacher-a'), path('calificaciones_v2/grade-record'));
  const grade = { schoolId: 'school-a', year: new Date().getUTCFullYear(), studentId: 'student-record-a', gradeId: 'grade-a', subjectId: 'math', updatedByUid: 'teacher-a', updatedByRole: 'teacher', updatedAt: now };
  console.info('[authorization-case] grades: reject unassigned subject');
  await assertFails(setDoc(target, { ...grade, subjectId: 'unassigned-subject' }));
  console.info('[authorization-case] grades: reject student enrolled in a different grade');
  await assertFails(setDoc(target, { ...grade, studentId: 'student-record-b' }));
  console.info('[authorization-case] grades: permit legitimate create');
  await assertSucceeds(setDoc(target, grade));
  console.info('[authorization-case] grades: permit legitimate update');
  await assertSucceeds(updateDoc(target, { updatedAt: Timestamp.now() }));
  console.info('[authorization-case] grades: reject student substitution within the same grade');
  await assertFails(updateDoc(target, { studentId: 'student-record-a2' }));
  await assertFails(updateDoc(target, { studentId: 'student-record-b' }));
});
test('security collections are inaccessible from client SDKs', async () => {
  for (const documentPath of ['security_2fa_users/admin-a', 'security_request_limits/arbitrary']) {
    await assertFails(getDoc(doc(db('admin-a'), documentPath)));
    await assertFails(setDoc(doc(db('admin-a'), documentPath), { value: 'synthetic' }));
  }
});

test('Storage accepts own teacher image and rejects foreign-school access', async () => {
  const image = ref(storage('teacher-a'), path('teachers/teacher-a/avatar.png'));
  await assertSucceeds(uploadBytes(image, Buffer.from('synthetic-image'), { contentType: 'image/png' }));
  await assertSucceeds(getBytes(image));
  await assertFails(getBytes(ref(storage('outsider'), path('teachers/teacher-a/avatar.png'))));
  await assertFails(uploadBytes(ref(storage('teacher-a'), 'schools/school-b/teachers/teacher-a/avatar.png'), Buffer.from('synthetic'), { contentType: 'image/png' }));
});
test('Storage rejects files with a disallowed MIME type or excessive size', async () => {
  await assertFails(uploadBytes(ref(storage('teacher-a'), path('teachers/teacher-a/file.html')), Buffer.from('<html>synthetic</html>'), { contentType: 'text/html' }));
  await assertFails(uploadBytes(ref(storage('teacher-a'), path('teachers/teacher-a/oversize.png')), Buffer.alloc(5 * 1024 * 1024), { contentType: 'image/png' }));
});
test('Storage chat attachments cannot be replaced by another member', async () => {
  const attachment = path('chat_uploads/synthetic-attachment.pdf');
  await assertSucceeds(uploadBytes(ref(storage('teacher-a'), attachment), Buffer.from('synthetic-pdf'), { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(ref(storage('student-a'), attachment)));
  await assertFails(uploadBytes(ref(storage('student-a'), attachment), Buffer.from('replacement'), { contentType: 'application/pdf' }));
});

test('student profile photos are readable by the school admin, linked UID or verified authorized email only', async () => {
  const own = path('alumnos/student-record-a/profile.png');
  const other = path('alumnos/student-record-b/profile.jpg');
  await assertSucceeds(uploadBytes(ref(storage('admin-a'), own), Buffer.from('synthetic-png'), { contentType: 'image/png' }));
  await assertSucceeds(uploadBytes(ref(storage('admin-a'), other), Buffer.from('synthetic-jpeg'), { contentType: 'image/jpeg' }));
  await assertSucceeds(getBytes(ref(storage('admin-a'), own)));
  await assertSucceeds(getBytes(ref(storage('student-a'), own)));
  const verifiedParent = context('verified-parent', true, 'parent@example.test').storage();
  const unverifiedParent = context('unverified-parent', false, 'parent@example.test').storage();
  await assertSucceeds(getBytes(ref(verifiedParent, own)));
  await assertFails(getBytes(ref(unverifiedParent, own)));
  await assertFails(getBytes(ref(verifiedParent, other)));
  await assertFails(getBytes(ref(storage('student-a'), other)));
  await assertFails(getBytes(ref(storage('teacher-a'), own)));
  await assertFails(getBytes(ref(storage('admin-b'), own)));
  await assertFails(getBytes(ref(storage('outsider'), own)));
  await assertFails(getBytes(ref(registroContext().storage(), own)));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), own)));
});

test('registration photo upload must use the server; client upload, overwrite, deletion and cross-school paths stay denied', async () => {
  const registrarStorage = registroContext().storage();
  const photoId = 'SyntheticPhotoId0001';
  const png = path(`alumnos/${photoId}/profile.png`);
  const metadata = { contentType: 'image/png', customMetadata: { registroUid } };
  await assertFails(uploadBytes(ref(registrarStorage, png), Buffer.from('synthetic-png'), metadata));
  await assertFails(uploadBytes(ref(registrarStorage, path(`alumnos/${photoId}/profile.jpg`)), Buffer.from('synthetic-jpeg'), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(registrarStorage, `schools/school-b/alumnos/${photoId}/profile.png`), Buffer.from('synthetic-png'), metadata));
  await assertSucceeds(uploadBytes(ref(storage('admin-a'), png), Buffer.from('synthetic-admin-png'), { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(registrarStorage, png), Buffer.from('synthetic-overwrite'), metadata));
  await assertFails(deleteObject(ref(registrarStorage, png)));
  await assertFails(uploadBytes(ref(storage('student-a'), png), Buffer.from('synthetic-overwrite'), { contentType: 'image/png' }));
  await assertFails(deleteObject(ref(storage('student-a'), png)));
});

test('admin profile management requires matching jpeg/png filenames, positive size under 5 MiB and owning school', async () => {
  const target = (fileName) => ref(storage('admin-a'), path(`alumnos/synthetic-profile/${fileName}`));
  await assertSucceeds(uploadBytes(target('profile.png'), Buffer.from('synthetic-png'), { contentType: 'image/png' }));
  await assertSucceeds(uploadBytes(target('profile.jpg'), Buffer.from('synthetic-jpeg'), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(target('profile.png'), Buffer.from('synthetic-jpeg'), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(target('profile.jpg'), Buffer.from('synthetic-png'), { contentType: 'image/png' }));
  await assertFails(uploadBytes(target('profile.png'), Buffer.from('<html>synthetic</html>'), { contentType: 'text/html' }));
  await assertFails(uploadBytes(target('profile.gif'), Buffer.from('synthetic-gif'), { contentType: 'image/gif' }));
  await assertFails(uploadBytes(target('profile.png'), Buffer.alloc(0), { contentType: 'image/png' }));
  await assertFails(uploadBytes(target('profile.png'), Buffer.alloc(5 * 1024 * 1024), { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(storage('admin-b'), path('alumnos/synthetic-profile/profile.png')), Buffer.from('synthetic-png'), { contentType: 'image/png' }));
  await assertSucceeds(deleteObject(target('profile.png')));
});
