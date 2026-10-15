# Corrección del acceso y guardado del registro de estudiantes

Fecha de revisión: 14 de octubre de 2026. Alcance: cambios locales, con datos sintéticos y emuladores. No hubo despliegues ni modificaciones de cuentas, credenciales o expedientes de producción.

El usuario autorizó explícitamente implementar una sesión temporal de registro, limitada al colegio, sin permisos administrativos, con vencimiento y revocación. Esa autorización no incluye publicar esta versión.

## Diagnóstico comprobado

El acceso anterior llamaba `validateSchoolRegistroAccess`, recibía `ok` y abría el formulario sin iniciar una sesión Firebase autorizada. El formulario consultaba alumnos y guardaba un batch de alumno, índice global y correos autorizados, mientras las reglas exigían administración del colegio. Entrar únicamente con la clave no cumplía ese requisito.

La captura muestra un mensaje genérico, no el código original de la excepción. Por eso se acredita el defecto del contrato de autorización y su reproducción con datos sintéticos; no se afirma haber identificado una excepción concreta de producción. También podían ocultarse problemas de red o índices bajo el mismo mensaje.

| Hallazgo | Riesgo | Corrección y evidencia |
| --- | --- | --- |
| Clave válida abría el formulario sin identidad autorizada para leer y guardar. | Alto, funcional y de autorización | Token personalizado de Firebase Auth, identidad temporal y permiso privado por colegio. Auth real de emulador, claims, lecturas autorizadas y denegadas probados. |
| El cliente comprobaba cupo y duplicados antes de un batch independiente; las comprobaciones podían competir y el cupo se omitía si fallaba la lectura de escuela. | Medio, integridad | Validación y escritura transaccional en servidor, agregación de conteo y bloqueo compartido del nuevo flujo. Dos altas simultáneas por el último cupo y duplicados reales en emulador dejan un solo alumno. |
| El conteo de cupo descargaba toda la colección de alumnos. | Medio, rendimiento | El servidor utiliza `count()` en la transacción; no descarga expedientes para contar. |
| La subida de fotos no tenía permiso para su ruta y su excepción se ignoraba. | Medio, funcional e integridad | Subida mediante callable con formato, tamaño, colegio, sesión, propietario y generación comprobados. Un fallo conserva el formulario y no se comunica como registro completado. |
| Las fotos se representaban mediante enlaces portadores de descarga. | Medio, privacidad | Las fotos nuevas guardan `photoPath` y `photoUrl: null`. El avatar usa descarga autenticada y comprueba que la ruta corresponda al estudiante. La prueba real confirma ausencia del token de descarga y denegación a terceros. No se migraron enlaces antiguos. |
| Los mensajes no distinguían recuperación de sesión, red, duplicados o entradas inválidas. | Medio, diagnóstico | Mensajes por códigos controlados, sin mostrar mensajes internos, rutas o datos del formulario. Renovación mediante la clave exacta sin borrar el borrador. |
| Durante la revisión se detectaron carreras entre subida y registro, y entre renovación y cierre. | Medio, integridad y sesión | Reserva privada de foto y verificación de generación; el cierre espera la renovación antes de revocar. Pruebas de servidor e inspección independiente del cierre. |
| El selector de foto no reflejaba el permiso recibido del servidor. | Medio, funcional | Selector deshabilitado sin permiso, comprobación antes de enviar, aviso al renovar y acción para retirar la foto conservando los demás datos. Prueba de interacción y revisión independiente. |

## Comportamiento implementado

