"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

test("IPv4 callers cannot match an invalid IPv4-mapped IPv6 trusted subnet", () => {
  for (const modulePath of ["../../node_modules/proxy-addr", "../node_modules/proxy-addr"]) {
    const proxy = require(modulePath);
    const malformed = proxy.compile("::ffff:10.0.0.0/8");
    assert.equal(malformed("192.0.2.9", 0), false);
    assert.equal(malformed("203.0.113.9", 0), false);
    const mapped = proxy.compile("::ffff:10.0.0.0/104");
    assert.equal(mapped("10.2.3.4", 0), true);
    assert.equal(mapped("192.0.2.9", 0), false);
  }
});

test("installed Firebase server SDKs load with the patched dependency tree", () => {
  const admin = require("firebase-admin");
  const { onCall } = require("firebase-functions/v2/https");
  assert.equal(typeof admin.initializeApp, "function");
  assert.equal(typeof onCall, "function");
  // No Firebase app is initialized and no production request is made.
});
