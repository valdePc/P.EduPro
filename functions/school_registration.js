"use strict";

const crypto = require("node:crypto");
const { normalizeSchoolId } = require("./security");

const SESSION_DURATION_MS = 2 * 60 * 60 * 1000;
const SESSION_COLLECTION = "registro_sessions";
const LEVELS = ["inicial", "primaria", "secundaria"];
const LABELS = { inicial: "Inicial", primaria: "Primaria", secundaria: "Secundaria" };

function secretFingerprint(config) {
  return JSON.stringify([config.password, config.passwordHash, config.passwordSalt, config.passwordAlgo]);
}

function schoolAvailable(school) {
  const status = String(school.accountStatus || school.status || "").trim().toLowerCase();
  return school.active !== false && school.enabled !== false &&
    (["active", "activa", "activo"].includes(status) || (!status && school.active === true));
}

function nameKey(value) {
  return value.toLowerCase().trim().replace(/\s+/gu, " ").replace(/[^a-z0-9ñáéíóúü ]/gu, "");
}

function createSchoolRegistration({ db, authService, firestore, HttpsError, getBucket, now = Date.now }) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const invalid = () => fail("invalid-argument", "Revisa el formato y la longitud de los campos.");
  const denied = () => fail("permission-denied", "La sesión de registro no está disponible. Vuelve a ingresar el código.");
  const checkObject = (value, fields) => {
    if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).some((key) => !fields.includes(key))) invalid();
    return value;
  };
  const text = (value, max, min = 0, pattern) => {
    if (value == null && min === 0) return "";
    if (typeof value !== "string" || value.length > max || /[\u0000-\u001f\u007f]/u.test(value)) invalid();
    const result = value.trim().replace(/\s+/gu, " ");
    if (result.length < min || (result && pattern && !pattern.test(result))) invalid();
    return result;
  };
  const name = (value, min = 0) => text(value, 100, min, /^[\p{L}\p{M} '\-]+$/u);
  const multiline = (value, max) => {
    if (value == null) return "";
    if (typeof value !== "string" || value.length > max || /[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f]/u.test(value)) invalid();
    return value.replace(/\r\n?/gu, "\n").trim();
  };
  const phone = (value, required = false) => text(value, 24, required ? 8 : 0, /^\+?[0-9]{8,15}$/u);
  const email = (value, required = false) => text(value, 254, required ? 3 : 0,
    /^[A-Za-z0-9.!#$%&'*+?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/u).toLowerCase();
  const id = (value, auto = false) => {
    if (typeof value !== "string" || !(auto ? /^[A-Za-z0-9]{20}$/u : /^[A-Za-z0-9_-]{1,128}$/u).test(value)) invalid();
    return value;
  };
  const schoolIdFrom = (value) => {
    const schoolId = normalizeSchoolId(value);
    if (!schoolId) invalid();
    return schoolId;
  };
  const level = (value) => {
    if (!LEVELS.includes(value)) invalid();
    return value;
  };
  const timestampMs = (value) => value?.toMillis?.() || 0;
  const sessionRef = (uid) => db.doc(`${SESSION_COLLECTION}/${uid}`);

  // Only code-issued custom-token sessions qualify. These principals receive
  // no administrator roles or membership documents.
  function requirePrincipal(auth, schoolId) {
    if (!auth?.uid) fail("unauthenticated", "Ingresa el código para abrir una sesión de registro.");
    if (!/^reg_[a-f0-9]{32}$/u.test(auth.uid) || auth.token?.eduproRegistro !== true ||
      auth.token?.registroSchoolId !== schoolId || auth.token?.firebase?.sign_in_provider !== "custom") denied();
  }

  async function readAccess(tx, auth, schoolId) {
    requirePrincipal(auth, schoolId);
    const [sessionSnap, schoolSnap, configSnap] = await Promise.all([
      tx.get(sessionRef(auth.uid)), tx.get(db.doc(`schools/${schoolId}`)),
      tx.get(db.doc(`schools/${schoolId}/config/registro`)),
    ]);
    const session = sessionSnap.data() || {};
    const school = schoolSnap.data() || {};
    const config = configSnap.data() || {};
    if (!sessionSnap.exists || !schoolSnap.exists || !configSnap.exists ||
      session.enabled !== true || session.schoolId !== schoolId ||
      timestampMs(session.expiresAt) <= now() || timestampMs(session.expiresAt) > now() + SESSION_DURATION_MS ||
      typeof config.accessVersion !== "string" || !config.accessVersion ||
      session.version !== config.accessVersion || !schoolAvailable(school)) denied();
    return { session, school, config };
  }

  async function issueSession({ schoolId, expectedConfig, migrationPatch, previousAuth }) {
    const freshUid = `reg_${crypto.randomBytes(16).toString("hex")}`;
    const previousUid = /^reg_[a-f0-9]{32}$/u.test(previousAuth?.uid || "") &&
      previousAuth.token?.eduproRegistro === true && previousAuth.token?.registroSchoolId === schoolId &&
      previousAuth.token?.firebase?.sign_in_provider === "custom" ? previousAuth.uid : null;
    const issuedAtMs = now();
    const expiresAtMs = issuedAtMs + SESSION_DURATION_MS;
    const result = await db.runTransaction(async (tx) => {
      const [configSnap, schoolSnap, previousSession] = await Promise.all([
        tx.get(db.doc(`schools/${schoolId}/config/registro`)), tx.get(db.doc(`schools/${schoolId}`)),
        previousUid ? tx.get(sessionRef(previousUid)) : Promise.resolve(null),
      ]);
      const config = configSnap.data() || {};
      if (!configSnap.exists || !schoolSnap.exists || !schoolAvailable(schoolSnap.data() || {}) ||
        secretFingerprint(config) !== secretFingerprint(expectedConfig)) denied();
      const version = typeof config.accessVersion === "string" && config.accessVersion ?
        config.accessVersion : crypto.randomBytes(24).toString("hex");
      const uid = previousSession?.exists && previousSession.data()?.schoolId === schoolId ? previousUid : freshUid;
      if (migrationPatch || version !== config.accessVersion) {
        tx.set(configSnap.ref, { ...migrationPatch, accessVersion: version }, { merge: true });
      }
      tx.set(sessionRef(uid), { schoolId, version, enabled: true,
        createdAt: firestore.Timestamp.fromMillis(issuedAtMs),
        expiresAt: firestore.Timestamp.fromMillis(expiresAtMs) });
      return { uid, permitirFotoAlumno: config.permitirFotoAlumno !== false,
        permitirEditarEstudiantes: config.permitirEditarEstudiantes !== false };
    });
    let customToken;
    try {
      customToken = await authService.createCustomToken(result.uid, { eduproRegistro: true, registroSchoolId: schoolId });
    } catch (error) {
      // A signing failure must not leave a usable session behind.
      await sessionRef(result.uid).set({ enabled: false }, { merge: true });
      throw error;
    }
    return { customToken, expiresAtMs, schoolId,
      permitirFotoAlumno: result.permitirFotoAlumno,
      permitirEditarEstudiantes: result.permitirEditarEstudiantes };
  }

  function validateStudent(raw) {
    const s = checkObject(raw, ["nombres", "apellidos", "matricula", "nivel", "gradoId", "tanda",
      "fechaNacimientoMillis", "sexo", "status", "direccion", "observaciones", "tutor", "emergencia", "accesos", "photoPath"]);
    const tutor = checkObject(s.tutor, ["nombre", "parentesco", "telefono", "whatsapp", "email"]);
    const emergencia = checkObject(s.emergencia, ["nombre", "telefono"]);
    const dobMs = s.fechaNacimientoMillis;
    const current = now();
    if (!Number.isSafeInteger(dobMs) || dobMs < Date.UTC(1900, 0, 1) || dobMs > current) invalid();
    const dob = new Date(dobMs);
    const dayMs = Date.UTC(dob.getUTCFullYear(), dob.getUTCMonth(), dob.getUTCDate());
    if (!Array.isArray(s.accesos) || s.accesos.length < 1 || s.accesos.length > 10) invalid();
    const seen = new Set();
    const accesos = s.accesos.map((entry) => {
      checkObject(entry, ["email", "usuario"]);
      const emailLower = email(entry.email, true);
      if (seen.has(emailLower)) invalid();
      seen.add(emailLower);
      return { email: emailLower, emailLower, usuario: text(entry.usuario, 80, 1, /^[\p{L}\p{M}\p{N}_. '@\-]+$/u) };
    }).sort((a, b) => a.emailLower.localeCompare(b.emailLower));
    if (!["Mañana", "Tarde", "Nocturna"].includes(s.tanda) ||
      !["femenino", "masculino"].includes(s.sexo) ||
      !["activo", "pendiente", "bloqueado"].includes(s.status)) invalid();
    return {
      nombres: name(s.nombres, 2), apellidos: name(s.apellidos, 2),
      matricula: text(s.matricula, 40, 0, /^[\p{L}\p{N}_.\- ]+$/u),
      nivel: level(s.nivel), gradoId: id(s.gradoId), tanda: s.tanda,
      fechaNacimientoMillis: dobMs, birthDayMillis: dayMs, sexo: s.sexo, status: s.status,
      direccion: multiline(s.direccion, 300), observaciones: multiline(s.observaciones, 2000),
      tutor: { nombre: name(tutor.nombre, 2), parentesco: text(tutor.parentesco, 60),
        telefono: phone(tutor.telefono, true), whatsapp: phone(tutor.whatsapp) || null,
        email: email(tutor.email) || null },
      emergencia: { nombre: name(emergencia.nombre), telefono: phone(emergencia.telefono) },
      accesos, photoPath: text(s.photoPath, 300) || null,
    };
  }

  async function resolvePhoto(auth, schoolId, studentId, path, state) {
    if (!path) return { photoPath: null, photoUrl: null };
    const prefix = `schools/${schoolId}/alumnos/${studentId}/profile.`;
    if (path !== `${prefix}jpg` && path !== `${prefix}png`) invalid();
    if (state?.status !== "ready" || state.owner !== auth.uid || state.photoPath !== path) {
      fail("failed-precondition", "Vuelve a cargar la foto del estudiante.");
    }
    const bucket = getBucket();
    const file = bucket.file(path);
    let metadata;
    try { [metadata] = await file.getMetadata(); } catch (_) {
      fail("failed-precondition", "Vuelve a cargar la foto del estudiante.");
    }
    const size = Number(metadata.size);
    if (!Number.isFinite(size) || size <= 0 || size > 5 * 1024 * 1024 ||
      metadata.contentType !== (path.endsWith(".png") ? "image/png" : "image/jpeg") ||
      metadata.metadata?.registroUid !== auth.uid || String(metadata.generation) !== String(state.generation)) invalid();
    // New photos use authenticated Storage reads. A persistent bearer URL
    // would bypass school and session revocation for anyone who obtained it.
    return { photoPath: path, photoUrl: null };
  }

  async function registerStudent(auth, payload) {
    checkObject(payload, ["schoolId", "studentId", "student"]);
    const schoolId = schoolIdFrom(payload.schoolId);
    const studentId = id(payload.studentId, true);
    requirePrincipal(auth, schoolId);
    const student = validateStudent(payload.student);
    // Check permission before Storage metadata lookup, and again at commit.
    await db.runTransaction(async (tx) => {
      const { config } = await readAccess(tx, auth, schoolId);
      if (student.photoPath && config.permitirFotoAlumno === false) denied();
    });
    const digest = crypto.createHash("sha256").update(JSON.stringify(student)).digest("hex");
    const basePath = `schools/${schoolId}`;
    const studentRef = db.doc(`${basePath}/alumnos/${studentId}`);
    const receiptRef = db.doc(`${basePath}/_registration_requests/${studentId}`);
    return db.runTransaction(async (tx) => {
      const { school, config } = await readAccess(tx, auth, schoolId);
      if (student.photoPath && config.permitirFotoAlumno === false) denied();
      const lockRef = db.doc(`${basePath}/_registration/state`);
      const [lockSnap, existing, receipt, gradeSnap, globalSnap, photoSnap] = await Promise.all([
        tx.get(lockRef), tx.get(studentRef), tx.get(receiptRef),
        tx.get(db.doc(`${basePath}/grados/${student.gradoId}`)), tx.get(db.doc(`alumnos_global/${studentId}`)),
        tx.get(db.doc(`${basePath}/_registration_photos/${studentId}`)),
      ]);
      if (existing.exists || receipt.exists || globalSnap.exists) {
        if (existing.exists && receipt.data()?.digest === digest &&
          existing.data()?.schoolId === schoolId && globalSnap.data()?.schoolId === schoolId) {
          return { ok: true, studentId, alreadyRegistered: true };
        }
        fail("already-exists", "Este registro ya está ocupado. Revisa los datos antes de reintentar.");
      }
      const photoState = photoSnap.data() || {};
      const expiredUpload = photoState.status === "uploading" && timestampMs(photoState.expiresAt) <= now();
      if (photoState.owner && photoState.owner !== auth.uid) denied();
      if (photoState.status === "uploading" && (!expiredUpload || student.photoPath)) {
        fail("failed-precondition", expiredUpload ? "Vuelve a cargar la foto del estudiante." :
          "Espera a que termine de cargar la foto antes de registrar al estudiante.");
      }
      if (!gradeSnap.exists) fail("failed-precondition", "Selecciona un grado válido para el nivel del estudiante.");
      const grade = gradeSnap.data() || {};
      const gradeName = text(grade.name, 120, 1);
      const inferredLevel = / de (inicial|primaria|secundaria)$/iu.exec(gradeName)?.[1]?.toLowerCase();
      const gradeLevel = typeof grade.nivel === "string" && grade.nivel ? grade.nivel.trim().toLowerCase() :
        String(grade.nivelLabel || inferredLevel || "").trim().toLowerCase();
      if (grade.enabled === false || gradeLevel !== student.nivel) {
        fail("failed-precondition", "Selecciona un grado válido para el nivel del estudiante.");
      }
      const alumnos = db.collection(`${basePath}/alumnos`);
      const rawLimit = school.planLimits?.students ?? school.studentsLimit ?? 0;
      const limit = Number(rawLimit);
      if (!Number.isSafeInteger(limit) || limit < 0 || limit > 1000000) {
        fail("failed-precondition", "El colegio necesita revisar su límite de estudiantes.");
      }
      const gradeKey = nameKey(gradeName);
      const duplicateQueries = [alumnos.where("nombresKey", "==", nameKey(student.nombres))
        .where("apellidosKey", "==", nameKey(student.apellidos))
        .where("fechaNacimiento", ">=", firestore.Timestamp.fromMillis(student.birthDayMillis))
        .where("fechaNacimiento", "<", firestore.Timestamp.fromMillis(student.birthDayMillis + 86400000)).limit(1)];
      if (student.matricula) duplicateQueries.push(alumnos.where("matricula", "==", student.matricula)
        .where("gradoKey", "==", gradeKey).where("tanda", "==", student.tanda).where("nivel", "==", student.nivel).limit(1));
      const [count, ...duplicates] = await Promise.all([
        limit > 0 ? tx.get(alumnos.count()) : Promise.resolve(null),
        ...duplicateQueries.map((query) => tx.get(query)),
      ]);
      if (count && count.data().count >= limit) fail("resource-exhausted", "El colegio alcanzó su límite de estudiantes.");
      if (duplicates.some((snap) => snap.size > 0)) fail("already-exists", "Ya existe un estudiante con esos datos de inscripción.");
      const photos = await resolvePhoto(auth, schoolId, studentId, student.photoPath, photoSnap.data());
      const dob = new Date(student.fechaNacimientoMillis);
      const today = new Date(now());
      let edad = today.getUTCFullYear() - dob.getUTCFullYear();
      if (today.getUTCMonth() < dob.getUTCMonth() ||
        (today.getUTCMonth() === dob.getUTCMonth() && today.getUTCDate() < dob.getUTCDate())) edad--;
      const timestamp = firestore.FieldValue.serverTimestamp();
      const common = {
        idGlobal: studentId, fx: studentId, role: "student", roleLower: "student", active: true,
        schoolId, nivel: student.nivel, nivelLabel: LABELS[student.nivel],
        status: student.status, enabled: student.status !== "bloqueado",
        nombres: student.nombres, apellidos: student.apellidos,
        nombresKey: nameKey(student.nombres), apellidosKey: nameKey(student.apellidos),
        matricula: student.matricula, grado: gradeName, gradoKey: gradeKey,
        gradoId: student.gradoId, gradeId: student.gradoId, tanda: student.tanda,
        fechaNacimiento: firestore.Timestamp.fromMillis(student.fechaNacimientoMillis),
        sexo: student.sexo, genero: student.sexo, accesosEmails: student.accesos.map((a) => a.emailLower),
        createdAt: timestamp, updatedAt: timestamp,
      };
      tx.set(studentRef, { ...common, schoolRef: basePath, statusAt: timestamp, ingresoAt: timestamp,
        edad, direccion: student.direccion || null, observaciones: student.observaciones || null,
        tutor: student.tutor, emergencia: student.emergencia, accesos: student.accesos, ...photos });
      tx.set(db.doc(`alumnos_global/${studentId}`), { ...common, studentPath: studentRef.path });
      for (const access of student.accesos) {
        tx.set(db.doc(`${basePath}/alumnos_login/${access.emailLower}`), {
          email: access.email, emailLower: access.emailLower, schoolId,
          studentIds: firestore.FieldValue.arrayUnion(studentId),
          gradeIds: firestore.FieldValue.arrayUnion(student.gradoId),
          gradoIds: firestore.FieldValue.arrayUnion(student.gradoId),
          usuarios: firestore.FieldValue.arrayUnion(access.usuario), updatedAt: timestamp,
        }, { merge: true });
      }
      tx.set(receiptRef, { digest, owner: auth.uid, createdAt: timestamp });
      if (expiredUpload) tx.set(photoSnap.ref, { status: "abandoned", updatedAt: timestamp }, { merge: true });
      tx.set(lockRef, { version: (Number(lockSnap.data()?.version) || 0) + 1, updatedAt: timestamp });
      return { ok: true, studentId, alreadyRegistered: false };
    });
  }

  async function createGrade(auth, payload) {
    checkObject(payload, ["schoolId", "name", "nivel"]);
    const schoolId = schoolIdFrom(payload.schoolId);
    requirePrincipal(auth, schoolId);
    const nivel = level(payload.nivel);
    const baseName = text(payload.name, 100, 1, /^[\p{L}\p{M}\p{N}_. '\-]+$/u);
    const gradeName = / de (inicial|primaria|secundaria)$/iu.test(baseName) ? baseName : `${baseName} de ${LABELS[nivel]}`;
    if (/ de (inicial|primaria|secundaria)$/iu.exec(gradeName)[1].toLowerCase() !== nivel) invalid();
    const basePath = `schools/${schoolId}`;
    const gradeRef = db.collection(`${basePath}/grados`).doc();
    return db.runTransaction(async (tx) => {
      await readAccess(tx, auth, schoolId);
      const lockRef = db.doc(`${basePath}/_registration/state`);
      const [lockSnap, duplicates] = await Promise.all([tx.get(lockRef),
        tx.get(db.collection(`${basePath}/grados`).where("gradoKey", "==", nameKey(gradeName)).limit(1))]);
      if (duplicates.size > 0) return { ok: true, gradeId: duplicates.docs[0].id, alreadyExists: true };
      const timestamp = firestore.FieldValue.serverTimestamp();
      tx.set(gradeRef, { gradeId: gradeRef.id, name: gradeName, gradoKey: nameKey(gradeName), nivel,
        createdAt: timestamp, updatedAt: timestamp });
      tx.set(lockRef, { version: (Number(lockSnap.data()?.version) || 0) + 1, updatedAt: timestamp });
      return { ok: true, gradeId: gradeRef.id, alreadyExists: false };
    });
  }

  async function uploadPhoto(auth, payload) {
    checkObject(payload, ["schoolId", "studentId", "contentType", "base64"]);
    const schoolId = schoolIdFrom(payload.schoolId);
    const studentId = id(payload.studentId, true);
    requirePrincipal(auth, schoolId);
    const maxBytes = 5 * 1024 * 1024;
    if (!["image/jpeg", "image/png"].includes(payload.contentType) ||
      typeof payload.base64 !== "string" || payload.base64.length === 0 ||
      payload.base64.length > Math.ceil(maxBytes / 3) * 4 ||
      payload.base64.length % 4 !== 0 || /[^A-Za-z0-9+/=]/u.test(payload.base64)) invalid();
    const bytes = Buffer.from(payload.base64, "base64");
    if (bytes.length > maxBytes || bytes.toString("base64") !== payload.base64) invalid();
    const png = payload.contentType === "image/png";
    const validMagic = png ? bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) :
      bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes.at(-2) === 255 && bytes.at(-1) === 217;
    if (!validMagic) invalid();
    const uploadId = crypto.randomBytes(16).toString("hex");
    const reservationRef = db.doc(`schools/${schoolId}/_registration_photos/${studentId}`);
    await db.runTransaction(async (tx) => {
      const { config } = await readAccess(tx, auth, schoolId);
      if (config.permitirFotoAlumno === false) denied();
      const [existing, reservation] = await Promise.all([
        tx.get(db.doc(`schools/${schoolId}/alumnos/${studentId}`)), tx.get(reservationRef),
      ]);
      if (existing.exists) fail("already-exists", "La foto de este estudiante debe editarse desde su ficha.");
      const state = reservation.data() || {};
      if (state.owner && state.owner !== auth.uid) denied();
      if (state.status === "uploading" && timestampMs(state.expiresAt) > now()) {
        fail("resource-exhausted", "Espera a que termine la carga de la foto.");
      }
      // This lease outlives the callable's 120-second timeout. Register reads
      // it even when photoPath is null, preventing writes during an upload.
      tx.set(reservationRef, { owner: auth.uid, uploadId, status: "uploading",
        expiresAt: firestore.Timestamp.fromMillis(now() + 5 * 60 * 1000) });
    });
    const photoPath = `schools/${schoolId}/alumnos/${studentId}/profile.${png ? "png" : "jpg"}`;
    const file = getBucket().file(photoPath);
    try {
      let generation = 0;
      try {
        const [existing] = await file.getMetadata();
        if (existing.metadata?.registroUid !== auth.uid) denied();
        generation = existing.generation;
      } catch (error) {
        if (error.code !== 404) throw error;
      }
      await file.save(bytes, { resumable: false, preconditionOpts: { ifGenerationMatch: generation },
        metadata: { contentType: payload.contentType,
          metadata: { registroUid: auth.uid } } });
      const [saved] = await file.getMetadata();
      await db.runTransaction(async (tx) => {
        const { config } = await readAccess(tx, auth, schoolId);
        if (config.permitirFotoAlumno === false) denied();
        const [state, existing] = await Promise.all([
          tx.get(reservationRef), tx.get(db.doc(`schools/${schoolId}/alumnos/${studentId}`)),
        ]);
        if (existing.exists || state.data()?.uploadId !== uploadId || state.data()?.status !== "uploading") {
          fail("failed-precondition", "La carga de la foto venció. Inténtalo de nuevo.");
        }
        tx.set(reservationRef, { owner: auth.uid, uploadId, status: "ready", photoPath,
          generation: String(saved.generation), updatedAt: firestore.FieldValue.serverTimestamp() });
      });
    } catch (error) {
      await db.runTransaction(async (tx) => {
        const state = await tx.get(reservationRef);
        if (state.data()?.uploadId === uploadId) tx.set(reservationRef, { status: "failed" }, { merge: true });
      });
      throw error;
    }
    return { ok: true, photoPath };
  }

  async function endSession(auth, payload) {
    checkObject(payload, ["schoolId"]);
    const schoolId = schoolIdFrom(payload.schoolId);
    requirePrincipal(auth, schoolId);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(sessionRef(auth.uid));
      if (snap.exists && snap.data()?.schoolId !== schoolId) denied();
      if (snap.exists) tx.set(snap.ref, { enabled: false, revokedAt: firestore.FieldValue.serverTimestamp() }, { merge: true });
      return { ok: true };
    });
  }

  return { issueSession, registerStudent, createGrade, uploadPhoto, endSession };
}

module.exports = { createSchoolRegistration, SESSION_COLLECTION, SESSION_DURATION_MS, secretFingerprint, schoolAvailable };
