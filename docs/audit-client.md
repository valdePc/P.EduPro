# Auditoria del cliente Flutter — 4 y 5 de octubre de 2026

## Alcance y conclusion

Revision estatica de `lib/` y pruebas locales de validadores y pantalla de acceso. No se iniciaron sesiones con cuentas reales, no se consultaron expedientes escolares y no se probaron pagos reales desde esta revision del cliente. Los cambios preexistentes del espacio de trabajo se conservaron. Este documento no certifica seguridad ni cumplimiento legal y no autoriza un despliegue.

**No apto aun para incorporar expedientes nacionales de menores.** Se corrigieron riesgos concretos del cliente, pero el control MFA de todos los accesos directos a Firestore/Storage, la configuracion efectiva de servicios, la recuperacion de datos, las pruebas de permisos por colegio y los flujos completos de autenticacion requieren cierre antes del lanzamiento. Las reglas y el backend, no la navegacion Flutter, son la frontera de autorizacion.

## Correcciones locales realizadas

| Area | Hallazgo comprobado | Cambio e impacto |
| --- | --- | --- |
| MFA | `EduProTwoFactorService` contenia un bypass temporal constante activado que devolvia `true`. | Bypass eliminado. Se consulta siempre al servidor. Estado incompleto/malformado no habilita acceso. Solo se omite el desafio si el servidor dice `required: false` o confirma una sesion ya verificada. |
| Endpoints MFA/dispositivo | El cliente invocaba cinco nombres `ValMich` que no existen entre los exports locales de Functions. | Se usan `getEduProTwoFactorStatus`, `startEduProTwoFactorEnrollment`, `confirmEduProTwoFactorEnrollment`, `verifyEduProTwoFactorCode`, `checkEduProTrustedDevice`. La confirmacion exige las marcas `ok`/`enrolled` o `ok`/`verified` recibidas del servidor; codigo de seis digitos. Cliente y backend deben desplegarse coordinadamente. |
| Roles | Rol vacio, desconocido o error de carga podia normalizarse a `super_admin`; el fallback de perfil inexistente tambien lo hacia. | Resultado `denied`, permisos falsos y ruta de login. Se conserva solo el alias conocido `superadmin`. Perfiles `users`/`Users` deshabilitados no conceden fallback. La pantalla general tambien inicia con `denied`. |
| Sesiones restauradas y rutas | El acceso restaurado del equipo podia mostrar el panel sin volver a comprobar MFA. `/coleAdmin` no tenia gate de equipo. | `_TeamSessionGate` consulta el estado de MFA antes de renderizar las pantallas protegidas del equipo y oculta el contenido si cambia/cierra la sesion. Solo la ruta visible abre el desafio. `/coleAdmin` exige rol de superadministrador; el backend ya reserva sus mutaciones a ese rol. Antes de `createSchool` se revalida MFA, porque la reautenticacion de contrasena previa puede cambiar `auth_time`. |
| Fallos de login | Excepciones posteriores al primer factor dejaban Firebase Auth autenticado; el login alumno conservaba seleccion/listas anteriores. | Login general, docentes y admin escolar cierran sesion ante fallo posterior. El login alumno vacia asignaciones previas y cierra sesion si no termina autorizado. Se simplifican algunos errores publicos para no exponer detalles internos. |
| Enlaces de archivos | Varias pantallas pasaban cualquier esquema de Firestore a `launchUrl`. | Nuevo `safeExternalDocumentUri`: exige HTTPS con host, sin credenciales, controles ni barras inversas. Aplicado a ocho pantallas de documentos, chat, material y calendario. Enlaces HTTP antiguos dejan de abrirse y deben migrarse. HTTPS no garantiza que el destino sea confiable. |
| Enlace de acceso | Parser con comparacion de esquema imposible (`toLowerCase()` frente a `ValMichapp`) y segmentos adicionales aceptados. | Parser probado para enlaces web/hash, relativos, `eduproapp` y `valmichapp`; modulo conocido y un solo ID de colegio, sin separadores codificados ni caracteres de control. La direccion solo identifica el colegio; no es una credencial. |
| Informacion sensible | Logs de correo/UID, datos de asistencia y URL con token de descarga; diagnosticos visibles en compilaciones release. | Se eliminan logs de identidad en guardado de ayuda y URL completas en errores de imagen. Logs de asistencia/chat/registro docente/configuracion solo en debug; la tarjeta de diagnostico de ayuda solo en debug. No equivale a una limpieza exhaustiva de todos los errores/pantallas. |
| Responsive/accesibilidad inicial | Formulario de acceso sin scroll para pantalla pequena; campo sin etiqueta visible permanente. | Scroll, etiqueta, teclado URL y envio por teclado. La revision principal corrigio adicionalmente el footer que el test encontro desbordado a 320 px. |

