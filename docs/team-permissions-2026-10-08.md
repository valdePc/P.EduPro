# Matriz de permisos del equipo EduPro

Corrección de la autorización del administrador general (8 de octubre de 2026).

| Acción | Superadministrador | Operaciones | Soporte | Facturación |
| --- | --- | --- | --- | --- |
| Entrar por login principal | Sí | Sí, dentro del horario | Sí, dentro del horario | Sí, dentro del horario |
| Consultar catálogo operativo y resumen de colegios | Sí | Sí | Sí | No |
| Ver Red Escolar y análisis agregado | Sí | Sí | No | No |
| Crear colegio | Sí | Plan Base y límites predeterminados | No | No |
| Corregir ubicación | Sí | Sí | No | No |
| Asignar o reemplazar administrador escolar | Sí | No | No | No |
| Editar planes y límites | Sí | No | No | No |
| Consultar planes, vencimientos y pagos | Sí | No | No | Sí |
| Gestionar equipo, configuración, IP y bloqueos | Sí | No | No | No |
| Leer directamente expedientes escolares desde Firestore | Sí, según las reglas existentes | No | No | No |

## Identidad y revocación

El servidor resuelve el primer documento existente en este orden: `users/{uid}`, `Users/{uid}`, `EquipoEduPro/{uid}`, `EquipoValMich/{uid}` (compatibilidad histórica). Exige `enabled: true` y prefiere `teamRole` cuando existe; `superadmin` se normaliza a `super_admin`. Un token con claims antiguos no puede sustituir esa decisión.

Si existe EquipoEduPro, se usa para horarios y bloqueo explícito; en su ausencia se consulta EquipoValMich y después el documento de identidad. `enabled: false` bloquea incluso al superadministrador. El superadministrador habilitado tiene acceso a cualquier hora. Los demás horarios se evalúan en República Dominicana (UTC−4) en el servidor.

La gestión del equipo guarda habilitación y roles de forma atómica en users y en las representaciones canónica e histórica; sincroniza también Users cuando ya existe. Conserva la misma precedencia al recuperar un perfil anterior. Las altas nuevas ya no guardan `role: superadmin` para todos los miembros. Las reglas permiten únicamente al superadministrador actualizar los campos de rol y sus etiquetas; el usuario no puede modificarlos por sí mismo. La pantalla confirma el guardado o informa del error y evita enviar cambios simultáneos.

## Acceso a datos

`getTeamAccess` confirma la identidad y el horario antes del segundo factor. Requiere autenticación y App Check. Los nuevos endpoints de catálogo, resumen, pagos y edición verifican nuevamente el rol y el segundo factor conforme a la política global o individual existente.

`listTeamSchools` limita cada página a 100 documentos y devuelve una lista explícita de campos por rol. `getTeamSchoolSummary` devuelve contadores, nunca expedientes individuales. `getTeamSchoolBilling` devuelve hasta 50 pagos recientes y omite comprobantes y datos de acceso. Los roles limitados siguen sin permiso de lectura directa sobre schools, alumnos, pagos y archivos escolares.

`createSchool` admite operaciones únicamente con Base (1 administrador, 10 docentes, 150 alumnos). Operaciones puede registrar un correo de contacto, pero el servidor rechaza `adminEmail`: la asignación inicial también exige superadministrador. El formulario distingue ambos casos y mantiene la asignación funcional desde el alta para el superadministrador. Las ubicaciones y los planes requieren reautenticación reciente. `updateSchoolPlanLimits` valida límites y escribe el cambio junto con un evento de auditoría en una transacción. Asignaciones de administradores, IP y seguridad siguen siendo exclusivas del superadministrador.

## Validación

- Servidor: **33 pruebas aprobadas**, con handlers reales y almacén simulado: roles, precedencia, revocación, App Check, MFA, proyecciones, paginación, creación restringida, bloqueo de asignación indirecta de administradores y auditoría. Incluye la secuencia de Operaciones y el rechazo de cambios de plan sin justificación, sesión reciente o auditoría completa.
- Emuladores Firestore/Storage: **25 pruebas aprobadas**, con datos sintéticos: lectura y escritura permitidas/denegadas, identidades contradictorias, claims antiguos, aislamiento por colegio, cambios atómicos de rol, bloqueo de la reactivación por el propio usuario y prohibición de modificar directamente planes y límites incluso como superadministrador.
- Flutter: **46 pruebas aprobadas y una omitida previamente**, incluyendo matriz de rutas, acciones visibles, decodificación de catálogo, sincronización de límites al cambiar de plan, conservación del alta tras errores, entrega protegida de la clave y editor de planes con justificación, errores, reintentos y confirmación cancelada. Compilación web de producción correcta; el análisis de los archivos modificados no encontró errores de compilación, aunque conserva avisos de estilo y miembros sin uso.
- Consulta de solo lectura en Firebase: la cuenta principal indicada por el propietario existe, está habilitada y tiene rol superadmin.
- Revisión de coherencia del equipo en Firebase: una identidad de equipo encontrada, sin roles contradictorios entre el perfil efectivo y la ficha del equipo. La comprobación imprime únicamente contadores y no cambia cuentas.

