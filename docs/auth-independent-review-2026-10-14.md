# Revisión independiente de autenticación — 2026-10-14

## Alcance y evidencia

Revisión independiente del estado local de `functions/security.js`, los endpoints de autenticación de `functions/index.js`, sus pruebas y los cambios relacionados en formularios Flutter. El repositorio contiene numerosos cambios anteriores: este informe no aprueba el diff completo contra HEAD. No se editaron archivos de implementación, no se consultaron servicios remotos ni se desplegó desde esta revisión. Se creó únicamente este informe.

Se ejecutó `node --test functions/test/security.test.js`: **54 aprobadas, 0 fallidas**. Incluye tipos inválidos, contraseñas exactas, migración del secreto de registro, presupuestos por cuenta y origen, reutilización TOTP y controles de rol. El almacén de pruebas es sintético y serializa transacciones; no acredita carga ni comportamiento de red/Firestore en producción. Las pruebas Flutter y demás suites corresponden al coordinador, no se ejecutaron independientemente aquí.

## Resultado del endurecimiento local

- La validación rechaza objetos, tipos y longitudes no admitidos con errores sin reproducir entradas. Las contraseñas no se convierten mediante `String` ni se recortan al enviarse a Firebase Auth.
- El presupuesto agregado de origen se limita a ámbitos sensibles. Lee todos los contadores antes de escribirlos y un rechazo no prolonga su ventana. La selección de la IP aún necesita comprobarse contra la topología real del servicio.
- Los códigos de registro nuevos usan sal aleatoria y scrypt. La migración elimina el campo de secreto heredado y las pruebas comprueban validación posterior.
- Se retiró el registro del identificador de colegio inválido crudo y del UID en los logs revisados de configuración.
- **Aclaración de permisos:** `canReadSchoolInternal` en `firestore.rules:502` exige sesión y superadministrador o administrador del colegio. La lectura de `config/registro` mediante este helper no está concedida a docentes ni alumnos. No se demuestra exposición de secretos a dichos roles.

## Compatibilidad y pendientes

1. **Media, compatibilidad de códigos de registro.** Antes se recortaban código recibido y secreto heredado; ahora se conserva el valor exacto. Los clientes antiguos que recortan no podrán utilizar claves nuevas con espacios en los extremos. Un secreto heredado que contenga esos espacios también cambia respecto de su interpretación anterior. Coordinar publicación de cliente/backend y no crear claves con espacios extremos hasta actualizar consumidores. No se comprobó que existan tales datos heredados y no se propone leerlos o imprimirlos.
2. **Media, origen de red pendiente.** `resolveClientIp` toma el último salto de X-Forwarded-For. Si representa un proxy compartido, el límite agregado puede agrupar personas no relacionadas. Las pruebas locales no verifican esa topología; no describir el resultado como protección comprobada por IP del usuario.
3. **Resuelto en revisión final:** `setSchoolRegistroConfig` invoca `consumeRequestBudget(request, "registro-config", 10)` después de autorizar al administrador. La lectura de configuración sigue limitada a administrador del colegio o superadministrador.
4. **Alta, pendiente anterior:** el precheck público de docentes distingue duplicados mediante `allowed`; ocultar solo el texto no impide enumeración. Cambiarlo requiere diseñar comprobación de duplicados durante aprobación administrativa y preservar solicitudes existentes. No se cambió este contrato en el endurecimiento revisado.
5. **Alta, pendiente anterior:** MFA de callables no prueba cobertura de accesos directos a Firestore/Storage. La activación de reglas exige señal compatible, pruebas de sesiones, inscripción y recuperación. Debe presentarse la propuesta concreta antes de aplicarla por su posible bloqueo de accesos legítimos.
6. **Limitación anterior:** los callables de telemetría de login no controlan por sí mismos los intentos directos contra Firebase Authentication.

El coordinador aportó `audit-auth-cloud-2026-10-14.json`, una inspección de metadatos: protección contra enumeración de correo activada; MFA nativo desactivado; enforcement de App Check para Auth/Firestore/Storage no activado; reglas Storage remotas diferentes de las locales. Esto no establece la política MFA personalizada actual ni demuestra el comportamiento del binario de funciones desplegado. Esta revisión no repitió esas consultas.

## Comprobación adicional del estado final

