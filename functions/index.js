"use strict";

const crypto = require("crypto");
const {
  TEAM_ROLES, OPERATIONS_ROLES, SUPPORT_ROLES, BILLING_ROLES,
  canonicalTeamRole, teamScheduleAllows, validatePlanLimits,
  projectSchoolForRole, projectPayment,
} = require("./team_permissions");
const {
  normalizeSchoolId,
  randomAlphaNumCode,
  resolveClientIp,
  totpCounter,
  validateAuthInput,
} = require("./security");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { syncMetrics, readDerivedMetrics } = require("./school_metrics");
const { schoolAdministrator, principalUid } = require("./school_administrator");
const schoolCatalog = require("./school_catalog");
const { createSchoolRegistration } = require("./school_registration");
const { setGlobalOptions } = require("firebase-functions/v2");

admin.initializeApp();

// 🌎 Región global (ajústala si tu base principal está en otra región)
// Preserve the limit observed on all deployed functions during the audit.
// This bounds scaling; per-user and per-school authorization/quotas still apply.
setGlobalOptions({ region: "us-central1", maxInstances: 3 });

// App Check opcional (NO lo fuerzo para no romper tu app si aún no lo activas)
// Cuando lo tengas listo: ENFORCE_APPCHECK=true en env
const ENFORCE_APPCHECK = String(process.env.ENFORCE_APPCHECK || "false") === "true";
const ADMIN_LOGIN_IP_LIMITS_COL = "admin_login_ip_limits";
const SCHOOL_ACCESS_IPS_SUBCOL = "access_ips";
const ADMIN_LOGIN_STAGES = [
  { maxFailures: 5, lockMinutes: 15 },
  { maxFailures: 3, lockMinutes: 30 },
  { maxFailures: 1, lockMinutes: 24 * 60 },
];

function callableOptions(extra = {}) {
  return {
    cors: true,
    enforceAppCheck: ENFORCE_APPCHECK,
    ...extra,
  };
}

function assertAppCheckIfRequired(app) {
  if (ENFORCE_APPCHECK && !app) {
    throw new HttpsError(
      "failed-precondition",
      "App Check requerido para esta acciÃ³n."
    );
  }
}

function schoolRegistrationService() {
  return createSchoolRegistration({
    db: admin.firestore(), authService: admin.auth(), firestore: admin.firestore,
    HttpsError, getBucket: () => admin.storage().bucket(),
  });
}

// -------------------------
// Helpers
// -------------------------

function lower(v) {
  return typeof v === "string" ? v.trim().toLowerCase() : "";
}

function isSuperAdminRoleValue(value) {
  const role = lower(value);
  return role === "superadmin" || role === "super_admin";
}

function isEnabledData(d) {
  return !(typeof d?.enabled === "boolean") || d.enabled === true;
}

function trimOrNull(value) {
  const v = String(value || "").trim();
  return v ? v : null;
}

function keyOrNull(value) {
  const v = String(value || "").trim().toLowerCase();
  return v ? v : null;
}

const SCHOOL_WEB_BASE_URL = "https://edupro-8c4fd.web.app/#/eduproapp";
const DEFAULT_SCHOOL_MODULES = [
  "registro",
  "docentes",
  "alumnos",
  "calificaciones",
  "asistencia",
  "chat",
  "reportes",
];
const DEFAULT_SCHOOL_LEVELS = ["inicial", "primaria", "secundaria"];

function buildSchoolRoleLink(schoolId, moduleName) {
  return `${SCHOOL_WEB_BASE_URL}/${schoolId}/${moduleName}`;
}

async function generateUniqueSchoolCode(db) {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const code = randomAlphaNumCode(8);
    const snap = await db.doc(`schools/${code}`).get();
    if (!snap.exists) return code;
  }
  throw new HttpsError(
    "resource-exhausted",
    "No se pudo generar un codigo unico para la escuela."
  );
}

function defaultAdminsLimitForPlan(planTier) {
  switch (lower(planTier)) {
    case "plus":
      return 3;
    case "premium":
      return 5;
    case "enterprise":
      return 10;
    case "base":
    default:
      return 1;
  }
}

function defaultTeachersLimitForPlan(planTier) {
  switch (lower(planTier)) {
    case "plus":
      return 25;
    case "premium":
      return 60;
    case "enterprise":
      return 150;
    case "base":
    default:
      return 10;
  }
}

function defaultStudentsLimitForPlan(planTier) {
  switch (lower(planTier)) {
    case "plus":
      return 300;
    case "premium":
      return 900;
    case "enterprise":
      return 3000;
    case "base":
    default:
      return 150;
  }
}

function normalizeCurriculoDocs(rawDocs) {
  if (!Array.isArray(rawDocs)) return [];
  if (rawDocs.length > 200) {
    throw new HttpsError("invalid-argument", "El catalogo admite hasta 200 documentos por solicitud.");
  }
  return rawDocs
    .map((item) => ({
      title: String(item?.title || "").trim(),
      category: String(item?.category || "").trim(),
      url: String(item?.url || "").trim(),
    }))
    .filter((item) => item.title && item.category && item.url)
    .map((item) => {
      // Built-in PDFs are private Firebase Storage object paths. The client
      // resolves them with getDownloadURL() after Storage rules authorize it.
      const builtInPdf = /^curriculo\/base\/[A-Za-z0-9][A-Za-z0-9._-]*\.pdf$/.test(item.url);
      let url;
      if (!builtInPdf) {
        try { url = new URL(item.url); } catch (_) {}
      }
      if ((!builtInPdf && (!url || url.protocol !== "https:" || url.username || url.password)) ||
          item.title.length > 200 || item.category.length > 100 || item.url.length > 2048) {
        throw new HttpsError("invalid-argument", "Documento de curriculo invalido. Usa una ruta interna valida o un enlace HTTPS sin credenciales.");
      }
      return item;
    });
}

function buildSchoolPublicMeta(schoolData, schoolId) {
  const grades = Array.isArray(schoolData.grades) ? schoolData.grades : [];
  return {
    schoolId: String(schoolId || "").trim(),
    name: String(schoolData.name || schoolData.nombre || "").trim(),
    officialName: String(schoolData.officialName || schoolData.name || "").trim(),
    adminLink: String(schoolData.adminLink || "").trim(),
    profLink: String(schoolData.profLink || "").trim(),
    alumLink: String(schoolData.alumLink || "").trim(),
    adminDeepLink: String(schoolData.adminDeepLink || "").trim(),
    profDeepLink: String(schoolData.profDeepLink || "").trim(),
    alumDeepLink: String(schoolData.alumDeepLink || "").trim(),
    code: String(schoolData.code || schoolId || "").trim(),
    institutionCode: String(
      schoolData.institutionCode || schoolData.code || schoolId || ""
    ).trim(),
    grades,
    grados: grades,
    active: schoolData.active !== false,
    accountStatus: String(schoolData.accountStatus || schoolData.status || "").trim(),
    createdAt: schoolData.createdAt || admin.firestore.Timestamp.now(),
    updatedAt: schoolData.updatedAt || admin.firestore.FieldValue.serverTimestamp(),
  };
}

function validateEmail(email) {
  const e = String(email || "").trim().toLowerCase();
  // validación básica segura (sin ser ultra estricta)
  return e.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
}

function authPayload(data, schema = {}) {
  try {
    return validateAuthInput(data, {
      schoolId: { max: 160 },
      audience: { max: 40 },
      ...schema,
    });
  } catch (_) {
    throw new HttpsError("invalid-argument", "Revisa el formato y la longitud de los campos.");
  }
}

function schoolStatusFromData(data) {
  const raw = String(data?.accountStatus || data?.status || "").trim();
  if (raw) return lower(raw);
  return data?.active === false ? "suspendida" : "activa";
}

function schoolAvailableForTeacherSignup(data) {
  const active = typeof data?.active === "boolean" ? data.active === true : true;
  const status = schoolStatusFromData(data);
  return active && !["suspendida", "bloqueada", "vencida"].includes(status);
}

function clampInt(value, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return min;
  if (n < min) return min;
  if (n > max) return max;
  return Math.floor(n);
}

function normalizeAttemptFlow(value) {
  const v = lower(value);
  if (v === "google") return "google";
  if (v === "registro") return "registro";
  return "desconocido";
}

function normalizeAudience(value) {
  const v = lower(value);
  if (v === "admin" || v === "admin_escolar") return "admin_escolar";
  if (v === "docente" || v === "docentes" || v === "teacher" || v === "teachers") {
    return "docentes";
  }
  if (v === "alumno" || v === "alumnos" || v === "student" || v === "students") {
    return "alumnos";
  }
  return "";
}

function audienceUsesAutoRateLimit(audience) {
  return audience === "docentes" || audience === "alumnos";
}

function hashIp(ip) {
  return crypto.createHash("sha256").update(ip).digest("hex");
}

function schoolAccessIpDocId(audience, ipHash) {
  return `${audience}__${ipHash}`;
}

function schoolAccessIpRef(db, schoolId, audience, ipHash) {
  return db.doc(
    `schools/${schoolId}/${SCHOOL_ACCESS_IPS_SUBCOL}/${schoolAccessIpDocId(audience, ipHash)}`
  );
}

function stageConfig(stage) {
  const index = clampInt(stage, 0, ADMIN_LOGIN_STAGES.length - 1);
  return ADMIN_LOGIN_STAGES[index];
}

function timestampMillis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  if (typeof ts._seconds === "number") return ts._seconds * 1000;
  return 0;
}

function buildLockMessage(lockMinutes) {
  if (lockMinutes >= 24 * 60) {
    return "Esta IP quedó bloqueada por 24 horas por demasiados intentos fallidos.";
  }
  return `Demasiados intentos fallidos. Esta IP debe esperar ${lockMinutes} minutos antes de volver a intentar.`;
}

function normalizeAdminLoginIpState(data) {
  const stage = clampInt(data?.stage, 0, ADMIN_LOGIN_STAGES.length - 1);
  const consecutiveFailures = clampInt(data?.consecutiveFailures, 0, 1000);
  const lockUntil = data?.lockUntil ?? null;

  return {
    stage,
    consecutiveFailures,
    lockUntil,
  };
}

