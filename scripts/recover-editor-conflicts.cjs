'use strict';
// Preserve both sides of these VS Code save conflicts; never edit live buffers.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const backupRoot = path.join(process.env.APPDATA, 'Code/Backups/07d360131d4c66cd27d725b4bde0bbc7/file');
const targets = new Set(['lib/services/app_check_bootstrap.dart', 'lib/screens/login_general.dart', 'lib/screens/acceso_enlace_screen.dart']);
const destination = path.join(root, '.editor-recovery/2026-10-05-save-conflicts');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
for (const id of ['-1a10a03', '-2a8b011b', '-2aa26049']) {
  const backup = fs.readFileSync(path.join(backupRoot, id));
  const newline = backup.indexOf(10);
  if (newline < 0) throw new Error('Invalid backup header');
  const uri = new URL(backup.subarray(0, newline).toString('utf8').trim().split(' ')[0]);
  if (uri.protocol !== 'file:' || uri.hostname) throw new Error('Expected a local file URI');
  const source = path.resolve(decodeURIComponent(uri.pathname).replace(/^\/([a-z]:\/)/i, '$1'));
  const relative = path.relative(root.toLowerCase(), source.toLowerCase()).replaceAll('\\', '/');
  if (!targets.has(relative)) throw new Error('Backup is outside the three expected files');
  const editor = backup.subarray(newline + 1);
  const disk = fs.readFileSync(source);
  for (const [version, data] of [['editor', editor], ['disk', disk]]) {
    const dest = path.join(destination, version, `${path.basename(source)}.txt`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, data, { flag: 'wx' });
  }
  console.log(JSON.stringify({ file: relative, editorBytes: editor.length, diskBytes: disk.length, identical: hash(editor) === hash(disk) }));
}
