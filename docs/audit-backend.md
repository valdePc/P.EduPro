# Auditoría local de backend — 2026-10-05

**No es una certificación de seguridad ni de capacidad nacional.** Se inspeccionaron los 16 endpoints de `functions/index.js` y se corrigieron riesgos en código local. No se desplegó, no se consultaron expedientes reales, no se probaron credenciales de producción y no se verificaron IAM, configuración Auth, políticas de respaldo, cuotas, facturación o alertas del proyecto desplegado.

## Correcciones realizadas

- Se fija `maxInstances: 3` en el código para conservar el límite observado en las 16 funciones desplegadas al volver a desplegar. Este límite no sustituye cuotas por usuario ni acredita capacidad para escala nacional. La consulta remota de configuración, separada de esta revisión inicial, está resumida en el informe principal.
- Se impide reiniciar bloqueos con `operation: success` sin autenticación y autorización para el colegio/audiencia. Los contadores administrativos se separan por colegio para evitar que el éxito en uno desbloquee otro.
- Se eliminó la confianza en `fastly-client-ip`, `cf-connecting-ip`, `x-real-ip` y el primer componente de X-Forwarded-For. Se valida y normaliza una IP desde el último salto proporcionado por la plataforma; ver limitación de topología abajo.
- Los IDs de colegio aceptan únicamente letras ASCII, números, guion y guion bajo, hasta 128 caracteres. No se interpolan rutas arbitrarias en Admin SDK. `ipHash` exige SHA-256 hexadecimal válido.
- El acceso administrativo por correo requiere `email_verified == true`. Una membresía deshabilitada prevalece sobre el correo/UID de administrador, y el colegio debe existir. Un usuario interno deshabilitado no conserva acceso con claims antiguos de superadministrador.
- TOTP: verificación transaccional, cinco fallos bloquean 15 minutos, códigos usados no se repiten, inscripción pendiente caduca a los 10 minutos y se vincula a audiencia/colegio. Se exige autenticación de los últimos cinco minutos para inscribir/confirmar y se impide reemplazar un factor ya habilitado solo con una contraseña.
- La verificación TOTP guarda `lastVerifiedAuthTime`. Los endpoints privilegiados comprueban esta sesión, con validez máxima de 12 horas, **cuando** `app_config/security.twoFAEnabled == true`. Las operaciones para iniciar/configurar/verificar el factor conservan acceso autenticado para permitir el inicio de sesión.
- `getEduProTwoFactorStatus` devuelve `verified`, calculado en servidor. El cliente debe consultar este estado y usar los nombres EduPro existentes en el backend.
- Se añaden presupuestos transaccionales en `security_request_limits` a registro, prevalidación docente, telemetría de acceso, configuración/verificación TOTP, dispositivos y geocodificación. El identificador del contador se deriva del UID o IP y del propósito.
- Nuevas contraseñas administrativas/de registro requieren de 12 a 128 caracteres. Los códigos nuevos de registro tienen 16 caracteres generados con `crypto.randomInt`. Se preserva la comprobación y migración de claves antiguas para no invalidar accesos existentes automáticamente.
- `upsertSchoolAdmin` verifica las tres colecciones internas antes de modificar una contraseña; conserva errores tipados y no devuelve mensajes internos del proveedor ni registra objetos completos de error. `assignSchoolAdmin` realiza la asignación y actualización en un lote y exige colegio existente.
- Se eliminan correos y longitudes de contraseñas de los logs revisados. El listado de dispositivos pendientes y las entradas de texto tienen límites. El conteo docente usa agregación en lugar de descargar cada registro.
- Geocodificación: consulta/código de país acotados, URL remota fija, parámetros codificados y timeout de ocho segundos. El catálogo inicial de currículo acepta hasta 200 enlaces HTTPS sin credenciales y textos acotados.

## Inventario de endpoints

