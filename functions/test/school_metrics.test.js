"use strict";
const test = require('node:test');
const assert = require('node:assert/strict');
const { deriveMetrics } = require('../school_metrics');

test('derived activity preserves legacy enabled/active precedence and defaults', () => {
  for (const input of [{}, { enabled: null }, { active: true }, { enabled: true, active: false }, { enabled: false, active: true }, { active: false }]) {
    const enabled = input.enabled ?? input.active;
    assert.equal(deriveMetrics('teachers', input).activeTeachers, (enabled ?? true) === true);
    assert.equal(deriveMetrics('teachers', input).pendingTeachers, (enabled ?? false) !== true);
    assert.equal(deriveMetrics('alumnos', input).activeStudents, (enabled ?? true) === true);
    assert.equal(deriveMetrics('members', input).activeUsers, (enabled ?? false) === true);
    assert.equal(deriveMetrics('members', input).blockedUsers, input.enabled === false || input.active === false);
  }
});

test('derived enrollment, subject and completion indicators preserve their definitions', () => {
  assert.equal(deriveMetrics('alumnos', { gradoId: 'grade-a' }).studentWithoutGrade, false);
  assert.equal(deriveMetrics('alumnos', { gradeId: '' }).studentWithoutGrade, true);
  assert.equal(deriveMetrics('subjects', { teacherUid: 'teacher-a' }).subjectsWithoutTeacher, false);
  assert.equal(deriveMetrics('subjects', {}).subjectsWithoutTeacher, true);
  for (const units of [undefined, [], [null], ['text'], [{ title: ' ' }], [{ titulo: 'Completa' }, {}]]) {
    assert.equal(deriveMetrics('planificaciones_anuales', { units }).completedPlans, false);
  }
  assert.equal(deriveMetrics('planificaciones_anuales', { units: [{ titulo: 'Unidad 1' }, { title: 'Unit 2' }] }).completedPlans, true);
  assert.equal(deriveMetrics('teachers', null), null);
  assert.throws(() => deriveMetrics('unsupported', {}));
});

test('derived rows contain counters only, never personal information', () => {
  const data = { name: 'private-name', email: 'private-email', medicalHistory: 'private-health', units: [{ title: 'private-title' }] };
  for (const collection of ['teachers', 'alumnos', 'members', 'subjects', 'planificaciones_anuales']) {
    const output = deriveMetrics(collection, data);
    assert.ok(Object.values(output).every((value) => typeof value === 'boolean'));
    assert.equal(JSON.stringify(output).includes('private-'), false);
  }
});
