"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createSchoolRegistration, SESSION_DURATION_MS } = require("../school_registration");

const NOW = Date.UTC(2026, 9, 14, 12);
const UID = `reg_${"a".repeat(32)}`;
const auth = (uid = UID, schoolId = "A") => ({ uid, token: {
  eduproRegistro: true, registroSchoolId: schoolId, firebase: { sign_in_provider: "custom" },
} });
const stamp = (ms) => ({ toMillis: () => ms });
const reject = (code) => (error) => error.code === code;
const id = (letter = "A") => letter.repeat(20);

// A serialized, isolated transactional store. The real service implementation
// runs here; no Firebase app, user or remote database is initialized.
function harness(extra = {}, { rejectWritePrefix, photoMetadata, beforePhotoSave } = {}) {
  const records = new Map(Object.entries({
    "schools/A": { active: true, studentsLimit: 100 },
    "schools/A/config/registro": { accessVersion: "version-one", permitirFotoAlumno: true },
    [`registro_sessions/${UID}`]: { schoolId: "A", version: "version-one", enabled: true,
      expiresAt: stamp(NOW + SESSION_DURATION_MS) },
    "schools/A/grados/grade": { name: "1 de Primaria", nivel: "primaria", gradoKey: "1 de primaria" },
    ...extra,
  }));
  const reads = [];
  const writes = [];
  const tokenCalls = [];
  const uploaded = [];
  const files = new Map(photoMetadata || []);
  let generated = 0;
  const snapshot = (ref) => ({ exists: records.has(ref.path), id: ref.id, ref, data: () => records.get(ref.path) });
  const doc = (path) => ({ path, id: path.split("/").at(-1), get: async () => snapshot(doc(path)),
    set: async (data, options) => apply(doc(path), data, options) });
  const value = (v) => v?.toMillis?.() ?? v;
  const collection = (path, filters = [], limit = null) => {
    const rows = () => [...records.entries()].filter(([key, data]) =>
      key.startsWith(`${path}/`) && key.split("/").length === path.split("/").length + 1 &&
      filters.every(([field, op, target]) => op === "==" ? value(data[field]) === value(target) :
        op === ">=" ? value(data[field]) >= value(target) : value(data[field]) < value(target)));
    return {
      doc: (documentId = id(String.fromCharCode(67 + generated++))) => doc(`${path}/${documentId}`),
      where: (field, op, target) => collection(path, [...filters, [field, op, target]], limit),
      limit: (n) => collection(path, filters, n),
      get: async () => {
        reads.push({ mode: "query", path, limit });
        const docs = rows().slice(0, limit ?? Infinity).map(([path]) => snapshot(doc(path)));
        return { docs, size: docs.length };
      },
      count: () => ({ get: async () => {
        reads.push({ mode: "count", path });
        return { data: () => ({ count: rows().length }) };
      } }),
    };
  };
  function apply(ref, patch, options = {}) {
    const next = options.merge ? { ...(records.get(ref.path) || {}) } : {};
    for (const [key, data] of Object.entries(patch)) {
      next[key] = data?.arrayUnion ? [...new Set([...(next[key] || []), ...data.arrayUnion])] : data;
    }
    records.set(ref.path, next);
  }
  let pending = Promise.resolve();
  const db = { doc, collection, runTransaction: (action) => {
    const operation = pending.then(async () => {
      const batch = [];
      const result = await action({
        get: async (ref) => {
          if (!ref.path) return ref.get();
          reads.push({ mode: "document", path: ref.path });
          return snapshot(ref);
        },
        set: (ref, patch, options) => {
          if (rejectWritePrefix && ref.path.startsWith(rejectWritePrefix)) throw new Error("Synthetic write failure");
          batch.push([ref, patch, options]);
        },
      });
      for (const row of batch) { apply(...row); writes.push(row[0].path); }
      return result;
    });
    pending = operation.catch(() => {});
    return operation;
  } };
  const firestore = { Timestamp: { fromMillis: stamp }, FieldValue: {
    serverTimestamp: () => stamp(NOW), arrayUnion: (...items) => ({ arrayUnion: items }),
  } };
  const bucket = { name: "synthetic-bucket", file: (path) => ({
    getMetadata: async () => {
      if (!files.has(path)) throw Object.assign(new Error("Synthetic missing file"), { code: 404 });
      return [files.get(path)];
    },
    save: async (bytes, options) => {
      if (beforePhotoSave) await beforePhotoSave();
      const current = files.get(path);
      if (String(options.preconditionOpts.ifGenerationMatch) !== String(current?.generation || 0)) {
        throw Object.assign(new Error("Synthetic generation conflict"), { code: 412 });
      }
      const metadata = { size: bytes.length, generation: String(Number(current?.generation || 0) + 1), ...options.metadata };
      files.set(path, metadata);
      uploaded.push({ path, size: bytes.length });
    },
  }) };
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const service = createSchoolRegistration({ db, firestore, HttpsError, getBucket: () => bucket, now: () => NOW,
    authService: { createCustomToken: async (uid, claims) => { tokenCalls.push({ uid, claims }); return "synthetic-token"; } } });
  return { service, records, reads, writes, tokenCalls, uploaded, files };
}

