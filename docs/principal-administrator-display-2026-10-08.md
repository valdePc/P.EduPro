# Presentación del administrador principal

La ficha utiliza `schools/{schoolId}.adminEmail` como correo principal. Al crear el colegio, su membresía puede contener únicamente UID y rol: esa ausencia de nombre o correo en `members` no significa que la asignación haya fallado.

`getTeamSchoolSummary` devuelve `adminAssigned` a partir del UID o del correo guardado en el colegio. Para el superadministrador consulta exclusivamente la membresía cuyo identificador coincide con `adminUid`, con límite de un documento y proyección de nombre y correo. Nunca utiliza otro administrador como respaldo. Los roles limitados mantienen su respuesta limitada y el correo del documento principal.

Si falta el nombre, la interfaz muestra «Administrador asignado». Si hay asignación pero falta el correo, muestra «Correo no registrado». Cuando no hay UID ni correo, muestra «No asignado» y «Sin asignar». Estos textos son información de presentación: no conceden acceso ni prueban que la cuenta esté habilitada para iniciar sesión.

No se modificaron asignaciones, cuentas, contraseñas, horarios ni permisos. Tampoco se duplican correos en las membresías ni se consultan perfiles de Firebase Auth al abrir la ficha.

## Validación local

- 42 pruebas del servidor aprobadas. Incluyen la creación real del manejador sin correo en la membresía, prioridad del correo principal, selección del UID actual frente a un administrador anterior y datos incompletos.
- 54 pruebas de Flutter aprobadas y una previamente omitida. Incluyen los textos de correo ausente, asignación sin nombre y compatibilidad con respuestas anteriores.
- Compilación web correcta. Los archivos nuevos no presentan errores del analizador; Admin General conserva avisos previos de estilo y elementos sin uso.

El cambio del servidor se publica exclusivamente en `getTeamSchoolSummary`. El cliente compilado queda en `build/web`; para verlo en desarrollo hay que reiniciar Flutter y recargar el navegador. La ficha permite «Actualizar» para descartar su resumen anterior en caché.

## Publicación y comprobaciones

Firebase confirmó la actualización de `getTeamSchoolSummary` en `edupro-8c4fd`. La inspección posterior confirmó la función activa y la última revisión de Cloud Run lista. No se publicaron otros manejadores ni cambios de reglas o Hosting.

La verificación de solo lectura de las consultas en los siete colegios existentes terminó correctamente, con cobertura completa de los indicadores. No se modificaron perfiles, cuentas ni documentos originales. Los ocho endpoints comprobados sin sesión devolvieron HTTP 401, incluido `getTeamSchoolSummary`.