Todos son callable HTTPS v2; Firebase valida la estructura del protocolo y los tokens que se aportan. App Check depende de la variable de entorno `ENFORCE_APPCHECK`.

| Endpoint | Autorización revisada | Límite o consideración |
| --- | --- | --- |
| `getEduProTwoFactorStatus` | Usuario habilitado de la audiencia/colegio | Solo estado y etiqueta; no devuelve secreto enrolado |
| `startEduProTwoFactorEnrollment` | Audiencia + autenticación reciente | 5 solicitudes/15 min; devuelve el secreto nuevo solo al usuario; no sustituye factor existente |
| `confirmEduProTwoFactorEnrollment` | Audiencia + autenticación reciente + código | Inscripción ligada a colegio/audiencia, 10 min; bloqueo y protección contra repetición |
| `verifyEduProTwoFactorCode` | Audiencia + código cuando política exige MFA | 30 solicitudes/15 min y bloqueo a 5 fallos; consume el código en transacción |
| `checkEduProTrustedDevice` | Usuario de la audiencia/colegio | 10/min; ID aportado por el cliente, no prueba criptográfica de dispositivo |
| `upsertSchoolAdmin` | Superadministrador + MFA si política activa | Claves nuevas 12–128; identidad interna protegida antes de mutar Auth |
| `assignSchoolAdmin` | Superadministrador + MFA si política activa | Colegio existente; lote atómico de documentos |
| `createSchool` | Superadministrador + MFA si política activa | Código aleatorio; límites de documentos, nombre y cupos |
| `adminSchoolLoginRateLimit` | Público para precheck/failure; admin del colegio para success | 120/min; ámbito colegio + IP; telemetría no reemplaza seguridad de Auth |
| `validateSchoolRegistroAccess` | Código compartido del colegio | 30/min, comprobación scrypt y límites progresivos; no emite sesión Auth |
| `setSchoolRegistroConfig` | Admin del colegio o superadministrador + MFA si política activa | Clave nueva 12–128; no responde con hash/sal |
| `precheckTeacherSignup` | Público | 30/min; aún revela disponibilidad de una solicitud y no reserva cupo atómicamente |
| `schoolAccessIpPing` | Público para precheck/failure; miembro de audiencia/colegio para success | 120/min; no puede autorizar lectura de datos |
| `listSchoolAccessIps` | Superadministrador + MFA si política activa | Máximo 300 documentos leídos y hasta 200 devueltos |
| `unlockSchoolAccessIp` | Superadministrador + MFA si política activa | Hash validado; auditoría de UID que desbloquea |
| `searchSchoolPlaces` | Superadministrador + MFA si política activa | 20/min por UID; timeout remoto; falta cuota global específica del proveedor |

## Bloqueos y riesgos pendientes antes de producción