function student(overrides = {}) {
  return { nombres: "Persona Sintética", apellidos: "Prueba", matricula: "12", nivel: "primaria", gradoId: "grade",
    tanda: "Mañana", fechaNacimientoMillis: Date.UTC(2015, 2, 8), sexo: "femenino", status: "activo",
    tutor: { nombre: "Tutor Sintético", parentesco: "Tutor", telefono: "8090000000" },
    emergencia: { nombre: "", telefono: "" }, accesos: [{ email: "tutor@example.test", usuario: "tutor" }],
    ...overrides };
}
const payload = (overrides = {}, studentId = id()) => ({ schoolId: "A", studentId, student: student(overrides) });

test("code issuance creates a two-hour custom principal without admin membership", async () => {
  const h = harness();
  const result = await h.service.issueSession({ schoolId: "A", expectedConfig: h.records.get("schools/A/config/registro") });
  assert.equal(result.expiresAtMs, NOW + SESSION_DURATION_MS);
  assert.equal(result.customToken, "synthetic-token");
  const token = h.tokenCalls[0];
  assert.match(token.uid, /^reg_[a-f0-9]{32}$/u);
  assert.deepEqual(token.claims, { eduproRegistro: true, registroSchoolId: "A" });
  assert.equal(h.records.get(`registro_sessions/${token.uid}`).enabled, true);
  assert.equal(h.writes.some((path) => path.startsWith("users/") || path.includes("/members/")), false);
});

test("rotated code cannot migrate or issue a token from a stale validation", async () => {
  const h = harness({ "schools/A/config/registro": { passwordHash: "new-hash", passwordSalt: "new-salt", passwordAlgo: "scrypt_v1" } });
  await assert.rejects(h.service.issueSession({ schoolId: "A", expectedConfig: { passwordHash: "old-hash" },
    migrationPatch: { passwordHash: "unexpected" } }), reject("permission-denied"));
  assert.equal(h.tokenCalls.length, 0);
  assert.equal(h.records.get("schools/A/config/registro").passwordHash, "new-hash");
});

test("validated code can renew an expired same-school principal and preserve pending photo ownership", async () => {
  const h = harness();
  const image = await h.service.uploadPhoto(auth(), imagePayload());
  h.records.get(`registro_sessions/${UID}`).expiresAt = stamp(NOW - 1);
  await h.service.issueSession({ schoolId: "A", expectedConfig: h.records.get("schools/A/config/registro"), previousAuth: auth() });
  assert.equal(h.tokenCalls[0].uid, UID);
  assert.equal(h.records.get(`registro_sessions/${UID}`).expiresAt.toMillis(), NOW + SESSION_DURATION_MS);
  await h.service.registerStudent(auth(), payload({ photoPath: image.photoPath }));
});

