'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { buildCatalogEntry, normalize, catalogPoint, fieldsForRole } = require('../school_catalog');

test('search normalizes accents and identity prefixes without indexing private fields', () => {
  const entry = buildCatalogEntry('A', { name: 'Colegio Águila', code: 'COD-123',
    location: { province: 'Santo Domingo', latitude: 18.5, longitude: -69.9 },
    adminEmail: 'private@example.test', contact: { name: 'Private Contact' }, registrationPassword: 'private-secret' });
  assert.equal(normalize('  ÁGUILA   Azul  '), 'aguila azul');
  for (const term of ['a', 'agui', 'colegio agui', 'cod-1']) assert.ok(entry.searchTokens.includes(term));
  assert.equal(JSON.stringify(entry).includes('private'), false);
  assert.equal(entry.searchTokens.includes('santo domingo'), false);
  assert.equal(entry.provinceKey, 'santo domingo');
  assert.equal(buildCatalogEntry('ValMichApp_Admin_X', { name: 'Internal' }), null);
  assert.equal(buildCatalogEntry('EDUPROAPP_ADMIN_X', { name: 'Internal' }), null);
});

test('coordinate and status aggregates preserve canonical and legacy locations', () => {
  for (const data of [{ location: { latitude: 18.5, longitude: -69.9 } },
    { location: { lat: '18.5', lng: '-69.9' } }, { geo: { lat: 18.5, lon: -69.9 } },
    { latitude: 18.5, longitude: -69.9 }]) {
    assert.deepEqual(catalogPoint(data), { latitude: 18.5, longitude: -69.9 });
    assert.equal(buildCatalogEntry('A', data).hasCoordinates, true);
  }
  for (const data of [{}, { location: { latitude: false, longitude: -69.9 } },
    { latitude: '', longitude: -69.9 }, { latitude: 0, longitude: 0 }, { latitude: Infinity, longitude: -69.9 }]) {
    assert.equal(catalogPoint(data), null);
  }
  assert.equal(buildCatalogEntry('A', { accountStatus: 'borrador' }).status, 'draft');
  assert.equal(buildCatalogEntry('A', { active: false }).status, 'suspended');
  assert.equal(buildCatalogEntry('A', { accountStatus: 'expired' }).status, 'other');
});

test('all root read masks exclude credentials and billing never reads geography or contacts', () => {
  for (const role of ['super_admin', 'operations_admin', 'support_onboarding', 'billing_admin']) {
    const fields = fieldsForRole(role);
    assert.equal(fields.includes('registrationPassword'), false);
    assert.equal(fields.includes('adminUid'), false);
    assert.equal(fields.includes('privateNotes'), false);
    if (role === 'billing_admin') {
      assert.equal(fields.some((field) => field.startsWith('location') || field.startsWith('contact') || field.startsWith('geo.')), false);
    } else if (role !== 'super_admin') {
      assert.equal(fields.includes('billingNextDueAt'), false);
      assert.equal(fields.includes('planPrice'), false);
    }
  }
});
