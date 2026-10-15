'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

// Fail before any request if Firebase has not explicitly selected an emulator.
const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!host || !/^127\.0\.0\.1:\d+$/.test(host)) {
  throw new Error('These tests require a loopback Firebase Auth emulator.');
}
const project = 'demo-edupro-auth';
const base = `http://${host}`;
const password = '  synthetic-á-password  ';
async function call(operation, payload) {
  const response = await fetch(`${base}/identitytoolkit.googleapis.com/v1/accounts:${operation}?key=demo-emulator-key`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload), signal: AbortSignal.timeout(10000),
  });
  return { status: response.status, body: await response.json() };
}
async function newAccount() {
  const email = `synthetic-${randomUUID()}@example.invalid`;
  const result = await call('signUp', { email, password, returnSecureToken: true });
  assert.equal(result.status, 200, 'synthetic registration must succeed');
  return { email, ...result.body };
}
async function outOfBandCode(email, requestType) {
  const response = await fetch(`${base}/emulator/v1/projects/${project}/oobCodes`, { signal: AbortSignal.timeout(10000) });
  assert.equal(response.status, 200);
  const { oobCodes = [] } = await response.json();
  const code = oobCodes.find(row => row.email === email && row.requestType === requestType)?.oobCode;
  assert.ok(code, 'emulator must produce an out-of-band code');
  return code;
}

test('legitimate accounts can register and sign in with the exact password', async () => {
  const account = await newAccount();
  const signedIn = await call('signInWithPassword', { email: account.email, password, returnSecureToken: true });
  assert.equal(signedIn.status, 200);
  assert.equal(signedIn.body.localId, account.localId);
  assert.equal((await call('signInWithPassword', { email: account.email, password: password.trim() })).status, 400);
});

test('wrong passwords and unknown accounts are rejected by the provider emulator', async () => {
  const account = await newAccount();
  assert.equal((await call('signInWithPassword', { email: account.email, password: 'synthetic-wrong-password' })).status, 400);
  assert.equal((await call('signInWithPassword', { email: `absent-${randomUUID()}@example.invalid`, password })).status, 400);
  // Emulator error bodies need not implement production email-privacy policy.
});

test('a password reset link restores access and cannot be consumed twice', async () => {
  const account = await newAccount();
  assert.equal((await call('sendOobCode', { email: account.email, requestType: 'PASSWORD_RESET' })).status, 200);
  const oobCode = await outOfBandCode(account.email, 'PASSWORD_RESET');
  const nextPassword = ' synthetic-reset-secret ';
  assert.equal((await call('resetPassword', { oobCode, newPassword: nextPassword })).status, 200);
  assert.equal((await call('signInWithPassword', { email: account.email, password: nextPassword })).status, 200);
  assert.equal((await call('signInWithPassword', { email: account.email, password })).status, 400);
  assert.equal((await call('resetPassword', { oobCode, newPassword: nextPassword })).status, 400);
});

test('email verification confirms ownership using a provider verification code', async () => {
  const account = await newAccount();
  assert.equal((await call('sendOobCode', { idToken: account.idToken, requestType: 'VERIFY_EMAIL' })).status, 200);
  const oobCode = await outOfBandCode(account.email, 'VERIFY_EMAIL');
  assert.equal((await call('update', { oobCode })).status, 200);
  const lookup = await call('lookup', { idToken: account.idToken });
  assert.equal(lookup.status, 200);
  assert.equal(lookup.body.users[0].emailVerified, true);
});