function safeTextEquals(expected, provided) {
  const a = Buffer.from(String(expected || ""), "utf8");
  const b = Buffer.from(String(provided || ""), "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

async function runAdminLoginRateLimit({
  db,
  ip,
  schoolId,
  attemptFlow,
  operation,
  reason = "",
}) {
  const ipHash = hashIp(ip);
  const ref = db.collection(ADMIN_LOGIN_IP_LIMITS_COL).doc(hashIp(`${schoolId}:${ipHash}`));
  const accessRef = schoolId ?
    schoolAccessIpRef(db, schoolId, "admin_escolar", ipHash) :
    null;
  const nowMs = Date.now();

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let state = normalizeAdminLoginIpState(snap.data());
    const currentLockUntilMs = timestampMillis(state.lockUntil);
    const lockActive = currentLockUntilMs > nowMs;
    let mutated = false;

    if (!lockActive && state.stage === ADMIN_LOGIN_STAGES.length - 1 && currentLockUntilMs > 0) {
      state = {
        stage: 0,
        consecutiveFailures: 0,
        lockUntil: null,
      };
      mutated = true;
    }

    if (operation === "precheck") {
      if (mutated) {
        tx.set(ref, {
          stage: 0,
          consecutiveFailures: 0,
          lockUntil: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSchoolId: schoolId,
          lastAttemptFlow: attemptFlow,
          ipSample: ip,
          version: 1,
        }, { merge: true });
        if (accessRef) {
          tx.set(accessRef, {
            schoolId,
            audience: "admin_escolar",
            ipHash,
            ipSample: ip,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            autoLockUntil: null,
            autoStage: 0,
            autoConsecutiveFailures: 0,
          }, { merge: true });
        }
      }

      if (lockActive) {
        const remainingSeconds = Math.max(
          1,
          Math.ceil((currentLockUntilMs - nowMs) / 1000)
        );
        return {
          allowed: false,
          blocked: true,
          stage: state.stage,
          attemptsRemaining: 0,
          lockUntilMs: currentLockUntilMs,
          waitSeconds: remainingSeconds,
          message: genericBlockedMessage(currentLockUntilMs, nowMs),
        };
      }

      const cfg = stageConfig(state.stage);
      const attemptsRemaining = Math.max(
        cfg.maxFailures - state.consecutiveFailures,
        1
      );

      return {
        allowed: true,
        blocked: false,
        stage: state.stage,
        attemptsRemaining,
        lockUntilMs: 0,
        waitSeconds: 0,
        message: "",
      };
    }

    if (operation === "success") {
      tx.set(ref, {
        stage: 0,
        consecutiveFailures: 0,
        lockUntil: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSuccessAt: admin.firestore.FieldValue.serverTimestamp(),
        totalSuccesses: admin.firestore.FieldValue.increment(1),
        lastAttemptFlow: attemptFlow,
        lastSchoolId: schoolId,
        ipSample: ip,
        version: 1,
        lastReason: null,
      }, { merge: true });
      if (accessRef) {
        tx.set(accessRef, {
          schoolId,
          audience: "admin_escolar",
          ipHash,
          ipSample: ip,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSuccessAt: admin.firestore.FieldValue.serverTimestamp(),
          totalSuccesses: admin.firestore.FieldValue.increment(1),
          autoLockUntil: null,
          autoStage: 0,
          autoConsecutiveFailures: 0,
          lastReason: null,
        }, { merge: true });
      }

      return {
        allowed: true,
        blocked: false,
        stage: 0,
        attemptsRemaining: ADMIN_LOGIN_STAGES[0].maxFailures,
        lockUntilMs: 0,
        waitSeconds: 0,
        message: "",
      };
    }

    if (lockActive) {
      const remainingSeconds = Math.max(
        1,
        Math.ceil((currentLockUntilMs - nowMs) / 1000)
      );
      return {
        allowed: false,
        blocked: true,
        stage: state.stage,
        attemptsRemaining: 0,
        lockUntilMs: currentLockUntilMs,
        waitSeconds: remainingSeconds,
        message: genericBlockedMessage(currentLockUntilMs, nowMs),
      };
    }

    const cfg = stageConfig(state.stage);
    let nextStage = state.stage;
    let nextConsecutive = state.consecutiveFailures + 1;
    let nextLockUntil = null;
    let blocked = false;
    let attemptsRemaining = Math.max(cfg.maxFailures - nextConsecutive, 0);
    let waitSeconds = 0;
    let message = "";

    if (nextConsecutive >= cfg.maxFailures) {
      blocked = true;
      nextLockUntil = admin.firestore.Timestamp.fromMillis(
        nowMs + (cfg.lockMinutes * 60 * 1000)
      );
      nextStage = Math.min(state.stage + 1, ADMIN_LOGIN_STAGES.length - 1);
      nextConsecutive = 0;
      attemptsRemaining = 0;
      waitSeconds = cfg.lockMinutes * 60;
      message = buildLockMessage(cfg.lockMinutes);
    }

    tx.set(ref, {
      stage: nextStage,
      consecutiveFailures: nextConsecutive,
      lockUntil: nextLockUntil,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
      totalFailures: admin.firestore.FieldValue.increment(1),
      lastAttemptFlow: attemptFlow,
      lastSchoolId: schoolId,
      ipSample: ip,
      version: 1,
      lastReason: reason,
    }, { merge: true });
    if (accessRef) {
      tx.set(accessRef, {
        schoolId,
        audience: "admin_escolar",
        ipHash,
        ipSample: ip,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
        lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
        totalFailures: admin.firestore.FieldValue.increment(1),
        autoLockUntil: nextLockUntil,
        autoStage: nextStage,
        autoConsecutiveFailures: nextConsecutive,
        lastReason: reason,
      }, { merge: true });
    }

    return {
      allowed: !blocked,
      blocked,
      stage: nextStage,
      attemptsRemaining,
      lockUntilMs: nextLockUntil ? nextLockUntil.toMillis() : 0,
      waitSeconds,
      message,
    };
  });
}

function resolveSchoolAccessLock(data, nowMs) {
  const manualLockUntilMs = timestampMillis(data?.manualLockUntil);
  const autoLockUntilMs = timestampMillis(data?.autoLockUntil);
  const lockUntilMs = Math.max(manualLockUntilMs, autoLockUntilMs);

  return {
    manualLockUntilMs,
    autoLockUntilMs,
    lockUntilMs,
    blocked: lockUntilMs > nowMs,
  };
}

function genericBlockedMessage(lockUntilMs, nowMs) {
  const waitSeconds = Math.max(1, Math.ceil((lockUntilMs - nowMs) / 1000));
  if (waitSeconds >= 24 * 60 * 60) {
    return "Esta IP está bloqueada por 24 horas.";
  }
  if (waitSeconds >= 60 * 60) {
    const hours = Math.ceil(waitSeconds / 3600);
    return `Esta IP está bloqueada por ${hours} hora${hours === 1 ? "" : "s"}.`;
  }
  const minutes = Math.max(1, Math.ceil(waitSeconds / 60));
  return `Esta IP está bloqueada por ${minutes} minuto${minutes === 1 ? "" : "s"}.`;
}

function mapSchoolAccessIpDoc(doc, nowMs) {
  const data = doc.data() || {};
  const lock = resolveSchoolAccessLock(data, nowMs);

  return {
    id: doc.id,
    schoolId: String(data.schoolId || ""),
    audience: normalizeAudience(data.audience),
    ipHash: String(data.ipHash || ""),
    ipSample: String(data.ipSample || ""),
    blocked: lock.blocked,
    lockUntilMs: lock.lockUntilMs,
    autoLockUntilMs: lock.autoLockUntilMs,
    manualLockUntilMs: lock.manualLockUntilMs,
    updatedAtMs: timestampMillis(data.updatedAt),
    lastSeenAtMs: timestampMillis(data.lastSeenAt),
    lastSuccessAtMs: timestampMillis(data.lastSuccessAt),
    lastFailureAtMs: timestampMillis(data.lastFailureAt),
    totalSuccesses: clampInt(data.totalSuccesses, 0, 100000000),
    totalFailures: clampInt(data.totalFailures, 0, 100000000),
    lastReason: String(data.lastReason || ""),
    blockedReason: String(data.manualBlockedReason || data.lastReason || ""),
    autoStage: clampInt(data.autoStage, 0, ADMIN_LOGIN_STAGES.length - 1),
    autoConsecutiveFailures: clampInt(data.autoConsecutiveFailures, 0, 1000000),
  };
}

// ✅ Fuente interna: users/{uid}, Users/{uid} o EquipoEduPro/{uid}
async function getInternalUserFromFirestore(uid) {
  const lowerSnap = await admin.firestore().doc(`users/${uid}`).get();
  if (lowerSnap.exists) return lowerSnap.data() || null;
  const upperSnap = await admin.firestore().doc(`Users/${uid}`).get();
  if (upperSnap.exists) return upperSnap.data() || null;
  const teamSnap = await admin.firestore().doc(`EquipoEduPro/${uid}`).get();
  if (teamSnap.exists) return teamSnap.data() || null;
  const legacyTeam = await admin.firestore().doc(`EquipoValMich/${uid}`).get();
  if (legacyTeam.exists) return legacyTeam.data() || null;
  return null;
}

async function hasInternalSuperAdminAccess(auth) {
  return (await internalTeamRole(auth)) === "super_admin";
}

async function internalTeamRole(auth) {
  if (!auth?.uid || auth.token?.firebase?.sign_in_provider === "anonymous") return "denied";
  const userData = await getInternalUserFromFirestore(auth.uid);
  const role = canonicalTeamRole(userData);
  if (role === "denied") return role;
  const teamSnap = await admin.firestore().doc(`EquipoEduPro/${auth.uid}`).get();
  const legacyTeam = teamSnap.exists ? null
    : await admin.firestore().doc(`EquipoValMich/${auth.uid}`).get();
  const schedule = teamSnap.exists ? teamSnap.data() : legacyTeam?.exists ? legacyTeam.data() : userData;
  return teamScheduleAllows(role, schedule) ? role : "denied";
}

async function assertTeamAccess({ auth, app }, roles = TEAM_ROLES, { requireSecondFactor = true } = {}) {
  if (!auth?.uid || auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Debes iniciar sesion con una cuenta del equipo.");
  }
  // Internal administration always requires App Check, even when a legacy
  // public endpoint still uses the project's optional enforcement setting.
  if (!app) throw new HttpsError("failed-precondition", "App Check requerido para esta accion.");
  const role = await internalTeamRole(auth);
  if (!roles.includes(role)) {
    throw new HttpsError("permission-denied", "Tu cuenta no tiene permiso o esta fuera de su horario de acceso.");
  }
  if (requireSecondFactor) await assertVerifiedSecondFactor(auth);
  return role;
}

async function isSchoolAdminForSchool(uid, schoolId, authToken = {}) {
  const db = admin.firestore();
  const schoolSnap = await db.doc(`schools/${schoolId}`).get();
  if (!schoolSnap.exists) return false;
  const memberSnap = await db.doc(`schools/${schoolId}/members/${uid}`).get();
  if (memberSnap.exists) {
    const member = memberSnap.data() || {};
    if (!isEnabledData(member)) return false;
    const role = lower(member.role || member.rol || member.enrol);
    if (isEnabledData(member) && (role === "admin" || role === "admin_escolar")) {
      return true;
    }
  }

  const school = schoolSnap.data() || {};
  if (String(school.adminUid || "").trim() === uid) return true;

  const tokenEmail = lower(authToken.email);
  return authToken.email_verified === true && !!tokenEmail && tokenEmail === lower(school.adminEmail);
}

async function assertSchoolAdminOrSuper({ auth, app, schoolId }) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  if (ENFORCE_APPCHECK && !app) {
    throw new HttpsError(
      "failed-precondition",
      "App Check requerido para esta acción."
    );
  }

  if (await hasInternalSuperAdminAccess(auth)) {
    await assertVerifiedSecondFactor(auth);
    return;
  }

  const ok = await isSchoolAdminForSchool(auth.uid, schoolId, auth.token || {});
  if (!ok) {
    throw new HttpsError(
      "permission-denied",
      "Solo la administración autorizada del colegio puede hacer este cambio."
    );
  }
  await assertVerifiedSecondFactor(auth);
}

async function assertLoginSuccessAccess(auth, schoolId, audience) {
  if (!auth?.uid || auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Debes iniciar sesion.");
  }
  if (audience === "admin_escolar") {
    if (await hasInternalSuperAdminAccess(auth) ||
        await isSchoolAdminForSchool(auth.uid, schoolId, auth.token || {})) return;
  } else {
    const index = audience === "docentes" ? "teachers_uid" : "alumnos_uid";
    const snap = await admin.firestore().doc(`schools/${schoolId}/${index}/${auth.uid}`).get();
    if (snap.exists && isEnabledData(snap.data())) return;
  }
  throw new HttpsError("permission-denied", "No tienes acceso a este colegio.");
}

function deriveRegistroSecret(password, saltHex) {
  return crypto.scryptSync(
    String(password || ""),
    String(saltHex || ""),
    64
  ).toString("hex");
}

function buildRegistroSecretPatch(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  return {
    passwordHash: deriveRegistroSecret(password, salt),
    passwordSalt: salt,
    passwordAlgo: "scrypt_v1",
    passwordUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    password: admin.firestore.FieldValue.delete(),
  };
}

const TWO_FACTOR_USERS_COL = "security_2fa_users";
const TWO_FACTOR_ISSUER = "EduPro";
const TWO_FACTOR_SECRET_BYTES = 20;
const TWO_FACTOR_STEP_SECONDS = 30;
const TWO_FACTOR_DIGITS = 6;
const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function normalizeTwoFactorAudience(value) {
  const v = lower(value);
  if (v === "admin_general" || v === "superadmin") return "admin_general";
  if (v === "admin_escolar" || v === "admin") return "admin_escolar";
  if (v === "docentes" || v === "docente" || v === "teacher") return "docentes";
  return "";
}

function twoFactorRef(db, uid) {
  return db.collection(TWO_FACTOR_USERS_COL).doc(uid);
}

function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let output = "";
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return output;
}

