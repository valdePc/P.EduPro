"use strict";

const text = (value) => typeof value === "string" ? value.trim() : "";

// The caller must pass only the member whose document ID equals adminUid.
// A different administrator must never supply the principal's name or email.
function schoolAdministrator(school, principalMember = null) {
  const uid = text(school.adminUid);
  const canonicalEmail = text(school.adminEmail).toLowerCase();
  const member = uid ? principalMember : null;
  const email = canonicalEmail || text(member?.email).toLowerCase();
  const assigned = !!(uid || canonicalEmail);
  const name = assigned ? text(school.adminName) || text(member?.name) ||
    text(member?.displayName) || text(member?.nombre) : "";
  return {
    adminAssigned: assigned,
    adminName: name || (assigned ? "Administrador asignado" : "No asignado"),
    adminEmail: email,
  };
}

function principalUid(school) {
  const uid = text(school.adminUid);
  return uid && uid.length <= 128 && !uid.includes("/") ? uid : null;
}

module.exports = { schoolAdministrator, principalUid };
