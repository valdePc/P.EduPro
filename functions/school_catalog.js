"use strict";

const { projectSchoolForRole, SUPPORT_ROLES, BILLING_ROLES } = require('./team_permissions');
const { isDeepStrictEqual } = require('node:util');
const { AggregateField } = require('firebase-admin/firestore');
const COLLECTION = 'team_school_catalog';
const META = 'team_catalog_meta/state';
const VERSION = 1;
const eligible = (id) => /^[A-Za-z0-9_-]{1,128}$/.test(id) && !/^(valmichapp|eduproapp)_admin_/i.test(id);
const normalize = (value) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().trim().replace(/\s+/g, ' ');

function schoolStatus(data) {
  const value = normalize(data.accountStatus ?? data.status);
  if (['suspended', 'suspendida', 'suspendido', 'blocked', 'bloqueada', 'bloqueado'].includes(value)) return 'suspended';
  if (['draft', 'borrador'].includes(value)) return 'draft';
  if (data.active === false) return 'suspended';
  if (!value || ['active', 'activa', 'activo'].includes(value)) return 'active';
  return 'other';
}

function buildCatalogEntry(id, data) {
  if (!eligible(id) || !data) return null;
  // Search public school identity and geography only. Never index contacts,
  // administrator emails, credentials, billing or individual student records.
  const values = [id, data.name, data.nombre, data.officialName, data.code, data.institutionCode]
    .map((value) => normalize(value).slice(0, 160)).filter(Boolean);
  const tokens = new Set();
  for (const value of values) {
    for (const term of [value, ...value.split(' ')]) {
      for (let length = 1; length <= Math.min(80, term.length); length++) tokens.add(term.slice(0, length));
    }
  }
  const point = catalogPoint(data);
  const status = schoolStatus(data);
  return { schemaVersion: VERSION, status,
    hasCoordinates: point !== null,
    activeCount: status === 'active' ? 1 : 0,
    suspendedCount: status === 'suspended' ? 1 : 0,
    draftCount: status === 'draft' ? 1 : 0,
    locatedCount: point !== null ? 1 : 0,
    provinceKey: normalize(data.location?.province).slice(0, 80),
    searchTokens: [...tokens].slice(0, 800).sort(),
  };
}

function catalogPoint(data) {
  for (const source of [data.location, data, data.geo]) {
    if (!source || typeof source !== 'object') continue;
    const number = (value) => typeof value === 'number' ? value :
      typeof value === 'string' && value.trim() ? Number(value) : NaN;
    const latitude = number(source.latitude ?? source.lat ?? source.y);
    const longitude = number(source.longitude ?? source.lng ?? source.lon ?? source.x);
    if (Number.isFinite(latitude) && Number.isFinite(longitude) && latitude >= 17.3 && latitude <= 20.2 &&
        longitude >= -72.1 && longitude <= -68) return { latitude, longitude };
  }
  return null;
}

async function syncCatalog(db, id) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) return;
  const root = db.doc(`schools/${id}`);
  const target = db.doc(`${COLLECTION}/${id}`);
  // Re-read current state: delayed/deleted/duplicate events cannot restore an
  // obsolete school or overwrite a newer search index.
  await db.runTransaction(async (transaction) => {
    const source = await transaction.get(root);
    const previous = await transaction.get(target);
    const next = buildCatalogEntry(id, source.exists ? source.data() : null);
    if (!next) {
      if (previous.exists) transaction.delete(target);
    } else if (!previous.exists || !isDeepStrictEqual(previous.data(), next)) {
      transaction.set(target, next);
    }
  });
}

const COMMON_FIELDS = ['name', 'nombre', 'officialName', 'code', 'institutionCode', 'active',
  'accountStatus', 'status', 'lifecycleStage', 'createdAt', 'updatedAt', 'planTier',
  'adminsLimit', 'teachersLimit', 'studentsLimit', 'maxUsers', 'planLimits'];