## Riesgos que siguen abiertos

### 1. Autorizacion, MFA y aislamiento

- **Critico: MFA integral pendiente.** Las reglas revisadas no vinculan todos los accesos directos a Firestore/Storage al TOTP validado. Un cliente modificado puede omitir los dialogos y usar un ID token del primer factor. El gate agregado protege la navegacion normal; no corrige esa via de acceso directo. Ver tambien `audit-backend.md`.
- La politica `twoFAEnabled` debe comprobarse en el entorno real. Retirar el bypass no activa automaticamente una politica ausente/deshabilitada. El MFA personalizado requiere una estrategia coherente para sesiones, recuperacion, revocacion y todos los almacenes; no se certifica equivalente a MFA nativo.
- El gate comprueba el estado al entrar, no continuamente durante toda la vida de una pantalla. Los cambios de politica, la revocacion y la expiracion de la verificacion deben imponerse en el servidor/reglas. El listener cliente detecta cambio de UID/cierre; no demuestra revocacion completa de tokens.
- `currentTeamRole` prioriza `EquipoEduPro` cuando existe. La correspondencia entre ese perfil, `users`/`Users`, claims y estado deshabilitado debe validarse de forma consistente en servidor. No se modifico el modelo de compatibilidad de perfiles existentes.
- El horario en `EquipoEduProAccess.isAllowedNow` depende del reloj local. No puede usarse como restriccion autoritativa sin un control de servidor.
- `EduProTrustedDeviceService` deriva un SHA-256 de metadatos de plataforma/navegador. No es un secreto ni una prueba criptografica de posesion de dispositivo; puede clonarse o cambiar al actualizarlo. El login general excluye al superadministrador de esa comprobacion.
- Existen rutas de docentes que construyen pantallas con un objeto `Escuela`, ademas del flujo de login. Todos sus datos deben estar protegidos por reglas y membresia real. Cambiar `schoolId`, enlaces o argumentos no debe conceder acceso.
- Persisten fallbacks de identificadores por mayusculas/minusculas y, en pantallas antiguas, por nombre del colegio. `normalizeSchoolIdFromEscuela` usa el ID real, pero no se ha certificado una identidad canonica unica en todos los flujos. Se necesitan pruebas de dos colegios con nombres similares, asignaciones cruzadas y cambios de colegio.
- No se usa actualmente `SessionService`/`AppRouter` desde `main`; estos archivos legacy basan rutas en preferencias o construyen paneles directamente. No reincorporarlos como controles de seguridad.

### 2. App Check, sesiones y datos locales

- `lib/services/app_check_bootstrap.dart` mantiene `VALMICH_APP_CHECK=false` y `VALMICH_APP_CHECK_STRICT=false` por defecto. Se requiere configurar proveedor/clave publica de sitio y enforcement de cada servicio con pruebas; esta auditoria no lo activo a ciegas.
- No hay configuracion explicita de persistencia de Firestore ni limpieza de caches por cambio/cierre de sesion. No se puede asegurar ausencia de expedientes en disco o memoria usando solo el `signOut` observado. Verificar politica de dispositivos compartidos y pruebas offline de segundo usuario; el comportamiento por plataforma debe comprobarse.
- `EscuelaRepository.escuelas` es un almacen global en memoria. No se encontro una estrategia central de vaciado de todos los repositorios, listas y suscripciones al cerrar sesion. `SharedPreferences` no debe contener secretos ni actuar como autorizacion; las preferencias revisadas son principalmente visuales/funcionales.
- La app guarda/usa URLs de descarga de Storage. Esos enlaces pueden incluir tokens compartibles. Evitar logs, enlaces publicos permanentes para expedientes y exposicion a terceros; probar revocacion y descarga con usuario no autorizado.

### 3. API, inyeccion y datos sensibles

