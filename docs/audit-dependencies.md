# Dependencias npm: corrección del árbol raíz y auditoría final de Functions

Fecha: 2026-10-05. Entorno observado: Node 24.12.0 y npm 11.6.2. Este trabajo no modifica `functions/package.json` ni `functions/package-lock.json` y no supone validación de las dependencias Flutter.

## Problema y cambio

El cliente Firebase de las pruebas de reglas (`firebase@12.19.0`, dependencia de desarrollo) incorpora `@firebase/firestore@4.17.2`, cuyo manifiesto solicita `@grpc/grpc-js ~1.9.0`. El árbol conservaba una copia anidada `1.9.16` con vulnerabilidad alta aunque el manifiesto raíz ya incluía este override:

```json
"overrides": {
  "@firebase/firestore": {
    "@grpc/grpc-js": "^1.14.5"
  }
}
```

`npm ls` marcaba esa copia como `invalid`. Una previsualización de `npm dedupe` no proponía sustituirla y ofrecía otros cuatro cambios ajenos a gRPC; no se aplicó esa deduplicación global.

Se retiró únicamente la entrada obsoleta `node_modules/@firebase/firestore/node_modules/@grpc/grpc-js` del lock, manteniendo el override y la copia raíz `1.14.5` ya descargada con su integridad. Después:

```powershell
$env:NODE_USE_SYSTEM_CA='1'
npm.cmd install --package-lock-only --ignore-scripts --no-audit --offline
npm.cmd install --ignore-scripts --no-audit --offline
```

npm validó el lock y retiró **un paquete**, la copia anidada antigua. Firestore cliente y google-gax pasan a utilizar `@grpc/grpc-js@1.14.5`. No se borró `node_modules`, no se utilizó `--force`, no se desactivó TLS ni se ejecutaron scripts de paquetes. `NODE_USE_SYSTEM_CA=1` conserva la validación de certificados usando las autoridades del sistema.

## Comprobaciones

- `npm ls @grpc/grpc-js --all`: árbol instalado válido, sin nodos `invalid`, ambos consumidores resuelven 1.14.5.
- `npm ls @grpc/grpc-js --all --package-lock-only`: misma resolución en el lock.
- Resolución de Node iniciada desde `node_modules/@firebase/firestore`: carga la copia raíz gRPC 1.14.5.
- `npm ci --dry-run --ignore-scripts --no-audit --offline`: finaliza correctamente. Es una validación en seco; no se afirma haber realizado una instalación limpia completa en otra máquina.
- `npm audit --json` y `npm audit --omit=dev --json`: **0 críticas, 0 altas, 12 moderadas** en el árbol raíz al momento de comprobar. Resultado completo en `audit-npm-root-final.json`.

Las 12 entradas moderadas son paquetes afectados directa o transitivamente por el mismo aviso de `uuid <11.1.1`, [GHSA-w5hq-g745-h8pq](https://github.com/advisories/GHSA-w5hq-g745-h8pq). No equivalen a doce vulnerabilidades independientes. Incluyen Firebase Admin, Firestore servidor, Storage, sus bibliotecas de autenticación/transporte y funciones. Están presentes también al omitir dependencias de desarrollo; **no son únicamente un riesgo de las pruebas**. `npm audit` no ofrece una corrección automática completa compatible para este árbol.

El alcance focalizado no cambió Firebase Admin a la siguiente versión principal ni aplicó cambios globales en gaxios/google-auth-library. Es necesaria una migración controlada y nuevas pruebas para cerrar los avisos restantes. El resultado de `functions/` debe citarse por separado; es otro manifiesto y otro lock. Cero avisos altos no constituye una garantía de seguridad del producto.

## Auditoría final: raíz y Functions

Se ejecutó de nuevo `npm audit` dentro de `functions/`, con TLS verificado (`NODE_USE_SYSTEM_CA=1`) y sin modificar su manifiesto, lock o dependencias. Los archivos siguientes contienen respuestas JSON válidas, guardadas como UTF-8, sin errores de consulta al registro:

| Árbol y alcance | Críticas | Altas | Moderadas | Evidencia |
| --- | ---: | ---: | ---: | --- |
| Raíz, dependencias completas | 0 | 0 | 12 | `audit-npm-root-final.json` |
| Raíz, `--omit=dev` | 0 | 0 | 12 | Comprobación de consola descrita arriba |
| Functions, dependencias completas | 0 | 0 | 14 | `audit-npm-functions-final.json` |
| Functions, `--omit=dev` | 0 | 0 | 12 | `audit-npm-functions-prod-final.json` |

En Functions, las doce entradas de producción corresponden al aviso de `uuid` indicado anteriormente y sus paquetes dependientes. Las dos entradas adicionales de desarrollo son `ts-deepmerge` y `firebase-functions-test`, afectadas por [GHSA-87mf-gv2c-c62c](https://github.com/advisories/GHSA-87mf-gv2c-c62c), sobre sobrescritura de métodos del prototipo que puede causar denegación de servicio. Estas dos entradas no aparecen al omitir desarrollo; las otras doce permanecen en el backend desplegable. Los conteos entre árboles no deben sumarse como si fueran vulnerabilidades independientes.

Sobre el código actual de Functions se confirmó además `node --check functions/index.js` sin errores y **13 de 13 pruebas aprobadas** con `node --test functions/test/security.test.js`. Las pruebas de autorización y TOTP usan dependencias simuladas; no acreditan login real ni eliminan los avisos de las bibliotecas. No se realizaron más cambios de código para esta confirmación final.

Los emuladores y la compilación de la aplicación son verificaciones separadas del proyecto; este informe acredita únicamente las comprobaciones de resolución y auditoría indicadas arriba. El override requiere revisar compatibilidad en las pruebas de reglas y retirarlo cuando Firebase adopte una versión corregida de forma nativa.

Referencias oficiales de npm: [overrides en package.json](https://docs.npmjs.com/cli/configuring-npm/package-json/#overrides) y [comportamiento de dedupe](https://docs.npmjs.com/cli/v11/commands/npm-dedupe/).
