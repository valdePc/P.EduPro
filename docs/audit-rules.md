# Auditoría de autorización Firestore y Storage

Fecha: 2026-10-05. Alcance: reglas locales, contratos del cliente relacionados y pruebas con datos sintéticos en `demo-edupro-security`. No se desplegaron reglas ni se modificaron datos reales. Firestore usa Security Rules, no RLS de SQL. Este informe no certifica que las reglas desplegadas coincidan con estos archivos ni que el sistema esté listo para gestionar datos nacionales de menores.

## Correcciones realizadas

| Severidad original | Problema confirmado | Corrección local |
| --- | --- | --- |
| Crítica | `changedKeys()` ignoraba campos añadidos/eliminados. Un usuario podía añadir `teamRole: superadmin` a su perfil; otros documentos permitían alterar campos fuera de la lista prevista. | Sustitución por `affectedKeys()` en todas las restricciones de actualización, incluidas las colecciones heredadas. |
| Crítica | La existencia de `teachers_public/{uid}`, cuya alta podía hacer un tercero, confería rol docente. | El rol requiere membresía habilitada y controlada. La solicitud pública pendiente no autoriza acceso. |
| Crítica | El alta pendiente en directorio permitía crear la membresía y el vínculo UID antes de aprobación. | El bootstrap requiere estado administrativo activo, identidad coincidente y correo verificado si se usa el correo como prueba de identidad. |
| Alta | Correo no verificado permitía apropiarse de accesos de padres/alumnos/docentes. | Se exige `email_verified` exclusivamente en las vías de identificación por correo; los vínculos legítimos por UID continúan disponibles. |
| Alta | Administrador de A podía sobrescribir el índice global de un alumno de B cambiando `schoolId` a A. | Actualización autorizada por el colegio anterior y `schoolId` inmutable, salvo superadministrador. |
| Alta | Bloques duplicados de calificaciones anulaban restricciones por grado/asignatura y permitían cambiar la identidad de una calificación. | Se mantiene una sola regla con asignaturas explícitas e identidad de alumno/año/colegio/grado/asignatura inmutable. |
| Alta | Reglas duplicadas de entregas permitían crear `finalPoints`/`gradeApproved` desde una cuenta de alumno. Había también un bloque con `studentId` fuera de su ámbito. | Consolidación de entregas, lista de campos al crear y de diferencias al actualizar; eliminación del bloque accidental. |
| Alta | Un docente deshabilitado podía intentar reactivar su membresía. La administración, paradójicamente, no podía guardar `enabled: false`. | La actualización propia conserva habilitación y requiere cuenta activa; la administración puede revocar. |
| Alta | `teachers_public` se podía enumerar entre colegios por cualquier cuenta autenticada. `estudiantes` completo era legible por alumnos del colegio. | Directorio disponible al personal del colegio o al propio correo verificado; padrón heredado completo limitado al personal. |
| Alta | Solicitudes de promoción/cambio de grado aceptaban vínculos públicos como autorización, y promoción no exigía rol docente real. | Se exige membresía docente, identificador docente propio y conservación del propietario al actualizar promoción. |
| Media | Bloque duplicado de citas omitía la audiencia; docentes podían cancelar citas ajenas. | Audiencia aplicada en ambos bloques y cancelación propia o administrativa. |
| Alta | Storage usaba `get/exists` sin el espacio de nombres de Firestore. | Uso de `firestore.get/firestore.exists`; roles, correo verificado y habilitación comprobados. |
| Alta | Cualquier integrante podía reemplazar el archivo al que apuntaba un mensaje de otra persona. | Subidas de chat requieren `resource == null`; modificación/borrado del objeto existente denegados. |
| Disponibilidad | Pruebas positivas superaron el límite de 1000 expresiones por resolución repetida de perfiles/membresías. | Resolución de datos una vez por helper y eliminación de comprobaciones repetidas en acceso del personal. |

## Pruebas y evidencia

`security-tests/firestore-storage.test.cjs` contiene 20 escenarios con denegaciones y operaciones legítimas. Rechaza endpoints que no sean loopback y proyectos distintos de `demo-edupro-security`. Inicializa y limpia únicamente los emuladores.

Cobertura: acceso anónimo, escalada en ambos perfiles, separación de colegios, índices globales, alta docente pendiente/aprobada, revocación, propiedad de alumnos, correo verificado, enumeración, manipulación de vínculos, entregas, audiencias, calificaciones, colecciones internas, archivos propios/ajenos, tamaño/MIME y reemplazo de adjuntos.

**Resultado final: 20/20 pruebas aprobadas**, sin fallos ni cancelaciones. Ambos juegos de reglas compilan en los emuladores. Las ejecuciones iniciales detectaron denegaciones por complejidad, un error de evaluación parcial de ternarios y una sobrescritura de Storage. Se corrigieron sin eliminar expectativas. El caso de calificaciones valida creación y actualización legítimas, asignatura no autorizada, alumno de otro grado y sustitución de alumno incluso dentro del mismo grado. La suite tiene límite de tiempo y watchdog: un bloqueo nunca cuenta como éxito.

Las pruebas no abarcan cada combinación de rol, documentos heredados, consultas de todas las pantallas, transferencias escolares, archivos con URL pública previamente emitida ni accesos mediante Admin SDK/IAM.

## Bloqueantes y trabajo pendiente

