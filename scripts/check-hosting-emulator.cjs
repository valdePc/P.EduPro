'use strict';
const http = require('node:http');
const assert = require('node:assert/strict');

const port = Number(process.argv[2] || 5000);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
const expected = new Map([
  ['/acerca.html', 200],
  ['/aviso-legal.html', 200],
  ['/privacidad.html', 200],
  ['/cookies.html', 200],
  ['/sitemap.xml', 200],
  ['/robots.txt', 200],
  ['/login', 200],
  ['/panel', 200],
  ['/docentes', 200],
  ['/eduproapp/test/admin', 200],
  ['/ruta-inexistente', 404],
]);

function check(path, status) {
  return new Promise((resolve, reject) => {
    const request = http.get({ hostname: '127.0.0.1', port, path, timeout: 5000 }, (response) => {
      response.resume();
      response.on('end', () => {
        try { assert.equal(response.statusCode, status, `${path}: HTTP`); resolve(); }
        catch (error) { reject(error); }
      });
    });
    request.on('timeout', () => request.destroy(new Error(`${path}: timeout`)));
    request.on('error', reject);
  });
}

Promise.all([...expected].map(([path, status]) => check(path, status)))
  .then(() => console.log(`Hosting emulator: ${expected.size} rutas verificadas.`))
  .catch((error) => { console.error(error.message); process.exitCode = 1; });