No se han realizado pruebas interactivas de login usando contraseñas de otras personas. Las pruebas de reglas emplean identidades sintéticas; las comprobaciones HTTP sin sesión verifican el rechazo del acceso público, no sustituyen una sesión interactiva para cada rol.

### Revisión del diagnóstico «Nueva escuela visible, pero createSchool exige superadministrador»

Ese diagnóstico describe el estado anterior a esta corrección. `createSchool` ahora autoriza `OPERATIONS_ROLES` (superadministrador y operaciones), y el cliente utiliza `listTeamSchools` para obtener un catálogo con campos permitidos por rol. Las restricciones de lectura y escritura directa en `/schools/{schoolId}` siguen siendo intencionales: las funciones ejecutan las operaciones admitidas después de validar el rol y la sesión. No es necesario abrir los documentos completos a Operaciones.

La comprobación específica volvió a aprobar 30 pruebas del servidor, 24 de reglas en emulador y tres pruebas Flutter de permisos. Se añadieron verificaciones de que los roles limitados no pueden crear colegios ni cambiar coordenadas escribiendo directamente en Firestore. En Firebase se comprobó que las últimas revisiones de `createSchool`, `listTeamSchools` y `updateSchoolLocation` están listas. Esta revisión adicional modificó pruebas y diagnóstico; no necesitó cambiar ni redesplegar la política ya publicada.

### Límites visibles y enviados al crear un colegio

El alta utiliza `SchoolPlanController` y campos conectados a sus controladores de texto. Al cambiar de plan, se actualizan los tres valores visibles; al enviar, se obtiene una selección inmutable desde esos mismos textos validados. Se retiraron las variables separadas de límites y el uso de `initialValue` en esos campos. Durante la confirmación de identidad se bloquean el plan, los límites y el botón de creación para evitar cambios o envíos simultáneos.

La creación y el editor posterior comparten los valores predeterminados del cliente mediante `SchoolPlanValues.defaultsFor`. Las tres pruebas nuevas verifican cambios entre los cuatro planes, límites personalizados, rechazo de campos vacíos o inválidos y bloqueo de edición para Operaciones. Esta corrección está en el cliente local y no requiere cambios en Firebase.

### Conservación del formulario durante la creación

`SchoolCreationDialog` mantiene montado el formulario hasta recibir una respuesta exitosa de `createSchool`. Ante errores de permisos, conexión o verificación muestra un mensaje dentro del diálogo y permite reintentar con los mismos datos. La cancelación de la confirmación de identidad o del segundo factor también conserva el alta. No se reenvían solicitudes automáticamente.

Durante toda la confirmación y creación, el botón muestra «Guardando…», se bloquean las pulsaciones repetidas, la edición y el cierre voluntario. Los controles se liberan al finalizar un intento fallido. La creación y las notificaciones posteriores están separadas: un error al enviar el correo después del éxito no reabre el alta ni propone volver a crear el colegio.

Seis pruebas de widgets comprueban errores simulados de Firebase, conservación de nombre, correo, plan y límites, rechazo de solicitudes simultáneas, bloqueo de cierre mientras se guarda, reintento, cancelación del segundo factor, datos inválidos y diseño de error en móvil. Esta corrección no modifica reglas ni funciones de Firebase.

## Entrega de la clave de registro

La creación ya no publica la clave en un SnackBar ni la copia automáticamente al portapapeles. El cliente extrae y elimina `password` de la respuesta y presenta un único diálogo de entrega tras la confirmación de identidad y el segundo factor existentes. La clave permanece oculta hasta pulsar «Mostrar clave»; «Copiar clave» es la única acción que la escribe en el portapapeles. Los mensajes de copia nunca incluyen su valor.

El diálogo está vinculado al UID que confirmó la creación. Se cierra si termina o cambia esa sesión y comprueba la sesión nuevamente antes de revelar o copiar. Al pasar la aplicación a segundo plano, la clave vuelve a ocultarse. No se guarda en almacenamiento del navegador ni se ofrece un botón para volver a abrir este recibo después de cerrarlo. Esto limita la exposición en la interfaz; no impide capturas de pantalla ni garantiza el borrado físico de cadenas en memoria. Una copia explícita permanece en el portapapeles del equipo.