1. **MFA no aplicada de forma integral a la base y archivos.** Las reglas autorizan por identidad/membresía, sin exigir prueba de segundo factor de la sesión. Endurecer los callables o la interfaz no impide llamadas directas al SDK. Hace falta una prueba de sesión emitida por backend y una matriz completa de rutas protegidas; preservar recuperación/enrolamiento y verificar revocación. No declarar MFA integral.

2. **Adjuntos compartidos a nivel de colegio.** `storage.rules`, bloques `chat_uploads` y `material_apoyo`, permiten leer a cualquier integrante autorizado del colegio. No comprueban participantes de la conversación ni `visibleToStudents` del documento Firestore. Deben migrarse rutas/metadatos a conversación y recurso, exigir la misma autorización que su documento y revisar/revocar URLs con token previamente emitidas. Denegar reemplazo no resuelve confidencialidad.

3. **Minimización de acceso del personal incompleta.** `alumnos` permite `list` a todo docente del colegio; asistencia y entregas también permiten lecturas docentes amplias. Un filtro visual no restringe el SDK. Definir grados, asignaturas, tutoría y sustituciones, adaptar consultas y aplicar permisos también a documentos, tutores e historial. El perfil de personal necesita un catálogo separado de datos administrativos/sensibles.

4. **Matrícula y tareas necesitan más invariantes.** La calificación V2 exige grado/asignatura autorizados, pero crear un documento todavía necesita cruzar `studentId` con la matrícula efectiva del alumno en ese grado. Las entregas comprueban propietario y existencia, pero no todos los límites de publicación/fecha de entrega/asignación por grado. Las calificaciones heredadas necesitan la misma matriz que V2.

5. **Altas anónimas y coste.** Solicitudes de docentes y `login_docentes` aún aceptan altas directas con campos válidos. No conceden rol tras estas correcciones, pero permiten suplantación de solicitudes, acaparamiento de identificadores y abuso de almacenamiento. Trasladar a un backend con App Check, identidad/verificación, límites, idempotencia y aprobación administrativa; adaptar antes la pantalla de registro.

6. **Deshabilitación/revocación repartida.** Existen `/users`, `/Users`, `/EquipoEduPro`, membresías, directorios y vínculos de alumno. No todas las rutas consultan un único estado canónico; algunas vías propias por correo/UID pueden sobrevivir a bloquear otro documento. Unificar autoridad y probar revocación global y por colegio, incluido Storage y tokens ya emitidos.

7. **Documentos de configuración/credenciales.** Se conserva acceso administrativo a `teacher_credentials` y a configuración que incluye hashes/salt. Verificar contenido sin divulgar valores y migrar autenticación a un backend: el cliente no necesita hashes para autenticar. Metadatos públicos deben contener solo campos públicos; reglas de lectura no ocultan campos individuales.

8. **Archivos.** El MIME lo declara el cliente; tamaño/tipo no equivalen a análisis del contenido. `image/.*` admite SVG y se aceptan algunos binarios genéricos. Incorporar validación de contenido, cuarentena/análisis y descarga segura antes de admitir material de usuarios a escala nacional. Las reglas Storage pueden acceder a solo dos documentos Firestore por evaluación: el fallback heredado miembro + UID alumno + email puede excederlo y requiere migración a vínculos UID canónicos.

9. **Operaciones administrativas y auditoría.** Las reglas mantienen atribuciones administrativas amplias sobre alumnos/credenciales. Registrar cambios críticos en backend con trazabilidad no modificable por el actor; reglas no reemplazan IAM, políticas de retención, copias ni pruebas de restauración. Los SDK de servidor privilegiados no quedan restringidos por estas reglas.

## Compatibilidad antes de desplegar

- Completar `teachers.gradeIds` y `subjectIds` con asignaciones confiables. Sin asignatura explícita se deniega calificación; no reintroducir la autorización por lista vacía para hacer pasar una pantalla.
- Las calificaciones V2 de docentes comprueban el grado del alumno en `schools/{schoolId}/alumnos/{studentId}` (`gradeId`, `gradoId` o `gradoKey`). Se necesita esa matrícula canónica. Tras una promoción, la edición de calificaciones de años anteriores requerirá una matrícula histórica por año; con esta regla, una discrepancia con el grado actual se deniega al docente y requiere intervención administrativa. Probar ese flujo antes del despliegue.
- Mantener estados de docente aprobados normalizados (`active`, `activo` o `activa`) y correo verificado si el inicio depende de correo. El vínculo UID ya autorizado sigue siendo válido.
- Consultar el directorio propio por `emailLower` verificado durante el inicio Google; una enumeración previa indiscriminada se deniega.
- Revisar pantallas que consultan todo `estudiantes`, que agregan campos a una actualización limitada o que reemplazan un adjunto existente. Usar nuevos nombres de objeto para nuevos adjuntos.
- Ejecutar pruebas funcionales con identidades sintéticas en un entorno separado, y revisar cada ruta heredada antes de desplegar. Las reglas locales endurecidas no cambian producción hasta un despliegue explícito.

## Fuentes primarias

- [Control de campos y `affectedKeys`](https://firebase.google.com/docs/firestore/security/rules-fields).
- [Condiciones Storage, integración Firestore y límite de dos documentos](https://firebase.google.com/docs/storage/security/rules-conditions).
- [Pruebas de Security Rules con emuladores](https://firebase.google.com/docs/rules/unit-tests).
