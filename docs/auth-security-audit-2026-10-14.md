# Auditoría y endurecimiento de autenticación de EduPro

Fecha de cierre de esta fase: 14 de octubre de 2026, America/La_Paz. Se conserva Firebase Auth. Dictamen: cambios locales acotados verificados; **publicación general BLOQUEADA** por controles pendientes y transición de acceso por aprobar.

## Alcance y arquitectura

EduPro usa Flutter/Dart, Firebase Auth, Firestore, Storage y Cloud Functions Node.js. Equipo interno: correo/contraseña y Google; docentes/alumnos: Google; administración escolar: Google y un código de registro independiente de las contraseñas Auth. Hay un segundo factor TOTP implementado en Functions y controles de rol, horario, escuela y autenticación reciente.

Se revisaron manifiestos, puntos de autenticación, funciones, reglas, formularios identificados y pruebas. El [inventario de formularios](auth-form-inventory-2026-10-13.md) registra entradas y destinos detectados. Es un inventario estático de formularios de texto y flujos relevantes, no una certificación exhaustiva de todos los selectores, importaciones, archivos o recorridos. Las escrituras directas de otros módulos siguen dependiendo de sus reglas particulares; no se afirma haber agregado validación nueva a todos los formularios de negocio.

Se consultaron metadatos de configuración remota en lectura, sin leer expedientes, exportar hashes, cambiar políticas o probar credenciales reales. Las comprobaciones activas usaron almacenamiento simulado o emuladores con cuentas y datos sintéticos. No se desplegó ni se modificó una base de producción.

## Hallazgos, gravedad y estado

| Hallazgo | Gravedad | Evidencia y estado |
| --- | --- | --- |
| Dependencia `proxy-addr` 2.0.7 vulnerable bajo ciertas configuraciones de subred de proxy | Crítica según aviso del mantenedor; exposición de EduPro no demostrada | Detectada en los dos árboles de dependencias. **Corregida localmente** con 2.0.8; lockfiles, módulos instalados, prueba de la condición y auditoría verificados. No acredita parche en funciones ya desplegadas. |
| Enumeración de correo/teléfono en `precheckTeacherSignup` | Alta | Respuestas `allowed` diferentes para datos existentes/libres. Un mensaje genérico no elimina el canal. **Pendiente** rediseño de registro con propiedad de identidad y validación final privada. |
| MFA custom sin cobertura de todos los accesos directos SDK | Alta si la política exige segundo factor para esos datos | Callables verifican estado TOTP, pero las reglas actuales no comprueban esa sesión. **Pendiente** diseño completo de señal, alcance, recuperación y transición compatible. |
| Telemetría de login eludible al llamar directamente al proveedor | Alta como limitación del control | El login usa Firebase Auth directamente; llamar al callable de telemetría no es obligatorio para intentar Auth. **Pendiente** verificar protección real del proveedor y su política antiabuso. |
| Tipos coercibles y longitudes insuficientemente limitadas en entradas del servidor | Media | **Corregida en puntos revisados:** MFA, dispositivo, cuentas de administración, asignación de administrador, código/configuración de registro, precheck docente, telemetría y nombres/contactos de alta de colegio. Validación previa a uso de credenciales o escrituras. No abarca toda entrada de todos los módulos. |
| Presupuesto elegido por UID o IP, sin agregado por origen para cuentas autenticadas | Media | **Corregido localmente** para scopes sensibles: presupuesto por cuenta/origen y agregado de IP, transacción con lecturas antes de escrituras y ventanas que no se prolongan al rechazar. El agregado permite más solicitudes para escuelas detrás de NAT. |
| Último hop de X-Forwarded-For no necesariamente identifica al usuario final | Media, dependiente de topología | Se conserva la política previa de confiar únicamente en el último hop. No se acepta un prefijo arbitrario del cliente ni encabezados alternativos. **Pendiente** confirmar ingress/proxies reales; un proxy compartido puede agrupar usuarios y límites. Si no hay IP resoluble pero sí identidad Auth, permanece el presupuesto de UID. |
| Recorte de contraseñas y claves de registro | Media | **Corregido localmente:** valores exactos en reautenticación, credenciales enviadas a Auth, configuración/verificación/migración de clave registro y clientes modificados. **Publicación condicionada** a transición de clientes antiguos y formatos heredados con espacios. |
| Contraseña de alta de equipo visible y errores/logs excesivos | Media | **Corregido localmente:** campo oculto sin sugerencias/autocorrección, mensajes controlados y logs docentes sin datos personales/respuestas/excepciones completas. Se retiró entrada inválida cruda del log de configuración de registro. |
| Claves de registro heredadas pueden existir en texto plano | Alta si existen | El código contiene compatibilidad heredada. La migración a scrypt/sal aleatoria ya existía; se verificó y corrigió conservación del valor exacto. **No se verificó existencia en producción ni se ejecutó migración masiva.** Las cuentas Auth delegan almacenamiento al proveedor. |
| App Check no exigido por servicios Auth/Firestore/Storage | Necesidad de endurecimiento; no demuestra acceso indebido | Confirmado en metadatos remotos. Las funciones sí tienen ENFORCE_APPCHECK configurado. **Pendiente** activación gradual y validación de clientes; las reglas de autorización siguen siendo necesarias. |
| Configuración de Storage desplegada difiere de la local | Riesgo de validación operativa, gravedad efectiva pendiente | Confirmado por hashes de rulesets. Las pruebas locales **no acreditan** las reglas vigentes de Storage. No se publicaron reglas. |
| Dependencias con avisos moderados restantes | Media según npm; impacto por uso pendiente | Auditoría final: raíz 9 moderadas, backend 8 moderadas, ambas 0 altas/0 críticas. Actualizaciones mayores sugeridas para parte del árbol requieren evaluación y autorización separadas. |