function base32Decode(input) {
  const clean = String(input || "")
    .toUpperCase()
    .replace(/=+$/g, "")
    .replace(/[^A-Z2-7]/g, "");
  let bits = 0;
  let value = 0;
  const bytes = [];
  for (const char of clean) {
    const idx = BASE32_ALPHABET.indexOf(char);
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

function generateTwoFactorSecret() {
  return base32Encode(crypto.randomBytes(TWO_FACTOR_SECRET_BYTES));
}

function generateTotpCode(secret, counter) {
  const key = base32Decode(secret);
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(counter));
  const digest = crypto.createHmac("sha1", key).update(buffer).digest();
  const offset = digest[digest.length - 1] & 0xf;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  return String(binary % (10 ** TWO_FACTOR_DIGITS)).padStart(
    TWO_FACTOR_DIGITS,
    "0"
  );
}

function buildTwoFactorUri({ secret, label }) {
  const account = String(label || "usuario");
  const path = encodeURIComponent(`${TWO_FACTOR_ISSUER}:${account}`);
  return `otpauth://totp/${path}?secret=${secret}&issuer=${encodeURIComponent(TWO_FACTOR_ISSUER)}&algorithm=SHA1&digits=${TWO_FACTOR_DIGITS}&period=${TWO_FACTOR_STEP_SECONDS}`;
}

async function assertTwoFactorAudienceAccess({ auth, audience, schoolId }) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesion.");
  }

  const db = admin.firestore();
  const normalizedAudience = normalizeTwoFactorAudience(audience);
  if (!normalizedAudience) {
    throw new HttpsError("invalid-argument", "audience invalida");
  }

  if (normalizedAudience === "admin_general") {
    if (!TEAM_ROLES.includes(await internalTeamRole(auth))) {
      throw new HttpsError("permission-denied", "Rol interno sin acceso a 2FA.");
    }
    return normalizedAudience;
  }

  if (!schoolId) {
    throw new HttpsError("invalid-argument", "schoolId requerido");
  }

  if (normalizedAudience === "admin_escolar") {
    const ok = await isSchoolAdminForSchool(auth.uid, schoolId, auth.token || {});
    if (!ok) {
      throw new HttpsError("permission-denied", "Solo la administracion del colegio puede usar este acceso.");
    }
    return normalizedAudience;
  }

  const teacherUidSnap = await db.doc(`schools/${schoolId}/teachers_uid/${auth.uid}`).get();
  if (!teacherUidSnap.exists || !isEnabledData(teacherUidSnap.data())) {
    throw new HttpsError("permission-denied", "Docente no autorizado para este colegio.");
  }
  return normalizedAudience;
}

async function readTwoFactorSecurityConfig() {
  const snap = await admin.firestore().doc("app_config/security").get();
  return snap.data() || {};
}

// Per-account policy is server-managed and cannot be changed by clients.
async function requiresSecondFactor(auth, security) {
  if (security.twoFAEnabled === true) return true;
  if (!auth?.uid) return false;
  const snap = await admin.firestore().doc(`security_2fa_policy/${auth.uid}`).get();
  return snap.data()?.required === true;
}

function hasVerifiedSecondFactor(auth, state) {
  const authTime = Number(auth?.token?.auth_time);
  const verifiedAt = timestampMillis(state?.lastVerifiedAt);
  return state?.enabled === true && Number.isFinite(authTime) && authTime > 0 &&
    state.lastVerifiedAuthTime === authTime && verifiedAt >= authTime * 1000 &&
    verifiedAt <= Date.now() + 60000 && Date.now() - verifiedAt <= 12 * 60 * 60 * 1000;
}

async function assertVerifiedSecondFactor(auth) {
  const security = await readTwoFactorSecurityConfig();
  if (!(await requiresSecondFactor(auth, security))) return;
  const snap = await twoFactorRef(admin.firestore(), auth.uid).get();
  if (!hasVerifiedSecondFactor(auth, snap.data())) {
    throw new HttpsError("permission-denied", "Completa la verificacion en dos pasos para continuar.");
  }
}

function normalizeTrustedDeviceEntries(security) {
  const detailed = Array.isArray(security?.trustedDeviceEntries) ?
    security.trustedDeviceEntries :
    [];

  const normalizedDetailed = detailed
    .map((item) => {
      const row = item && typeof item === "object" ? item : {};
      const deviceId = String(row.deviceId || "").trim();
      const deviceLabel = String(row.deviceLabel || row.label || "").trim();
      if (!deviceId || !deviceLabel) return null;
      return { deviceId, deviceLabel };
    })
    .filter(Boolean);

  if (normalizedDetailed.length > 0) {
    return normalizedDetailed;
  }

  const legacy = Array.isArray(security?.trustedDevices) ? security.trustedDevices : [];
  return legacy
    .map((value) => String(value || "").trim())
    .filter((value) => value.length > 0)
    .map((value) => ({ deviceId: value, deviceLabel: value }));
}

function normalizePendingTrustedDeviceEntries(security) {
  const pending = Array.isArray(security?.pendingTrustedDeviceEntries) ?
    security.pendingTrustedDeviceEntries :
    [];

  return pending
    .map((item) => {
      const row = item && typeof item === "object" ? item : {};
      const deviceId = String(row.deviceId || "").trim();
      const deviceLabel = String(row.deviceLabel || row.label || "").trim();
      if (!deviceId || !deviceLabel) return null;
      return {
        deviceId,
        deviceLabel,
        audience: normalizeTwoFactorAudience(row.audience),
        schoolId: normalizeSchoolId(row.schoolId),
        lastAttemptAt: row.lastAttemptAt || null,
      };
    })
    .filter(Boolean);
}

async function resolveTwoFactorAccountLabel(auth) {
  const tokenEmail = lower(auth?.token?.email);
  if (tokenEmail) return tokenEmail;

  const internalUser = await getInternalUserFromFirestore(auth.uid);
  const internalEmail = lower(internalUser?.email);
  if (internalEmail) return internalEmail;

  try {
    const userRecord = await admin.auth().getUser(auth.uid);
    const authEmail = lower(userRecord?.email);
    if (authEmail) return authEmail;
  } catch (_) {}

  return auth.uid;
}

function sanitizeTwoFactorCode(raw) {
  return String(raw || "").replace(/\s+/g, "").trim();
}

function assertRecentAuthentication(auth) {
  const authTime = Number(auth?.token?.auth_time);
  const ageSeconds = Date.now() / 1000 - authTime;
  if (!Number.isFinite(authTime) || ageSeconds < -60 || ageSeconds > 300) {
    throw new HttpsError("unauthenticated", "Vuelve a iniciar sesion para configurar la verificacion en dos pasos.");
  }
}

async function consumeRequestBudget(request, scope, limit = 60, windowMs = 60000) {
  const ip = resolveClientIp(request.rawRequest);
  const identity = request.auth?.uid || ip;
  if (!identity) {
    throw new HttpsError("failed-precondition", "No se pudo verificar el origen de la solicitud.");
  }
  const db = admin.firestore();
  // Preserve the existing account/IP counter and add an aggregate origin
  // counter so rotating authenticated accounts cannot bypass the IP budget.
  // The larger origin allowance accommodates schools behind a shared NAT.
  const budgets = [{ key: `${scope}:${identity}`, limit }];
  const sensitiveScope = ["two-factor-enrollment", "two-factor-code", "trusted-device",
    "registro-code", "teacher-signup-precheck", "admin-login-telemetry", "school-login-telemetry",
    "school-admin-account", "registro-config", "registro-student", "registro-grade", "registro-photo", "registro-session-end"].includes(scope);
  if (ip && sensitiveScope) budgets.push({ key: `${scope}:ip:${ip}`, limit: Math.max(120, limit * 10) });
  const refs = budgets.map(({ key }) => db.collection("security_request_limits").doc(hashIp(key)));
  const now = Date.now();
  const allowed = await db.runTransaction(async (tx) => {
    // All reads precede writes, and a rejected request never extends a lock.
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    const states = snapshots.map((snap) => {
      const state = snap.data() || {};
      const expires = timestampMillis(state.expiresAt);
      const count = expires > now ? Math.max(0, Number(state.count) || 0) : 0;
      return { expires, count };
    });
    if (states.some((state, i) => state.count >= budgets[i].limit)) return false;
    states.forEach((state, i) => tx.set(refs[i], {
      count: state.count + 1,
      expiresAt: admin.firestore.Timestamp.fromMillis(state.expires > now ? state.expires : now + windowMs),
    }));
    return true;
  });
  if (!allowed) {
    console.warn("auth_request_throttled", { scope });
    throw new HttpsError("resource-exhausted", "Demasiadas solicitudes. Espera antes de volver a intentar.");
  }
}

// The transaction persists failures before returning an error, prevents parallel
// guesses from bypassing the budget, and consumes each accepted TOTP only once.
async function verifyAndRecordTwoFactor({ auth, audience, schoolId, code, enrollment }) {
  const db = admin.firestore();
  const ref = twoFactorRef(db, auth.uid);
  const now = Date.now();
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.data() || {};
    if (timestampMillis(current.lockUntil) > now) return "locked";
    const secret = String(enrollment ? current.pendingSecret || "" : current.secret || "").trim();
    if (enrollment) {
      if (current.enabled === true) return "already-enrolled";
      const pendingCreated = timestampMillis(current.pendingCreatedAt);
      if (!secret || !pendingCreated || now - pendingCreated > 600000 ||
          current.pendingAudience !== audience || (current.pendingSchoolId || "") !== (schoolId || "")) {
        return "expired";
      }
    } else if (current.enabled !== true || !secret) {
      return "not-enrolled";
    }
    const counter = totpCounter(secret, code, now, generateTotpCode);
    if (counter === null || (Number.isFinite(current.lastUsedCounter) && counter <= current.lastUsedCounter)) {
      const failures = timestampMillis(current.lockUntil) > 0
        ? 1 : clampInt(current.failedAttempts, 0, 5) + 1;
      tx.set(ref, {
        failedAttempts: failures,
        lockUntil: failures >= 5 ? admin.firestore.Timestamp.fromMillis(now + 900000) : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return failures >= 5 ? "locked" : "invalid";
    }
    const patch = {
      failedAttempts: 0,
      lockUntil: null,
      lastUsedCounter: counter,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastVerifiedAuthTime: Number(auth.token?.auth_time || 0),
      lastVerifiedAudience: audience,
      lastVerifiedSchoolId: schoolId || null,
    };
    if (enrollment) Object.assign(patch, {
      secret,
      enabled: true,
      issuer: TWO_FACTOR_ISSUER,
      digits: TWO_FACTOR_DIGITS,
      stepSeconds: TWO_FACTOR_STEP_SECONDS,
      enrolledAt: admin.firestore.FieldValue.serverTimestamp(),
      pendingSecret: admin.firestore.FieldValue.delete(),
      pendingCreatedAt: admin.firestore.FieldValue.delete(),
      pendingAudience: admin.firestore.FieldValue.delete(),
      pendingSchoolId: admin.firestore.FieldValue.delete(),
    });
    tx.set(ref, patch, { merge: true });
    return "verified";
  });
  if (result === "locked") throw new HttpsError("resource-exhausted", "Demasiados intentos. Espera 15 minutos.");
  if (result === "invalid") throw new HttpsError("permission-denied", "Codigo incorrecto o ya utilizado. Espera un nuevo codigo.");
  if (result !== "verified") throw new HttpsError("failed-precondition", "La configuracion de verificacion no esta disponible. Revisa tu cuenta.");
}

exports.getEduProTwoFactorStatus = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {});
    const audience = normalizeTwoFactorAudience(payload.audience);
    const schoolId = normalizeSchoolId(payload.schoolId);

    await assertTwoFactorAudienceAccess({ auth, audience, schoolId });

    const security = await readTwoFactorSecurityConfig();
    const required = await requiresSecondFactor(auth, security);
    const ref = twoFactorRef(admin.firestore(), auth.uid);
    const snap = await ref.get();
    const twoFactor = snap.data() || {};

    return {
      ok: true,
      required,
      verified: !required || hasVerifiedSecondFactor(auth, twoFactor),
      enrolled: twoFactor.enabled === true && String(twoFactor.secret || "").trim().length > 0,
      issuer: TWO_FACTOR_ISSUER,
      digits: TWO_FACTOR_DIGITS,
      stepSeconds: TWO_FACTOR_STEP_SECONDS,
      accountLabel: await resolveTwoFactorAccountLabel(auth),
    };
  }
);