Cinco pruebas nuevas comprueban ocultación, copia exclusivamente explícita, cierre por cambio de sesión, comprobación de sesión antes de copiar y fallo del portapapeles con reintento en móvil. Este cambio no modifica ni despliega funciones o reglas de Firebase.

## Cambio sensible de plan y límites

La opción de edición y el punto de entrada del editor admiten únicamente al superadministrador. El cambio utiliza `updateSchoolPlanLimits`, que exige App Check, permiso vigente del equipo, sesión autenticada hace menos de cinco minutos y segundo factor cuando la política lo exige. La interfaz confirma nuevamente la identidad y la verificación requerida antes de guardar.

La justificación de 10 a 500 caracteres es obligatoria en interfaz y servidor. Una transacción guarda los límites planos, `planLimits`, `maxUsers` y un evento `school.plan-limits.updated` con actor, rol, colegio, motivo, fecha y valores anteriores y nuevos. Si falla la escritura del evento, no se confirma el cambio del colegio. Las reglas impiden modificar directamente esos seis campos desde clientes, incluso como superadministrador; las operaciones de creación y los otros campos mantienen sus permisos previos.

El editor conserva plan, límites y justificación al cancelar la confirmación o fallar el guardado. Mientras espera se bloquean envíos repetidos, edición y cierre voluntario. Los errores se presentan dentro del diálogo, con mensajes específicos para permisos, sesión, red, datos inválidos o colegio inexistente. Una respuesta sin `success: true` no se trata como éxito. No se reintentan solicitudes automáticamente: si la conexión impide confirmar el resultado, se indica revisar el plan actual antes de repetir el envío.

Las pruebas usan datos sintéticos; no se modificaron planes reales para comprobar este flujo. La compilación web local incluye el nuevo editor.

Se publicaron `updateSchoolPlanLimits` y las reglas de Firestore en `edupro-8c4fd`. El primer intento recibió un 503 temporal del servicio de reglas; el reintento terminó con `Deploy complete`. La función quedó `ACTIVE` y la revisión `updateschoolplanlimits-00002-zol` lista con el 100 % del tráfico. La comprobación HTTP sin sesión devolvió 401 para esta función. No se publicó Hosting; hay que reiniciar Flutter para cargar el nuevo editor en desarrollo.

## Despliegue verificado

El 8 de octubre de 2026 se publicaron las 22 funciones afectadas y las reglas de Firestore en `edupro-8c4fd`. Los reintentos de `unlockSchoolAccessIp` y `searchSchoolPlaces` terminaron correctamente. La comprobación posterior de Cloud Run confirmó que la última revisión creada coincide con la última lista para servir tráfico para esas dos funciones y `createSchool`.

Los ocho endpoints comprobados sin credenciales respondieron **HTTP 401**: `getTeamAccess`, `listTeamSchools`, `getTeamSchoolSummary`, `getTeamSchoolBilling`, `updateSchoolPlanLimits`, `unlockSchoolAccessIp`, `searchSchoolPlaces` y `createSchool`. Ninguna comprobación envió datos de colegios ni modificó cuentas.

La compilación del cliente está en `build/web`. En esta corrección no se publicó Hosting: para usar los cambios en desarrollo hay que reiniciar la ejecución de Flutter y recargar el navegador. Las reglas de Storage se validaron en emulador, sin modificarlas ni volverlas a desplegar en esta tarea.

## Recursos de ejecución

La revisión posterior de rendimiento de la ficha pasó 39 pruebas del servidor, 26 de reglas y 51 de Flutter (una omisión previa). El resumen usa agregaciones y contadores derivados privados, con caché temporal y reintento explícito en la interfaz. Véase [Indicadores de la ficha del colegio](school-summary-performance-2026-10-08.md) para lecturas, inicialización y límites de actualización.

`unlockSchoolAccessIp` y `searchSchoolPlaces` usan 256 MiB, CPU `gcf_gen1` (0,1666 CPU) y una solicitud simultánea por instancia, con el límite global existente de tres instancias. Son operaciones administrativas con esperas de red; el ajuste reduce el consumo de CPU pero limita su concurrencia total. No modifica sus validaciones de permisos, App Check ni segundo factor. Se introdujo tras fallos de despliegue por la cuota regional de CPU. El [modelo de CPU y concurrencia de Firebase](https://firebase.google.com/docs/functions/manage-functions) documenta estas opciones.