No se confirmó creación anónima de expedientes de alumnos: las reglas exigen administración. El código de registro solo habilita navegación, sin emitir una autorización de escritura del servidor. El recorrido completo sin sesión administrativa requiere prueba funcional; no se presenta como bypass demostrado.

## Correcciones implementadas

- `validateAuthInput` y `authPayload` rechazan arreglos como payload, tipos incorrectos, campos de identificador con controles, correos mal formados, longitudes excesivas y booleanos coercibles. Los campos opcionales de alta de colegio admiten `null` donde el contrato anterior lo hacía. Nombres humanos conservan acentos, apóstrofes y texto significativo.
- Contraseñas y claves se validan sin convertir números/objetos en strings ni limpiar su contenido. El límite existente de 12–128 para cuentas escolares y claves nuevas se conserva y alinea en las interfaces modificadas. La política global del proveedor aún no se ha modificado.
- Se preserva Firebase Auth como verificador y almacén de las contraseñas de cuenta. El secreto independiente de registro usa scrypt y sal aleatoria; la prueba verifica ausencia de texto plano en la configuración nueva y salts distintos para el mismo valor. No se añadieron hashes MD5/SHA-1/SHA-256 para contraseñas; SHA-256 de identificadores de contadores no es almacenamiento de contraseñas.
- Se añadió agregado IP únicamente a scopes sensibles y un presupuesto de configuración de registro tras comprobar permisos. Los contadores guardan claves derivadas y número/expiración; el evento de rechazo registra solo un scope fijo. Los límites del código/TOTP ya existentes conservan bloqueos temporales y recuperación al expirar. No se afirma que limiten todos los endpoints directos del proveedor.
- La generación de claves temporales en `coleAdmin` usa `Random.secure()` sin fallback inseguro y genera 16 caracteres. Las interfaces de clave registro se alinean con 12–128 caracteres; la reautenticación sigue aceptando contraseñas de cuentas existentes sin imponer una política nueva.
- Se sustituyeron errores crudos y registros personales en los puntos cliente revisados. En Firebase se confirmó `enableImprovedEmailPrivacy: true`; la protección de mensajes del cliente no sustituye esa política.
- Se aplicó el parche autorizado `proxy-addr` 2.0.8. Un test inicialmente detectó una instalación raíz aún en 2.0.7 a pesar del lockfile; se invalidó su caché generada de npm con copia de respaldo y se reinstaló. La versión cargada final y la condición vulnerable quedaron verificadas en ambos árboles.

## SQL, XSS y tiempos

No se identificó una base SQL ni ensamblado de SQL en los puntos revisados. Firestore usa consultas estructuradas del SDK; no corresponde introducir una biblioteca SQL para parametrizarlas. El control de inyección relevante es validar identificadores, tipos, rutas y autorización.

Las vistas revisadas presentan datos como texto Flutter. La búsqueda dirigida no encontró sinks HTML como innerHTML/outerHTML ni renderizadores HTML en esos puntos. Ya existen pruebas de rechazo de esquemas y URLs peligrosos en utilidades de enlaces/documentos. No se aplicó una limpieza general de contraseñas ni una codificación HTML innecesaria a datos que se presentan como texto. Si se añade renderizado HTML, deberá usar escape/sanitización según el contexto real.