- Se conserva Firebase Auth. `validateSchoolRegistroAccess` verifica la clave con la protección existente y emite un token personalizado para una identidad `reg_*`. La clave no se recorta ni se normaliza.
- Una app Firebase secundaria aísla el registro de la cuenta principal. En web usa persistencia de Auth en memoria; la caché persistente de Firestore se desactiva para esta app. En móvil el SDK de Auth puede persistir su sesión: el permiso del servidor sigue venciendo y el cierre solicita revocación y limpia la sesión local.
- El permiso privado comprueba colegio, estado habilitado, vencimiento máximo de dos horas y versión de acceso. Guardar la configuración de registro rota la versión. Renovar exige otra validación de la clave y conserva la identidad pendiente del mismo colegio.
- Las reglas aíslan estas identidades del bootstrap y de los permisos de cuentas normales. Solo añaden lectura de alumnos y grados del colegio autorizado. No permiten escribir alumnos, índices, accesos, roles, membresías o secretos desde el cliente de registro.
- `registerSchoolStudent` valida campos, formatos, longitudes, fechas, estado, grado, correos y rutas; construye las escrituras en servidor. Conserva el esquema que usan los perfiles y vínculos de acceso existentes.
- Un identificador estable del intento y un recibo privado hacen idempotente el reintento de la misma solicitud. Una carga distinta con un identificador ya confirmado se rechaza; no se sobrescribe al estudiante.
- `createSchoolRegistroGrade` permite crear grados para la inscripción sin conceder administración general. La edición rápida de alumnos continúa siendo el aviso preexistente, no se presenta como función implementada.
- Las nuevas callables usan las comprobaciones existentes de App Check cuando está configurado como obligatorio, y presupuestos por identidad y origen confiable. La subida tiene una sola solicitud simultánea por instancia, 256 MiB y 120 segundos de tiempo máximo; mantiene el límite global de instancias existente.
- Las fotos nuevas aceptan JPG/PNG de hasta 5 MiB, con comprobación de bytes y reserva contra carreras. El cliente de registro no recibe escritura directa de Storage. El servidor no genera enlaces portadores para esas fotos.
- Los borradores solo se limpian al confirmar el registro. Los errores y la renovación conservan los datos. Se mantiene la confirmación al salir con datos sin guardar.

Las reglas preparadas son un **prototipo revisado localmente y probado en emuladores**, no una certificación de toda la configuración remota. Requieren comprobar el cambio completo en el entorno de destino antes de publicar.

## Archivos de este cambio

| Área | Archivos |
| --- | --- |
| Backend | `functions/index.js`, `functions/school_registration.js` |
| Reglas e índices | `firestore.rules`, `storage.rules`, `firestore.indexes.json` |
| Acceso y formulario | `lib/admin_escolar/screens/admin_login_escolar.dart`, `lib/admin_escolar/screens/registro_equipo_screen.dart`, `lib/admin_escolar/services/school_registration_session.dart`, `lib/admin_escolar/utils/registration_error_message.dart`, `lib/admin_escolar/widgets/registro_equipo_widgets.dart` |
| App Check | `lib/services/app_check_bootstrap.dart` |
| Visualización de foto | `lib/alumnos/shared/alumno_common.dart`, `lib/alumnos/widgets/student_photo_avatar.dart` |
| Pruebas de servidor | `functions/test/security.test.js`, `functions/test/school_registration.test.js` |
| Pruebas de permisos e integración | `security-tests/firestore-storage.test.cjs`, `security-tests/school-registration.integration.test.cjs`, `firebase.registration-tests.json` |
| Pruebas Flutter | `test/app_check_bootstrap_test.dart`, `test/registration_errors_and_dialogs_test.dart`, `test/student_photo_avatar_test.dart` |
| Ejecución y documentación | `package.json`, este informe |

El árbol de trabajo ya contenía numerosos cambios y archivos nuevos de trabajos anteriores. No se reinició Git ni se descartaron esos cambios. Los archivos de compilación y logs de emuladores no representan una publicación.

## Verificación

| Comando o escenario | Resultado |
| --- | --- |
| `npm.cmd run test:security` | 96 pruebas aprobadas, 0 fallidas. Incluye validación, guardas de callable, revocación, atomicidad, reintentos y carreras de fotos. Parte de esta suite usa un almacén transaccional simulado. |
| `npm.cmd run test:rules` | 36 pruebas aprobadas, 0 fallidas en Firestore y Storage; incluye accesos legítimos anteriores y aislamiento de registro. Ejecutado por el especialista de reglas. |
| `npm.cmd run test:registration` | 5 pruebas aprobadas, 0 fallidas con SDKs reales y emuladores Auth, Firestore y Storage. Incluye token personalizado real de emulador, revocación, dos registros concurrentes por cupo, duplicados, `arrayUnion`, reintento, fecha conservada y lectura privada de foto. |
| `flutter test --no-pub test/student_photo_avatar_test.dart test/registration_errors_and_dialogs_test.dart test/registro_equipo_widgets_test.dart test/admin_back_button_test.dart test/auth_gate_sign_out_test.dart` | 24 pruebas aprobadas. Incluyen permiso de foto, renovación con clave exacta, borrador, aislamiento de fotos al cambiar de alumno, distribución adaptable y navegación. |
| `flutter test --no-pub --dart-define=VALMICH_APP_CHECK=true test/app_check_bootstrap_test.dart` | 2 pruebas aprobadas y 1 caso omitido porque comprueba la configuración contraria. Proveedor de app secundaria comprobado mediante canal simulado. |
| `flutter analyze --no-pub` sobre sesión, formulario, utilidades, widgets de registro, bootstrap, avatar y sus pruebas nuevas | Sin incidencias en el alcance indicado. No equivale a un análisis global limpio: el archivo de login mantiene avisos heredados. |
| `node --check functions/index.js` y `node --check functions/school_registration.js` | Sintaxis correcta. |
| Compilación web local | `flutter build web --no-pub --no-wasm-dry-run` produjo `build/web`. No se publicó. |