const SUPPORT_FIELDS = ['adminEmail', 'adminName', 'schoolType', 'country', 'timezone', 'foundedAt', 'foundedYear',
  'regionalCode', 'regionalName', 'districtCode', 'districtName', 'districtKey', 'startedAt',
  'adminLink', 'profLink', 'alumLink', 'adminDeepLink', 'profDeepLink', 'alumDeepLink',
  'location.latitude', 'location.longitude', 'location.province', 'location.municipality',
  'location.lat', 'location.lng', 'location.lon', 'location.x', 'location.y',
  'latitude', 'longitude', 'lat', 'lng', 'lon', 'geo.latitude', 'geo.longitude', 'geo.lat', 'geo.lng', 'geo.lon',
  'location.sector', 'location.addressLine', 'location.source',
  'contact.name', 'contact.role', 'contact.phone', 'contact.whatsapp', 'contact.email',
  'grades', 'grados', 'modulesEnabled', 'levelsEnabled'];
const BILLING_FIELDS = ['planPrice', 'billingCycle', 'renewalAt', 'billingNextDueAt', 'billingLastPaidAt', 'currency'];
function fieldsForRole(role) {
  return [...COMMON_FIELDS, ...(SUPPORT_ROLES.includes(role) ? SUPPORT_FIELDS : []),
    ...(BILLING_ROLES.includes(role) ? BILLING_FIELDS : [])];
}

function validateCatalogQuery(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new RangeError('Consulta inválida.');
  const limit = payload.limit ?? 25;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new RangeError('Límite inválido.');
  const cursor = payload.cursor ?? null;
  if (cursor !== null && (typeof cursor !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(cursor))) throw new RangeError('Página inválida.');
  for (const key of ['search', 'province']) {
    if (payload[key] != null && (typeof payload[key] !== 'string' || payload[key].length > 80 || /[\u0000-\u001f]/.test(payload[key]))) {
      throw new RangeError('Filtro inválido.');
    }
  }
  for (const key of ['includeMetrics', 'includeTotal']) {
    if (payload[key] != null && typeof payload[key] !== 'boolean') throw new RangeError('Consulta inválida.');
  }
  return { limit, cursor, search: normalize(payload.search), province: normalize(payload.province),
    includeMetrics: payload.includeMetrics !== false, includeTotal: payload.includeTotal !== false };
}

async function catalogMetrics(collection, role) {
  // A single aggregation snapshot keeps the totals mutually consistent even
  // while a school changes status. Numeric flags avoid a hot global counter.
  const spec = { total: AggregateField.count(), active: AggregateField.sum('activeCount'),
    suspended: AggregateField.sum('suspendedCount'), draft: AggregateField.sum('draftCount'),
    ...(SUPPORT_ROLES.includes(role) ? { located: AggregateField.sum('locatedCount') } : {}) };
  const values = (await collection.aggregate(spec).get()).data();
  return { ...values, ...(values.located != null ? { unlocated: values.total - values.located } : {}), fetchedAt: Date.now() };
}

async function readCatalogPage(db, role, options, documentId) {
  const collection = db.collection(COLLECTION);
  let matching = collection;
  if (options.search) matching = matching.where('searchTokens', 'array-contains', options.search);
  if (options.province) matching = matching.where('provinceKey', '==', options.province);
  let query = matching.orderBy(documentId);
  if (options.cursor) query = query.startAfter(options.cursor);
  const [snapshot, metrics, total] = await Promise.all([
    query.limit(options.limit + 1).select().get(),
    options.includeMetrics ? catalogMetrics(collection, role) : Promise.resolve(null),
    options.includeTotal ? matching.count().get() : Promise.resolve(null),
  ]);
  const rows = snapshot.docs.slice(0, options.limit);
  const refs = rows.filter((row) => eligible(row.id)).map((row) => db.doc(`schools/${row.id}`));
  // Projection at the read boundary and again at the response boundary. Even
  // superadmins never receive registration passwords through the catalog.
  const roots = refs.length ? await db.getAll(...refs, { fieldMask: fieldsForRole(role) }) : [];
  return { role, schools: roots.filter((root) => root.exists)
    .map((root) => {
      const source = root.data();
      const point = catalogPoint(source);
      return { id: root.id, data: projectSchoolForRole({ ...source,
        location: { ...(source.location || {}), ...(point || {}) } }, role) };
    }),
    nextCursor: snapshot.size > options.limit ? rows.at(-1).id : null,
    ...(metrics ? { metrics } : {}), ...(total ? { matchingTotal: total.data().count } : {}), fetchedAt: Date.now() };
}

module.exports = { COLLECTION, META, VERSION, eligible, normalize, buildCatalogEntry, syncCatalog,
  fieldsForRole, validateCatalogQuery, catalogMetrics, readCatalogPage, catalogPoint };