Se inspeccionaron `firebase.auth-tests.json`, `security-tests/authentication.test.cjs` y `test:auth`: el proyecto es sintético y el código falla antes de cualquier solicitud si el host no es loopback. Sus cuatro pruebas cubren registro/login con contraseña exacta, rechazo de credenciales, recuperación con código de un solo uso y verificación de correo. No prueban navegación Flutter ni políticas reales de abuso del proveedor.

El coordinador informa: Auth emulado **4/4**, suite Node completa **66/66**, Flutter **88 aprobadas y 1 omitida**, reglas **27 aprobadas y 0 fallidas**. Estos resultados son evidencia aportada por el coordinador; la ejecución independiente de esta revisión sigue siendo la suite de seguridad de 54 pruebas indicada arriba. Se comprobó también que el formulario de código de registro muestra mensajes controlados para excepciones del callable y un mensaje específico de límite de intentos.

Tras el parche autorizado, se comprobaron las versiones instaladas en ambos árboles: **proxy-addr 2.0.8**. Se ejecutó independientemente `node --test functions/test/proxy_security.test.js`: **2/2 aprobadas**, incluyendo rechazo de direcciones públicas ante la subred de confianza problemática y carga de los SDK. Los artefactos finales `audit-auth-dependencies-root-final-2026-10-14.json` y `audit-auth-dependencies-functions-final-2026-10-14.json` informan **0 críticas y 0 altas**; quedan respectivamente **9 y 8 moderadas**. No sumar los árboles como avisos únicos. El aviso crítico GHSA-jqcg-44mw-7w3h queda resuelto en las dependencias locales verificadas; no se demostró explotación previa ni se acredita el binario desplegado. El coordinador informa suite Node final **68/68** y Auth emulado **4/4** con un runner que evita registrar enlaces sintéticos de verificación. No se modificaron dependencias desde esta revisión.

### Comprobación puntual del código de registro de alumnos

El resultado de `validateSchoolRegistroAccess` permite navegar al formulario; no devuelve una autorización persistente verificable por reglas. El formulario escribe directamente un batch en alumnos e índices (`registro_equipo_screen.dart:812`). Sin embargo, **no se confirma creación anónima**: `firestore.rules:2295` limita la escritura de alumnos a `adminForSchool`; los índices globales (`:1435`, `:1454`) y estudiantes heredados (`:2780`) también exigen administración. Por tanto, omitir la pantalla no demuestra una escalada de permisos. El riesgo observado es funcional: conocer el código no concede a una persona sin sesión administrativa permisos para completar ese batch. Si se desea registro externo, hace falta un flujo servidor autorizado, acotado y probado antes de ampliar reglas; no se cambió ese contrato.

## Dictamen

Revisión de la última modificación: `createSchool` valida nombre, correos y campos opcionales de contacto/ubicación antes de crear registros o modificar Auth; los textos opcionales admiten `null` para preservar el contrato del cliente. Se verificó el runner Auth de Windows: comando estático, sin interpolación de entradas, ventana oculta, DEBUG vacío y filtrado de enlaces de verificación. No se leyeron credenciales ni documentos de usuarios. Ejecución independiente final de `node --test functions/test/security.test.js functions/test/proxy_security.test.js`: **57/57 aprobadas** (55 de seguridad y 2 del parche). El coordinador informa suite completa **69/69** y Auth emulado **4/4**. Estos recuentos sustituyen los anteriores para el estado final.

La política de transición de claves continúa pendiente de coordinar: conservar valores exactos, actualizar consumidores que recortan y evitar crear claves con espacios extremos mientras convivan clientes antiguos. No se migraron credenciales reales ni se cambió la política MFA/registro público.

**Revisión local favorable del endurecimiento acotado y del parche proxy-addr. El bloqueo específico por esa dependencia crítica queda levantado. Publicación general BLOQUEADA por los riesgos altos pendientes de MFA y enumeración del registro docente.** No se encontraron nuevos fallos altos en las validaciones y el presupuesto revisados. Permanecen también pendientes la topología de origen, compatibilidad de claves y definición del registro externo de alumnos. No se emite certificación integral ni se autoriza publicación de esas superficies. La autorización de publicación corresponde al usuario para versión y destino concretos después del informe consolidado. Cualquier modificación posterior de estas superficies exige revisar el cambio adicional.