Se comprobaron errores uniformes de cliente y configuración de privacidad del proveedor. **No se midieron tiempos de respuesta de cuentas reales ni se demuestra indistinguibilidad temporal completa.** El precheck docente mantiene una diferencia de respuesta confirmada. Los emuladores no reproducen todas las políticas antiabuso/privacidad del servicio de producción. No se pretende resolver la enumeración introduciendo un retraso frontend que pueda omitirse.

## Configuración remota comprobada

Evidencia: `audit-auth-cloud-2026-10-14.json`, consulta de metadatos.

- Correo/contraseña habilitados; privacidad de correo mejorada habilitada.
- MFA nativo del proveedor: DISABLED. Esto no establece el estado de la política TOTP custom almacenada en documentos, que no se consultó.
- No se devolvió una política de contraseñas personalizada. No se acredita una política más fuerte que los valores predeterminados.
- Auth, Firestore y Storage: App Check UNENFORCED; 28 funciones con ENFORCE_APPCHECK configurado.
- 28 funciones conservan una variable heredada de bypass MFA. El código local no usa esa variable; su presencia no demuestra su ejecución en el código desplegado. Evaluar y retirar configuración obsoleta en un despliegue autorizado.
- Ruleset Firestore coincide con archivo local; Storage difiere.

## Archivos modificados en esta auditoría

Todos los archivos ya tenían cambios ajenos a esta fase o eran nuevos según el estado inicial; se conservaron esos cambios. Esta lista identifica el alcance propio, no atribuye todo el diff global a la auditoría.

| Archivo | Cambio propio |
| --- | --- |
| `functions/index.js` | Conexión de esquemas, validación de alta de colegio, secretos exactos, presupuesto agregado en scopes sensibles y log minimizado |
| `functions/security.js` | Validador de entradas sin normalización de secretos |
| `functions/test/security.test.js` | Nuevas regresiones y soporte incremental fiel en almacenamiento simulado |
| `functions/test/proxy_security.test.js` | Regresión de subredes y carga de SDK con árbol parcheado |
| `lib/screens/admin_general.dart` | Reautenticación/secreto exactos y errores controlados |
| `lib/screens/equipoedupro.dart` | Contraseña oculta, validación exacta y errores controlados |
| `lib/screens/coleAdmin.dart` | Claves exactas, generación segura y límites consistentes |
| `lib/admin_escolar/screens/A_registro.dart` | Clave exacta y longitud alineada |
| `lib/admin_escolar/screens/admin_login_escolar.dart` | Código exacto y errores controlados |
| `lib/docentes/screens/crearcuentadocentes.dart` | Logs sin datos personales ni respuestas/excepciones completas |
| `lib/utils/auth_input_validation.dart` | Construcción de credencial Firebase que conserva contraseña |
| `test/auth_input_validation_test.dart` | Regresión de serialización exacta de contraseña |
| `package.json` | Ejecución de nuevas suites de Auth/proxy |
| `functions/package.json` | Incluye prueba de proxy en suite backend |
| `package-lock.json`, `functions/package-lock.json` | Único paquete actualizado respecto del snapshot previo al parche: proxy-addr 2.0.7 → 2.0.8 |
| `firebase.auth-tests.json` | Emulador Auth aislado, loopback y UI deshabilitada |
| `security-tests/authentication.test.cjs` | Acceso, rechazo, recuperación y verificación con cuentas sintéticas |
| `scripts/run-auth-tests.cjs` | Ejecuta proyecto demo; evita volcar entorno y enlaces de verificación en logs |
| `docs/auth-form-inventory-2026-10-13.md` | Inventario y arquitectura de formularios |
| `docs/auth-test-plan-2026-10-14.md` | Matriz y evidencia QA |
| `docs/auth-independent-review-2026-10-14.md` | Revisión independiente de seguridad |
| `docs/auth-risky-changes-proposal-2026-10-14.md` | Propuestas de transición que requieren aprobación |
| `docs/auth-security-audit-2026-10-14.md` | Este informe |

No se modificaron `firestore.rules`, `storage.rules`, proveedores, credenciales reales, política Auth ni datos de producción en esta fase.

## Pruebas y resultados finales

