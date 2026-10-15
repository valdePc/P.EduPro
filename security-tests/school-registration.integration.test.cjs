'use strict';

const assert = require('node:assert/strict');
const { before, beforeEach, after, test } = require('node:test');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { createRequire } = require('node:module');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithCustomToken, getIdTokenResult, signOut } = require('firebase/auth');
const { getFirestore, connectFirestoreEmulator, getDocFromServer, doc } = require('firebase/firestore');
const { getStorage, connectStorageEmulator, ref, getBytes } = require('firebase/storage');

const projectId = 'demo-edupro-security';
const bucketName = `${projectId}.appspot.com`;
function endpoint(name) {
  const address = process.env[name];
  if (!address || !/^(127\.0\.0\.1|localhost):\d+$/u.test(address)) {
    throw new Error(`${name} must explicitly point at a loopback emulator.`);
  }
  const [host, portString] = address.split(':');
  const port = Number(portString);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error(`Invalid emulator port for ${name}.`);
  return { address, host, port };
}
// All endpoints and project selections are checked before SDK initialization
// or any request. There is deliberately no fallback to deployed services.
const authEndpoint = endpoint('FIREBASE_AUTH_EMULATOR_HOST');
const firestoreEndpoint = endpoint('FIRESTORE_EMULATOR_HOST');
const storageEndpoint = endpoint('FIREBASE_STORAGE_EMULATOR_HOST');
for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
  if (process.env[name] && process.env[name] !== projectId) throw new Error('Only demo-edupro-security is permitted.');
}
if (process.env.FIREBASE_CONFIG) {
  const selected = JSON.parse(process.env.FIREBASE_CONFIG).projectId;
  if (selected && selected !== projectId) throw new Error('FIREBASE_CONFIG selected a different project.');
}

// Use exactly the Admin SDK installed for the deployed Functions module.
const functionsRequire = createRequire(resolve(__dirname, '../functions/index.js'));
const admin = functionsRequire('firebase-admin');
const { HttpsError } = functionsRequire('firebase-functions/v2/https');
const { createSchoolRegistration, SESSION_DURATION_MS } = require('../functions/school_registration');
const clients = [];
let env, adminApp, db, service, serial = 0;
const watchdog = setTimeout(() => {
  console.error('[registration-integration] Timeout: local emulators or SDK did not complete.');
  process.exit(1);
}, 120_000);
const schoolId = 'synthetic-school-a';
const otherSchoolId = 'synthetic-school-b';
const gradeId = 'synthetic-grade';
const id = (letter = 'A') => letter.repeat(20);
const reject = (code) => (error) => error.code === code;
const dbDenied = (error) => error.code === 'permission-denied';
const storageDenied = (error) => error.code === 'storage/unauthorized';

