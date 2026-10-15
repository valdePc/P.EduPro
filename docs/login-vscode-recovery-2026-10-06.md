# App Check 403 y conflictos de guardado en VS Code

El registro aportado muestra `403` en `exchangeDebugToken`: la aplicación activa App Check, pero Firebase rechaza el token de su navegador de desarrollo. La ventana inspeccionada usaba `http://localhost:50516`, distinto del origen `http://localhost:55595` comprobado anteriormente.

Se autorizó ese navegador con un token privado nuevo y se comprobó su emisión real. La llamada de prueba sin sesión llegó al controlador y recibió `Debes iniciar sesion.`, conservando la autenticación obligatoria. No se cambiaron roles, horarios, contraseñas, reglas ni enforcement.

## Evitar cambios de origen desde VS Code

`.vscode/settings.json` fija `--web-port=55595` y `--web-hostname=localhost` para las ejecuciones de Flutter iniciadas por la extensión, incluido F5 sin configuración explícita. El perfil **EduPro Web (App Check)** selecciona Chrome. La terminal necesita los mismos argumentos:

```powershell
flutter run -d chrome --web-port=55595 --web-hostname=localhost
```

No mantener dos ejecuciones Chrome de Flutter sobre la misma caché. Un perfil nuevo, otro origen, `flutter clean` o pérdida de la caché pueden requerir registrar de nuevo el token de desarrollo; no hay una exención de App Check para cualquier navegador.

## Conflictos del editor

Se recuperaron los respaldos de los tres documentos abiertos en VS Code y se guardaron ambas versiones en `.editor-recovery/2026-10-05-save-conflicts/`, fuera del seguimiento de Git y con extensión `.txt`. No se modificaron los buffers vivos ni los respaldos internos de VS Code.

La comparación encontró versiones anteriores en los buffers:

| Archivo | Correcciones que ya tiene la versión en disco |
| --- | --- |
| `app_check_bootstrap.dart` | Activación web, proveedor Enterprise, comprobación del token y errores controlados. |
| `login_general.dart` | Cierre de sesión ante fallos y mensajes que no revelan datos internos. |
| `acceso_enlace_screen.dart` | Validación de enlaces, accesibilidad y adaptación a pantallas pequeñas. |

No pulsar **Overwrite**, porque restauraría versiones anteriores. Para cada uno de esos tres archivos, abrir la pestaña y usar **Ctrl+Shift+P → File: Revert File** (Archivo: Revertir archivo). Esto vuelve a cargar el contenido guardado en disco; no ejecuta `git revert`. Las versiones anteriores permanecen en las copias de recuperación. Si se hicieron cambios después de obtener esas copias, usar **Compare** y conservarlos antes de recargar.

Después iniciar **EduPro Web (App Check)** con F5. Los conflictos de buffers requieren esta acción en el editor; las herramientas disponibles no proporcionan acceso al estado vivo de sus pestañas.

## Resultado del análisis

El análisis de seguridad de `main.dart`, las dos pantallas y los dos servicios terminó con **0 errores**. Después se reparó también el resto del proyecto: el análisis global registra **0 errores**, con advertencias y avisos de mantenimiento aún pendientes. Los detalles y pruebas figuran en `dart-errors-repair-2026-10-06.md`. El mensaje general **Errors exist in your project** del editor puede persistir por un buffer sin guardar o por esas advertencias; por sí solo no demuestra que Firebase haya rechazado al usuario.

Fuentes: [configuración de ejecución Dart Code](https://dartcode.org/docs/settings/#dartflutterrunadditionalargs), [proveedor debug App Check](https://firebase.google.com/docs/app-check/web/debug-provider).
