# Lectura de colegios sin reparación automática

El listado actual utiliza `TeamSchoolAccessService.watchSchools()` y ya no ejecutaba la reparación masiva anterior. Se retiraron sus restos de Admin General: el conjunto de identificadores sincronizados y los métodos privados sin uso que escribían metadatos. La creación del colegio sigue delegándose a `createSchool`, que escribe el colegio, `public/meta` y su configuración en el mismo lote del servidor.

Se encontró otra escritura implícita en `ColeAdminScreen._refreshSchool()`: después de leer la ficha y la configuración reconstruía `public/meta`. También se retiró. El refresco consulta datos y avisa si falla la lectura; no repara ni escribe metadatos.

## Revisión de colegios antiguos

La herramienta `scripts/migrate-school-public-meta.cjs` se ejecuta fuera de la app y no tiene ningún enlace desde las pantallas. Por defecto solo consulta identificadores y la existencia de metadatos, en páginas de 200 colegios:

```powershell
node scripts/migrate-school-public-meta.cjs
```

Si una revisión encuentra documentos faltantes, la ejecución explícita con `--apply` crea únicamente esos documentos:

```powershell
node scripts/migrate-school-public-meta.cjs --apply
```

La ejecución utiliza la sesión administrativa existente de Firebase CLI, sin archivos de credenciales nuevos. No modifica colegios originales, cuentas o metadatos existentes. No utiliza un lote con todos los colegios.

Cada creación relee el colegio y `public/meta` dentro de una transacción. Si el colegio fue eliminado o alguien creó sus metadatos después del inventario, no los crea ni sobrescribe. La creación y el evento `school.public-meta.created-by-migration` de `team_audit` son atómicos. Una auditoría fallida impide la escritura.

La transacción proyecta únicamente los campos públicos permitidos. No lee contactos, administradores, facturación ni claves de registro. Filtra grados con valores no textuales y enlaces con protocolos ejecutables, credenciales o parámetros. Un colegio bloqueado, suspendido o vencido no se reactiva. Las salidas contienen cantidades, sin nombres, enlaces, identificadores de colegios ni credenciales. Los fallos se cuentan y producen código de salida distinto de cero; una ejecución posterior puede reintentar los documentos que sigan faltando.

## Comprobación del proyecto

La consulta de solo lectura de `edupro-8c4fd` encontró siete colegios, los siete con `public/meta`, cero faltantes y cero fallos. No fue necesario ejecutar `--apply`: esta corrección no escribió datos en producción ni cambió reglas o funciones desplegadas.

Pasaron 49 pruebas del servidor y de migración. Incluyen la creación real del manejador con metadatos públicos sin información privada, selección de campos, estados bloqueados, repetición segura, concurrencia frente a un documento ya creado, colegio eliminado y fallo de auditoría. El análisis de las pantallas afectadas no encontró errores; permanecen avisos previos de estilo y elementos sin uso.

También pasaron las 58 pruebas de Flutter, con una omisión previa, y la compilación web. El cliente compilado queda en `build/web`; no se publicó Hosting. Para ver el cambio en desarrollo hay que reiniciar la ejecución actual de Flutter y recargar el navegador.