async function client() {
  const app = initializeApp({ projectId, apiKey: 'demo-emulator-key', authDomain: `${projectId}.firebaseapp.com`,
    storageBucket: bucketName }, `registration-emulator-client-${++serial}`);
  clients.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${authEndpoint.address}`, { disableWarnings: true });
  const firestore = getFirestore(app);
  connectFirestoreEmulator(firestore, firestoreEndpoint.host, firestoreEndpoint.port);
  const storage = getStorage(app);
  connectStorageEmulator(storage, storageEndpoint.host, storageEndpoint.port);
  return { app, auth, firestore, storage };
}

async function registrar(previous) {
  const config = (await db.doc(`schools/${schoolId}/config/registro`).get()).data();
  const issued = await service.issueSession({ schoolId, expectedConfig: config, previousAuth: previous?.requestAuth });
  const current = previous || await client();
  await signInWithCustomToken(current.auth, issued.customToken);
  const decoded = await getIdTokenResult(current.auth.currentUser, true);
  current.requestAuth = { uid: current.auth.currentUser.uid, token: decoded.claims };
  current.expiresAtMs = issued.expiresAtMs;
  return current;
}

function student(changes = {}) {
  return { nombres: 'Persona Sintética', apellidos: 'Prueba', matricula: '12', nivel: 'primaria', gradoId: gradeId,
    tanda: 'Mañana', fechaNacimientoMillis: Date.UTC(2015, 2, 8, 4), sexo: 'femenino', status: 'activo',
    tutor: { nombre: 'Tutor Sintético', parentesco: 'Tutor', telefono: '8090000000' },
    emergencia: { nombre: '', telefono: '' }, accesos: [{ email: 'tutor@example.test', usuario: 'tutor' }], ...changes };
}
const payload = (changes = {}, studentId = id()) => ({ schoolId, studentId, student: student(changes) });

before(async () => {
  env = await initializeTestEnvironment({ projectId,
    firestore: { host: firestoreEndpoint.host, port: firestoreEndpoint.port,
      rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8') },
    storage: { host: storageEndpoint.host, port: storageEndpoint.port,
      rules: readFileSync(resolve(__dirname, '../storage.rules'), 'utf8') },
  });
  adminApp = admin.initializeApp({ projectId, storageBucket: bucketName }, 'registration-integration-admin');
  db = admin.firestore(adminApp);
  service = createSchoolRegistration({ db, authService: admin.auth(adminApp), firestore: admin.firestore,
    HttpsError, getBucket: () => admin.storage(adminApp).bucket(bucketName) });
});

beforeEach(async () => {
  await Promise.all([env.clearFirestore(), env.clearStorage()]);
  const clearedAuth = await fetch(`http://${authEndpoint.address}/emulator/v1/projects/${projectId}/accounts`, {
    method: 'DELETE', signal: AbortSignal.timeout(10_000),
  });
  assert.equal(clearedAuth.status, 200, 'Only the local demo Auth emulator is cleared.');
  const batch = db.batch();
  batch.set(db.doc(`schools/${schoolId}`), { active: true, accountStatus: 'active', studentsLimit: 100 });
  batch.set(db.doc(`schools/${otherSchoolId}`), { active: true, accountStatus: 'active' });
  batch.set(db.doc(`schools/${schoolId}/config/registro`), { accessVersion: 'synthetic-version-one', permitirFotoAlumno: true });
  batch.set(db.doc(`schools/${schoolId}/grados/${gradeId}`), { name: '1 de Primaria', gradoKey: '1 de primaria', nivel: 'primaria' });
  batch.set(db.doc(`schools/${otherSchoolId}/grados/${gradeId}`), { name: '1 de Primaria', nivel: 'primaria' });
  await batch.commit();
});

after(async () => {
  await Promise.allSettled(clients.map(async (app) => { await signOut(getAuth(app)); await deleteApp(app); }));
  if (env) await env.cleanup();
  if (adminApp) { await db.terminate(); await adminApp.delete(); }
  clearTimeout(watchdog);
});

test('real custom-token authentication exposes scoped claims and revocable Firestore access', async () => {
  const current = await registrar();
  assert.match(current.requestAuth.uid, /^reg_[a-f0-9]{32}$/u);
  assert.equal(current.requestAuth.token.eduproRegistro, true);
  assert.equal(current.requestAuth.token.registroSchoolId, schoolId);
  assert.equal(current.requestAuth.token.firebase.sign_in_provider, 'custom');
  assert.ok(current.expiresAtMs <= Date.now() + SESSION_DURATION_MS);
  const grade = doc(current.firestore, `schools/${schoolId}/grados/${gradeId}`);
  assert.equal((await getDocFromServer(grade)).exists(), true);
  await assert.rejects(getDocFromServer(doc(current.firestore, `schools/${otherSchoolId}/grados/${gradeId}`)), dbDenied);
  await assert.rejects(getDocFromServer(doc(current.firestore, `registro_sessions/${current.requestAuth.uid}`)), dbDenied);
  assert.equal((await db.doc(`schools/${schoolId}/members/${current.requestAuth.uid}`).get()).exists, false);
  await db.doc(`schools/${schoolId}/config/registro`).update({ accessVersion: 'synthetic-rotated-version' });
  await assert.rejects(getDocFromServer(grade), dbDenied);
  await assert.rejects(service.registerStudent(current.requestAuth, payload()), reject('permission-denied'));
  const previousUid = current.requestAuth.uid;
  await registrar(current);
  assert.equal(current.requestAuth.uid, previousUid);
  assert.equal((await getDocFromServer(grade)).exists(), true);
  await service.endSession(current.requestAuth, { schoolId });
  await assert.rejects(getDocFromServer(grade), dbDenied);
  await assert.rejects(service.registerStudent(current.requestAuth, payload()), reject('permission-denied'));
});

