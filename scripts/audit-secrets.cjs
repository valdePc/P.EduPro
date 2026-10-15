// Heuristic local scan. Only paths, line numbers and classifications are emitted.
// No credentials are sent to any service. Not a replacement for a secret scanner.
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const git = (...args) => execFileSync('git', args, {
  cwd: root, encoding: 'utf8', maxBuffer: 128 * 1024 * 1024,
});
const excluded = /(^|\/)(node_modules|build|\.git|\.dart_tool|\.firebase)(\/|$)|\.(png|jpg|jpeg|gif|ico|ttf|woff2?|jar|pdf|lock|log)$/i;
const patterns = [
  ['private_key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['service_account_private_key', /["']private_key["']\s*:\s*["'](?!["'])/],
  ['provider_secret', /\b(?:sk_live_|rk_live_|sk_test_|ghp_|github_pat_|xox[baprs]-)[A-Za-z0-9_-]{16,}/],
  ['aws_access_key', /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/],
  ['google_oauth_secret', /\bGOCSPX-[A-Za-z0-9_-]{20,}/],
  ['credential_in_url', /https?:\/\/[^\s\/:]+:[^\s\/@]{4,}@/],
];
let inspected = 0;
const findings = [];
const firebaseConfigFiles = new Set();
function scan(name, content, revision) {
  if (excluded.test(name) || content.includes('\0')) return;
  inspected++;
  content.split(/\r?\n/).forEach((line, index) => {
    for (const [kind, pattern] of patterns) {
      if (pattern.test(line)) {
        const synthetic = kind === 'credential_in_url'
          && name === 'test/client_security_test.dart'
          && line.includes('https:' + '//user:pass@example.org');
        findings.push({ file: name, line: index + 1, kind,
          classification: synthetic ? 'synthetic-test-fixture' : 'review-required',
          ...(revision ? { revision } : {}) });
      }
    }
    if (/\bAIza[A-Za-z0-9_-]{30,}\b/.test(line)) firebaseConfigFiles.add(name);
  });
}
for (const file of new Set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0').filter(Boolean))) {
  if (excluded.test(file)) continue;
  const absolute = path.resolve(root, file);
  if (!absolute.startsWith(root + path.sep) || !fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) continue;
  scan(file, fs.readFileSync(absolute, 'utf8'));
}
// Ignored environment files are checked locally too; only variable names are recorded.
const envFiles = ['.env', 'functions/.env'].filter(file => fs.existsSync(path.join(root, file)));
const envSummary = envFiles.map(file => {
  const content = fs.readFileSync(path.join(root, file), 'utf8');
  scan(file, content);
  return { file, variables: content.split(/\r?\n/).map(line => /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(line)?.[1]).filter(Boolean) };
});
let historicalFiles = 0;
if (process.argv.includes('--history')) {
  // Scan each unique reachable text blob once. Deleted files remain covered.
  for (const entry of git('rev-list', '--objects', '--all').split('\n')) {
    const space = entry.indexOf(' ');
    if (space < 0) continue;
    const object = entry.slice(0, space), file = entry.slice(space + 1).trim();
    if (excluded.test(file)) continue;
    if (git('cat-file', '-t', object).trim() !== 'blob') continue;
    if (Number(git('cat-file', '-s', object)) > 2 * 1024 * 1024) continue;
    scan(file, git('cat-file', '-p', object), object.slice(0, 12));
    historicalFiles++;
  }
}
console.log(JSON.stringify({
  scope: 'Heuristic patterns; ignored files other than the named env files, binary and historical blobs over 2 MiB are excluded.',
  inspected, historicalFiles, findings, envSummary,
  publicFirebaseApiKeyFiles: [...firebaseConfigFiles],
}, null, 2));
process.exitCode = findings.some(finding => finding.classification !== 'synthetic-test-fixture') ? 1 : 0;
