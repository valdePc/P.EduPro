# Plan de pruebas de autenticación — 2026-10-14

## Alcance y evidencia

Diagnóstico local y validación de cambios de autenticación. Sin despliegues ni pruebas sobre datos de producción. Los cambios de aplicación y pruebas pertenecen a los especialistas asignados; este documento registra la coordinación QA.

Baseline anterior a la implementación, obtenido el 13 de octubre:

| Comando | Resultado |
| --- | --- |
| `npm.cmd run test:security` | 58 aprobadas, 0 fallidas, código 0 |
| `flutter test --no-pub` | 86 aprobadas, 1 omitida, código 0 |
| `flutter analyze --no-pub` | 930 incidencias, código 1; salida truncada, sin desglose fiable por severidad |

La omisión Flutter corresponde a la alternativa de configuración App Check en `test/app_check_bootstrap_test.dart`; ambas ramas deben ejecutarse con sus configuraciones correspondientes. Estos resultados no constituyen aprobación de los cambios posteriores.

Ejecución del 14 de octubre:

| Comando | Resultado y evidencia |
| --- | --- |
| `npm.cmd run test:rules` | 27 aprobadas, 0 fallidas, 0 omitidas; código 0. Log: `audit-auth-rules-2026-10-14.log` |

Se configuró `JAVA_HOME=C:/Program Files/Android/Android Studio/jbr` y se añadió su directorio `bin` al PATH del proceso. El script usa `demo-edupro-security`, `firebase.security-tests.json` y exclusivamente emuladores Firestore/Storage. La suite restringe los endpoints a loopback y usa fixtures sintéticos. El primer intento restringido falló por EPERM al acceder a la configuración local de Firebase CLI; la repetición con escalación completó correctamente. El log actual corresponde a la ejecución exitosa.

## Matriz de regresión

| Área | Casos | Evidencia existente / trabajo pendiente |
| --- | --- | --- |
| Identidad | Correo no verificado, usuario deshabilitado, perfiles conflictivos, rol desconocido | `client_security_test.dart`, suite Node y reglas; añadir regresiones de los defectos corregidos |
| Permisos | Rol y escuela propia/ajena, revocación con claims antiguos, cambio de rol durante sesión | Suite Node, reglas, `team_permissions_test.dart` |
| MFA | Factor requerido, expiración, cambio de autenticación, reutilización, concurrencia, bloqueo y enrolamiento | Suite Node; ampliar límites que cambie el endurecimiento |
| App Check | Deshabilitado, token ausente/inválido, error de activación y configuración habilitada | `app_check_bootstrap_test.dart`; ejecutar ambas configuraciones |
| Sesión cliente | Logout/cambio de usuario durante petición, respuesta tardía, timeout y fallo de red | `auth_gate_sign_out_test.dart`, `team_access_gate_test.dart` |
| Reautenticación | Rechazo/cancelación de comprobación adicional, conservar identidad inicial y rechazar credencial de otra cuenta | Pendiente de pruebas específicas del cambio cliente |
| SDK directo | Evitar callables, manipular campos de permisos, leer datos de otra escuela | Suite de reglas emulada; 27 casos aprobados |
| Recorrido completo | Login, selección de escuela, operación permitida, revocación y petición posterior denegada | Recorrido UI de EduPro pendiente; se añadió emulador Auth aislado y pruebas REST del proveedor |

## Límites y cierre pendiente

Los handlers Node se ejecutan con un almacenamiento aislado simulado; los tests de widgets no son E2E. Las pruebas REST de Auth añadidas al cierre prueban el emulador del proveedor, no todas las políticas de producción ni el recorrido UI de EduPro. No se han comprobado navegadores o dispositivos físicos ni se ha medido cobertura porcentual.

Flutter requiere acceso a la caché del SDK fuera del proyecto. El lanzador `C:/src/flutter/bin/internal/shared.bat` reintenta la apertura de `flutter.bat.lock` silenciosamente cuando no puede escribir; las ejecuciones autorizadas con escalación funcionaron. No ejecutar comandos Flutter simultáneamente.

Tras finalizar la implementación: ejecutar suite Node actualizada, tests Flutter afectados y suite completa, configuración alternativa App Check y análisis estático con log íntegro. Comparar con baseline sin atribuir deuda anterior al cambio. Registrar resultados finales y revisión independiente antes de cualquier dictamen de publicación.

## Validación posterior a los cambios

Ejecutada secuencialmente el 14 de octubre, sin modificar código de aplicación:

| Comando | Resultado | Log |
| --- | --- | --- |
| `flutter test --no-pub` | 88 aprobadas, 1 omitida; código 0. Incluye las nuevas pruebas `auth_input_validation_test.dart` | `audit-auth-flutter-2026-10-14.log` |
| `flutter test --no-pub --dart-define=VALMICH_APP_CHECK=true test/app_check_bootstrap_test.dart` | 1 aprobada, 1 omitida; código 0. Ejecuta la rama habilitada y omite la deshabilitada | `audit-auth-appcheck-2026-10-14.log` |
| `flutter analyze --no-pub` | 0 errores, 130 advertencias y 800 informaciones; 930 incidencias, código 1 | `audit-auth-analyze-2026-10-14.log` |

El número total de incidencias estáticas coincide con el baseline (930); no existe salida inicial íntegra suficiente para afirmar igualdad caso por caso. No aparecen diagnósticos para el nuevo helper de validación ni sus pruebas. Las advertencias e informaciones restantes impiden declarar limpio el análisis global.

Al cierre, el coordinador ejecutó la suite actualizada: 69/69 pruebas Node aprobadas, incluyendo parche de proxy y validación de alta de colegio. Repitió Flutter después del último cambio cliente: 88 aprobadas y 1 omisión condicional, código 0. El emulador Auth aislado pasó 4/4 pruebas REST de acceso, rechazo de credenciales, recuperación y verificación; estas pruebas no recorren la interfaz completa de EduPro. El revisor independiente ejecutó 57/57 pruebas de handlers/proxy. Los logs y limitaciones detalladas están en `auth-security-audit-2026-10-14.md`.
