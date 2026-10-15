# Cambios de autenticación con impacto pendiente de autorización

Esta propuesta acompaña al endurecimiento local y no autoriza una publicación. Se conserva Firebase Auth. No incluye borrar bases, resetear cuentas ni modificar credenciales reales.

## Parche de dependencia proxy-addr

La consulta autorizada de npm detectó `proxy-addr` 2.0.7 en raíz y Functions. El aviso del mantenedor GHSA-jqcg-44mw-7w3h clasifica el problema como crítico y fija el parche en 2.0.8. La dependencia instalada de Express admite `~2.0.7`, que permite 2.0.8. No se ha demostrado que EduPro use la configuración de subred específica vulnerable; no se afirma una explotación.

Autorizado y aplicado localmente el 14 de octubre: `proxy-addr` 2.0.7 a 2.0.8 en raíz y Functions, con scripts de instalación deshabilitados. La comparación de lockfiles muestra un único paquete cambiado en cada árbol. Se comprobó la versión instalada real, el rechazo de subredes mal configuradas y la carga del SDK. No se actualizó Firebase Admin de 13 a 14. La publicación requiere destino, pruebas y autorización propios.

Fuente: https://github.com/jshttp/proxy-addr/security/advisories/GHSA-jqcg-44mw-7w3h

## Registro público de docentes

Estado observado: `precheckTeacherSignup` recibe correo/teléfono sin comprobar propiedad; respuestas distintas revelan coincidencias. Las reglas de solicitudes pendientes admiten creación sin autenticar y limitan claves/campos mínimos. Tres escrituras independientes crean la solicitud.

Propuesta: conservar consultas públicas sobre disponibilidad del colegio; pedir Google antes de enviar datos personales; verificar en servidor el token, correo verificado y coincidencia con el correo solicitado. Trasladar envío y unicidad a una operación transaccional; limitar por UID/IP y reservar claves de unicidad de forma privada. La comparación de teléfonos requiere prueba de propiedad o revisión administrativa, no un endpoint de búsqueda para el solicitante. Preservar solicitudes existentes y sus estados. QA comprobará alta legítima, repetición, fallo intermedio, otra escuela y límites.

Impacto que requiere autorización: añade un paso de Google antes del envío y cambia el contrato de solicitud. No retirar simplemente la comprobación de duplicados: permitiría entradas que hoy se rechazan. Archivos afectados previstos: crearcuentadocentes.dart, docentes.dart, Functions, reglas y pruebas de registro.

## Cobertura MFA de acceso directo

Estado observado: funciones locales comprueban TOTP por sesión, pero Firestore y Storage no usan esa señal. MFA nativo está deshabilitado según consulta de configuración. Una variable heredada de bypass está configurada en funciones desplegadas; el código local no la consulta, por lo que su presencia no demuestra por sí sola un bypass ejecutable.

Propuesta: acordar alcance de MFA por rol y operación, recuperación verificada y señal de sesión que puedan comprobar tanto reglas como callables. Si se reutiliza el estado custom, validar `auth_time`, caducidad, enrolamiento, revocación y presupuesto de lecturas en reglas; documentar soporte de Storage. Evaluar MFA del proveedor solo si conserva proveedores, disponibilidad y costos aceptados. Probar antes usuarios con/sin factor, recuperación, sesiones renovadas, revocación y accesos SDK directos.

Impacto que requiere autorización: exigir MFA en reglas sin migración y recuperación completas puede impedir accesos legítimos. No activar reglas ni políticas de producción hasta tener evidencia de compatibilidad y reversión.

## Compatibilidad de secretos de registro

El cambio local conserva exactamente claves nuevas y heredadas, incluidos espacios. Los clientes anteriores recortan el código y no pueden enviar una clave nueva con espacios en sus bordes. Además, una clave heredada originalmente almacenada con espacios antes aceptaba una versión recortada.

Antes de publicar: autorizar y probar una transición compatible (versión de algoritmo/modo de validación para claves históricas) o publicación coordinada cliente/backend con inventario de formatos sin exponer valores. No rotar secretos reales. Mantener generación alfanumérica/segura reduce el impacto de espacios, pero no demuestra ausencia de secretos históricos afectados.

## Políticas del proveedor y App Check

Se confirmó protección de enumeración de correo. No se devolvió una política de contraseña personalizada; esto no acredita parámetros más fuertes que los predeterminados. Auth, Firestore y Storage figuran UNENFORCED en App Check; las funciones sí tienen ENFORCE_APPCHECK configurado. La protección del login directo de Firebase no puede certificarse con la telemetría de un callable.

Propuesta: medir disponibilidad de clientes y tokens en un entorno de pruebas; acordar política de contraseñas aplicada a nuevas altas/cambios, reCAPTCHA y controles del proveedor sobre registro/recuperación. Activar App Check gradualmente con monitoreo y reversión. No imponer una contraseña nueva ni cambiar credenciales existentes.
