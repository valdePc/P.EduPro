"use strict";

const crypto = require("node:crypto");
const { isIP } = require("node:net");

function normalizeSchoolId(raw) {
  if (typeof raw !== "string") return "";
  const value = raw.trim().replace(/^eduproapp_admin_/, "");
  return /^[A-Za-z0-9_-]{1,128}$/.test(value) ? value : "";
}

function randomAlphaNumCode(length = 8) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  return Array.from({ length }, () => chars[crypto.randomInt(chars.length)]).join("");
}

function normalizeIp(value) {
  if (typeof value !== "string") return "";
  const candidate = value.trim().replace(/^::ffff:/i, "");
  if (!isIP(candidate)) return "";
  // Canonicalize equivalent IPv6 representations to the same rate-limit key.
  if (isIP(candidate) !== 6) return candidate;
  try {
    return new URL(`http://[${candidate}]/`).hostname.slice(1, -1);
  } catch (_) {
    return "";
  }
}

function resolveClientIp(request) {
  // Cloud Functions appends its routing information to X-Forwarded-For.
  // Only use the last platform-provided hop, never an arbitrary client prefix
  // or Fastly/Cloudflare headers. A proxy hop can group clients; verify the
  // deployed ingress topology before interpreting this value as an end-user IP.
  const forwarded = request?.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string") {
    const parts = forwarded.split(",");
    return normalizeIp(parts[parts.length - 1]);
  }
  return normalizeIp(request?.socket?.remoteAddress);
}

function totpCounter(secret, code, nowMs, generateCode) {
  if (!/^\d{6}$/.test(code)) return null;
  const counter = Math.floor(nowMs / 30000);
  for (let drift = -1; drift <= 1; drift += 1) {
    if (counter + drift < 0) continue;
    const expected = Buffer.from(generateCode(secret, counter + drift));
    const actual = Buffer.from(code);
    if (expected.length === actual.length && crypto.timingSafeEqual(expected, actual)) {
      return counter + drift;
    }
  }
  return null;
}

// Validate before normalizing identifiers. Secret values are never trimmed,
// coerced to strings, case-folded or HTML-escaped. Errors contain no input data.
function validateAuthInput(data, schema = {}) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new TypeError("Solicitud inválida.");
  }
  for (const [field, rule] of Object.entries(schema)) {
    const value = data[field];
    if (value === undefined || (value === null && rule.nullable && !rule.required)) {
      if (rule.required) throw new TypeError("Faltan campos obligatorios.");
      continue;
    }
    if (rule.type === "boolean") {
      if (typeof value !== "boolean") throw new TypeError("Campo booleano inválido.");
      continue;
    }
    if (typeof value !== "string" || value.length > rule.max ||
        (rule.required && value.length === 0)) {
      throw new TypeError("Tipo o longitud de campo inválido.");
    }
    if (rule.secret) continue;
    if (/[\u0000-\u001f\u007f]/u.test(value)) {
      throw new TypeError("Formato de campo inválido.");
    }
    if (rule.email && value.length && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(value.trim())) {
      throw new TypeError("Correo electrónico inválido.");
    }
    if (rule.pattern && value.length && !rule.pattern.test(value)) {
      throw new TypeError("Formato de campo inválido.");
    }
  }
  return data;
}

module.exports = { normalizeSchoolId, randomAlphaNumCode, resolveClientIp, totpCounter, validateAuthInput };
