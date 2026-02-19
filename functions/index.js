const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1" }); // misma región que Flutter

exports.upsertSchoolAdmin = onCall(async (req) => {
  const data = req.data || {};
  const schoolId = String(data.schoolId || "").trim();
  const email = String(data.email || data.adminEmail || "").trim().toLowerCase();
  const password = data.password ?? data.adminPassword;

  if (!schoolId) throw new HttpsError("invalid-argument", "schoolId requerido");
  if (!email) throw new HttpsError("invalid-argument", "email requerido");

  try {
    let userRecord = null;

    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e?.code !== "auth/user-not-found") throw e;
    }

    if (!userRecord) {
      if (!password || String(password).trim().length < 6) {
        throw new HttpsError(
          "failed-precondition",
          "Password requerido para crear el admin (mínimo 6)."
        );
      }
      userRecord = await admin.auth().createUser({
        email,
        password: String(password),
      });
    } else {
      if (password && String(password).trim().length > 0) {
        await admin.auth().updateUser(userRecord.uid, {
          password: String(password),
        });
      }
    }

    await admin.firestore().doc(`schools/${schoolId}`).set(
      {
        adminEmail: email,
        adminUid: userRecord.uid,
        adminPasswordSet: true,
        adminUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { uid: userRecord.uid };
  } catch (e) {
    const code = e?.code || "";
    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Ese email ya existe en Auth.");
    }
    if (code === "auth/invalid-password") {
      throw new HttpsError("invalid-argument", "Password inválido.");
    }
    throw new HttpsError("internal", e?.message || "Error interno", { code });
  }
});


const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

// -------------------------
// Helpers seguridad
// -------------------------
async function getUserRoleFromFirestore(uid) {
  // Soporta /users y /Users (compat)
  const db = admin.firestore();

  const doc1 = await db.doc(`users/${uid}`).get();
  if (doc1.exists) return (doc1.data() || {});

  const doc2 = await db.doc(`Users/${uid}`).get();
  if (doc2.exists) return (doc2.data() || {});

  return {};
}

function lower(v) {
  return (typeof v === "string") ? v.trim().toLowerCase() : "";
}

function isEnabledData(d) {
  return !(typeof d.enabled === "boolean") || d.enabled === true;
}

async function assertSuperAdmin(req) {
  // Callable auth obligatorio
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  // 1) Custom claims (si existen)
  const token = req.auth.token || {};
  const claimRole = lower(token.role);
  const claimSuper = token.superadmin === true;

  if (claimSuper || claimRole === "superadmin") return;

  // 2) Fallback a Firestore (/users o /Users)
  const u = await getUserRoleFromFirestore(req.auth.uid);
  const role = lower(u.role);
  const enabledOk = isEnabledData(u);

  if (!enabledOk) {
    throw new HttpsError("permission-denied", "Usuario deshabilitado.");
  }
  if (role !== "superadmin") {
    throw new HttpsError("permission-denied", "Solo superadmin puede ejecutar esta acción.");
  }
}

// ==================================================
// upsertSchoolAdmin (CALLABLE) + CORS (para web)
// ==================================================
exports.upsertSchoolAdmin = onCall(
  {
    // Para que Flutter Web no se rompa con preflight
    // Seguridad REAL: assertSuperAdmin(req)
    cors: true,

    // Si luego quieres restringir orígenes, lo hacemos con lista fija
    // y dejamos localhost solo en dev.
  },
  async (req) => {
    await assertSuperAdmin(req);

    const data = req.data || {};
    const schoolId = String(data.schoolId || "").trim();
    const email = String(data.email || data.adminEmail || "").trim().toLowerCase();
    const password = data.password ?? data.adminPassword;

    if (!schoolId) throw new HttpsError("invalid-argument", "schoolId requerido");
    if (!email) throw new HttpsError("invalid-argument", "email requerido");

    try {
      let userRecord = null;

      try {
        userRecord = await admin.auth().getUserByEmail(email);
      } catch (e) {
        if (e?.code !== "auth/user-not-found") throw e;
      }

      // Crear si no existe
      if (!userRecord) {
        if (!password || String(password).trim().length < 6) {
          throw new HttpsError(
            "failed-precondition",
            "Password requerido para crear el admin (mínimo 6)."
          );
        }
        userRecord = await admin.auth().createUser({
          email,
          password: String(password),
        });
      } else {
        // Reset solo si mandan password
        if (password && String(password).trim().length > 0) {
          await admin.auth().updateUser(userRecord.uid, {
            password: String(password),
          });
        }
      }

      // ✅ IMPORTANTE: este write lo hace servidor (Admin SDK),
      // no depende de rules (evita permission-denied del navegador).
      await admin.firestore().doc(`schools/${schoolId}`).set(
        {
          adminEmail: email,
          adminUid: userRecord.uid,
          adminPasswordSet: true,
          adminUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        uid: userRecord.uid,
        email,
        schoolId,
      };
    } catch (e) {
      const code = e?.code || "";

      if (code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "Ese email ya existe en Auth.");
      }
      if (code === "auth/invalid-password") {
        throw new HttpsError("invalid-argument", "Password inválido.");
      }

      // Log para ver el error real en Functions logs
      console.error("upsertSchoolAdmin error:", e);

      throw new HttpsError("internal", e?.message || "Error interno", { code });
    }
  }
);