exports.startEduProTwoFactorEnrollment = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {});
    const audience = normalizeTwoFactorAudience(payload.audience);
    const schoolId = normalizeSchoolId(payload.schoolId);

    await assertTwoFactorAudienceAccess({ auth, audience, schoolId });
    assertRecentAuthentication(auth);
    await consumeRequestBudget(request, "two-factor-enrollment", 5, 900000);

    const security = await readTwoFactorSecurityConfig();
    if (!(await requiresSecondFactor(auth, security))) {
      throw new HttpsError(
        "failed-precondition",
        "La verificación en dos pasos no está habilitada."
      );
    }

    const db = admin.firestore();
    const ref = twoFactorRef(db, auth.uid);
    const secret = generateTwoFactorSecret();
    const accountLabel = await resolveTwoFactorAccountLabel(auth);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.data()?.enabled === true) {
        throw new HttpsError("failed-precondition", "La cuenta ya tiene un factor configurado. Usa el proceso de recuperacion verificado.");
      }
      tx.set(ref, {
        pendingSecret: secret,
        pendingCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
        pendingAudience: audience,
        pendingSchoolId: schoolId || null,
        accountLabel,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return {
      ok: true,
      required: true,
      secret,
      issuer: TWO_FACTOR_ISSUER,
      digits: TWO_FACTOR_DIGITS,
      stepSeconds: TWO_FACTOR_STEP_SECONDS,
      accountLabel,
      otpauthUri: buildTwoFactorUri({ secret, label: accountLabel }),
    };
  }
);

exports.confirmEduProTwoFactorEnrollment = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, { code: { max: 32, required: true } });
    const audience = normalizeTwoFactorAudience(payload.audience);
    const schoolId = normalizeSchoolId(payload.schoolId);
    const code = sanitizeTwoFactorCode(payload.code);

    await assertTwoFactorAudienceAccess({ auth, audience, schoolId });
    assertRecentAuthentication(auth);
    await consumeRequestBudget(request, "two-factor-code", 30, 900000);

    const security = await readTwoFactorSecurityConfig();
    if (!(await requiresSecondFactor(auth, security))) {
      throw new HttpsError(
        "failed-precondition",
        "La verificación en dos pasos no está habilitada."
      );
    }
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Código inválido.");
    }

    await verifyAndRecordTwoFactor({ auth, audience, schoolId, code, enrollment: true });

    return {
      ok: true,
      enrolled: true,
      required: true,
    };
  }
);

exports.verifyEduProTwoFactorCode = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, { code: { max: 32, required: true } });
    const audience = normalizeTwoFactorAudience(payload.audience);
    const schoolId = normalizeSchoolId(payload.schoolId);
    const code = sanitizeTwoFactorCode(payload.code);

    await assertTwoFactorAudienceAccess({ auth, audience, schoolId });
    await consumeRequestBudget(request, "two-factor-code", 30, 900000);

    const security = await readTwoFactorSecurityConfig();
    if (!(await requiresSecondFactor(auth, security))) {
      return {
        ok: true,
        required: false,
        verified: true,
      };
    }
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Código inválido.");
    }

    await verifyAndRecordTwoFactor({ auth, audience, schoolId, code, enrollment: false });

    return {
      ok: true,
      required: true,
      verified: true,
    };
  }
);

exports.checkEduProTrustedDevice = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, {
      deviceId: { max: 128, required: true }, deviceLabel: { max: 200, required: true },
    });
    const audience = normalizeTwoFactorAudience(payload.audience);
    const schoolId = normalizeSchoolId(payload.schoolId);
    const deviceId = String(payload.deviceId || "").trim();
    const deviceLabel = String(payload.deviceLabel || "").trim();

    if (!deviceId || !deviceLabel || deviceId.length > 128 || deviceLabel.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "deviceId y deviceLabel son requeridos."
      );
    }

    await assertTwoFactorAudienceAccess({ auth, audience, schoolId });
    await consumeRequestBudget(request, "trusted-device", 10);

    if (await hasInternalSuperAdminAccess(auth)) {
      return {
        ok: true,
        allowed: true,
        restricted: false,
        message: "",
      };
    }

    const security = await readTwoFactorSecurityConfig();
    const trustedDevices = normalizeTrustedDeviceEntries(security);

    if (trustedDevices.length === 0) {
      return {
        ok: true,
        allowed: true,
        restricted: false,
        message: "",
      };
    }

    const matched = trustedDevices.some((item) => item.deviceId === deviceId);

    if (!matched) {
      const pending = normalizePendingTrustedDeviceEntries(security);
      const existingIndex = pending.findIndex((item) => item.deviceId === deviceId);
      const nextEntry = {
        deviceId,
        deviceLabel,
        audience,
        schoolId: schoolId || "",
        lastAttemptAt: admin.firestore.Timestamp.now(),
      };

      if (existingIndex >= 0) {
        pending[existingIndex] = nextEntry;
      } else {
        pending.unshift(nextEntry);
      }

      await admin.firestore().doc("app_config/security").set({
        pendingTrustedDeviceEntries: pending.slice(0, 100),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    return {
      ok: true,
      allowed: matched,
      restricted: true,
      message: matched ?
        "" :
        `Este dispositivo (${deviceLabel}) no está en la lista de dispositivos confiables.`,
    };
  }
);

// Canonical Firestore documents are authoritative, including role revocation.
async function assertSuperAdmin({ auth, app }) {
  await assertTeamAccess({ auth, app }, ["super_admin"]);
}

// These endpoints expose a field allowlist and aggregates, not private school
// documents. Limited internal roles have no direct Firestore catalog access.
exports.getTeamAccess = onCall(callableOptions(), async (request) => {
  if (!request.auth?.uid || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "Inicia sesion con tu cuenta del equipo.");
  }
  if (!request.app) throw new HttpsError("failed-precondition", "App Check requerido.");
  const role = await internalTeamRole(request.auth);
  return { role, allowed: TEAM_ROLES.includes(role), enabled: TEAM_ROLES.includes(role) };
});

exports.listTeamSchools = onCall(callableOptions(), async (request) => {
  const role = await assertTeamAccess(request);
  await consumeRequestBudget(request, "team-catalog", 120);
  let options;
  try { options = schoolCatalog.validateCatalogQuery(request.data || {}); }
  catch (error) { throw new HttpsError("invalid-argument", error.message); }
  if (options.province && !SUPPORT_ROLES.includes(role)) {
    throw new HttpsError("permission-denied", "El rol de facturación no permite filtros geográficos.");
  }
  const db = admin.firestore();
  const state = await db.doc(schoolCatalog.META).get();
  if (state.data()?.ready !== true || state.data()?.schemaVersion !== schoolCatalog.VERSION) {
    throw new HttpsError("failed-precondition", "El catálogo está en preparación. Intenta nuevamente más tarde.");
  }
  return schoolCatalog.readCatalogPage(db, role, options, admin.firestore.FieldPath.documentId());
});

exports.syncTeamSchoolCatalog = onDocumentWritten({ document: "schools/{schoolId}",
  cpu: "gcf_gen1", concurrency: 1, memory: "256MiB", retry: true }, async (event) => {
  await schoolCatalog.syncCatalog(admin.firestore(), event.params.schoolId);
});

async function teamSchoolReference(payload) {
  const schoolId = normalizeSchoolId(payload?.schoolId);
  if (!schoolId) throw new HttpsError("invalid-argument", "Colegio invalido.");
  const ref = admin.firestore().doc(`schools/${schoolId}`);
  const school = await ref.get();
  if (!school.exists) throw new HttpsError("not-found", "No existe el colegio.");
  return { ref, school, schoolId };
}

exports.getTeamSchoolSummary = onCall(callableOptions(), async (request) => {
  const role = await assertTeamAccess(request, SUPPORT_ROLES);
  await consumeRequestBudget(request, "team-summary", 60);
  const { ref, school } = await teamSchoolReference(request.data);
  const collections = { totalTeachers: "teachers", totalStudents: "alumnos", totalUsers: "members",
    totalSubjects: "subjects", totalGrades: "grados", totalPlans: "planificaciones_anuales" };
  const counts = await Promise.all(Object.entries(collections).map(async ([key, collection]) => {
    const snapshot = await ref.collection(collection).count().get();
    return [key, snapshot.data().count];
  }));
  const data = school.data();
  const summary = { ...Object.fromEntries(counts), ...schoolAdministrator(data), fetchedAt: Date.now() };
  if (role !== "super_admin") return summary;
  const totals = Object.fromEntries(Object.entries(collections).map(([key, collection]) => [collection, summary[key]]));
  const assignedUid = principalUid(data);
  const [metrics, lastAccess, lastLogin, administrator, payments] = await Promise.all([
    readDerivedMetrics(ref, totals),
    ref.collection("members").orderBy("lastAccessAt", "desc").limit(1).select("lastAccessAt").get(),
    ref.collection("members").orderBy("lastLoginAt", "desc").limit(1).select("lastLoginAt").get(),
    assignedUid ? ref.collection("members").where(admin.firestore.FieldPath.documentId(), "==", assignedUid).limit(1)
      .select("name", "displayName", "nombre", "email").get() : Promise.resolve(null),
    ref.collection("payments").orderBy("createdAt", "desc").limit(1).select("status", "estado", "createdAt").get(),
  ]);
  const principal = administrator?.docs[0]?.data();
  const latest = payments.docs[0]?.data();
  const millis = (timestamp) => typeof timestamp?.toMillis === "function" ? timestamp.toMillis() : null;
  const accessDates = [millis(lastAccess.docs[0]?.data().lastAccessAt), millis(lastLogin.docs[0]?.data().lastLoginAt)]
    .filter((value) => value !== null);
  return { ...summary, ...metrics,
    ...schoolAdministrator(data, principal),
    lastAccessAt: accessDates.length ? Math.max(...accessDates) : null,
    paymentStatus: latest ? String(latest.status ?? latest.estado ?? "Reportado").trim() : "Sin pagos",
    lastPaymentAt: millis(latest?.createdAt),
  };
});

// Each trigger observes only its source collection; derived writes never recurse.
function schoolMetricsTrigger(collection) {
  return onDocumentWritten({ document: `schools/{schoolId}/${collection}/{recordId}`,
    cpu: "gcf_gen1", concurrency: 1, memory: "256MiB", retry: true }, async (event) => {
    await syncMetrics(admin.firestore(), event.params.schoolId, collection, event.params.recordId);
  });
}
exports.syncSchoolTeacherMetrics = schoolMetricsTrigger("teachers");
exports.syncSchoolStudentMetrics = schoolMetricsTrigger("alumnos");
exports.syncSchoolMemberMetrics = schoolMetricsTrigger("members");
exports.syncSchoolSubjectMetrics = schoolMetricsTrigger("subjects");
exports.syncSchoolPlanMetrics = schoolMetricsTrigger("planificaciones_anuales");

exports.getTeamSchoolBilling = onCall(callableOptions(), async (request) => {
  const role = await assertTeamAccess(request, BILLING_ROLES);
  await consumeRequestBudget(request, "team-billing", 60);
  const { ref, school } = await teamSchoolReference(request.data);
  const payments = await ref.collection("payments").orderBy("createdAt", "desc").limit(50).get();
  return { school: projectSchoolForRole(school.data(), role),
    payments: payments.docs.map((doc) => projectPayment(doc.data(), doc.id)) };
});

exports.updateSchoolPlanLimits = onCall(callableOptions(), async (request) => {
  await assertSuperAdmin(request);
  assertRecentAuthentication(request.auth);
  const reason = typeof request.data?.reason === "string" ? request.data.reason.trim() : "";
  if (reason.length < 10 || reason.length > 500) {
    throw new HttpsError("invalid-argument", "La justificacion debe tener entre 10 y 500 caracteres.");
  }
  let values;
  try { values = validatePlanLimits(request.data || {}, "super_admin", { requireAll: true }); }
  catch (error) { throw new HttpsError("invalid-argument", error.message); }
  const { ref, schoolId } = await teamSchoolReference(request.data);
  const db = admin.firestore();
  const audit = db.collection("team_audit").doc();
  await db.runTransaction(async (transaction) => {
    const previous = await transaction.get(ref);
    if (!previous.exists) throw new HttpsError("not-found", "No existe el colegio.");
    const updatedAt = admin.firestore.Timestamp.now();
    const next = { ...values,
      planLimits: { admins: values.adminsLimit, teachers: values.teachersLimit, students: values.studentsLimit },
      maxUsers: values.adminsLimit + values.teachersLimit + values.studentsLimit };
    transaction.update(ref, { ...next, updatedAt, updatedBy: request.auth.uid });
    transaction.set(audit, { action: "school.plan-limits.updated", schoolId, actorUid: request.auth.uid,
      actorRole: "super_admin", reason,
      before: projectSchoolForRole(previous.data(), "billing_admin"), after: next, createdAt: updatedAt });
  });
  return { success: true, schoolId };
});

