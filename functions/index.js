const functions = require("firebase-functions");
const admin = require("firebase-admin");
const bcrypt = require("bcryptjs");

admin.initializeApp();

exports.loginWithNip = functions.https.onCall(async (data, context) => {
  const nipRaw = data && data.nip ? data.nip : "";
  const passRaw = data && data.password ? data.password : "";

  const nip = String(nipRaw).trim();
  const password = String(passRaw).trim();

  if (!nip || !password) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "NIP dan password wajib diisi."
    );
  }

  const userDoc = await admin.firestore().collection("users").doc(nip).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "NIP tidak terdaftar.");
  }

  const userData = userDoc.data();

  if (userData.isActive !== true) {
    throw new functions.https.HttpsError("permission-denied", "Akun nonaktif.");
  }

  const credDoc = await admin.firestore().collection("credentials").doc(nip).get();
  if (!credDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Password belum dibuat oleh admin.");
  }

  const credData = credDoc.data();
  const hash = credData.passwordHash;

  const ok = await bcrypt.compare(password, hash);
  if (!ok) {
    throw new functions.https.HttpsError("unauthenticated", "Password salah.");
  }

  return {
    nip: nip,
    name: userData.name || "",
    uid: userData.uid || "",
    isActive: userData.isActive,
  };
});
