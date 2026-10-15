'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const pages = ['acerca.html', 'aviso-legal.html', 'privacidad.html', 'cookies.html', '404.html'];
const files = [...pages, 'index.html', 'legal.css', 'robots.txt', 'sitemap.xml', 'favicon.png'];
for (const file of files) assert(fs.existsSync(path.join(root, 'web', file)), `Falta ${file}`);

const publicOrigin = 'https://edupro-8c4fd.web.app';
function luminance(hex) {
  const channels = hex.match(/[0-9a-f]{2}/gi).map((part) => parseInt(part, 16) / 255);
  const linear = channels.map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}
function contrast(foreground, background) {
  const values = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}
for (const [foreground, background] of [
  ['15243d', 'f6f8fc'], // main text / page
  ['0b438e', 'f6f8fc'], // links / page
  ['0b438e', 'e8f0fc'], // eyebrow / panel
  ['ffffff', '0d47a1'], // primary button
  ['ffffff', '006b5e'], // WhatsApp button
]) assert(contrast(foreground, background) >= 4.5, `Contraste insuficiente: ${foreground}/${background}`);

for (const page of pages) {
  const html = fs.readFileSync(path.join(root, 'web', page), 'utf8');
  assert(html.includes('<html lang="es-DO">'), `${page}: idioma`);
  assert(html.includes('name="viewport"'), `${page}: viewport`);
  assert(html.includes('<title>'), `${page}: título`);
  for (const image of html.matchAll(/<img\b[^>]*>/g)) {
    assert(/\balt="[^"]+"/.test(image[0]), `${page}: imagen sin texto alternativo`);
    assert(/\bwidth="\d+"/.test(image[0]) && /\bheight="\d+"/.test(image[0]), `${page}: imagen sin dimensiones`);
  }
  if (page !== '404.html') {
    assert(html.includes(`<link rel="canonical" href="${publicOrigin}/${page}">`), `${page}: canonical incorrecta`);
    assert(/<meta name="description" content="[^"]+">/.test(html), `${page}: falta descripción`);
  }
  for (const match of html.matchAll(/(?:href|src)="(\/[^"#?]*)/g)) {
    const target = match[1] === '/' ? 'index.html' : match[1].slice(1);
    assert(fs.existsSync(path.join(root, 'web', target)), `${page}: enlace roto ${match[1]}`);
  }
}

const home = fs.readFileSync(path.join(root, 'web', 'acerca.html'), 'utf8');
assert(home.includes('application/ld+json'), 'Faltan datos estructurados');
const structuredData = JSON.parse(home.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
assert.equal(structuredData.name, 'EduPro', 'Nombre de marca incorrecto en datos estructurados');
assert.equal(structuredData.url, `${publicOrigin}/acerca.html`, 'URL incorrecta en datos estructurados');
assert.equal((home.match(/class="cta"/g) || []).length, 1, 'Debe haber una CTA principal');
assert(home.includes('https://wa.me/4915756052305'), 'Falta WhatsApp autorizado');
assert(!home.includes('gtag.js'), 'Analítica no debe cargarse sin ID ni consentimiento');

const sitemap = fs.readFileSync(path.join(root, 'web', 'sitemap.xml'), 'utf8');
for (const page of pages.filter((x) => x !== '404.html')) assert(sitemap.includes(`/${page}`), `${page}: falta sitemap`);
for (const match of sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)) {
  const url = new URL(match[1]);
  assert.equal(url.origin, publicOrigin, `Sitemap: origen inesperado ${url.origin}`);
  assert(fs.existsSync(path.join(root, 'web', url.pathname.slice(1))), `Sitemap: falta ${url.pathname}`);
}
assert(!sitemap.includes('/index.html'), 'El login privado no debe figurar en el sitemap');
assert(fs.readFileSync(path.join(root, 'web', 'index.html'), 'utf8').includes('noindex'), 'El login debe estar noindex');

const hosting = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8')).hosting;
assert(!hosting.rewrites.some((rule) => rule.source === '**'), 'El catch-all impide 404 reales');
const appRoutes = new Set(hosting.rewrites.map((rule) => rule.source));
for (const route of ['/login', '/panel', '/docentes', '/colocarCalificaciones']) assert(appRoutes.has(route), `Falta ruta ${route}`);
assert(!appRoutes.has('/ruta-inexistente'), 'La ruta inexistente debe dar 404');
console.log('Sitio público: páginas, enlaces, SEO, privacidad y rutas verificados.');