// ==================================================
// upsertSchoolAdmin (CALLABLE v2) - seguro para EduPro
// ==================================================
exports.upsertSchoolAdmin = onCall(callableOptions(), async (request) => {
  const { data, auth, app } = request;

  await assertSuperAdmin({ auth, app });

  // Data hardening
  const payload = authPayload(data ?? {}, {
    email: { max: 254, email: true }, adminEmail: { max: 254, email: true },
    password: { max: 128, secret: true }, adminPassword: { max: 128, secret: true },
    allowPasswordUpdate: { type: "boolean" }, setSchoolAdminClaims: { type: "boolean" },
  });

  // ✅ schoolId: acepta "eduproapp_admin_XXXX" o "XXXX"
  const schoolId = normalizeSchoolId(payload.schoolId);

  const email = lower(payload.email || payload.adminEmail);
  const password = payload.password ?? payload.adminPassword;

  // Por defecto: NO cambiar password de un usuario existente (seguridad + no romper cuentas)
  const allowPasswordUpdate = payload.allowPasswordUpdate === true;

  // (Opcional) si luego quieres claims para el admin escolar, lo activas con flag
  const setSchoolAdminClaims = payload.setSchoolAdminClaims === true;

  if (!schoolId) {
    throw new HttpsError("invalid-argument", "schoolId requerido");
  }

  if (!email || !validateEmail(email)) {
    throw new HttpsError("invalid-argument", "email inválido");
  }

  await consumeRequestBudget(request, "school-admin-account", 30);

  const db = admin.firestore();

  // ✅ No crear el colegio accidentalmente: debe existir
  const schoolRef = db.doc(`schools/${schoolId}`);
  const schoolSnap = await schoolRef.get();
  if (!schoolSnap.exists) {
    throw new HttpsError(
      "not-found",
      `El colegio '${schoolId}' no existe en /schools. Crea el colegio primero.`
    );
  }

  try {
    let userRecord = null;
    let created = false;

    // 1) Buscar usuario por email en Auth
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e?.code !== "auth/user-not-found") throw e;
    }

    // Check privileged identities before any password mutation.
    if (userRecord && await getInternalUserFromFirestore(userRecord.uid)) {
      throw new HttpsError("permission-denied", "Usa una cuenta exclusiva para la administracion escolar.");
    }

    // 2) Crear si no existe
    if (!userRecord) {
      // Apply the server policy even when the UI is bypassed.
      if (!password || password.length < 12 || password.length > 128) {
        throw new HttpsError(
          "failed-precondition",
          "Password requerido (entre 12 y 128 caracteres)."
        );
      }

      userRecord = await admin.auth().createUser({
        email,
        password,
      });

      created = true;
    } else {
      // 3) Si existe, NO tocar password a menos que explícitamente lo permitan
      if (password && password.length > 0) {
        if (!allowPasswordUpdate) {
          throw new HttpsError(
            "failed-precondition",
            "El usuario ya existe. Para cambiar password, envía allowPasswordUpdate:true."
          );
        }

        if (password.length < 12 || password.length > 128) {
          throw new HttpsError(
            "invalid-argument",
            "Password invalido (entre 12 y 128 caracteres)."
          );
        }

        await admin.auth().updateUser(userRecord.uid, {
          password,
        });
      }
    }

    // 4) Bloqueo: no permitir usar un email que sea de staff interno (users/{uid} existe)
    const internalDoc = await db.doc(`users/${userRecord.uid}`).get();
    if (internalDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "Ese email pertenece a un usuario interno de EduPro. Usa otro email para admin escolar."
      );
    }

    // 5) Actualizar SOLO el doc existente del colegio (no crear)
    await schoolRef.update({
      adminEmail: email,
      adminUid: userRecord.uid,
      adminPasswordSet: true, // indica que el admin existe en Auth
      adminUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      adminUpdatedBy: auth.uid, // auditoría
    });

    // 6) (Opcional) Claims para reglas futuras del admin escolar
    if (setSchoolAdminClaims) {
      const full = await admin.auth().getUser(userRecord.uid);
      const currentClaims = full.customClaims || {};
      await admin.auth().setCustomUserClaims(userRecord.uid, {
        ...currentClaims,
        schoolAdmin: true,
        schoolId, // ojo: si en tu modelo el admin puede manejar varias escuelas, cambia esto a lista
      });
    }

    return {
      ok: true,
      created,
      uid: userRecord.uid,
      email,
      schoolId,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    const code = e?.code || "";

    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Ese email ya existe en Auth.");
    }

    if (code === "auth/invalid-password") {
      throw new HttpsError("invalid-argument", "Password inválido.");
    }

    console.error("upsertSchoolAdmin failed", { code: String(code).slice(0, 80) });
    throw new HttpsError("internal", "No se pudo actualizar la cuenta. Intenta de nuevo o contacta soporte.");
  }
});