- No se encontro SQL construido por el cliente; usa Firestore y callables. Esto no prueba que todo backend sea inmune a inyeccion. Validacion de campos/IDs y autorizacion deben mantenerse en servidor.
- No se encontro un uso directo de `innerHTML`, `eval` o WebView con JavaScript en los archivos revisados. Flutter `Text` es el patron predominante. Se corrigio el lanzamiento de esquemas no permitidos, pero no se realizo pentest XSS del sitio desplegado, archivos subidos o cabeceras web.
- Siguen apareciendo objetos de error/paths en mensajes de algunas pantallas y diagnosticos de debug. No usar datos reales en builds debug; pendiente un sistema central de errores con redaccion y codigo de referencia.
- `Image.network`/`NetworkImage` aceptan URLs presentes en datos de perfiles/chat/branding. El origen puede recibir IP y solicitudes de usuarios; falta definir origenes permitidos y servir imagenes sensibles mediante almacenamiento controlado.
- **Endpoints funcionales ausentes:** `lib/screens/coleAdmin.dart` invoca `createSchoolAdminAccount` y `setSchoolAdminStatus`, no exportados por `functions/index.js` local. No se sustituyeron por mutaciones inventadas. Verificar si existen funciones desplegadas adicionales; implementar contratos autorizados antes de depender de esas acciones.
- El backend endurecido exige claves nuevas de 12 a 128 caracteres, pero `coleAdmin.dart` conserva validacion minima de 6 y un generador temporal de 10. Ajustar UX y contratos conjuntamente; el servidor debe seguir rechazando claves debiles.
- `admin_general.dart` reautentica con contrasena antes de crear un colegio. Se agrego una sola consulta `ensureVerified` inmediatamente antes de `createSchool`, despues de esa reautenticacion, con comprobacion de widget montado y mismo UID. Si la politica exige un nuevo desafio o el usuario cancela, no se envia la mutacion. Falta probar el recorrido completo con Auth real/emulado; no se implementaron bucles de desafio.

### 4. Pagos

- Las pantallas observadas registran reportes manuales de pago, referencias y aprobaciones. No se encontro captura directa de PAN/CVV ni un checkout real de Stripe/PayPal. No se puede declarar comprobada una integracion de cobro o cumplimiento PCI a partir de estos nombres.
- `A_pagos.dart` crea un documento `payments` con `status: submitted`; `pagos_edupro_screen.dart` cambia estado y vencimiento desde el cliente mediante batch. La aprobacion necesita una operacion backend con permisos financieros, auditoria e idempotencia y una fuente verificable del cobro.
- La lectura previa de fecha y batch posterior no comprueban en una transaccion que el pago siga pendiente. Un reintento o aprobaciones concurrentes pueden dar resultados incorrectos. No se ejecutaron cargos/reembolsos ni se cambio la contabilidad.

### 5. Escala, carga y disponibilidad

- `colegios.dart` y `admin_general.dart` escuchan la coleccion de colegios completa. `estudiantes.dart` carga colecciones completas; el detalle general hace varias lecturas completas seriales. Se requieren paginacion, indices, agregaciones y presupuestos medidos para escala nacional.
- El backfill automatico de metadata publica de `admin_general.dart` agrega todos los colegios pendientes a un solo batch y oculta errores. No se ha probado su comportamiento con miles de colegios ni limites del servicio.
- `red_escolar_screen.dart` geocodifica direcciones por HTTP directamente a Nominatim, sin timeout explicito, y resuelve multiples escuelas con `Future.wait`. Revisar cuotas/terminos del proveedor, concurrencia, cache, privacidad y reemplazo por un endpoint controlado. El timeout del callable backend no corrige esta llamada directa.
- Los chats revisados usan limites de 80 mensajes y la verificacion de pagos limita 50; esto es parcial y no demuestra paginacion completa del historial.
- No se midieron tiempo inicial, latencia p50/p95, memoria ni costo por colegio. La compilacion web correcta no sustituye una prueba de carga con datos sinteticos representativos.

### 6. Errores, accesibilidad, analytics y legal