test('real transaction aggregate and school lock permit only one concurrent remaining quota slot', async () => {
  await db.doc(`schools/${schoolId}`).update({ studentsLimit: 1 });
  const [first, second] = await Promise.all([registrar(), registrar()]);
  const results = await Promise.allSettled([
    service.registerStudent(first.requestAuth, payload()),
    service.registerStudent(second.requestAuth, payload({ nombres: 'Otra Persona', matricula: '13' }, id('B'))),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.find((result) => result.status === 'rejected').reason.code, 'resource-exhausted');
  assert.equal((await db.collection(`schools/${schoolId}/alumnos`).count().get()).data().count, 1);
});

test('real concurrent duplicate checks commit one student and one set of global/login indexes', async () => {
  const [first, second] = await Promise.all([registrar(), registrar()]);
  const results = await Promise.allSettled([
    service.registerStudent(first.requestAuth, payload()), service.registerStudent(second.requestAuth, payload({}, id('B'))),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.find((result) => result.status === 'rejected').reason.code, 'already-exists');
  assert.equal((await db.collection(`schools/${schoolId}/alumnos`).count().get()).data().count, 1);
  assert.equal((await db.collection('alumnos_global').count().get()).data().count, 1);
  assert.equal((await db.doc(`schools/${schoolId}/alumnos_login/tutor@example.test`).get()).data().studentIds.length, 1);
});

test('real arrayUnion merges siblings and access accounts atomically; retry and birth date remain stable', async () => {
  const current = await registrar();
  const data = payload({ accesos: [{ email: 'tutor@example.test', usuario: 'tutor' }, { email: 'other-tutor@example.test', usuario: 'second' }] });
  await service.registerStudent(current.requestAuth, data);
  assert.equal((await service.registerStudent(current.requestAuth, data)).alreadyRegistered, true);
  await service.registerStudent(current.requestAuth, payload({ nombres: 'Otra Persona', matricula: '13' }, id('B')));
  const shared = (await db.doc(`schools/${schoolId}/alumnos_login/tutor@example.test`).get()).data();
  assert.deepEqual([...shared.studentIds].sort(), [id(), id('B')].sort());
  assert.deepEqual(shared.gradeIds, [gradeId]);
  const other = (await db.doc(`schools/${schoolId}/alumnos_login/other-tutor@example.test`).get()).data();
  assert.deepEqual(other.studentIds, [id()]);
  const saved = (await db.doc(`schools/${schoolId}/alumnos/${id()}`).get()).data();
  assert.equal(saved.fechaNacimiento.toMillis(), data.student.fechaNacimientoMillis);
  assert.equal((await getDocFromServer(doc(current.firestore, `schools/${schoolId}/alumnos/${id()}`))).exists(), true);
  await assert.rejects(service.registerStudent(current.requestAuth, { ...payload(), schoolId: otherSchoolId }), reject('permission-denied'));
});

test('real Storage upload has no bearer token; linked verified tutor can read and strangers cannot', async () => {
  const current = await registrar();
  const bytes = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0]);
  const uploaded = await service.uploadPhoto(current.requestAuth, { schoolId, studentId: id(), contentType: 'image/png', base64: bytes.toString('base64') });
  const [metadata] = await admin.storage(adminApp).bucket(bucketName).file(uploaded.photoPath).getMetadata();
  assert.equal(metadata.metadata.registroUid, current.requestAuth.uid);
  assert.equal(metadata.metadata.firebaseStorageDownloadTokens, undefined);
  await service.registerStudent(current.requestAuth, payload({ photoPath: uploaded.photoPath }));
  const saved = (await db.doc(`schools/${schoolId}/alumnos/${id()}`).get()).data();
  assert.equal(saved.photoUrl, null);
  assert.equal(saved.photoPath, uploaded.photoPath);
  await admin.auth(adminApp).createUser({ uid: 'synthetic-linked-tutor', email: 'tutor@example.test', emailVerified: true });
  const tutor = await client();
  await signInWithCustomToken(tutor.auth, await admin.auth(adminApp).createCustomToken('synthetic-linked-tutor'));
  const downloaded = await getBytes(ref(tutor.storage, uploaded.photoPath), 5 * 1024 * 1024);
  assert.deepEqual(Buffer.from(downloaded), bytes);
  const anonymous = await client();
  await assert.rejects(getBytes(ref(anonymous.storage, uploaded.photoPath)), storageDenied);
  await assert.rejects(getBytes(ref(current.storage, uploaded.photoPath)), storageDenied);
  await db.doc(`schools/${schoolId}/alumnos/${id()}`).update({ enabled: false });
  await assert.rejects(getBytes(ref(tutor.storage, uploaded.photoPath)), storageDenied);
});