Los emuladores utilizaron exclusivamente `demo-edupro-security`, puertos loopback y datos sintéticos. La suite de integración falla antes de inicializar SDKs si algún endpoint no es local o el proyecto no corresponde. Solo se limpian sus datos de prueba. La prueba real mostró reintentos por contención y terminó sin exceder el cupo ni duplicar alumnos; no es una medición de capacidad o de latencia de producción.

Hubo fallos iniciales de fixtures y un selector de prueba de widget; se corrigieron y las ejecuciones finales indicadas pasaron. También se corrigió el exceso de expresiones de una lectura legítima detectado por el especialista de reglas y se repitió su suite completa.

## Revisión independiente

- Ciberseguridad revisó backend, sesión, reglas, índices, App Check y fotos. Ejecutó independientemente las 25 pruebas dedicadas de registro, aprobadas. Aprobó el cambio local revisado; no evaluó una publicación.
- El especialista de datos y reglas implementó y verificó las reglas con las 36 pruebas de emulador. Sus cambios fueron revisados por ciberseguridad.
- El revisor independiente de interfaz detectó el selector de foto incompatible con su permiso y aprobó la corrección posterior por inspección. No ejecutó el navegador completo.
- El coordinador ejecutó las pruebas adicionales con SDKs reales en emuladores, las pruebas Flutter y la compilación. Esa verificación no se presenta como una auditoría independiente de su propia implementación.

## Pendientes y recomendaciones

1. **Validación en entorno de prueba antes de publicar:** recorrer el flujo completo desde el navegador y un dispositivo, con la app Firebase secundaria, App Check, subida y visualización de foto. Los emuladores no acreditan CORS del bucket ni permisos reales para firmar tokens personalizados (`signBlob`) del servicio desplegado. No se ejecutó Functions HTTP en el emulador; se probaron sus guardas con harness y el módulo con SDKs reales.
2. **Coordinación del despliegue:** deben publicarse de forma compatible Functions, reglas, índices y cliente. Hay dos índices nuevos para las consultas de duplicados; verificar que estén listos antes de habilitar el cliente. Un cliente nuevo contra el backend anterior no dispone del token necesario.
3. **Sesión CLI remota:** la consulta de metadatos de Firestore no pudo completarse porque la credencial local de Firebase CLI venció. No se reautenticó al titular ni se modificaron credenciales. La edición del emulador es Standard; la edición y configuración remotas no quedaron verificadas en este trabajo.
4. **Limpieza:** definir retención y limpieza controlada de permisos y cuentas temporales vencidas, recibos y fotos abandonadas. El vencimiento limita acceso, no elimina automáticamente esos recursos.
5. **Altas externas:** los procesos administrativos que escriban por otras vías no participan en el bloqueo compartido de este flujo. No se afirma que el cupo sea globalmente inviolable si hay escritores ajenos a esta transacción.
6. **Rendimiento del listado:** la lista de este formulario aún consulta el grado completo. El conteo para guardar ya no descarga todos los expedientes; la paginación del listado sigue siendo un trabajo separado.
7. **Fotos heredadas:** no se revocaron ni migraron enlaces antiguos. Quien posea un enlace portador antiguo puede seguir usándolo conforme a su vigencia. Esta corrección evita producirlos para fotos nuevas.
8. **Zonas horarias:** se conserva el instante del selector, compatible con las fechas existentes del flujo actual. Verificar casos de registro desde zonas horarias muy distintas antes de extender ese supuesto.

No se considera aprobada una publicación con estos puntos de validación obligatoria pendientes. El proyecto exige además el informe de publicación y autorización explícita para la versión y destino concretos.

Referencias de diseño: [tokens personalizados de Firebase Auth](https://firebase.google.com/docs/auth/admin/create-custom-tokens), [condiciones de seguridad Firestore](https://firebase.google.com/docs/firestore/security/rules-conditions), [límites de lecturas de reglas Storage](https://firebase.google.com/docs/storage/security/rules-conditions).