test("renewal never reuses a principal without a matching private session and custom provider", async () => {
  for (const previousAuth of [auth(UID, "B"), { uid: UID, token: { ...auth().token, firebase: { sign_in_provider: "password" } } }]) {
    const h = harness();
    await h.service.issueSession({ schoolId: "A", expectedConfig: h.records.get("schools/A/config/registro"), previousAuth });
    assert.notEqual(h.tokenCalls[0].uid, UID);
  }
  const h = harness();
  h.records.get(`registro_sessions/${UID}`).schoolId = "B";
  await h.service.issueSession({ schoolId: "A", expectedConfig: h.records.get("schools/A/config/registro"), previousAuth: auth() });
  assert.notEqual(h.tokenCalls[0].uid, UID);
});

test("missing version is created once and all issued sessions share it", async () => {
  const h = harness({ "schools/A/config/registro": {} });
  await Promise.all([h.service.issueSession({ schoolId: "A", expectedConfig: {} }), h.service.issueSession({ schoolId: "A", expectedConfig: {} })]);
  const version = h.records.get("schools/A/config/registro").accessVersion;
  assert.match(version, /^[a-f0-9]{48}$/u);
  for (const token of h.tokenCalls) assert.equal(h.records.get(`registro_sessions/${token.uid}`).version, version);
});

test("unauthenticated, non-custom, wrong-school and revoked sessions cannot register", async () => {
  for (const [inputAuth, sessionPatch, expected] of [
    [null, {}, "unauthenticated"],
    [{ uid: UID, token: { ...auth().token, firebase: { sign_in_provider: "password" } } }, {}, "permission-denied"],
    [auth(UID, "B"), {}, "permission-denied"],
    [auth(), { enabled: false }, "permission-denied"],
    [auth(), { schoolId: "B" }, "permission-denied"],
    [auth(), { version: "obsolete" }, "permission-denied"],
    [auth(), { expiresAt: stamp(NOW) }, "permission-denied"],
    [auth(), { expiresAt: stamp(NOW + SESSION_DURATION_MS + 1) }, "permission-denied"],
  ]) {
    const h = harness();
    h.records.set(`registro_sessions/${UID}`, { ...h.records.get(`registro_sessions/${UID}`), ...sessionPatch });
    await assert.rejects(h.service.registerStudent(inputAuth, payload()), reject(expected));
    assert.equal(h.writes.length, 0);
  }
});

test("school suspension, deletion and configuration revocation block subsequent writes", async () => {
  for (const patch of [{ active: false }, { enabled: false }, { accountStatus: "bloqueada" }, { status: "unknown" }]) {
    const h = harness({ "schools/A": patch });
    await assert.rejects(h.service.registerStudent(auth(), payload()), reject("permission-denied"));
  }
  const h = harness();
  h.records.get("schools/A/config/registro").accessVersion = "rotated";
  await assert.rejects(h.service.createGrade(auth(), { schoolId: "A", name: "2", nivel: "primaria" }), reject("permission-denied"));
  h.records.delete("schools/A");
  await assert.rejects(h.service.registerStudent(auth(), payload()), reject("permission-denied"));
});

test("server rejects forbidden fields, malformed emails, long names and invalid dates before writes", async () => {
  for (const change of [
    { role: "admin" }, { schoolId: "B" }, { nombres: "x".repeat(101) }, { nombres: "<script>" },
    { fechaNacimientoMillis: NOW + 1 }, { fechaNacimientoMillis: "date" }, { status: "admin" },
    { gradoId: "../another" }, { accesos: [{ email: "bad/address@example.test", usuario: "user" }] },
    { accesos: Array.from({ length: 11 }, (_, i) => ({ email: `t${i}@example.test`, usuario: "test" })) },
    { accesos: [{ email: "duplicate@example.test", usuario: "one" }, { email: "DUPLICATE@example.test", usuario: "two" }] },
  ]) {
    const h = harness();
    await assert.rejects(h.service.registerStudent(auth(), payload(change)), reject("invalid-argument"));
    assert.equal(h.writes.length, 0);
  }
});

