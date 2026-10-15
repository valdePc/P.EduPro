"use strict";

// Internal staff authorization is document-based. Custom claims are deliberately
// absent here: an old ID token must never resurrect a revoked or downgraded role.
const TEAM_ROLES = Object.freeze([
  "super_admin", "operations_admin", "support_onboarding", "billing_admin",
]);
const OPERATIONS_ROLES = Object.freeze(["super_admin", "operations_admin"]);
const SUPPORT_ROLES = Object.freeze([...OPERATIONS_ROLES, "support_onboarding"]);
const BILLING_ROLES = Object.freeze(["super_admin", "billing_admin"]);

function normalizeTeamRole(value) {
  const role = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (role === "superadmin") return "super_admin";
  return TEAM_ROLES.includes(role) ? role : "denied";
}

function canonicalTeamRole(data) {
  if (!data || data.enabled !== true) return "denied";
  return normalizeTeamRole(data.teamRole ?? data.role);
}

function teamScheduleAllows(role, teamData, now = new Date()) {
  if (teamData?.enabled === false) return false;
  if (role === "denied") return false;
  // The principal role has round-the-clock access, but can still be disabled.
  if (role === "super_admin") return true;
  const data = teamData || {};
  // Staff schedules use Dominican time (UTC-4, with no daylight-saving time),
  // independently of the browser, caller, or Cloud Functions host timezone.
  const local = new Date(now.getTime() - 4 * 60 * 60 * 1000);
  const weekday = local.getUTCDay() || 7;
  const weekdays = data.allowedWeekdays;
  if (weekdays != null && !Array.isArray(weekdays)) return false;
  if (Array.isArray(weekdays) && weekdays.length) {
    if (weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7)) return false;
    if (!weekdays.includes(weekday)) return false;
  }
  const start = data.startMinute ?? 0;
  const end = data.endMinute ?? 1439;
  if (![start, end].every((minute) => Number.isInteger(minute) && minute >= 0 && minute <= 1439)) return false;
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  return start === end || (start < end ? minute >= start && minute <= end : minute >= start || minute <= end);
}

const PLAN_DEFAULTS = Object.freeze({
  base: [1, 10, 150], plus: [3, 25, 300], premium: [5, 60, 900], enterprise: [10, 150, 3000],
});

function validatePlanLimits(payload, role, { requireAll = false } = {}) {
  const planTier = typeof payload.planTier === "string" ? payload.planTier.trim().toLowerCase() : "base";
  if (!Object.hasOwn(PLAN_DEFAULTS, planTier)) throw new RangeError("Plan no valido.");
  const keys = ["adminsLimit", "teachersLimit", "studentsLimit"];
  const maximums = [1000, 100000, 1000000];
  const values = keys.map((key, i) => {
    const value = payload[key] ?? (requireAll ? undefined : PLAN_DEFAULTS[planTier][i]);
    if (!Number.isInteger(value) || value < 1 || value > maximums[i]) throw new RangeError(`Limite no valido: ${key}.`);
    return value;
  });
  if (role !== "super_admin" &&
      (role !== "operations_admin" || planTier !== "base" || values.some((n, i) => n !== PLAN_DEFAULTS.base[i]))) {
    throw new RangeError("El equipo operativo solo puede crear colegios con el plan Base y sus limites predeterminados.");
  }
  return { planTier, ...Object.fromEntries(keys.map((key, i) => [key, values[i]])) };
}

function scalar(value) {
  if (value == null || ["string", "boolean"].includes(typeof value)) return value ?? null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return undefined;
}

function select(data, fields) {
  return Object.fromEntries(fields.flatMap((key) => {
    if (!Object.hasOwn(data, key)) return [];
    const value = scalar(data[key]);
    return value === undefined ? [] : [[key, value]];
  }));
}

function projectSchoolForRole(data, role) {
  if (!TEAM_ROLES.includes(role)) return null;
  const result = select(data, [
    "name", "nombre", "officialName", "code", "institutionCode", "active",
    "accountStatus", "status", "lifecycleStage", "createdAt", "updatedAt",
    "planTier", "adminsLimit", "teachersLimit", "studentsLimit", "maxUsers",
  ]);
  result.planLimits = select(data.planLimits || {}, ["admins", "teachers", "students"]);
  if (SUPPORT_ROLES.includes(role)) {
    Object.assign(result, select(data, [
      "adminEmail", "adminName", "schoolType", "country", "timezone", "foundedAt", "foundedYear",
      "regionalCode", "regionalName", "districtCode", "districtName", "districtKey", "startedAt",
      "adminLink", "profLink", "alumLink", "adminDeepLink", "profDeepLink", "alumDeepLink",
    ]));
    result.location = select(data.location || {}, ["latitude", "longitude", "province", "municipality", "sector", "addressLine", "source"]);
    result.contact = select(data.contact || {}, ["name", "role", "phone", "whatsapp", "email"]);
    for (const key of ["grades", "grados", "modulesEnabled", "levelsEnabled"]) {
      if (Array.isArray(data[key])) result[key] = data[key].filter((v) => typeof v === "string").slice(0, 200);
    }
  }
  if (BILLING_ROLES.includes(role)) {
    Object.assign(result, select(data, [
      "planPrice", "billingCycle", "renewalAt", "billingNextDueAt", "billingLastPaidAt", "currency",
    ]));
  }
  return result;
}

function projectPayment(data, id) {
  return { id, ...select(data, ["status", "estado", "amount", "monto", "currency", "createdAt", "paidAt"]) };
}

module.exports = {
  TEAM_ROLES, OPERATIONS_ROLES, SUPPORT_ROLES, BILLING_ROLES,
  canonicalTeamRole, normalizeTeamRole, teamScheduleAllows, validatePlanLimits,
  projectSchoolForRole, projectPayment,
};
