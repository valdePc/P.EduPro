# Verificación de acceso al login principal

Solicitud: permitir que `valdeymse@gmail.com` inicie sesión todos los días, a cualquier hora, conservando los controles de seguridad.

Seguimiento: el error posterior de la llamada al segundo factor se diagnosticó y corrigió en [login-app-check-fix-2026-10-05.md](login-app-check-fix-2026-10-05.md). El resultado de horarios que sigue corresponde a la consulta inicial de solo lectura.

## Resultado en Firebase

Consulta administrativa de solo lectura en `edupro-8c4fd` el 5 de octubre de 2026. La cuenta se identificó por correo en Firebase Authentication y las consultas de perfiles se hicieron exclusivamente con su UID devuelto por Auth.

- Authentication: cuenta activa y correo verificado.
- `users/{uid}`: `enabled: true`, `role: superadmin`; sin campos de horario.
- `Users/{uid}`, `EquipoEduPro/{uid}` y `EquipoValMich/{uid}`: no existen.

La configuración actual ya permite acceso sin restricción horaria. `EquipoEduProAccess.validateUser` devuelve autorización horaria cuando no existe el documento `EquipoEduPro/{uid}`. `currentTeamRole` obtiene el rol existente desde `users/{uid}`. El login, la puerta de sesión y el panel utilizan estos controles.

No fue necesario modificar Firebase, crear perfiles ni desplegar código. No se cambiaron contraseñas, roles, MFA, reglas ni políticas de otros usuarios. Tampoco se introdujo una excepción por correo en el cliente. Como cualquier permiso administrable, esta configuración podría cambiar si un administrador crea posteriormente un horario para esa cuenta.

## Validación y alcance

`flutter test --no-pub test/team_access_schedule_test.dart`: **4 pruebas aprobadas**. Cubren los siete días completos, el último segundo de cada minuto, la denegación de cuentas desactivadas y la conservación de horarios ordinarios y nocturnos.

Se verificaron identidad, configuración y rutas de código. No se realizó un inicio de sesión interactivo con la contraseña del titular; esta revisión no demuestra que todos los servicios externos del login estén funcionando de extremo a extremo.

La pantalla actual de gestión escribe `EquipoValMich`, mientras el control de horario consulta `EquipoEduPro`. Ambas colecciones se comprobaron para este UID; ninguna contiene un horario. Esta diferencia preexistente no se modificó en esta tarea.

Herramienta de consulta: `scripts/inspect-team-access.cjs`. Reutiliza la sesión administrativa de Firebase CLI, limita los campos devueltos y omite cuerpos de solicitudes/respuestas en los registros. No contiene operaciones de escritura. La operación HTTP POST de [accounts.lookup](https://docs.cloud.google.com/identity-platform/docs/reference/rest/v1/projects.accounts/lookup) es una consulta de identidad.
