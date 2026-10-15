'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const read = file => {
  const bytes = fs.readFileSync(file);
  return bytes[0] === 0xff && bytes[1] === 0xfe
    ? bytes.subarray(2).toString('utf16le')
    : bytes.toString('utf8').replace(/^\uFEFF/, '');
};
const json = file => JSON.parse(read(file));
function nodeTests(file) {
  const log = read(file);
  const count = name => Number(log.match(new RegExp(`(?:ℹ|#) ${name} (\\d+)`))?.[1] ?? NaN);
  const tests = count('tests'), pass = count('pass'), fail = count('fail');
  return { status: Number.isFinite(tests) && pass === tests && fail === 0 ? 'passed' : 'not-passed', tests, pass, fail, cancelled: count('cancelled'), log: file };
}
const cloud = json('audit-cloud-security.log');
const db = json('audit-cloud-database.log').result;
const secrets = json('audit-secrets-final.log');
const analysis = read('audit-flutter-analyze-final.log');
const testLog = read('audit-flutter-tests.log');
const report = {
  generatedAt: new Date().toISOString(),
  productionApproved: false,
  deployedDuringAudit: false,
  studentRecordsReadFromProduction: false,
  backend: nodeTests('audit-backend-tests.log'),
  rules: nodeTests('audit-rules-tests.log'),
  flutterTests: { passed: /\+4: All tests passed!/.test(testLog), tests: 4, scope: 'Validators and one entry form; no end-to-end login.' },
  webBuild: { passed: /Built build[\\/]web/.test(read('audit-flutter-build.log')), appCheckProductionConfigurationValidated: false },
  flutterAnalysis: { passed: false, errors: (analysis.match(/^\s*error -/gm) || []).length, issues: Number(analysis.match(/(\d+) issues found/)?.[1]), log: 'audit-flutter-analyze-final.log' },
  dependencies: Object.fromEntries([
    ['root', 'audit-npm-root-final.json'],
    ['functionsAll', 'audit-npm-functions-final.json'],
    ['functionsProduction', 'audit-npm-functions-prod-final.json'],
  ].map(([name, file]) => [name, json(file).metadata.vulnerabilities])),
  secrets: { inspected: secrets.inspected, historicalFiles: secrets.historicalFiles, patternMatches: secrets.findings.length, syntheticFixtures: secrets.findings.filter(f => f.classification === 'synthetic-test-fixture').length, requiresReview: secrets.findings.filter(f => f.classification !== 'synthetic-test-fixture').length, limitation: secrets.scope },
  configurationObservedAt: cloud.inspectedAt,
  cloud: {
    location: db.locationId,
    pitr: db.pointInTimeRecoveryEnablement,
    deleteProtection: db.deleteProtectionState,
    scheduledBackups: json('audit-cloud-backups.log').result.length,
    nativeMfa: cloud.authentication.mfa.state,
    appCheck: cloud.appCheck,
    deployedFunctions: cloud.functions.length,
    functionsWithLegacyMfaBypassVariable: cloud.functions.filter(fn => fn.legacyMfaBypassConfigured).length,
    applicationRestrictions: cloud.apiKeyRestrictions.map(key => ({ name: key.displayName, browser: key.restrictions.browserKeyRestrictions, android: key.restrictions.androidKeyRestrictions, ios: key.restrictions.iosKeyRestrictions })),
    rulesAtInspection: cloud.rules,
  },
  currentLocalRules: Object.fromEntries(['firestore.rules', 'storage.rules'].map(file => [file, crypto.createHash('sha256').update(read(file).replace(/\r\n/g, '\n')).digest('hex')])),
  limitations: ['No full authentication E2E', 'No national-scale load test', 'No backup restoration', 'No complete IAM/monitoring audit', 'No accessibility or legal certification', 'Outstanding critical findings documented in security-audit-2026-10-05.md'],
};
fs.writeFileSync('docs/security-audit-results.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ backend: report.backend, rules: report.rules, flutterTests: report.flutterTests, webBuild: report.webBuild, dependencies: report.dependencies, secrets: report.secrets }, null, 2));