1. **Crítico: MFA integral pendiente.** Las reglas actuales de Firestore/Storage no vinculan todas las operaciones a `lastVerifiedAuthTime`. Una persona con una sesión Firebase de primer factor puede intentar acceso directo permitido por esas reglas, sin pasar por el diálogo MFA ni los callables. El endurecimiento de estos endpoints no elimina ese camino. Diseñar MFA nativo de Firebase/Identity Platform o un mecanismo de sesión backend verificable en todas las reglas y probarlo con emuladores antes de introducir expedientes reales.
2. **Crítico: registro por clave compartida.** `validateSchoolRegistroAccess` devuelve un resultado, no una identidad/grant Firebase con colegio, permisos y vencimiento. Este booleano no debe conceder acceso a datos escolares por sí solo. El flujo de registro necesita un permiso comprobable en servidor y reglas, o cuentas de personal aprobadas. Debe probarse de extremo a extremo al endurecer las reglas.
3. **App Check y protección de abuso requieren configuración real.** El código mantiene el default opcional previo; `functions/.env.example` solicita `ENFORCE_APPCHECK=true`. Verificar proveedores y rollout de clientes antes del despliegue; no se cambiaron servicios remotos. Las cuotas añadidas cuestan lecturas/escrituras de Firestore y no sustituyen cuotas del servicio, protección de borde ni protección de Firebase Auth. Los callables públicos de telemetría no pueden impedir que alguien llame directamente a Firebase Auth omitiéndolos.
4. **Topología IP por validar en staging.** El último salto evita usar un prefijo inyectado por el cliente pero, según proxies, Hosting o balanceadores, puede representar un proxy común. Los usuarios detrás de NAT/proxy comparten cuotas y bloqueos. Probar solicitudes con encabezados falsificados y redes distintas, confirmar el salto confiable por cada ingreso y ajustar únicamente después de obtener evidencia. No usar esta IP como identidad o como única frontera de seguridad.
5. **Recuperación y revocación.** No existe en este módulo un proceso de recuperación de factor con prueba de identidad, auditoría y revocación. El reemplazo inseguro ahora se rechaza: administrar la recuperación fuera del cliente hasta implementar el flujo. Verificar cierre de sesiones, revocación de tokens, política de contraseñas, proveedores habilitados, usuarios anónimos y tiempos de revocación efectivos en Firebase Auth. No se validaron sesiones reales.
6. **Dispositivo confiable no es un segundo factor.** El backend compara un ID entregado por el cliente; la huella se puede imitar. El superadministrador conserva el bypass existente de esta restricción. Usar únicamente como señal operativa hasta adoptar una credencial ligada al dispositivo.
7. **Secretos y retención.** El secreto TOTP es necesario para verificar códigos y permanece en Firestore, protegido por IAM y reglas que niegan clientes. Evaluar cifrado adicional con KMS y acceso mínimo de cuentas de servicio. Configurar TTL en `security_request_limits.expiresAt` y retención explícita de IPs/auditorías; `expiresAt` por sí solo no activa el borrado de Firestore. No se imprime ningún secreto en este informe.
8. **Enumeración y cupos.** La prevalidación docente limita frecuencia y usa mensajes genéricos, pero el resultado allowed aún permite inferir disponibilidad. No garantiza cupos ni unicidad frente a altas concurrentes. La creación docente debería convertirse en operación backend atómica con aprobación y autorización del colegio.
9. **Pagos y respaldos no implementados aquí.** No se encontró en estos endpoints un procesador de pagos, creación de cargos ni webhook firmado. No se verificó cumplimiento PCI ni seguridad de conciliación financiera. Tampoco hay aquí tareas de respaldo/restauración: confirmar configuración remota, RPO/RTO y restauración con datos sintéticos.
10. **Admin SDK omite reglas.** El módulo debe conservar verificación explícita de identidad/colegio en cada nueva función. Las pruebas de reglas por sí solas no validan estos endpoints. La capacidad nacional exige pruebas de carga, presupuestos, alertas, revisión independiente y auditoría de IAM; no se ha demostrado mediante esta revisión local.

## Verificación reproducible

`node --check functions/index.js`

`node --test functions/test/security.test.js`

Resultado local: **13 pruebas aprobadas**, con handlers reales cargados sobre dependencias simuladas y un almacén transaccional aislado. Incluyen traversal, IP inyectada, correo no verificado, separación de colegio, roles deshabilitados, reset anónimo, vector TOTP RFC 6238, bloqueo, repetición concurrente, inscripción expirada/otro colegio, sustitución de factor, política MFA y orden de autorización antes de cambiar una contraseña interna. Estas pruebas no demuestran conectividad, latencia ni configuración de Firebase desplegado.

Referencias oficiales: [Cabeceras de Cloud Run functions](https://docs.cloud.google.com/functions/docs/reference/headers), [App Check para Cloud Functions](https://firebase.google.com/docs/app-check/cloud-functions). La elección del último salto es una medida conservadora del código y requiere validar la topología concreta; la documentación no garantiza que siempre corresponda a una persona individual.