test("legitimate registration atomically preserves existing student and login contracts", async () => {
  const h = harness();
  const result = await h.service.registerStudent(auth(), payload());
  assert.deepEqual(result, { ok: true, studentId: id(), alreadyRegistered: false });
  const saved = h.records.get(`schools/A/alumnos/${id()}`);
  assert.equal(saved.role, "student");
  assert.equal(saved.grado, "1 de Primaria");
  assert.equal(saved.gradeId, "grade");
  assert.equal(saved.gradoId, "grade");
  assert.equal(saved.edad, 11);
  assert.equal(saved.nombresKey, "persona sintética");
  assert.equal(saved.photoUrl, null);
  assert.equal(h.records.get(`alumnos_global/${id()}`).studentPath, `schools/A/alumnos/${id()}`);
  assert.deepEqual(h.records.get("schools/A/alumnos_login/tutor@example.test").studentIds, [id()]);
  assert.ok(h.reads.some((row) => row.mode === "count"));
  assert.ok(h.reads.some((row) => row.path === "schools/A/_registration/state"));
  assert.ok(h.reads.filter((row) => row.mode === "query").every((row) => row.limit === 1));
});

test("multiline notes and address preserve their lines without accepting control characters", async () => {
  const h = harness();
  await h.service.registerStudent(auth(), payload({ observaciones: "Primera línea\r\nSegunda línea", direccion: "Calle sintética\nCiudad" }));
  assert.equal(h.records.get(`schools/A/alumnos/${id()}`).observaciones, "Primera línea\nSegunda línea");
  assert.equal(h.records.get(`schools/A/alumnos/${id()}`).direccion, "Calle sintética\nCiudad");
  const other = harness();
  await assert.rejects(other.service.registerStudent(auth(), payload({ observaciones: "invalid\u0000control" })), reject("invalid-argument"));
});

test("an index write failure commits no student, global record, login or quota lock", async () => {
  const h = harness({}, { rejectWritePrefix: "schools/A/alumnos_login" });
  await assert.rejects(h.service.registerStudent(auth(), payload()), /Synthetic write failure/u);
  for (const path of [`schools/A/alumnos/${id()}`, `alumnos_global/${id()}`, "schools/A/_registration/state"])
    assert.equal(h.records.has(path), false);
  assert.equal(h.writes.length, 0);
});

