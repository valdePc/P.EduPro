'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const windows = process.platform === 'win32';
const testCommand = 'node --test --test-timeout=30000 security-tests/authentication.test.cjs';
const emulatorArgs = [
  'emulators:exec', '--project', 'demo-edupro-auth', '--config', 'firebase.auth-tests.json',
  '--only', 'auth', testCommand,
];
// Windows requires cmd to execute the CLI shim. The command is entirely static;
// no paths, request values or credentials are interpolated into command text.
const binary = windows ? 'cmd.exe' : 'firebase';
const args = windows ? ['/d', '/s', '/c',
  `"firebase.cmd emulators:exec --project demo-edupro-auth --config firebase.auth-tests.json --only auth "${testCommand}""`,
] : emulatorArgs;
const result = spawnSync(binary, args, {
  cwd: path.resolve(__dirname, '..'),
  env: { ...process.env, DEBUG: '' },
  encoding: 'utf8', windowsHide: true, windowsVerbatimArguments: windows,
  maxBuffer: 8 * 1024 * 1024,
});

function safeOutput(output = '') {
  return output.split(/\r?\n/).map(line => {
    if (line.includes('with environment {')) return '[Firebase CLI environment omitted]';
    if (line.includes('oobCode=')) return '[Synthetic emulator verification link omitted]';
    return line;
  }).join('\n');
}
if (result.stdout) process.stdout.write(safeOutput(result.stdout));
if (result.stderr) process.stderr.write(safeOutput(result.stderr));
if (result.error) process.stderr.write('The local Auth test runner could not start.\n');
process.exitCode = result.status ?? 1;