exports.assignSchoolAdmin = onCall(
  callableOptions(),
  async (request) => {
    await assertSuperAdmin({ auth: request.auth, app: request.app });
    const payload = authPayload(request.data ?? {}, {
      schoolCode: { max: 160, required: true }, email: { max: 254, email: true, required: true },
      createIfMissing: { type: "boolean" },
    });
    const { schoolCode, email } = payload;
    const createIfMissing = payload.createIfMissing === true;
    const normalizedEmail = lower(email);

    if (!normalizeSchoolId(schoolCode) || !validateEmail(normalizedEmail)) {
      throw new HttpsError("invalid-argument", "Datos incompletos");
    }

    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }

    const callerAuth = request.auth || null;
    const allowed = await hasInternalSuperAdminAccess(callerAuth);
    if (!allowed) {
      throw new HttpsError("permission-denied", "No autorizado");
    }

    const normalizedSchool = normalizeSchoolId(schoolCode);
    const db = admin.firestore();
    const schoolRef = db.doc(`schools/${normalizedSchool}`);
    const schoolSnap = await schoolRef.get();
    if (!schoolSnap.exists) {
      throw new HttpsError("not-found", "El colegio no existe.");
    }
    const previousUid = String(schoolSnap.data()?.adminUid || "").trim();
    const previousMemberRef = previousUid
      ? db.doc(`schools/${normalizedSchool}/members/${previousUid}`)
      : null;
    const previousMember = previousMemberRef ? await previousMemberRef.get() : null;

    let userRecord;
    let created = false;
    try {
      userRecord = await admin.auth().getUserByEmail(normalizedEmail);
    } catch (error) {
      if (error?.code !== "auth/user-not-found") {
        throw error;
      }
      if (!createIfMissing) {
        throw new HttpsError(
          "not-found",
          "El correo aún no tiene cuenta. Activa la opción de crearla para asignarlo."
        );
      }
      // El administrador define su propia clave con el correo de restablecimiento.
      // Esta clave aleatoria no se envía al cliente ni se guarda en Firestore.
      try {
        userRecord = await admin.auth().createUser({
          email: normalizedEmail,
          password: crypto.randomBytes(32).toString("base64url"),
          emailVerified: false,
        });
        created = true;
      } catch (createError) {
        if (createError?.code !== "auth/email-already-exists") throw createError;
        userRecord = await admin.auth().getUserByEmail(normalizedEmail);
      }
    }

    const uid = userRecord.uid;
    if (await getInternalUserFromFirestore(uid)) {
      if (created) await admin.auth().deleteUser(uid);
      throw new HttpsError("permission-denied", "Usa una cuenta exclusiva para la administracion escolar.");
    }
    const batch = db.batch();

    // La pantalla asigna un administrador principal. Al reemplazarlo, su
    // membresía anterior no debe seguir concediendo acceso al colegio.
    if (previousUid && previousUid !== uid) {
      if (previousMember?.exists && previousMember.data()?.role === "admin_escolar") {
        batch.update(previousMemberRef, {
          enabled: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    batch.set(db.doc(`schools/${normalizedSchool}/members/${uid}`), {
      uid: uid,
      role: "admin_escolar",
      audience: "admin",
      enabled: true,
      tokens: [],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastTokenAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    batch.update(schoolRef, {
      adminEmail: normalizedEmail,
      adminUid: uid,
      adminPasswordSet: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (error) {
      if (created) {
        try {
          await admin.auth().deleteUser(uid);
        } catch (cleanupError) {
          console.error("assignSchoolAdmin cleanup failed", cleanupError?.code || "unknown");
        }
      }
      throw error;
    }

    return { success: true, created, email: normalizedEmail };
  }
);

function validatedSchoolCoordinates(payload) {
  const latitude = payload?.latitude;
  const longitude = payload?.longitude;
  if (typeof latitude !== "number" || typeof longitude !== "number" ||
      !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < 17.3 || latitude > 20.2 ||
      longitude < -72.1 || longitude > -68.0) {
    throw new HttpsError(
      "invalid-argument",
      "Selecciona una ubicación válida del colegio en República Dominicana."
    );
  }
  return {
    latitude: Math.round(latitude * 1000000) / 1000000,
    longitude: Math.round(longitude * 1000000) / 1000000,
  };
}

exports.createSchool = onCall(
  callableOptions(),
  async (request) => {
    assertAppCheckIfRequired(request.app);
    const auth = request.auth || null;
    const teamRole = await assertTeamAccess(request, OPERATIONS_ROLES);
    // School creation requires a fresh provider reauthentication. A client-side
    // PIN can be skipped by calling this endpoint directly, so it is not used.
    assertRecentAuthentication(auth);
    if (!auth?.uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesion.");
    }

    const optionalText = (max) => ({ max, nullable: true });
    const payload = authPayload(request.data ?? {}, {
      nombre: { max: 200, required: true }, officialName: optionalText(200),
      adminEmail: { max: 254, email: true, nullable: true },
      contactEmail: { max: 254, email: true, nullable: true },
      contactName: optionalText(200), contactRole: optionalText(100),
      contactPhone: optionalText(40), contactWhatsApp: optionalText(40),
      schoolType: optionalText(80), country: optionalText(100), timezone: optionalText(100),
      regionalCode: optionalText(40), regionalName: optionalText(200),
      districtCode: optionalText(40), districtName: optionalText(200),
      province: optionalText(200), municipality: optionalText(200), sector: optionalText(200),
      addressLine: optionalText(1000),
    });
    let validatedLimits;
    try { validatedLimits = validatePlanLimits(payload, teamRole); }
    catch (error) { throw new HttpsError("invalid-argument", error.message); }
    const coordinates = validatedSchoolCoordinates(payload);
    const cleanName = payload.nombre.trim();
    if (!cleanName || cleanName.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "Debes indicar el nombre del colegio."
      );
    }
    // El correo de contacto por sí solo no concede acceso. Solo el campo
    // adminEmail explícito crea/asigna una identidad de administración escolar.
    const adminEmail = lower(payload.adminEmail);
    if (adminEmail && teamRole !== "super_admin") {
      throw new HttpsError("permission-denied", "Solo el superadministrador puede asignar la administracion escolar.");
    }
    if (adminEmail && !validateEmail(adminEmail)) {
      throw new HttpsError("invalid-argument", "Correo del administrador escolar inválido.");
    }

    const db = admin.firestore();
    const schoolId = await generateUniqueSchoolCode(db);
    const registroPassword = randomAlphaNumCode(16);
    const { planTier: plan, adminsLimit, teachersLimit, studentsLimit } = validatedLimits;

    const internalUser = await getInternalUserFromFirestore(auth.uid);
    const creatorEmail = trimOrNull(auth.token?.email) || trimOrNull(internalUser?.email);
    const creatorName =
      trimOrNull(internalUser?.displayName) ||
      trimOrNull(internalUser?.name) ||
      trimOrNull(auth.token?.name);
    const now = admin.firestore.Timestamp.now();

    const data = {
      name: cleanName,
      officialName: trimOrNull(payload.officialName) || cleanName,
      code: schoolId,
      institutionCode: schoolId,
      adminLink: buildSchoolRoleLink(schoolId, "admin"),
      profLink: buildSchoolRoleLink(schoolId, "docentes"),
      alumLink: buildSchoolRoleLink(schoolId, "alumnos"),
      adminDeepLink: `eduproapp://${schoolId}/admin`,
      profDeepLink: `eduproapp://${schoolId}/docentes`,
      alumDeepLink: `eduproapp://${schoolId}/alumnos`,
      grades: [],
      active: true,
      accountStatus: "activa",
      lifecycleStage: "activa",
      planTier: plan,
      planPrice: 0,
      billingCycle: "monthly",
      maxUsers: adminsLimit + teachersLimit + studentsLimit,
      planLimits: {
        admins: adminsLimit,
        teachers: teachersLimit,
        students: studentsLimit,
      },
      adminsLimit,
      teachersLimit,
      studentsLimit,
      modulesEnabled: DEFAULT_SCHOOL_MODULES,
      levelsEnabled: DEFAULT_SCHOOL_LEVELS,
      createdAt: now,
      updatedAt: now,
      startedAt: now,
      renewalAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000
      ),
      createdByUid: auth.uid,
      createdByEmail: creatorEmail,
      createdByName: creatorName,
      createdByAt: now,
    };

    const schoolType = trimOrNull(payload.schoolType);
    const country = trimOrNull(payload.country);
    const timezone = trimOrNull(payload.timezone);
    if (schoolType) data.schoolType = schoolType;
    if (country) data.country = country;
    if (timezone) data.timezone = timezone;

    const regionalCode = trimOrNull(payload.regionalCode);
    const regionalName = trimOrNull(payload.regionalName);
    const districtCode = trimOrNull(payload.districtCode);
    const districtName = trimOrNull(payload.districtName);
    if (regionalCode) data.regionalCode = regionalCode;
    if (regionalName) data.regionalName = regionalName;
    if (districtCode) data.districtCode = districtCode;
    if (districtName) data.districtName = districtName;
    const districtKey = keyOrNull(districtCode);
    if (districtKey) data.districtKey = districtKey;

    const location = { ...coordinates, source: "manual_pin" };
    const province = trimOrNull(payload.province);
    const municipality = trimOrNull(payload.municipality);
    const sector = trimOrNull(payload.sector);
    const addressLine = trimOrNull(payload.addressLine);
    if (province) location.province = province;
    if (municipality) location.municipality = municipality;
    if (sector) location.sector = sector;
    if (addressLine) location.addressLine = addressLine;
    if (Object.keys(location).length > 0) data.location = location;
    data.locationUpdatedAt = now;
    data.locationUpdatedBy = auth.uid;

    const contact = {};
    const contactName = trimOrNull(payload.contactName);
    const contactRole = trimOrNull(payload.contactRole);
    const contactPhone = trimOrNull(payload.contactPhone);
    const contactWhatsApp = trimOrNull(payload.contactWhatsApp);
    const contactEmail = trimOrNull(payload.contactEmail);
    if (contactName) contact.name = contactName;
    if (contactRole) contact.role = contactRole;
    if (contactPhone) contact.phone = contactPhone;
    if (contactWhatsApp) contact.whatsapp = contactWhatsApp;
    if (contactEmail) contact.email = contactEmail;
    if (Object.keys(contact).length > 0) data.contact = contact;

    const foundedAtMillis = Number(payload.foundedAtMillis || 0);
    if (Number.isFinite(foundedAtMillis) && foundedAtMillis > 0) {
      const foundedAt = new Date(foundedAtMillis);
      if (!Number.isNaN(foundedAt.getTime())) {
        data.foundedAt = admin.firestore.Timestamp.fromDate(foundedAt);
        data.foundedYear = foundedAt.getFullYear();
      }
    }

    const schoolRef = db.doc(`schools/${schoolId}`);
    const publicMetaRef = db.doc(`schools/${schoolId}/public/meta`);
    const registroConfigRef = db.doc(`schools/${schoolId}/config/registro`);
    const curriculoDocs = normalizeCurriculoDocs(payload.curriculoDocs);
    let adminUser = null;
    let adminAccountCreated = false;
    if (adminEmail) {
      try {
        adminUser = await admin.auth().getUserByEmail(adminEmail);
      } catch (error) {
        if (error?.code !== "auth/user-not-found") throw error;
        try {
          adminUser = await admin.auth().createUser({
            email: adminEmail,
            password: crypto.randomBytes(32).toString("base64url"),
            emailVerified: false,
          });
          adminAccountCreated = true;
        } catch (createError) {
          if (createError?.code !== "auth/email-already-exists") throw createError;
          adminUser = await admin.auth().getUserByEmail(adminEmail);
        }
      }
      if (!adminAccountCreated && await getInternalUserFromFirestore(adminUser.uid)) {
        throw new HttpsError(
          "permission-denied",
          "Usa una cuenta exclusiva para la administración escolar."
        );
      }
      data.adminEmail = adminEmail;
      data.adminUid = adminUser.uid;
      data.adminPasswordSet = true;
      data.adminUpdatedAt = now;
      data.adminUpdatedBy = auth.uid;
    }
    const batch = db.batch();

    batch.set(schoolRef, data);
    batch.set(db.doc(`${schoolCatalog.COLLECTION}/${schoolId}`), schoolCatalog.buildCatalogEntry(schoolId, data));
    if (adminUser) {
      batch.set(db.doc(`schools/${schoolId}/members/${adminUser.uid}`), {
        uid: adminUser.uid,
        role: "admin_escolar",
        audience: "admin",
        enabled: true,
        tokens: [],
        updatedAt: now,
        lastTokenAt: now,
      });
    }
    batch.set(publicMetaRef, buildSchoolPublicMeta(data, schoolId), { merge: true });
    batch.set(
      registroConfigRef,
      {
        permitirFotoAlumno: true,
        permitirEditarEstudiantes: true,
        updatedAt: now,
        ...buildRegistroSecretPatch(registroPassword),
      },
      { merge: true }
    );

    curriculoDocs.forEach((doc, index) => {
      const docId = `doc_${String(index + 1).padStart(2, "0")}`;
      batch.set(
        db.doc(`schools/${schoolId}/curriculo_docs/${docId}`),
        {
          title: doc.title,
          category: doc.category,
          url: doc.url,
          order: index + 1,
          active: true,
          createdAt: now,
          updatedAt: now,
        },
        { merge: true }
      );
    });

    try {
      await batch.commit();
    } catch (error) {
      if (adminAccountCreated) {
        try {
          await admin.auth().deleteUser(adminUser.uid);
        } catch (cleanupError) {
          console.error("createSchool admin cleanup failed", cleanupError?.code || "unknown");
        }
      }
      throw error;
    }

    return {
      ok: true,
      schoolId,
      code: schoolId,
      password: registroPassword,
      officialName: data.officialName,
      planTier: plan,
      adminEmail: adminEmail || null,
      adminAccountCreated,
    };
  }
);

exports.updateSchoolLocation = onCall(callableOptions(), async (request) => {
  assertAppCheckIfRequired(request.app);
  const auth = request.auth || null;
  await assertTeamAccess(request, OPERATIONS_ROLES);
  assertRecentAuthentication(auth);
  const payload = request.data || {};
  const schoolId = normalizeSchoolId(payload.schoolId);
  if (!schoolId) {
    throw new HttpsError("invalid-argument", "Código de colegio inválido.");
  }
  const coordinates = validatedSchoolCoordinates(payload);
  const db = admin.firestore();
  const schoolRef = db.doc(`schools/${schoolId}`);
  await db.runTransaction(async (transaction) => {
    const school = await transaction.get(schoolRef);
    if (!school.exists) throw new HttpsError("not-found", "No existe el colegio.");
    const location = { ...(school.data().location || {}), ...coordinates, source: "manual_pin" };
    transaction.update(schoolRef, { location, locationUpdatedAt: admin.firestore.Timestamp.now(), locationUpdatedBy: auth.uid });
    transaction.set(db.doc(`${schoolCatalog.COLLECTION}/${schoolId}`),
      schoolCatalog.buildCatalogEntry(schoolId, { ...school.data(), location }));
  });
  return { success: true, schoolId };
});

exports.adminSchoolLoginRateLimit = onCall(
  callableOptions(),
  async (request) => {
    const { data, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, {
      operation: { max: 20, required: true }, attemptFlow: { max: 32 }, reason: { max: 120 },
    });
    const operation = lower(payload.operation);
    const attemptFlow = normalizeAttemptFlow(payload.attemptFlow);
    const schoolId = normalizeSchoolId(payload.schoolId);
    const reason = String(payload.reason || "").trim().slice(0, 120);

    if (!["precheck", "failure", "success"].includes(operation)) {
      throw new HttpsError("invalid-argument", "operation inválida");
    }
    if (!schoolId) throw new HttpsError("invalid-argument", "schoolId requerido");
    if (operation === "success") {
      await assertLoginSuccessAccess(request.auth, schoolId, "admin_escolar");
    }
    await consumeRequestBudget(request, "admin-login-telemetry", 120);

    const rawRequest = request.rawRequest;
    const ip = resolveClientIp(rawRequest);
    if (!ip) {
      throw new HttpsError(
        "failed-precondition",
        "No se pudo resolver la IP del cliente."
      );
    }

    const db = admin.firestore();
    const result = await runAdminLoginRateLimit({
      db,
      ip,
      schoolId,
      attemptFlow,
      operation,
      reason,
    });

    return result;
  }
);

exports.validateSchoolRegistroAccess = onCall(
  callableOptions(),
  async (request) => {
    const { data, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, { code: { max: 128, required: true, secret: true } });
    const schoolId = normalizeSchoolId(payload.schoolId);
    const code = payload.code;

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }
    if (!code || code.length > 128) {
      throw new HttpsError("invalid-argument", "code requerido");
    }
    await consumeRequestBudget(request, "registro-code", 30);

    const ip = resolveClientIp(request.rawRequest);
    if (!ip) {
      throw new HttpsError(
        "failed-precondition",
        "No se pudo resolver la IP del cliente."
      );
    }

    const db = admin.firestore();
    const precheck = await runAdminLoginRateLimit({
      db,
      ip,
      schoolId,
      attemptFlow: "registro",
      operation: "precheck",
    });

    if (!precheck.allowed) {
      return {
        ok: false,
        blocked: true,
        configured: true,
        waitSeconds: precheck.waitSeconds || 0,
        lockUntilMs: precheck.lockUntilMs || 0,
        message: precheck.message || "Esta IP debe esperar antes de volver a intentar.",
      };
    }

    const registroSnap = await db.doc(`schools/${schoolId}/config/registro`).get();
    const registro = registroSnap.data() || {};
    const expectedLegacy = typeof registro.password === "string" ? registro.password : "";
    const expectedHash = String(registro.passwordHash || "").trim();
    const expectedSalt = String(registro.passwordSalt || "").trim();
    const expectedAlgo = String(registro.passwordAlgo || "").trim();

    let matches = false;
    let migrateLegacy = false;

    if (expectedHash && expectedSalt && expectedAlgo === "scrypt_v1") {
      const providedHash = deriveRegistroSecret(code, expectedSalt);
      matches = safeTextEquals(expectedHash, providedHash);
    } else if (expectedLegacy) {
      matches = safeTextEquals(expectedLegacy, code);
      migrateLegacy = matches;
    }

    if (!expectedLegacy && !expectedHash) {
      return {
        ok: false,
        blocked: false,
        configured: false,
        message: "Aún no se ha generado el código de registro para este colegio.",
      };
    }

    if (!matches) {
      const failure = await runAdminLoginRateLimit({
        db,
        ip,
        schoolId,
        attemptFlow: "registro",
        operation: "failure",
        reason: "wrong_code",
      });

      return {
        ok: false,
        blocked: failure.blocked === true,
        configured: true,
        waitSeconds: Number(failure.waitSeconds || 0),
        lockUntilMs: Number(failure.lockUntilMs || 0),
        message: failure.blocked === true ?
          (failure.message || "Esta IP fue bloqueada temporalmente.") :
          "Código incorrecto.",
        };
      }

    const session = await schoolRegistrationService().issueSession({
      schoolId,
      expectedConfig: registro,
      previousAuth: request.auth,
      migrationPatch: migrateLegacy ? {
        ...buildRegistroSecretPatch(code),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        legacyMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : undefined,
    });

    await runAdminLoginRateLimit({
      db,
      ip,
      schoolId,
      attemptFlow: "registro",
      operation: "success",
    });

    return {
      ok: true,
      blocked: false,
      configured: true,
      ...session,
    };
  }
);

exports.setSchoolRegistroConfig = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;
    const payload = authPayload(data ?? {}, {
      password: { max: 128, secret: true }, permitirFotoAlumno: { type: "boolean" },
      permitirEditarEstudiantes: { type: "boolean" },
    });
    const schoolId = normalizeSchoolId(payload.schoolId);
    console.info("[setSchoolRegistroConfig] start", {
      schoolId,
      hasAuth: !!(auth && auth.uid),
      hasAppCheck: !!app,
      hasPassword: (payload.password || "").length > 0,
      permitirFotoAlumno: payload.permitirFotoAlumno,
      permitirEditarEstudiantes: payload.permitirEditarEstudiantes,
    });

    if (!schoolId) {
      console.warn("[setSchoolRegistroConfig] invalid_schoolId");
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }

    await assertSchoolAdminOrSuper({ auth, app, schoolId });
    await consumeRequestBudget(request, "registro-config", 10);
    console.info("[setSchoolRegistroConfig] access_granted", {
      schoolId,
    });

    const db = admin.firestore();
    const ref = db.doc(`schools/${schoolId}/config/registro`);
    const snap = await ref.get();
    const current = snap.data() || {};
    console.info("[setSchoolRegistroConfig] current_state", {
      schoolId,
      exists: snap.exists,
      hasPasswordHash: String(current.passwordHash || "").trim().length > 0,
      hasLegacyPassword: String(current.password || "").trim().length > 0,
      permitirFotoAlumno: current.permitirFotoAlumno,
      permitirEditarEstudiantes: current.permitirEditarEstudiantes,
    });

    const incomingPassword = payload.password || "";
    const hasExistingSecret =
      String(current.passwordHash || "").trim().length > 0 ||
      (typeof current.password === "string" && current.password.length > 0);

    if (!incomingPassword && !hasExistingSecret) {
      console.warn("[setSchoolRegistroConfig] missing_initial_password", {
        schoolId,
      });
      throw new HttpsError(
        "failed-precondition",
        "Debes definir una clave inicial para el equipo de registro."
      );
    }

    const permitirFotoAlumno = typeof payload.permitirFotoAlumno === "boolean" ?
      payload.permitirFotoAlumno :
      current.permitirFotoAlumno !== false;
    const permitirEditarEstudiantes = typeof payload.permitirEditarEstudiantes === "boolean" ?
      payload.permitirEditarEstudiantes :
      current.permitirEditarEstudiantes !== false;

    const patch = {
      permitirFotoAlumno,
      permitirEditarEstudiantes,
      accessVersion: crypto.randomBytes(24).toString("hex"),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (incomingPassword) {
      if (incomingPassword.length < 12 || incomingPassword.length > 128) {
        console.warn("[setSchoolRegistroConfig] short_password", {
          schoolId,
        });
        throw new HttpsError(
          "invalid-argument",
          "La clave de registro debe tener entre 12 y 128 caracteres."
        );
      }
      Object.assign(patch, buildRegistroSecretPatch(incomingPassword));
    } else if (typeof current.password === "string" && current.password.length > 0) {
      Object.assign(patch, buildRegistroSecretPatch(current.password));
      patch.legacyMigratedAt = admin.firestore.FieldValue.serverTimestamp();
    }

    await ref.set(patch, { merge: true });
    console.info("[setSchoolRegistroConfig] saved", {
      schoolId,
      hasPasswordHash:
        typeof patch.passwordHash === "string" && patch.passwordHash.length > 0,
      permitirFotoAlumno,
      permitirEditarEstudiantes,
    });

    return {
      ok: true,
      hasPassword: true,
      permitirFotoAlumno,
      permitirEditarEstudiantes,
    };
  }
);

exports.registerSchoolStudent = onCall(callableOptions(), async (request) => {
  assertAppCheckIfRequired(request.app);
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Ingresa el código de registro.");
  await consumeRequestBudget(request, "registro-student", 20);
  return schoolRegistrationService().registerStudent(request.auth, request.data);
});

exports.createSchoolRegistroGrade = onCall(callableOptions(), async (request) => {
  assertAppCheckIfRequired(request.app);
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Ingresa el código de registro.");
  await consumeRequestBudget(request, "registro-grade", 10);
  return schoolRegistrationService().createGrade(request.auth, request.data);
});

exports.uploadSchoolRegistroPhoto = onCall(callableOptions({
  timeoutSeconds: 120, concurrency: 1, cpu: "gcf_gen1", memory: "256MiB",
}), async (request) => {
  assertAppCheckIfRequired(request.app);
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Ingresa el código de registro.");
  await consumeRequestBudget(request, "registro-photo", 10);
  return schoolRegistrationService().uploadPhoto(request.auth, request.data);
});

exports.endSchoolRegistroSession = onCall(callableOptions(), async (request) => {
  assertAppCheckIfRequired(request.app);
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Ingresa el código de registro.");
  await consumeRequestBudget(request, "registro-session-end", 20);
  return schoolRegistrationService().endSession(request.auth, request.data);
});

exports.precheckTeacherSignup = onCall(
  callableOptions(),
  async (request) => {
    const { data, app } = request;

    if (ENFORCE_APPCHECK && !app) {
      throw new HttpsError(
        "failed-precondition",
        "App Check requerido para esta acción."
      );
    }

    const payload = authPayload(data ?? {}, {
      emailLower: { max: 254, email: true, required: true },
      phoneHash: { max: 64, pattern: /^[a-fA-F0-9]{64}$/ },
    });
    const schoolId = normalizeSchoolId(payload.schoolId);
    const emailLower = String(payload.emailLower || "").trim().toLowerCase();
    const phoneHash = String(payload.phoneHash || "").trim();

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }
    if (!validateEmail(emailLower)) {
      throw new HttpsError("invalid-argument", "email inválido");
    }
    if (phoneHash.length > 128) throw new HttpsError("invalid-argument", "phoneHash invalido");
    await consumeRequestBudget(request, "teacher-signup-precheck", 30);

    console.info("[precheckTeacherSignup] start", {
      schoolId,
      hasPhoneHash: phoneHash.length > 0,
    });

    const db = admin.firestore();
    const schoolRef = db.doc(`schools/${schoolId}`);
    const publicMetaRef = db.doc(`schools/${schoolId}/public/meta`);
    const [schoolSnap, publicMetaSnap] = await Promise.all([
      schoolRef.get(),
      publicMetaRef.get(),
    ]);

    if (!schoolSnap.exists) {
      console.warn("[precheckTeacherSignup] school_not_found", {
        schoolId,
        publicMetaExists: publicMetaSnap.exists,
      });
      return {
        ok: false,
        allowed: false,
        reason: "signup_unavailable",
        message: "Este colegio no esta disponible para nuevas solicitudes docentes.",
      };
    }

    const schoolData = schoolSnap.data() || {};
    const publicMeta = publicMetaSnap.data() || {};
    const schoolAccessData = publicMetaSnap.exists ?
      { ...schoolData, ...publicMeta } :
      schoolData;
    const schoolVisible = schoolAvailableForTeacherSignup(schoolData) &&
      (!publicMetaSnap.exists || schoolAvailableForTeacherSignup(publicMeta));

    console.info("[precheckTeacherSignup] school_access_eval", {
      schoolId,
      schoolExists: schoolSnap.exists,
      publicMetaExists: publicMetaSnap.exists,
      accessSource: publicMetaSnap.exists ? "school+public_meta" : "school_root_only",
      schoolActive: schoolData?.active,
      schoolStatus: schoolStatusFromData(schoolData),
      publicActive: publicMeta?.active,
      publicStatus: schoolStatusFromData(publicMeta),
      effectiveActive: schoolAccessData?.active,
      effectiveStatus: schoolStatusFromData(schoolAccessData),
      schoolVisible,
    });

    if (!schoolVisible) {
      console.warn("[precheckTeacherSignup] school_unavailable", {
        schoolId,
        publicMetaExists: publicMetaSnap.exists,
        schoolActive: schoolData?.active,
        schoolStatus: schoolStatusFromData(schoolData),
        publicActive: publicMeta?.active,
        publicStatus: schoolStatusFromData(publicMeta),
        effectiveActive: schoolAccessData?.active,
        effectiveStatus: schoolStatusFromData(schoolAccessData),
      });
      return {
        ok: false,
        allowed: false,
        reason: "signup_unavailable",
        message: "Este colegio no está disponible para nuevas solicitudes docentes.",
      };
    }
    let teachersLimit = 0;
    if (schoolData.planLimits && typeof schoolData.planLimits === "object") {
      const raw = schoolData.planLimits.teachers;
      teachersLimit = Number.isFinite(Number(raw)) ? clampInt(raw, 0, 100000) : 0;
    } else if (Number.isFinite(Number(schoolData.teachersLimit))) {
      teachersLimit = clampInt(schoolData.teachersLimit, 0, 100000);
    }

    if (teachersLimit > 0) {
      const existingTeachersSnap = await db
        .collection(`schools/${schoolId}/teachers`)
        .limit(teachersLimit + 1)
        .count()
        .get();
      const existingTeachers = existingTeachersSnap.data().count;
      console.info("[precheckTeacherSignup] teachers_limit_check", {
        schoolId,
        teachersLimit,
        existingTeachers,
      });
      if (existingTeachers >= teachersLimit) {
        console.warn("[precheckTeacherSignup] teachers_limit_reached", {
          schoolId,
          teachersLimit,
          existingTeachers,
        });
        return {
          ok: false,
          allowed: false,
          reason: "signup_unavailable",
          message: `Esta escuela ya alcanzó su límite de docentes (${teachersLimit}).`,
        };
      }
    }

    const [dupPublicByEmail, dupLoginByEmail] = await Promise.all([
      db.collection(`schools/${schoolId}/teachers_public`)
        .where("emailLower", "==", emailLower)
        .limit(1)
        .get(),
      db.collection(`schools/${schoolId}/login_docentes`)
        .where("emailLower", "==", emailLower)
        .limit(1)
        .get(),
    ]);

    console.info("[precheckTeacherSignup] email_duplicate_check", {
      schoolId,
      dupTeachersPublic: !dupPublicByEmail.empty,
      dupLoginDocentes: !dupLoginByEmail.empty,
    });

    if (!dupPublicByEmail.empty || !dupLoginByEmail.empty) {
      console.warn("[precheckTeacherSignup] email_exists", {
        schoolId,
        dupTeachersPublic: !dupPublicByEmail.empty,
        dupLoginDocentes: !dupLoginByEmail.empty,
      });
      return {
        ok: false,
        allowed: false,
        reason: "signup_unavailable",
        message: "No se pudo procesar esta solicitud docente. Revisa tus datos o contacta la administracion escolar.",
      };
    }

    if (phoneHash) {
      const [dupPublicByPhone, dupLoginByPhone] = await Promise.all([
        db.collection(`schools/${schoolId}/teachers_public`)
          .where("phoneHash", "==", phoneHash)
          .limit(1)
          .get(),
        db.collection(`schools/${schoolId}/login_docentes`)
          .where("phoneHash", "==", phoneHash)
          .limit(1)
          .get(),
      ]);

      console.info("[precheckTeacherSignup] phone_duplicate_check", {
        schoolId,
        hasPhoneHash: true,
        dupTeachersPublic: !dupPublicByPhone.empty,
        dupLoginDocentes: !dupLoginByPhone.empty,
      });

      if (!dupPublicByPhone.empty || !dupLoginByPhone.empty) {
        console.warn("[precheckTeacherSignup] phone_exists", {
          schoolId,
          hasPhoneHash: true,
          dupTeachersPublic: !dupPublicByPhone.empty,
          dupLoginDocentes: !dupLoginByPhone.empty,
        });
        return {
          ok: false,
          allowed: false,
          reason: "signup_unavailable",
          message: "No se pudo procesar esta solicitud docente. Revisa tus datos o contacta la administracion escolar.",
        };
      }
    }

    console.info("[precheckTeacherSignup] allowed", {
      schoolId,
      teachersLimit,
    });

    return {
      ok: true,
      allowed: true,
      teachersLimit,
    };
  }
);

exports.schoolAccessIpPing = onCall(
  callableOptions(),
  async (request) => {
    assertAppCheckIfRequired(request.app);
    const payload = authPayload(request.data ?? {}, {
      operation: { max: 20, required: true }, reason: { max: 120 },
    });
    const operation = lower(payload.operation);
    const schoolId = normalizeSchoolId(payload.schoolId);
    const audience = normalizeAudience(payload.audience);
    const reason = String(payload.reason || "").trim().slice(0, 120);

    if (!["precheck", "success", "failure"].includes(operation)) {
      throw new HttpsError("invalid-argument", "operation inválida");
    }
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }
    if (!audience) {
      throw new HttpsError("invalid-argument", "audience inválida");
    }
    if (operation === "success") await assertLoginSuccessAccess(request.auth, schoolId, audience);
    await consumeRequestBudget(request, "school-login-telemetry", 120);

    const ip = resolveClientIp(request.rawRequest);
    if (!ip) {
      throw new HttpsError(
        "failed-precondition",
        "No se pudo resolver la IP del cliente."
      );
    }

    const db = admin.firestore();
    const ipHash = hashIp(ip);
    const ref = schoolAccessIpRef(db, schoolId, audience, ipHash);
    const nowMs = Date.now();

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data() || {};
      const useAutoRateLimit = audienceUsesAutoRateLimit(audience);
      const manualLockUntilMs = timestampMillis(data?.manualLockUntil);
      const rawAutoLockUntilMs = timestampMillis(data?.autoLockUntil);
      let autoStage = clampInt(data?.autoStage, 0, ADMIN_LOGIN_STAGES.length - 1);
      let autoConsecutiveFailures = clampInt(data?.autoConsecutiveFailures, 0, 1000);
      let autoLockUntilMs = rawAutoLockUntilMs;
      let resetExpiredFinalLock = false;

      if (
        useAutoRateLimit &&
        autoLockUntilMs > 0 &&
        autoLockUntilMs <= nowMs &&
        autoStage === ADMIN_LOGIN_STAGES.length - 1
      ) {
        autoStage = 0;
        autoConsecutiveFailures = 0;
        autoLockUntilMs = 0;
        resetExpiredFinalLock = true;
      }

      const effectiveLockUntilMs = Math.max(manualLockUntilMs, autoLockUntilMs);
      const lock = {
        blocked: effectiveLockUntilMs > nowMs,
        lockUntilMs: effectiveLockUntilMs,
      };

      const basePatch = {
        schoolId,
        audience,
        ipHash,
        ipSample: ip,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (operation === "precheck") {
        if (resetExpiredFinalLock) {
          tx.set(ref, {
            ...basePatch,
            autoLockUntil: null,
            autoStage: 0,
            autoConsecutiveFailures: 0,
          }, { merge: true });
        }

        if (lock.blocked) {
          return {
            allowed: false,
            blocked: true,
            lockUntilMs: lock.lockUntilMs,
            waitSeconds: Math.max(1, Math.ceil((lock.lockUntilMs - nowMs) / 1000)),
            message: genericBlockedMessage(lock.lockUntilMs, nowMs),
          };
        }

        return {
          allowed: true,
          blocked: false,
          stage: useAutoRateLimit ? autoStage : 0,
          attemptsRemaining: useAutoRateLimit
            ? Math.max(stageConfig(autoStage).maxFailures - autoConsecutiveFailures, 1)
            : 0,
          lockUntilMs: 0,
          waitSeconds: 0,
          message: "",
        };
      }

      if (operation === "success") {
        tx.set(ref, {
          ...basePatch,
          lastSuccessAt: admin.firestore.FieldValue.serverTimestamp(),
          totalSuccesses: admin.firestore.FieldValue.increment(1),
          lastReason: null,
          autoLockUntil: null,
          autoStage: 0,
          autoConsecutiveFailures: 0,
        }, { merge: true });

        return {
          allowed: !lock.blocked,
          blocked: lock.blocked,
          stage: 0,
          attemptsRemaining: useAutoRateLimit ? ADMIN_LOGIN_STAGES[0].maxFailures : 0,
          lockUntilMs: lock.lockUntilMs,
          waitSeconds: lock.blocked ? Math.max(1, Math.ceil((lock.lockUntilMs - nowMs) / 1000)) : 0,
          message: lock.blocked ? genericBlockedMessage(lock.lockUntilMs, nowMs) : "",
        };
      }

      if (lock.blocked) {
        return {
          allowed: false,
          blocked: true,
          stage: useAutoRateLimit ? autoStage : 0,
          attemptsRemaining: 0,
          lockUntilMs: lock.lockUntilMs,
          waitSeconds: Math.max(1, Math.ceil((lock.lockUntilMs - nowMs) / 1000)),
          message: genericBlockedMessage(lock.lockUntilMs, nowMs),
        };
      }

      if (useAutoRateLimit) {
        const cfg = stageConfig(autoStage);
        let nextStage = autoStage;
        let nextConsecutiveFailures = autoConsecutiveFailures + 1;
        let nextAutoLockUntil = null;
        let blocked = false;
        let attemptsRemaining = Math.max(cfg.maxFailures - nextConsecutiveFailures, 0);
        let waitSeconds = 0;
        let message = "";

        if (nextConsecutiveFailures >= cfg.maxFailures) {
          blocked = true;
          nextAutoLockUntil = admin.firestore.Timestamp.fromMillis(
            nowMs + (cfg.lockMinutes * 60 * 1000)
          );
          nextStage = Math.min(autoStage + 1, ADMIN_LOGIN_STAGES.length - 1);
          nextConsecutiveFailures = 0;
          attemptsRemaining = 0;
          waitSeconds = cfg.lockMinutes * 60;
          message = buildLockMessage(cfg.lockMinutes);
        }

        tx.set(ref, {
          ...basePatch,
          lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
          totalFailures: admin.firestore.FieldValue.increment(1),
          lastReason: reason,
          autoLockUntil: nextAutoLockUntil,
          autoStage: nextStage,
          autoConsecutiveFailures: nextConsecutiveFailures,
        }, { merge: true });

        return {
          allowed: !blocked,
          blocked,
          stage: nextStage,
          attemptsRemaining,
          lockUntilMs: nextAutoLockUntil ? nextAutoLockUntil.toMillis() : 0,
          waitSeconds,
          message,
        };
      }

      tx.set(ref, {
        ...basePatch,
        lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
        totalFailures: admin.firestore.FieldValue.increment(1),
        lastReason: reason,
      }, { merge: true });

      return {
        allowed: !lock.blocked,
        blocked: lock.blocked,
        lockUntilMs: lock.lockUntilMs,
        waitSeconds: lock.blocked ? Math.max(1, Math.ceil((lock.lockUntilMs - nowMs) / 1000)) : 0,
        message: lock.blocked ? genericBlockedMessage(lock.lockUntilMs, nowMs) : "",
      };
    });
  }
);

exports.listSchoolAccessIps = onCall(
  callableOptions(),
  async (request) => {
    const { data, auth, app } = request;
    await assertSuperAdmin({ auth, app });

    const payload = (data && typeof data === "object") ? data : {};
    const schoolId = normalizeSchoolId(payload.schoolId);
    const audience = normalizeAudience(payload.audience);
    const limit = clampInt(payload.limit, 1, 200);

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }

    const query = admin.firestore()
      .collection("schools")
      .doc(schoolId)
      .collection(SCHOOL_ACCESS_IPS_SUBCOL);

    const snap = await query.orderBy("updatedAt", "desc").limit(300).get();
    const nowMs = Date.now();
    const docs = audience ?
      snap.docs.filter((doc) => normalizeAudience(doc.data()?.audience) === audience) :
      snap.docs;

    return {
      items: docs.slice(0, limit).map((doc) => mapSchoolAccessIpDoc(doc, nowMs)),
    };
  }
);

