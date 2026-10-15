# Comprobación de acceso del administrador general

Se sustituyó la combinación de `Future<bool>`, rol mutable y
`_teamRoleResolved` por una comprobación con estados separados: pendiente,
autorizado, denegado y error. La espera máxima es de 30 segundos; un fallo
permite reintentar o salir sin mostrar contenido protegido ni cerrar la sesión
automáticamente.

El servidor debe devolver una decisión explícita (`allowed: false`) para
mostrar una denegación. Las respuestas incompletas y los roles desconocidos en
una respuesta autorizada generan un error recuperable. Los errores técnicos
no se imprimen en la interfaz.

Cada resultado está ligado a su intento y sesión. Cambiar de cuenta, cerrar
sesión o desmontar la pantalla invalida los resultados anteriores. El panel
reinicia su catálogo y caché de indicadores al iniciar otra comprobación.

Se aplicó el mismo componente a las rutas de equipo en `main.dart`, para que un
fallo previo a abrir el panel también ofrezca reintento. Se eliminó la consulta
duplicada del rol en la selección de la pantalla inicial. La salida diferida
del inicio conserva su condición de denegación explícita y misma sesión.

Validación: 9 pruebas nuevas de respuesta del servidor, fallos de red,
timeout, reintento, respuestas tardías, cambio de cuenta, cierre de sesión,
pantalla estrecha, desmontaje y retorno al login. Suite completa: 75 pruebas
aprobadas y 1 omitida previamente. Compilación web correcta. El analizador de
los archivos revisados no detectó errores; conserva 42 advertencias y avisos
previos. No se modificaron reglas, permisos del servidor, App Check ni MFA, y
no se escribieron datos ni se desplegó Firebase.
