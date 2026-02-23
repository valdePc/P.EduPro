const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// -------------------------
// Helpers seguridad
// -------------------------

async function getUserRoleFromFirestore(uid) {
  const db = admin.firestore();

  const doc1 = await db.doc(`users/${uid}`).get();
  if (doc1.exists) return doc1.data() || {};

  const doc2 = await db.doc(`Users/${uid}`).get();
  if (doc2.exists) return doc2.data() || {};

  return {};
}

function lower(v) {
  return typeof v === "string" ? v.trim().toLowerCase() : "";
}

function isEnabledData(d) {
  return !(typeof d.enabled === "boolean") || d.enabled === true;
}

async function assertSuperAdmin(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Debes iniciar sesión."
    );
  }

  const token = context.auth.token || {};
  const claimRole = lower(token.role);
  const claimSuper = token.superadmin === true;

  if (claimSuper || claimRole === "superadmin") return;

  const userData = await getUserRoleFromFirestore(context.auth.uid);
  const role = lower(userData.role);
  const enabledOk = isEnabledData(userData);

  if (!enabledOk) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Usuario deshabilitado."
    );
  }

  if (role !== "superadmin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Solo superadmin puede ejecutar esta acción."
    );
  }
}

// ==================================================
// upsertSchoolAdmin (CALLABLE v1)
// ==================================================

exports.upsertSchoolAdmin = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    await assertSuperAdmin(context);

    const schoolId = String(data.schoolId || "").trim();
    const email = String(data.email || data.adminEmail || "")
      .trim()
      .toLowerCase();
    const password = data.password ?? data.adminPassword;

    if (!schoolId)
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId requerido"
      );

    if (!email)
      throw new functions.https.HttpsError(
        "invalid-argument",
        "email requerido"
      );

    try {
      let userRecord = null;

      try {
        userRecord = await admin.auth().getUserByEmail(email);
      } catch (e) {
        if (e?.code !== "auth/user-not-found") throw e;
      }

      if (!userRecord) {
        if (!password || String(password).trim().length < 6) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Password requerido (mínimo 6)."
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

      return {
        uid: userRecord.uid,
        email,
        schoolId,
      };
    } catch (e) {
      const code = e?.code || "";

      if (code === "auth/email-already-exists") {
        throw new functions.https.HttpsError(
          "already-exists",
          "Ese email ya existe en Auth."
        );
      }

      if (code === "auth/invalid-password") {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Password inválido."
        );
      }

      console.error("upsertSchoolAdmin error:", e);

      throw new functions.https.HttpsError(
        "internal",
        e?.message || "Error interno"
      );
    }
  });