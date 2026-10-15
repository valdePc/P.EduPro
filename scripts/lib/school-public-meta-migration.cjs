'use strict';

// Explicit allowlist: never read or publish contacts, billing, administrators,
// passwords, registration secrets or student records during this migration.
const SOURCE_FIELDS = Object.freeze([
  'name', 'nombre', 'officialName', 'code', 'institutionCode', 'grades', 'grados',
  'adminLink', 'profLink', 'alumLink', 'adminDeepLink', 'profDeepLink', 'alumDeepLink',
  'active', 'accountStatus', 'status', 'createdAt', 'updatedAt',
]);

function eligibleSchoolId(id) {
  return typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id) &&
    !/^(valmichapp|eduproapp)_admin_/i.test(id);
}

const text = (value) => typeof value === 'string' ? value.trim() : '';
function publicLink(value) {
  const candidate = text(value);
  if (!candidate || candidate.length > 2048 || /[\u0000-\u0020\\]/.test(candidate)) return '';
  try {
    const url = new URL(candidate);
    return ['https:', 'eduproapp:', 'valmichapp:'].includes(url.protocol) && url.hostname &&
      !url.username && !url.password && !url.search && !url.hash.includes('?') ? candidate : '';
  } catch { return ''; }
}

function buildMissingPublicMeta(data, schoolId, { now, serverTimestamp }) {
  if (!eligibleSchoolId(schoolId)) throw new Error('Invalid school identifier');
  const rawGrades = Array.isArray(data.grades) ? data.grades : data.grados;
  const grades = Array.isArray(rawGrades) ? rawGrades.filter((value) => typeof value === 'string')
    .map((value) => value.trim()).filter(Boolean) : [];
  const status = text(data.accountStatus) || text(data.status);
  return {
    schoolId,
    name: text(data.name) || text(data.nombre),
    officialName: text(data.officialName) || text(data.name) || text(data.nombre),
    code: text(data.code) || schoolId,
    institutionCode: text(data.institutionCode) || text(data.code) || schoolId,
    ...Object.fromEntries(['adminLink', 'profLink', 'alumLink', 'adminDeepLink', 'profDeepLink', 'alumDeepLink']
      .map((field) => [field, publicLink(data[field])])),
    grades, grados: grades,
    // A missing metadata document must not reopen a blocked or suspended school.
    active: (data.active == null || data.active === true) &&
      !['suspendida', 'bloqueada', 'vencida'].includes(status.toLowerCase()),
    accountStatus: status,
    createdAt: typeof data.createdAt?.toMillis === 'function' ? data.createdAt : now(),
    updatedAt: serverTimestamp(),
  };
}

async function createMissingPublicMeta(db, schoolId, actorEmail, clock) {
  if (!eligibleSchoolId(schoolId) || !text(actorEmail)) throw new Error('Invalid migration context');
  const source = db.doc(`schools/${schoolId}`);
  const target = db.doc(`schools/${schoolId}/public/meta`);
  const audit = db.collection('team_audit').doc();
  return db.runTransaction(async (transaction) => {
    // Re-read current source and target atomically; a preview is not write input.
    const [school, meta] = await transaction.getAll(source, target, { fieldMask: SOURCE_FIELDS });
    if (!school.exists) return 'source-missing';
    if (meta.exists) return 'existing';
    transaction.create(target, buildMissingPublicMeta(school.data(), schoolId, clock));
    transaction.create(audit, {
      action: 'school.public-meta.created-by-migration',
      schoolId, actorEmail: text(actorEmail), tool: 'migrate-school-public-meta-v1',
      createdAt: clock.serverTimestamp(),
    });
    return 'created';
  });
}

module.exports = { SOURCE_FIELDS, eligibleSchoolId, buildMissingPublicMeta, createMissingPublicMeta };