exports.unlockSchoolAccessIp = onCall(
  // Administrative, I/O-bound action: use fractional CPU within regional quota.
  callableOptions({ cpu: "gcf_gen1", concurrency: 1, memory: "256MiB" }),
  async (request) => {
    const { data, auth, app } = request;
    await assertSuperAdmin({ auth, app });

    const payload = (data && typeof data === "object") ? data : {};
    const schoolId = normalizeSchoolId(payload.schoolId);
    const audience = normalizeAudience(payload.audience);
    const ipHash = String(payload.ipHash || "").trim().toLowerCase();

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId requerido");
    }
    if (!audience) {
      throw new HttpsError("invalid-argument", "audience inválida");
    }
    if (!/^[a-f0-9]{64}$/.test(ipHash)) {
      throw new HttpsError("invalid-argument", "ipHash requerido");
    }

    const db = admin.firestore();
    const accessRef = schoolAccessIpRef(db, schoolId, audience, ipHash);

    await db.runTransaction(async (tx) => {
      tx.set(accessRef, {
        schoolId,
        audience,
        ipHash,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        manualLockUntil: null,
        manualBlockedReason: null,
        autoLockUntil: null,
        autoStage: 0,
        autoConsecutiveFailures: 0,
        unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
        unlockedBy: auth.uid,
      }, { merge: true });

      if (audience === "admin_escolar") {
        tx.set(db.collection(ADMIN_LOGIN_IP_LIMITS_COL).doc(hashIp(`${schoolId}:${ipHash}`)), {
          stage: 0,
          consecutiveFailures: 0,
          lockUntil: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
          unlockedBy: auth.uid,
          lastReason: null,
        }, { merge: true });
      }
    });

    return { ok: true };
  }
);