- No se encontro instalacion central de Crashlytics/Sentry ni handlers globales de errores Flutter/async. Hay numerosos `catch` silenciosos y mensajes tecnicos locales. Falta captura sin PII, alertas, responsables y pruebas de fallos de red/permiso.
- No se encontro instrumentacion de analytics de producto en los archivos revisados. Si se incorpora, definir eventos minimos sin nombres, correos, documentos, notas, salud o mensajes de menores; no confundir logs de acceso con analytics anonimo.
- Se probo solo un formulario pequeno. Quedan teclado, lector de pantalla, foco, escalado de texto, contraste, tablet, orientacion y pantallas principales. No se declara conformidad de accesibilidad.
- `app_info_menu.dart` contiene textos genericos de privacidad/terminos, soporte de ejemplo y una solicitud de borrado por correo. No prueban responsable legal identificado, aviso aprobado, flujo real de derechos, retencion, consentimiento/representacion de menores, contratos con colegios o transferencias internacionales. La revision juridica dominicana y operativa corresponde al informe principal; no se emitio dictamen legal desde el codigo.
- **Backups:** el coordinador de la auditoria consulto metadata operativa y reporto PITR deshabilitado, proteccion contra eliminacion deshabilitada y ausencia de backups. Esta revision del cliente no inspecciono expedientes ni restauro respaldos. Tratar la recuperacion y un ensayo de restauracion como bloqueo de lanzamiento; ver evidencia en el informe principal.

## Verificacion local y limites de evidencia

- `test/client_security_test.dart`: tres pruebas, roles desconocidos sin privilegios; rechazo de esquemas peligrosos/HTTP/credenciales en adjuntos; enlaces de colegio con IDs aislados y rechazo de rutas ambiguas. El log `audit-flutter-tests.log` registra las tres como aprobadas.
- `test/widget_test.dart`: formulario real de acceso a 320 × 420 y rechazo de enlace invalido, sin inicializar Firebase ni enviar solicitudes. Detecto inicialmente un overflow horizontal; tras el ajuste del footer por el coordinador, el mismo log registra **4 pruebas totales aprobadas**.
- `audit-flutter-build.log` registra compilacion web completada. `audit-flutter-analyze-final.log` conserva **1179 incidencias** y errores, incluidos archivos legacy con sintaxis ajena a Dart y referencias antiguas. Un build del grafo usado por `main` no implica que todo `lib/` pase el analizador.
- El coordinador repitio las pruebas y la compilacion despues de los ajustes finales del gate `/coleAdmin`, los defaults `denied` y la revalidacion MFA previa a `createSchool`: 4 pruebas aprobadas y build web correcto. El analisis completo sigue registrando las incidencias indicadas; compilar `main` no valida los archivos fuera de su grafo.
- No hay pruebas end-to-end de Google, correo/contrasena, recuperacion, MFA, deshabilitacion/revocacion, cambio de colegio, permisos alumno/tutor ni pagos. No afirmar «Auth funciona» o «acceso unico garantizado» hasta probar esos recorridos con cuentas sinteticas y reglas efectivas.

## Archivos modificados por esta revision del cliente

Cambios sobre archivos que ya estaban modificados se aplicaron de manera acotada; no se reemplazo el trabajo anterior.

- Seguridad y sesion: `lib/main.dart`, `lib/utils/equipo_edupro_access.dart`, `lib/services/edupro_two_factor_service.dart`, `lib/services/edupro_trusted_device_service.dart`, `lib/screens/admin_general.dart`.
- Login y entrada: `lib/screens/login_general.dart`, `lib/docentes/screens/docentes.dart`, `lib/admin_escolar/screens/admin_login_escolar.dart`, `lib/alumnos/screens/alumnos.dart`, `lib/screens/acceso_enlace_screen.dart`.
- Validadores nuevos: `lib/utils/safe_external_uri.dart`, `lib/utils/school_access_link.dart`.
- Enlaces y logs: `lib/alumnos/tabs/documentos_tab.dart`, `lib/docentes/screens/D_chat_thread_screen.dart`, `lib/docentes/screens/material_de_apoyo_docente.dart`, `lib/admin_escolar/screens/chat_admin_docentes_screen.dart`, `lib/alumnos/screens/chat_grado_screen.dart`, `lib/docentes/screens/curriculo.dart`, `lib/docentes/screens/calendario.dart`, `lib/admin_escolar/screens/A_calendarioacademico.dart`, `lib/alumnos/tabs/asistencia_tab.dart`, `lib/admin_escolar/screens/A_registro.dart`, `lib/docentes/screens/crearcuentadocentes.dart`, `lib/widgets/app_info_menu.dart`.
- Pruebas/informe: `test/client_security_test.dart`, `test/widget_test.dart`, `docs/audit-client.md`.

No se modificaron desde esta revision `firebase_options.dart`, dependencias, reglas de bases de datos, Functions, configuracion de hosting, claves o ajustes del proyecto cloud. Esas areas pertenecen a las revisiones paralelas y al informe principal.
