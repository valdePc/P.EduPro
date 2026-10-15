# Inventario de entradas y autenticación — 2026-10-13

Inspección estática local, sin consultar producción. El índice de formularios cubre las declaraciones TextField/TextFormField encontradas en lib. No demuestra accesibilidad de pantallas ni autorización del backend; selectores, archivos, importaciones y componentes personalizados requieren seguimiento adicional. No se ejecutaron pruebas desde este subagente.

## Identidad y credenciales

| Archivo en lib | Operación | Backend |
| --- | --- | --- |
| screens/login_general.dart | Equipo: correo/contraseña y Google | Firebase Auth; rol, dispositivo y MFA antes de navegar |
| screens/admin_general.dart | Reautenticación, alta colegio, enlace de contraseña | Firebase Auth; createSchool; sendPasswordResetEmail |
| services/team_action_verification.dart | Reautenticación acciones sensibles | Firebase Auth + MFA |
| screens/equipoedupro.dart | Alta equipo, roles y horarios | Auth secundaria; batch EquipoEduPro, EquipoValMich, users |
| admin_escolar/screens/admin_login_escolar.dart | Google y clave de equipo de registro | Auth, members/admins/users; adminSchoolLoginRateLimit; validateSchoolRegistroAccess |
| docentes/screens/docentes.dart | Google docente | Auth, teachers/teachers_uid; schoolAccessIpPing |
| docentes/screens/crearcuentadocentes.dart | Solicitud docente | precheckTeacherSignup; writes teachers, teacher_directory, teachers_public |
| alumnos/screens/alumnos.dart | Google alumno, selección de alumno/grado | Auth, alumnos/alumnos_login/estudiantes; schoolAccessIpPing |
| admin_escolar/screens/registro_equipo_screen.dart | Registro alumno | alumnos/alumnos_global/alumnos_login; foto en Storage |
| screens/coleAdmin.dart | Alta/actualización administrador, clave registro | createSchoolAdminAccount, upsertSchoolAdmin, setSchoolAdminStatus, setSchoolRegistroConfig |
| admin_escolar/screens/A_registro.dart | Rotación clave registro | setSchoolRegistroConfig |
| screens/colegios.dart | Asignación administrador y enlace de contraseña | assignSchoolAdmin, sendPasswordResetEmail |
| docentes/screens/recuperarcontrasena.dart | Pantalla antigua de recuperación | Ninguno: espera simulada. No se encontró referencia a la pantalla desde otras fuentes Dart |
| services/edupro_two_factor_service.dart | Inscripción/verificación TOTP | getEduProTwoFactorStatus, startEduProTwoFactorEnrollment y llamadas de confirmación/verificación; App Check y sesión |
| services/edupro_trusted_device_service.dart | Dispositivo | checkEduProTrustedDevice |
| screens/acceso_enlace_screen.dart | Enlace/código colegio | Lectura schools y navegación |

No se encontraron llamadas updatePassword, confirmPasswordReset ni verifyPasswordResetCode en lib. No se verificó configuración remota de los enlaces del proveedor. La clave de registro es distinta de una contraseña Firebase Auth. Docentes y alumnos utilizan Google; no introducir contraseñas locales como sustitución implícita.

## Hallazgos y controles cliente

- Corregido: admin_general recortaba espacios de contraseña en reautenticación, mientras login_general conserva el valor exacto. Ahora conserva el valor intacto.
- Corregido: nueva contraseña de equipo visible por defecto; ahora oculta, sin sugerencias ni autocorrección. Validación sobre el mismo valor exacto enviado a Auth. Se conserva mínimo existente de seis caracteres, que no sustituye una política en servidor.
- Corregido: errores crudos del alta equipo y fallback de reautenticación reemplazados por mensajes controlados. No certifica ausencia de enumeración remota.
- Corregido en la continuación: admin_login_escolar presenta mensajes controlados para el fallback Google y la colisión de proveedor; otros errores de funciones necesitan revisión de sus contratos.
- Corregido en la continuación: crearcuentadocentes registra solo eventos constantes, sin nombre, correo, IDs, respuestas precheck ni excepciones completos. Se conserva su límite a kDebugMode.
- Pendiente: registro docente usa tres escrituras independientes; comprobar reglas y atomicidad antes de concluir viabilidad.
- Pendiente: alta equipo combina Auth y batch Firestore; el fallo del batch podría dejar cuenta Auth sin perfil. No se ejecutó ese escenario ni se demostró escalada.
- Secretos de entrada: contraseña equipo/reautenticación, contraseña temporal de administrador, clave registro, código TOTP y secreto de inscripción TOTP. Evitar registros y persistencia legible; mostrar el secreto de inscripción únicamente al titular durante el alta.