exports.searchSchoolPlaces = onCall(
  // Requests wait on the geocoder; one request per small instance is sufficient.
  callableOptions({ cpu: "gcf_gen1", concurrency: 1, memory: "256MiB" }),
  async (request) => {
    const { data, auth, app } = request;
    await assertTeamAccess({ auth, app }, OPERATIONS_ROLES);

    const payload = (data && typeof data === "object") ? data : {};
    const query = String(payload.query || "").trim();
    const countryCode = lower(payload.countryCode || "do");
    const limit = clampInt(payload.limit, 1, 8);

    if (query.length < 3 || query.length > 200 || !/^[a-z]{2}$/.test(countryCode)) {
      throw new HttpsError(
        "invalid-argument",
        "La búsqueda debe tener al menos 3 caracteres."
      );
    }
    await consumeRequestBudget(request, "place-search", 20);

    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", query);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("accept-language", "es");
    if (countryCode) {
      url.searchParams.set("countrycodes", countryCode);
    }

    const response = await fetch(url.toString(), {
      method: "GET",
      signal: AbortSignal.timeout(8000),
      headers: {
        "User-Agent": "EduProAdmin/1.0 school-location-search",
        "Accept": "application/json",
      },
    });

    if (!response.ok) {
      throw new HttpsError(
        "unavailable",
        `No se pudo consultar lugares (${response.status}).`
      );
    }

    const json = await response.json();
    const items = Array.isArray(json) ? json : [];

    return {
      items: items.map((item) => {
        const address = item && typeof item.address === "object" ? item.address : {};
        return {
          placeId: String(item.place_id || ""),
          label: String(item.display_name || ""),
          latitude: Number(item.lat || 0),
          longitude: Number(item.lon || 0),
          country: String(address.country || ""),
          province: String(
            address.state ||
              address.region ||
              address.province ||
              ""
          ),
          municipality: String(
            address.city ||
              address.town ||
              address.municipality ||
              address.county ||
              ""
          ),
          sector: String(
            address.suburb ||
              address.city_district ||
              address.neighbourhood ||
              address.village ||
              ""
          ),
          addressLine: String(
            address.road ||
              address.amenity ||
              address.building ||
              address.house_number ||
              ""
          ),
          type: String(item.type || ""),
          className: String(item.class || ""),
        };
      }).filter((item) =>
        Number.isFinite(item.latitude) &&
        Number.isFinite(item.longitude) &&
        item.label.trim().length > 0
      ),
    };
  }
);
