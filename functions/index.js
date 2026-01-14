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
