# Error de autenticación al comprobar el segundo factor

Seguimiento del 6 de octubre: [App Check 403 y conflictos de VS Code](login-vscode-recovery-2026-10-06.md). La configuración del workspace ahora fija host y puerto también para F5 implícito.

## Diagnóstico confirmado

`valdeymse@gmail.com` existe en Firebase Authentication, está activo y tiene el correo verificado. Su documento `users/{uid}` mantiene `enabled: true` y `role: superadmin`. No se creó otra cuenta ni se cambiaron sus permisos u horarios.

Los registros de `getEduProTwoFactorStatus` mostraron 15 llamadas recientes con `verifications.auth: VALID` y `verifications.app: MISSING`, incluida la de `2026-10-05T22:57:43Z`. La función desplegada exige `ENFORCE_APPCHECK=true`. El SDK rechaza estas solicitudes con `unauthenticated / Unauthenticated` antes de ejecutar el controlador de 2FA. Estos registros no incluyen identificación del usuario y no prueban por sí solos quién originó cada llamada.

También se verificó que la ejecución local de Flutter tenía App Check desactivado. Esto explica el error de la captura, aunque Firebase Authentication acepte el inicio de sesión. La comprobación anterior de horarios era correcta, pero no probaba la llamada al segundo factor.

## Corrección aplicada

- Firebase App Check: se asoció al proveedor web reCAPTCHA Enterprise una clave pública SCORE ya existente, restringida a `edupro-8c4fd.web.app`. Se conservó el proveedor V3 anterior. No se cambiaron las restricciones de dominio de las claves.
- Se registró un token privado de desarrollo del navegador local en App Check y se verificó que Google emitiera un token de aplicación válido. El secreto permanece en el almacenamiento del SDK del navegador; no se escribió en código, configuración de lanzamiento, compilaciones ni informes.
- `AppCheckBootstrap` activa App Check por defecto en web, conserva las configuraciones V3 explícitas y renueva tokens automáticamente. Los valores predeterminados de las plataformas móviles se conservaron.
- Las llamadas 2FA comprueban App Check y la sesión antes de invocar la función. Los errores de configuración/atestación muestran mensajes controlados; no se reenvían automáticamente códigos TOTP.
- La pantalla de fondo solo puede cerrar una sesión ante una denegación explícita, estando visible y con el mismo UID. Un fallo transitorio de lectura no cierra otra sesión.
- `.vscode/launch.json` incorpora **EduPro Web (App Check)** y `.vscode/settings.json` fija el puerto `55595` y el host `localhost` para F5. El origen estable permite reutilizar el almacenamiento del navegador que conserva Flutter entre ejecuciones.

No se modificaron Auth, MFA, contraseñas, roles, IAM, reglas de datos ni la exigencia de App Check del servidor. No se desplegaron funciones, reglas ni Hosting.

## Validación

- 15 pruebas Flutter aprobadas entre la ejecución ordinaria y la variante `VALMICH_APP_CHECK=true`.
- Compilación web completada con `flutter build web --no-pub --no-wasm-dry-run`.
- Emisión real de un token App Check comprobada desde el navegador local.
- Prueba negativa real: la función respondió `Debes iniciar sesion.` al invocarse sin usuario autenticado. Esto confirma que App Check pasó y que el controlador conserva la exigencia de autenticación. El token de desarrollo temporal anterior se revocó tras verificar su sustituto.
- La misma prueba pasó después de cerrar Chrome y reiniciar completamente Flutter en el puerto `55595`, sin registrar otro token ni volver a configurar Firebase.
- El inicio de sesión interactivo del titular requiere que este introduzca sus credenciales; no se solicitó, leyó ni utilizó su contraseña.

## Uso local

En VS Code, seleccionar **EduPro Web (App Check)** y ejecutar con F5. Por terminal:

```powershell
flutter run -d chrome --web-port=55595 --web-hostname=localhost
```

Si se borra el almacenamiento del navegador, se usa otro perfil/puerto o se ejecuta `flutter clean`, puede ser necesario autorizar nuevamente el token de desarrollo. El script administrativo `scripts/configure-web-app-check.cjs --debug-port=PUERTO_CDP` valida primero el alcance; `--apply` registra el token de ese navegador concreto. Requiere la sesión administrativa de Firebase CLI y no acepta páginas remotas ni aplicaciones de otros proyectos. `PUERTO_CDP` es el puerto de depuración de Chrome, distinto del puerto web.

La autorización de desarrollo se puede revocar en Firebase Console > App Check > aplicación web > Manage debug tokens, identificada como `Local Flutter browser ...`. No distribuir el perfil/caché de desarrollo ni usar tokens debug en producción. El proveedor de producción requiere publicar la nueva compilación en el dominio autorizado; esta tarea no publicó Hosting.

La última consulta adicional a Cloud Logging devolvió cuota `429`; no se confundió con un fallo del login ni se insistió en consultas repetidas. La validación final utilizó la respuesta directa de la función desde el navegador.

Referencias: [enforcement de App Check en Functions](https://firebase.google.com/docs/app-check/cloud-functions), [proveedor debug web](https://firebase.google.com/docs/app-check/web/debug-provider), [configuración de lanzamiento de Dart Code](https://dartcode.org/docs/launch-configuration/).

## Incidencia nueva del 6 de octubre

Una ejecución desde otro origen local (`http://localhost:53699`) generó un token debug distinto y Firebase rechazó su intercambio con HTTP 403. No se registró el token divulgado en la captura. Se generó y registró un token **privado nuevo** para el navegador ya abierto, se guardó en el almacenamiento del SDK de ese origen y se recargó la aplicación. La API de App Check emitió un token válido. Una llamada real de prueba sin sesión llegó al controlador 2FA y recibió `Debes iniciar sesion.`, confirmando que la capa App Check dejó de bloquearla y que Auth sigue siendo obligatorio.

Se volvió a consultar Firebase Auth y los cuatro perfiles del titular: la cuenta permanece activa, con correo verificado, rol `superadmin` y sin límite de días ni horas. `EquipoEduPro/{uid}` no existe, por lo que la validación de horario no impone un horario adicional. Las credenciales y el 2FA siguen siendo necesarios. Si Flutter se ejecuta en otro puerto o perfil de Chrome, se genera otro token local y habrá que autorizarlo de forma privada; usar el perfil de VS Code y el puerto fijo evita cambiar de origen en las ejecuciones habituales.
