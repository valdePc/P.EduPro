# Preparación para producción de EduPro

Fecha de evaluación: 9 de octubre de 2026, zona horaria America/La_Paz.

**Estimación: alrededor del 60 %, con un intervalo orientativo de 55–65 %.**
Se evalúa la preparación para operar con datos reales de colegios y menores a
escala nacional, no el porcentaje de pantallas diseñadas. Hay bloqueos que
impiden aprobar ese lanzamiento aunque muchos módulos compilen y funcionen.
La cifra es un juicio técnico aproximado, no una medida de cobertura, una
certificación ni una probabilidad de seguridad. No significa que se haya
terminado el 60 % del trabajo o que el 40 % restante tenga un esfuerzo uniforme.

## Alcance y metodología

Se inventariaron 198 archivos Dart de `lib/` (77.383 líneas), los módulos de
equipo, administración escolar, docentes y alumnos, las funciones, reglas,
configuración, sitio público, dependencias y pruebas. Se ejecutó el analizador
de todo Flutter y se revisaron flujos y contratos representativos de cada área,
incluyendo consultas, permisos, facturación, configuraciones, adjuntos y rutas.
Esto no equivale a haber ejecutado cada interacción de esas 77.383 líneas.

Las comprobaciones remotas leyeron configuración de Firebase/Google Cloud y
páginas públicas. No se descargaron expedientes, archivos privados ni usuarios
para este diagnóstico; no se alteraron permisos, cuentas, backups o servicios.
No se hicieron cargos ni pruebas de ataque en producción. Las pruebas recientes
del catálogo sí habían comprobado previamente siete entradas derivadas de
colegios, sin expedientes personales.

Para ponderar el juicio se usan funciones principales (20 %), seguridad y
privacidad (25 %), pruebas y calidad (15 %), rendimiento (15 %), operación y
recuperación (15 %) y publicación/legal (10 %). Las valoraciones aproximadas
80/55/65/60/25/50 respectivamente producen 57,25 puntos, redondeados a unos 60.
No se compensan bloqueos críticos de seguridad o recuperación con puntos de
diseño: la autorización de lanzamiento exige cerrarlos por separado.

| Área | Evaluación aproximada | Motivo |
| --- | --- | --- |
| Funciones principales | Avanzada, ~80 % | Hay módulos reales, alta de colegios, MFA del propietario, matriz del equipo y catálogo; persisten contratos ausentes y configuración sin efecto global. No se certificaron todos los procesos académicos. |
| Seguridad y privacidad | Parcial, ~55 % | Se endurecieron reglas y funciones; faltan MFA en accesos directos, actualización de reglas de archivos, mínimo privilegio interno y enforcement coordinado de App Check. |
| Pruebas y calidad | Parcial, ~65 % | Build web y pruebas recientes pasan; no hay cobertura E2E visible de los procesos completos, y siguen 930 incidencias del analizador. |
| Rendimiento y escala | Parcial, ~60 % | Catálogo paginado y resúmenes agregados; otros módulos descargan colecciones completas. No hay prueba de carga nacional ni medición real de arranque. |
| Operación y recuperación | Baja, ~25 % | Funciones activas y datos replicados, pero sin backups programados, PITR, protección de borrado ni políticas de alerta verificadas. |
| Publicación y legal | Parcial, ~50 % | Páginas públicas preparadas localmente; el Hosting actual no las sirve y falta revisión jurídica/operativa. |

## Comprobaciones actuales

- Análisis completo Flutter: **0 errores, 130 advertencias y 800 avisos**. El
  comando devuelve código 1 por esas incidencias; no se presenta como un análisis
  completamente limpio.
- Validación reciente, con el mismo código de aplicación: **86 pruebas Flutter,
  58 de servidor y 27 de reglas aprobadas**; una prueba Flutter se omite según
  la configuración de App Check. Compilación web correcta. Esta revisión no
  volvió a repetir esas suites porque no cambió la aplicación.
- Las 28 funciones observadas están activas. Firestore publicado coincide con
  las reglas locales y no conserva usos de `changedKeys()`.
- El catálogo del equipo ya está paginado, proyecta campos por rol, utiliza
  métricas agregadas y rechaza accesos sin sesión en los endpoints comprobados.
