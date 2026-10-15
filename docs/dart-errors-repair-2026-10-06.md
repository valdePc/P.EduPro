# Reparación de errores Dart — 2026-10-06

El análisis completo pasó de **215 errores** a **0 errores**. No se excluyeron archivos ni se deshabilitaron reglas del analizador. Tras corregir las advertencias de `main.dart`, el resultado conserva **134 advertencias** y **789 avisos informativos**, en su mayoría sobre código sin uso y APIs obsoletas. Esos avisos requieren una limpieza separada porque varios archivos tienen cambios de trabajo y reglas de acceso sensibles.

Cambios concretos:

- La agenda de administración usa el servicio y modelo de calendario vigentes, que resuelven la identidad y el rol del usuario antes de crear una cita. El servicio antiguo conserva su contrato y ahora importa el enum `UserRole` desde su ubicación real. Los errores de Firestore ya no se muestran íntegros en la interfaz.
- El inicio de administración recuperó las seis páginas y sus elementos de navegación. Las llamadas de la pizarra conservan los índices existentes.
- Doce pestañas de perfiles importan `alumno_ui.dart` desde la ubicación correcta. El archivo de avisos inválido reutiliza la pantalla de avisos existente.
- Tres archivos `.dart` que contenían React/TypeScript se convirtieron a un modelo Dart, una tarjeta Flutter de docentes y un gráfico Flutter. El gráfico admite desplazamiento horizontal cuando hay muchos períodos.
- El panel de competencias usa un servicio opcional y mantiene la suscripción estable al reconstruirse. La utilidad web de errores usa la interoperabilidad JavaScript actual de Dart.
- La dependencia usada por la prueba de App Check se declaró directamente en `dev_dependencies`.

Verificación: `flutter analyze --no-pub` encontró 0 errores; `flutter build web --no-pub --no-wasm-dry-run` compiló; pasaron las pruebas de interfaz, roles, sesiones, horarios y App Check. La rama activa de App Check pasó también con `--dart-define=VALMICH_APP_CHECK=true`. La prueba del gráfico incluye una pantalla de 320 píxeles con 12 períodos. No se hizo un inicio de sesión interactivo con credenciales ni un despliegue de Firebase.

El error del editor en `EduProTwoFactorService._call` puede persistir si VS Code mantiene una versión sin guardar de `app_check_bootstrap.dart`: el método `ensureReadyForProtectedCall` existe en el archivo del disco y el analizador completo no lo marca como error. Ambas versiones están respaldadas en `.editor-recovery/2026-10-05-save-conflicts/`. Para resolver el conflicto de guardado, comparar la pestaña y usar **File: Revert File** después de conservar cualquier cambio nuevo del editor; **Overwrite** restauraría la versión antigua.

En una revisión posterior, `main.dart` mostraba cinco advertencias propias y una referencia subrayada a `AppCheckBootstrap.strict`. Las cinco advertencias se corrigieron. El método `strict` existe en el archivo guardado, pero la copia antigua que retiene VS Code carece de él y de `ensureReadyForProtectedCall`. Se abrió otra ventana de VS Code con `code --new-window .` para cargar el proyecto desde disco, conservando intactas las pestañas de la ventana anterior. El análisis dirigido de `main.dart`, `app_check_bootstrap_test.dart` y `client_security_test.dart` da **0 errores y 0 advertencias**; las pruebas de ambos archivos pasan y la compilación web también. La ventana anterior puede seguir mostrando diagnósticos de sus buffers sin guardar.