## Resto del inventario de formularios

Todos los archivos se expresan relativos a lib. Los destinos son referencias presentes en el archivo; una búsqueda local no implica que todos sus campos escriban en todos los destinos. Los flujos de identidad de la tabla anterior también forman parte del inventario de TextField/TextFormField.

| Archivos | Operación / destinos identificados |
| --- | --- |
| chat/ui/chat_thread_screen.dart | Mensajes; mensajes |
| calendario/ui/calendario_screen.dart; admin_escolar/screens/admin_calendar_screen.dart | Citas; AppointmentsService |
| alumnos/shared/alumno_common.dart | Componentes compartidos; callbacks/estado |
| alumnos/screens/chat_grado_screen.dart | Chat; chat_grados/mensajes, alumnos/alumnos_login/grados/teachers_uid |
| admin_escolar/screens/admin_chat_room_screen.dart | Chat; messages |
| admin_escolar/widgets/asignaturas.dart | Asignaturas; schools/subjects, SubjectsService |
| admin_escolar/screens/A_calendario_escolar.dart | Calendario; calendario_escolar_items/grados/subjects/teachers |
| admin_escolar/screens/A_cambios_grado.dart | Cambios académicos; movimientos_academicos/alumnos_global |
| alumnos/tabs/tareas_tab.dart | Entregas; tareas_docentes/submissions |
| admin_escolar/screens/A_competencias.dart | Competencias; CompetenciasService |
| admin_escolar/screens/A_gestiondemaestros.dart | Gestión docente; teachers/teacher_directory/teachers_public/members/users |
| admin_escolar/screens/A_grados.dart | Grados; schools/grados |
| docentes/screens/asistencia.dart | Asistencia; alumnos/asistencia/rows/grados/teachers_uid |
| admin_escolar/screens/A_MonitoreoDocentes.dart | Monitoreo y comentarios; admin_feedback/curricular_progress/asistencia/tasks/mensajes; MonitoreoService |
| admin_escolar/screens/A_pagos.dart | Reportes de pago; schools/payments, app_config |
| docentes/screens/cambio_grado_docente_screen.dart | Cambio académico; schools y rutas dinámicas |
| docentes/screens/chat_docentes_screen.dart | Chat; mensajes/reads/teachers/teachers_uid |
| docentes/screens/colocar_calificaciones.dart | Notas; rutas dinámicas, requiere seguimiento adicional |
| admin_escolar/screens/chat_admin_docentes_screen.dart | Chat; mensajes |
| docentes/screens/D_chat_thread_screen.dart | Chat; escuelas/messages |
| widgets/app_info_menu.dart | Información app; AppInfoContentRepository/app_config/Users |
| screens/configuracion.dart | Configuración; estado/callbacks |
| admin_escolar/screens/estudiantes.dart | Gestión alumnos; alumnos/alumnos_login/grados/users |
| admin_escolar/screens/nota_competencias.dart | Competencias/notas; schools/subjects |
| admin_escolar/screens/notificaciones_admin.dart | Avisos; notificaciones_alumnos/notificaciones_docentes/notificaciones_admin_cuota_diaria |
| screens/branding_y_apariencia.dart | Apariencia; estado/callbacks |
| docentes/screens/planificaciones.dart | Planificación; PlanificacionService, schools/grados/subjects/teachers |
| docentes/screens/material_de_apoyo_docente.dart | Material; material_apoyo_docente, schools/members/teachers |
| docentes/screens/promocion_docente_screen.dart | Promoción; schools/Users y rutas dinámicas |
| docentes/screens/tarea.dart | Tareas; tareas_docentes/submissions/alumnos/members |
| widgets/school_plan_fields.dart; widgets/school_plan_edit_dialog.dart | Plan colegio; callbacks hacia propietario |
| screens/facturacion.dart | Facturación; app_config/freelancers/payments/schools/users |
| screens/preferenciadelsistema.dart | Preferencias; estado/callbacks |
| screens/seguridad.dart | Controles seguridad; access_logs/app_config/blocked_devices/blocked_ips |
| screens/pagos_facturacion.dart | Facturación; EscuelaRepository |
| widgets/school_catalog_view.dart | Filtro catálogo; callback/controlador |

## Plan compatible

Mantener proveedores existentes y semántica de secretos. Validar tipo, límites y permisos en servidor y reglas, no solo Flutter. Centralizar altas sensibles y contratos antes de migrar escrituras. Probar contraseñas con espacios, fallo Auth seguido de fallo perfil, permisos por escuela, MFA incompleto y mensajes públicos. Toda publicación exige revisión independiente y autorización de versión/destino.
