"use strict";

// Derived rows contain only counters, never names, emails or student records.
const METRICS = Object.freeze({
  teachers: ["activeTeachers", "pendingTeachers"],
  alumnos: ["activeStudents", "studentWithoutGrade"],
  members: ["activeUsers", "blockedUsers"],
  subjects: ["subjectsWithoutTeacher"],
  planificaciones_anuales: ["completedPlans"],
});

function metricCollection(collection) {
  if (!Object.hasOwn(METRICS, collection)) throw new Error("Unsupported metric collection");
  return `_operational_${collection}`;
}

const text = (value) => String(value ?? "").trim();

function deriveMetrics(collection, data) {
  if (!data) return null;
  const enabled = data.enabled ?? data.active;
  switch (collection) {
    case "teachers":
      return { activeTeachers: (enabled ?? true) === true, pendingTeachers: (enabled ?? false) !== true };
    case "alumnos":
      return { activeStudents: (enabled ?? true) === true,
        studentWithoutGrade: text(data.gradeId ?? data.gradoId).length === 0 };
    case "members":
      return { activeUsers: (enabled ?? false) === true,
        blockedUsers: data.enabled === false || data.active === false };
    case "subjects":
      return { subjectsWithoutTeacher: !text(data.teacherDocId) && !text(data.teacherUid) };
    case "planificaciones_anuales":
      return { completedPlans: Array.isArray(data.units) && data.units.length > 0 &&
        data.units.every((unit) => unit && typeof unit === "object" && !Array.isArray(unit) &&
          text(unit.titulo ?? unit.title).length > 0) };
    default:
      throw new Error("Unsupported metric collection");
  }
}

async function syncMetrics(db, schoolId, collection, recordId) {
  const school = db.doc(`schools/${schoolId}`);
  const source = school.collection(collection).doc(recordId);
  const derived = school.collection(metricCollection(collection)).doc(recordId);
  // Read CURRENT state within the transaction. Duplicate or delayed events
  // cannot apply a delta twice or overwrite newer metrics with an old event.
  await db.runTransaction(async (transaction) => {
    const schoolSnap = await transaction.get(school);
    const sourceSnap = await transaction.get(source);
    const previous = await transaction.get(derived);
    const next = schoolSnap.exists && sourceSnap.exists ? deriveMetrics(collection, sourceSnap.data()) : null;
    if (!next) {
      if (previous.exists) transaction.delete(derived);
      return;
    }
    if (previous.exists && Object.keys(next).every((key) => previous.data()[key] === next[key])) return;
    transaction.set(derived, next);
  });
}

async function readDerivedMetrics(ref, totals) {
  const result = {};
  const pending = [];
  await Promise.all(Object.entries(METRICS).map(async ([collection, fields]) => {
    const derived = ref.collection(metricCollection(collection));
    const [coverage, ...values] = await Promise.all([
      derived.count().get(),
      ...fields.map((field) => derived.where(field, "==", true).count().get()),
    ]);
    const complete = coverage.data().count === totals[collection];
    if (!complete) pending.push(collection);
    fields.forEach((field, i) => { result[field] = complete ? values[i].data().count : null; });
  }));
  return { ...result, metricsPending: pending.sort() };
}

module.exports = { METRICS, metricCollection, deriveMetrics, syncMetrics, readDerivedMetrics };