test("concurrent registrations cannot exceed a school's remaining quota", async () => {
  const h = harness({ "schools/A": { active: true, studentsLimit: 1 } });
  const results = await Promise.allSettled([
    h.service.registerStudent(auth(), payload()),
    h.service.registerStudent(auth(), payload({ nombres: "Otra Persona", matricula: "13" }, id("B"))),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "resource-exhausted");
  assert.equal([...h.records.keys()].filter((path) => /^schools\/A\/alumnos\//u.test(path)).length, 1);
});

test("concurrent duplicate registrations commit only one student", async () => {
  const h = harness();
  const results = await Promise.allSettled([
    h.service.registerStudent(auth(), payload()), h.service.registerStudent(auth(), payload({}, id("B"))),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "already-exists");
});

test("a legacy same-day birth timestamp is detected without downloading a class", async () => {
  const h = harness({ "schools/A/alumnos/legacy": { nombresKey: "persona sintética", apellidosKey: "prueba",
    fechaNacimiento: stamp(Date.UTC(2015, 2, 8, 4)) } });
  await assert.rejects(h.service.registerStudent(auth(), payload()), reject("already-exists"));
  assert.equal(h.reads.filter((row) => row.mode === "query").every((row) => row.limit === 1), true);
});

test("birth timestamps retain the picker offset so local rendering does not change the calendar day", async () => {
  const h = harness();
  const original = Date.UTC(2015, 2, 8, 4);
  await h.service.registerStudent(auth(), payload({ fechaNacimientoMillis: original }));
  assert.equal(h.records.get(`schools/A/alumnos/${id()}`).fechaNacimiento.toMillis(), original);
  await assert.rejects(h.service.registerStudent(auth(), payload({ matricula: "13", fechaNacimientoMillis: original }, id("B"))), reject("already-exists"));
});

test("retry is idempotent, including a renewed session, and different payload cannot overwrite", async () => {
  const h = harness();
  await h.service.registerStudent(auth(), payload());
  const before = h.writes.length;
  const renewedUid = `reg_${"b".repeat(32)}`;
  h.records.set(`registro_sessions/${renewedUid}`, { ...h.records.get(`registro_sessions/${UID}`) });
  const repeated = await h.service.registerStudent(auth(renewedUid), payload());
  assert.equal(repeated.alreadyRegistered, true);
  assert.equal(h.writes.length, before);
  await assert.rejects(h.service.registerStudent(auth(), payload({ apellidos: "Diferente" })), reject("already-exists"));
  assert.deepEqual(h.records.get("schools/A/alumnos_login/tutor@example.test").studentIds, [id()]);
});

test("student status and legacy inferred grade level remain supported", async () => {
  const h = harness({ "schools/A/grados/grade": { name: "1 de Primaria" } });
  await h.service.registerStudent(auth(), payload({ status: "bloqueado" }));
  assert.equal(h.records.get(`schools/A/alumnos/${id()}`).enabled, false);
  const other = harness({ "schools/A/grados/grade": { name: "1 de Secundaria", nivel: "secundaria" } });
  await assert.rejects(other.service.registerStudent(auth(), payload()), reject("failed-precondition"));
});

test("grade creation is scoped, bounded and duplicate-safe", async () => {
  const h = harness();
  const calls = await Promise.all([h.service.createGrade(auth(), { schoolId: "A", name: "2", nivel: "primaria" }),
    h.service.createGrade(auth(), { schoolId: "A", name: "2 de Primaria", nivel: "primaria" })]);
  assert.equal(calls[0].gradeId, calls[1].gradeId);
  assert.equal(calls[1].alreadyExists, true);
  assert.equal(h.records.get(`schools/A/grados/${calls[0].gradeId}`).nivel, "primaria");
  await assert.rejects(h.service.createGrade(auth(), { schoolId: "B", name: "2", nivel: "primaria" }), reject("permission-denied"));
  await assert.rejects(h.service.createGrade(auth(), { schoolId: "A", name: "2", nivel: "primaria", role: "admin" }), reject("invalid-argument"));
});

const imagePayload = (overrides = {}) => ({ schoolId: "A", studentId: id(), contentType: "image/png",
  base64: Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0]).toString("base64"), ...overrides });

test("photo uploads validate decoded bytes, ownership and exact server paths", async () => {
  const h = harness();
  const result = await h.service.uploadPhoto(auth(), imagePayload());
  assert.deepEqual(result, { ok: true, photoPath: `schools/A/alumnos/${id()}/profile.png` });
  assert.equal(h.files.get(result.photoPath).metadata.registroUid, UID);
  assert.equal(h.files.get(result.photoPath).metadata.firebaseStorageDownloadTokens, undefined);
  await h.service.registerStudent(auth(), payload({ photoPath: result.photoPath }));
  const saved = h.records.get(`schools/A/alumnos/${id()}`);
  assert.equal(saved.photoPath, result.photoPath);
  assert.equal(saved.photoUrl, null);
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("already-exists"));
});

test("photo retries after a renewed session do not require the original photo owner", async () => {
  const h = harness();
  const uploaded = await h.service.uploadPhoto(auth(), imagePayload());
  const data = payload({ photoPath: uploaded.photoPath });
  await h.service.registerStudent(auth(), data);
  const nextUid = `reg_${"c".repeat(32)}`;
  h.records.set(`registro_sessions/${nextUid}`, { ...h.records.get(`registro_sessions/${UID}`) });
  assert.equal((await h.service.registerStudent(auth(nextUid), data)).alreadyRegistered, true);
});

test("disabled photos, oversized uploads, invalid magic and forged Storage paths are rejected", async () => {
  const h = harness();
  for (const change of [{ base64: "malformed" }, { base64: Buffer.from("text").toString("base64") },
    { contentType: "text/html" }, { base64: "A".repeat(4 * Math.ceil((5 * 1024 * 1024 + 1) / 3)) },
    { schoolId: "B" }]) {
    await assert.rejects(h.service.uploadPhoto(auth(), imagePayload(change)), reject(change.schoolId ? "permission-denied" : "invalid-argument"));
  }
  await assert.rejects(h.service.registerStudent(auth(), payload({ photoPath: "schools/B/alumnos/other/profile.png" })), reject("invalid-argument"));
  h.records.get("schools/A/config/registro").permitirFotoAlumno = false;
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("permission-denied"));
  await assert.rejects(h.service.registerStudent(auth(), payload({ photoPath: `schools/A/alumnos/${id()}/profile.png` })), reject("permission-denied"));
  assert.equal(h.uploaded.length, 0);
});