| Comprobación | Resultado | Evidencia |
| --- | --- | --- |
| `npm.cmd run test:security` | 69 aprobadas, 0 fallidas/omitidas; código 0 | `audit-auth-node-2026-10-14.log` |
| `npm.cmd run test:auth` | 4 aprobadas; código 0 | `audit-auth-emulator-2026-10-14.log` |
| `npm.cmd run test:rules` | 27 aprobadas, 0 fallidas/omitidas; código 0 | `audit-auth-rules-2026-10-14.log` |
| `flutter test --no-pub` | 88 aprobadas, 1 omisión condicional; código 0 | `audit-auth-flutter-2026-10-14.log` |
| `flutter test --no-pub --dart-define=VALMICH_APP_CHECK=true test/app_check_bootstrap_test.dart` | 1 aprobada, rama contraria omitida; código 0 | `audit-auth-appcheck-2026-10-14.log` |
| `flutter analyze --no-pub` | 0 errores, 130 advertencias, 800 informaciones; código 1 | `audit-auth-analyze-2026-10-14.log` |
| Revisión independiente Node | 57 aprobadas | Informe independiente; handlers y proxy |
| `npm audit --omit=dev --json` en raíz y backend | 0 críticas/altas; 9/8 moderadas; código 1 por pendientes | `audit-auth-dependencies-*-final-2026-10-14.json` |
| Escáner de secretos local/historial | 1.079 archivos inspeccionados, 633 históricos; código 1 por fixtures señalados | `audit-auth-secrets-2026-10-14.json`; revisión manual de avisos |

El análisis Flutter conserva el total previo de 930 incidencias; la salida inicial truncada no permite afirmar coincidencia individual. No hubo diagnósticos del helper nuevo. Las omisiones de App Check corresponden a ramas excluyentes, probadas con ambas configuraciones. El escáner señaló URLs con credenciales sintéticas en pruebas actuales/históricas; no se confirmó un secreto real con sus patrones, y no se presenta como escaneo sin observaciones o detección exhaustiva.

Las pruebas nuevas verifican rechazo antes de mutar Auth/datos, contraseñas exactas con espacios/Unicode, salts únicos, ausencia de texto plano en configuración nueva, migración sintética, límites concurrentes y recuperación al vencer ventanas. El emulador verifica que cuentas legítimas sintéticas mantienen acceso y que recuperación/verificación funcionan a nivel proveedor. Esto no sustituye un recorrido visual completo de EduPro en navegador/dispositivo ni prueba cuentas reales de producción.

## Pendientes y recomendaciones

1. Aprobar el rediseño del registro docente: Google antes de enviar datos personales, propiedad de correo y escritura/duplicados transaccionales privados. Mantener solicitudes existentes. No retirar solo la comprobación actual.
2. Aprobar diseño de MFA para todos los accesos relevantes con recuperación segura y señal de sesión que pueda verificarse en reglas/callables, antes de activar restricciones.
3. Resolver transición de códigos exactos y clientes antiguos. No rotar credenciales reales como sustitución de compatibilidad.
4. Confirmar topología de ingress, comportamiento de límites en NAT, almacenamiento/retención de contadores y política antiabuso de endpoints directos Firebase, incluidos registro y recuperación.
5. Evaluar políticas de nuevas contraseñas, App Check y reCAPTCHA con pruebas de cliente y despliegue gradual. Revisar reglas reales de Storage antes de publicar.
6. Evaluar avisos moderados y actualización mayor de Firebase Admin en una fase independiente con pruebas y reversión.
7. Añadir recorridos de EduPro completos por rol/escuela con backend emulado; validar registro con código sin sesión administrativa y consistencia Auth/perfil ante fallos.
8. Para credenciales heredadas de registro, inventariar únicamente metadatos de formato/algoritmo sin valores y definir migración compatible autorizada. Firebase Auth conserva el almacenamiento de contraseñas de cuenta.

La [propuesta de cambios con impacto](auth-risky-changes-proposal-2026-10-14.md) detalla riesgos y alcance. La exigencia de autorización procede de la regla del usuario: «Si alguna modificación representa un riesgo, detente y solicita autorización». No se autoriza publicar mediante este informe.

## Fuentes oficiales y del mantenedor

- [Protección contra enumeración de correo](https://docs.cloud.google.com/identity-platform/docs/admin/email-enumeration-protection).
- [Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth).
- [Emulador de Authentication y sus diferencias con producción](https://firebase.google.com/docs/emulator-suite/connect_auth).
- [Aviso y parche de proxy-addr](https://github.com/jshttp/proxy-addr/security/advisories/GHSA-jqcg-44mw-7w3h).