- `npm audit`: raíz, ocho paquetes con avisos moderados y uno crítico; Functions
  **sin dependencias de desarrollo**, nueve moderados y uno crítico. No se suman
  ambas listas como vulnerabilidades independientes: hay dependencias y avisos
  compartidos.
- `proxy-addr` instalado es **2.0.7** en ambos árboles. El mantenedor identifica
  esas versiones como afectadas por GHSA-jqcg-44mw-7w3h; la versión corregida es
  2.0.8. La explotación depende de la configuración de proxies de confianza: no
  se demostró explotación en este proyecto. Se requiere actualización revisada
  y pruebas, sin recurrir indiscriminadamente a `npm audit fix --force`.
  [Aviso del mantenedor](https://github.com/jshttp/proxy-addr/security/advisories/GHSA-jqcg-44mw-7w3h).
- El escaneo heurístico local/histórico inspeccionó 993 entradas, incluidas 589
  históricas. Las coincidencias de credenciales en URL se verificaron como
  valores ficticios de pruebas negativas. No se confirmó una clave privada o
  token secreto en los patrones revisados. El script todavía marca dos de esos
  archivos de pruebas como `review-required`; por tanto no se afirma que la
  ejecución del escáner haya pasado sin observaciones ni que detecte todo secreto.
- El chequeo local del sitio público pasa: documentos, enlaces, metadatos,
  sitemap, rutas y contraste de las combinaciones comprobadas.

## Bloqueos antes de admitir expedientes reales a escala nacional

### 1. Respaldos y restauración — crítico, confirmado remotamente

Firestore `(default)` sigue con `POINT_IN_TIME_RECOVERY_DISABLED`,
`DELETE_PROTECTION_DISABLED`, retención de versiones de 3.600 segundos y **cero
calendarios de respaldo**, comprobados nuevamente en esta revisión. Esto no
descarta exportaciones externas que no se hayan mostrado, pero no acredita
recuperación. La base está en `nam5`.

Storage está en `US-CENTRAL1`, con versionado desactivado y borrado reversible
de siete días; eso no constituye un plan probado de recuperación de todo el
sistema. Faltan cobertura de archivos, identidades/configuración, retención,
responsables, tiempo objetivo de recuperación y una restauración ensayada en
un entorno separado. Activar backups por sí solo no demuestra que se puedan
restaurar y usar los datos correctamente.

**Criterio de cierre:** calendario y retención definidos, protección contra
borrado donde corresponda, recuperación de Firestore y archivos probada con
datos ficticios y evidencia del tiempo y de la integridad recuperados.
[Recuperación de Firestore](https://firebase.google.com/docs/firestore/disaster-recovery).

### 2. Protección de los datos, MFA y App Check — crítico

El TOTP personalizado funciona en el acceso probado del propietario y se exige
en las funciones según la política configurada. Sin embargo, las reglas de
Firestore y Storage no exigen ese estado de segundo factor para los accesos
directos. Por ejemplo, `isSuperAdmin()` valida la identidad y revocación, sin
comprobar la sesión TOTP. Un diálogo de Flutter no controla un cliente modificado.
Auth informa MFA nativo deshabilitado: esto describe el mecanismo nativo y **no**
significa que el TOTP personalizado haya dejado de funcionar.

App Check figura `UNENFORCED` en Firestore, Storage y Authentication. Las
funciones tienen `ENFORCE_APPCHECK=true` y las llamadas comprobadas conservan
protección; es una situación diferente de exigirlo en los tres servicios.
El cliente lo activa por defecto en web, pero en plataformas móviles requiere
configuración de compilación/proveedores. La activación debe coordinarse con
clientes legítimos probados para evitar dejarlos sin acceso.

Las reglas publicadas de Storage datan del 7 de abril de 2026 y **difieren de
las reglas locales probadas**. La revisión del texto publicado confirmó permiso
de lectura y escritura de `chat_uploads` mediante el helper de acceso al
colegio; no contiene la denegación explícita local de actualización/borrado.
No se ejecutó una sobrescritura real para comprobarlo. Tanto el acceso general
al colegio como el local deben revisarse para exigir pertenencia a la
conversación concreta, en lugar de permitir leer cualquier adjunto escolar.

Las reglas actuales de alumnos permiten `list` a `isTeacherForSchool(schoolId)`
sin limitar allí el curso o asignación (`firestore.rules`, alrededor de 2290).
El filtro por grado de la pantalla docente no impone esa restricción al cliente
modificado. Debe decidirse el mínimo dato que cada profesor necesita y adaptar
consulta, documento y reglas, separando datos personales y de salud si procede.

Las tres claves cliente tienen restricciones por API, pero ninguna lista de
referrers, aplicaciones Android o bundle IDs. Son identificadores públicos;
esto no prueba filtración de una contraseña. Falta revisar y limitar sus usos
por plataforma de manera compatible con Auth y App Check. IAM tiene tres
miembros con `roles/editor` y uno con `roles/owner`; no hay bindings públicos en
el proyecto. Deben justificarse esos privilegios y revisar cuentas de servicio
y permisos de recursos individuales. La ausencia de un binding público global
no demuestra por sí sola privacidad de cada objeto o servicio.

Existe todavía `DISABLE_TWO_FACTOR=true` en el entorno de funciones. El código
actual revisado no lee esa variable; no se la presenta como un bypass efectivo.
Conviene retirarla o documentar su obsolescencia para evitar ambigüedad futura.

**Criterio de cierre:** segundo factor y revocación exigidos en cada frontera
relevante; reglas de archivos publicadas y probadas; matriz negativa y positiva
por colegio, alumno, clase y conversación; App Check validado en clientes
release; IAM y claves revisados. No basta con que el superadministrador logre
entrar correctamente.
[Checklist de seguridad de Firebase](https://firebase.google.com/support/guides/security-checklist).

### 3. Pruebas completas y publicación controlada — alto

No existen `integration_test/` ni `.github/workflows/` en este repositorio.
Podría haber automatización externa, pero no se aportó evidencia. Las suites
actuales cubren especialmente la matriz del equipo, reglas y correcciones del
administrador general; no sustituyen la aceptación de todos los procesos
académicos y accesos reales.

Falta un entorno separado con datos ficticios y pruebas de administrador
escolar, docente, alumno y tutor: alta/aprobación, contraseña y Google, factor
perdido, cuenta suspendida, cambio de cuenta/colegio, asistencia, tareas,
notas, promoción/cierre de período, documentos y chat. Deben incluir errores
de conexión, duplicados, reintentos y revocación, con resultados esperados.
Hay compatibilidad legacy (`users`/`Users`, índices docentes/alumnos y colecciones
de notas) que necesita una fuente canónica y migraciones verificadas.

Falta automatizar análisis, pruebas, dependencias, escaneo de secretos y build,
con versión de release, revisión, despliegue y rollback. Un build correcto no
garantiza que el servicio completo funcione con roles y datos reales.

### 4. Monitoreo y respuesta a incidentes — alto, parcialmente confirmado

La consulta actual de Cloud Monitoring devuelve **cero políticas de alerta**.
No se encontró integración cliente de Crashlytics/Sentry/Performance ni un
manejador global de errores Flutter en `main.dart`. Existen logs y auditorías
de algunas operaciones, pero no se acreditó detección y aviso al responsable.

Faltan alertas de errores, latencia, disponibilidad, abuso, fallos de disparadores
y gasto; retención y filtrado de datos sensibles; responsables y procedimiento
de respuesta. La consulta de presupuestos falló con HTTP 500: **su existencia
no quedó verificada**, y no se afirma que haya cero presupuestos. Debe revisarse
también cualquier plataforma externa de monitoreo si existe.

**Criterio de cierre:** simular una incidencia en pruebas, recibir el aviso,
investigarla sin datos personales en logs y ejecutar recuperación/rollback.

### 5. Privacidad y responsabilidad legal — alto

Existen documentos públicos locales y un contacto de privacidad; sus textos
reconocen que EduPro es un nombre de servicio y no una sociedad registrada.
Falta confirmar la identidad exacta del responsable y revisar con asesoría
dominicana los acuerdos con colegios, menores y tutores, datos de salud,
finalidades, conservación, acceso/corrección/borrado, proveedores y alojamiento
fuera del país. No se exige aquí constituir una sociedad como requisito técnico:
la identidad y obligaciones aplicables deben determinarse correctamente.

No se encontró un proceso completo y probado de atención de derechos,
retención/borrado y cierre de cuentas con documentos y archivos relacionados.
La revisión del código no acredita cumplimiento legal.
[Ley 172-13, fuente oficial](https://proconsumidor.gob.do/transparencia/files/Ley_172_13_Proteccion_Datos_Caracter_Personal.pdf).

## Funciones incompletas o inconsistentes

| Hallazgo actual | Evidencia | Acción para cerrarlo |
| --- | --- | --- |
| Crear administradores adicionales y cambiar su estado depende de endpoints ausentes | `coleAdmin.dart:191` y `:208` invocan `createSchoolAdminAccount` y `setSchoolAdminStatus`; no aparecen en exports ni en las 28 funciones publicadas. Hay botones que llaman ambos helpers. | Implementar el contrato autorizado, auditado y probado o retirar/unificar esas acciones. La asignación principal usa otro endpoint y sí es un flujo distinto. |
| Pagos y Facturación mezcla configuración local con datos financieros | `pagos_facturacion.dart:153` guarda métodos, impuestos, roles y avisos en SharedPreferences. `:203` usa `EscuelaRepository.escuelas` y `:206` fija importe 50 para ingresos estimados; ese repositorio es una lista en memoria. | Una única fuente de datos y cálculo financiero, configuración de servidor y semántica clara entre preferencia personal y ajuste global. Elegir cobro manual o integración real y probar conciliación. |
| Facturación actual permite consultar, sin ofrecer una aprobación completa | `/facturacion` abre `TeamBillingScreen`, cuyo diálogo lista hasta 50 pagos. Los antiguos `FacturacionScreen` y `PagosEduProScreen` contienen escrituras, pero no se encontró navegación activa hacia ellas. | Unificar el flujo de revisión autorizado en servidor, con auditoría, idempotencia y pruebas de renovación; no anunciar checkout/webhooks por listar PayPal o Stripe. |
| El código viejo de revisión financiera tampoco coincide plenamente con reglas | `facturacion.dart:934` escribe `reviewedByUid`/`rejectedAt`; las reglas de payments permiten otros campos y exigen `verifiedByUid`/`verifiedAt`. | Corregir o retirar ese código al unificar. No se presenta como un fallo de un botón actualmente visible porque no está en la ruta activa. |
| Marca, preferencias y plantillas se guardan localmente | Branding y preferencias usan SharedPreferences; el guardado no demuestra aplicación a otros usuarios o conexión de plantillas a un sistema de envío. | Decidir qué es personal/global, conectar la configuración aplicable y ocultar opciones que todavía no producen su efecto anunciado. |
| Algunas rutas y módulos conservan pantallas provisionales | Abrir `/docentes` sin Escuela conduce a `DocentesPlaceholder` (`main.dart:312`). Hay archivos de tabs provisionales; algunos fallbacks no tienen llamadas activas. | Reparar la resolución de rutas y completar u ocultar lo que sea alcanzable; eliminar duplicados muertos después de confirmar referencias. No se califican todos los archivos con la palabra placeholder como funciones rotas. |
| Notificaciones push requieren validación de extremo a extremo | Docentes solicita permiso/token y suscripción a topics; no se encontró worker de Firebase Messaging en `web/` ni implementación visible de entrega push del servidor. | Probar entrega y apertura de avisos por plataforma, revocación de tokens y denegación de permisos. Si el lanzamiento solo promete avisos dentro de la app, delimitarlo explícitamente. |

## Rendimiento, experiencia y publicación

El catálogo administrativo y su ficha ya reducen lecturas mediante páginas,
proyecciones, caché y agregados. Esa mejora **no** se aplica todavía a todo el
programa: `A_reporteyanalisis.dart:102` carga nueve colecciones completas y luego
colecciones por alumno/tarea; `A_MonitoreoDocentes.dart` tiene lecturas completas
de docentes, alumnos, planes y otras colecciones; `colocar_calificaciones.dart:350`
descarga alumnos sin página en ese punto. Hay que medir y limitar donde el
volumen lo requiera, preservando los permisos y evitando cálculos en cada fila.

`build/web/main.dart.js` mide 5.164.933 bytes sin comprimir. No se ha medido
Lighthouse/Core Web Vitals, arranque o latencias p50/p95 en dispositivos/redes
representativos de RD, ni carga simultánea o coste por colegio/sesión. No se
afirma que ese tamaño, por sí solo, haga inviable la app. Faltan objetivos de
tiempo, escenarios con volumen sintético, índices y límites de concurrencia
verificados; no deben ejecutarse pruebas de carga invasivas en producción.

Los mapas usan `tile.openstreetmap.org` y el buscador del servidor usa Nominatim
público. Este último tiene un límite global por aplicación de una solicitud por
segundo; la cuota individual actual de 20 solicitudes no lo impone. Para uso
nacional hace falta un proveedor y estrategia de disponibilidad/cuotas/caché
adecuados. Las teselas públicas tampoco garantizan disponibilidad por SLA.
[Política Nominatim](https://operations.osmfoundation.org/policies/nominatim/),
[política de teselas](https://operations.osmfoundation.org/policies/tiles/).

La adaptación móvil y el contraste tienen pruebas en pantallas concretas,
especialmente accesos y administrador general; falta comprobar todas las áreas
escolares con teclado, lector de pantalla, zoom, texto grande, móviles pequeños
y navegadores reales. No se acredita WCAG con esos tests parciales.

**Hosting publicado:** las solicitudes actuales a `/acerca.html`,
`/aviso-legal.html`, `/privacidad.html`, `/cookies.html`, `/sitemap.xml`,
`/robots.txt` y `/404.html` devuelven HTTP 200 con el shell de Flutter, no los
archivos locales esperados. No traen CSP; sí HSTS del servicio. Las páginas y
cabeceras preparadas no están publicadas en ese Hosting como se espera.
Se requiere publicar una release revisada y comprobar contenido, login/OAuth,
404 real, HTTPS, cabeceras y enlaces desde fuera del entorno localhost.

El dominio propio no es imprescindible: el dominio de Firebase puede servir
una producción válida. La ficha de Google sigue pendiente de referencia exacta,
horario y verificación; es un objetivo comercial, no un bloqueo de seguridad.
No hay ID GA4 y no se carga analítica opcional. Si se necesita, definir eventos
mínimos y consentimiento, sin enviar información de menores. La ausencia de
Google Analytics no es, por sí sola, un defecto de preparación técnica.

Si se publican Android/iOS, hay que probar esas compilaciones release con sus
proveedores de App Check, configuración OAuth/push y firma. En este espacio de
trabajo no existe `android/key.properties`; Gradle informa falta de firma release.
Solo la compilación web está acreditada por estas verificaciones. Este requisito
móvil no bloquea un lanzamiento exclusivamente web.

## Orden de cierre y condición de aprobación

1. Dependencia crítica y fronteras de datos: MFA/revocación, Storage, aislamiento
   interno, App Check y permisos administrativos.
2. Backups y restauración probada; alertas, responsables y presupuestos.
3. Staging y aceptación completa con identidades ficticias por rol y colegio.
4. Resolver administradores adicionales; unificar pagos, ajustes y datos legacy.
5. Medir carga/latencia/costes y verificar los límites del proveedor de mapas.
6. Revisar privacidad/legal, publicar la release y probar móvil/accesibilidad.
7. Piloto con pocos colegios y aceptación documentada antes de ampliar la red.

Se considerará el 100 % del **checklist de lanzamiento acordado** cerrado cuando
cada requisito tenga evidencia y responsables, todos los bloqueos estén resueltos
y se apruebe el piloto. La seguridad y el mantenimiento siguen siendo continuos;
ningún porcentaje garantiza ausencia absoluta de errores o ataques.

Informes locales ignorados por Git: `audit-production-*2026-10-09.*`.
Inspección reproducible: `node scripts/inspect-production-readiness.cjs` y
`node scripts/audit-cloud-security.cjs`; requieren la cuenta Firebase CLI ya
autorizada. Solo consultan metadatos y páginas públicas. Algunos checks pueden
no verificarse por permisos/errores de API, lo que se informa explícitamente.