test("another owner cannot overwrite or register a pending photo", async () => {
  const path = `schools/A/alumnos/${id()}/profile.png`;
  const h = harness({}, { photoMetadata: [[path, { size: 9, contentType: "image/png", generation: "1",
    metadata: { registroUid: "different-owner" } }]] });
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("permission-denied"));
  await assert.rejects(h.service.registerStudent(auth(), payload({ photoPath: path })), reject("failed-precondition"));
  assert.equal(h.uploaded.length, 0);
});

test("in-flight photo upload blocks registration and cannot overwrite a committed student's photo", async () => {
  let signalStarted, release;
  const started = new Promise((resolve) => { signalStarted = resolve; });
  const barrier = new Promise((resolve) => { release = resolve; });
  const h = harness({}, { beforePhotoSave: async () => { signalStarted(); await barrier; } });
  const upload = h.service.uploadPhoto(auth(), imagePayload());
  await started;
  await assert.rejects(h.service.registerStudent(auth(), payload()), reject("failed-precondition"));
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("resource-exhausted"));
  release();
  const result = await upload;
  await h.service.registerStudent(auth(), payload({ photoPath: result.photoPath }));
  const generation = h.files.get(result.photoPath).generation;
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("already-exists"));
  assert.equal(h.files.get(result.photoPath).generation, generation);
});

test("an expired upload lease can be discarded without blocking registration indefinitely", async () => {
  const leasePath = `schools/A/_registration_photos/${id()}`;
  const h = harness({ [leasePath]: { owner: UID, status: "uploading", uploadId: "abandoned-operation", expiresAt: stamp(NOW - 1) } });
  await h.service.registerStudent(auth(), payload());
  assert.equal(h.records.get(leasePath).status, "abandoned");
  assert.equal(h.records.get(`schools/A/alumnos/${id()}`).photoPath, null);
  await assert.rejects(h.service.uploadPhoto(auth(), imagePayload()), reject("already-exists"));
});

test("session logout is idempotent and subsequent registration is denied", async () => {
  const h = harness();
  await h.service.endSession(auth(), { schoolId: "A" });
  await h.service.endSession(auth(), { schoolId: "A" });
  assert.equal(h.records.get(`registro_sessions/${UID}`).enabled, false);
  await assert.rejects(h.service.registerStudent(auth(), payload()), reject("permission-denied"));
  await assert.rejects(h.service.endSession(auth(), { schoolId: "B" }), reject("permission-denied"));
});
