# Equipo de agentes de EduPro

## Contexto y reglas comunes

- Responde en español. EduPro usa Flutter/Dart en `lib/` y Firebase con Cloud Functions Node.js en `functions/`, Firestore y Storage.
- Lee el estado de Git antes de editar. Conserva todos los cambios previos del usuario, incluidos archivos nuevos y cambios preparados. Limita el trabajo al pedido actual.
- Usa evidencia del repositorio; no inventes resultados, pruebas, métricas ni aprobaciones. Diferencia lo comprobado de lo pendiente.
- Nunca incluyas contraseñas, tokens, cuentas de servicio ni datos personales de estudiantes en código, informes o fixtures. Usa datos sintéticos y emuladores.
- Respeta los permisos del entorno. Los perfiles de agentes no conceden acceso adicional ni sustituyen controles técnicos.
- Las tareas locales autorizadas de implementación, pruebas y corrección no requieren una nueva autorización por cada paso. Una publicación requiere autorización explícita del usuario para esa versión y destino después del informe final.

## Delegación

Para trabajo de implementación o revisión que se beneficie de especialistas, delega en los agentes correspondientes de `.codex/agents/`. El agente principal coordina; no invoques todos los agentes para cada cambio trivial. Ejecuta revisiones independientes en paralelo cuando sea útil, respetando el límite disponible. Asigna archivos concretos a cada escritor y evita escrituras simultáneas sobre el mismo archivo. Los especialistas devuelven resultados al principal y no crean cadenas de delegación por su cuenta.

Si la sesión no permite cargar perfiles o delegar, lee las instrucciones del perfil correspondiente y aplica sus controles secuencialmente. Informa esta limitación; no presentes una revisión propia como auditoría independiente.

| Agente | Cuándo participa |
| --- | --- |
| `edupro-ciberseguridad` | Prioridad crítica: autenticación, permisos, sesiones, APIs, secretos, reglas y datos personales; obligatorio antes de publicar cambios sensibles. |
| `edupro-arquitecto` | Nuevos módulos, cambios de contratos, dependencias, estructura y escalabilidad. |
| `edupro-fullstack` | Implementación de Flutter, Functions y lógica de negocio siguiendo el diseño acordado. |
| `edupro-auditor-codigo` | Revisión independiente del código implementado y sus riesgos de regresión. |
| `edupro-qa` | Pruebas unitarias, widgets, integración y flujos completos según el alcance. |
| `edupro-datos-privacidad` | Modelos, consultas, reglas, índices, integridad y datos de estudiantes. |
| `edupro-uiux-accesibilidad` | Interfaces, navegación, formularios, adaptación y accesibilidad. |
| `edupro-rendimiento` | Consultas, listas, red, carga, memoria y operaciones costosas. |
| `edupro-devops` | CI, entornos, secretos, compilación, monitoreo, despliegue y reversión. |
| `edupro-dominio-academico` | Reglas de notas, recuperaciones, asistencia, promoción, egreso y cierre escolar; valida criterios con responsables educativos y entrega casos a QA. |
| `edupro-facturacion-conciliacion` | Planes, importes, pagos reportados/confirmados, conciliación, renovaciones, duplicados, anulaciones y trazabilidad. |
| `edupro-coordinador-final` | Consolidación de evidencias y dictamen previo a cada publicación. |

## Flujo de trabajo

1. Define alcance, criterios de aceptación, archivos y revisiones aplicables. El arquitecto interviene cuando hay decisiones estructurales; el diseño puede aprobarlo técnicamente el coordinador dentro del alcance pedido. Incluye Dominio Académico al cambiar cálculos o decisiones escolares y Facturación y Conciliación al cambiar importes, estados de pago o renovaciones. Ambos entregan reglas y ejemplos verificables a Full Stack y QA; no inventan criterios de negocio faltantes.
2. Para cambios sensibles, identifica amenazas y controles con ciberseguridad antes de implementar. Incluye datos y privacidad cuando corresponda.
3. Implementa cambios mínimos. Ejecuta las pruebas pertinentes y corrige fallos atribuibles al cambio.
4. Solicita revisión independiente al auditor de código y a los especialistas afectados. Ciberseguridad revisa el resultado final de todo cambio sensible antes de publicar. Un cambio posterior que afecte la revisión exige revisarla nuevamente.
5. Antes de publicar, el coordinador final recoge el estado de los doce roles: `APROBADO`, `BLOQUEADO`, `NO EJECUTADO` o `NO APLICA` con motivo y evidencia. No sustituye revisiones faltantes con una aprobación general.
6. Presenta el informe de `docs/agentes/plantilla-publicacion.md`, la versión concreta, el entorno destino y la reversión. Riesgos críticos o altos pendientes y controles obligatorios no ejecutados bloquean el dictamen favorable. Espera autorización explícita del usuario para esa publicación; una autorización ya otorgada para la misma versión y destino no se pide de nuevo.

## Comprobaciones disponibles

Ejecuta desde la raíz solo las comprobaciones pertinentes. En PowerShell puede usarse `npm.cmd` si `npm` está bloqueado por la política de scripts.

- `flutter analyze --no-pub`: análisis estático cuando las dependencias estén disponibles.
- `flutter test --no-pub`: pruebas Flutter; pueden seleccionarse archivos específicos de `test/`.
- `npm run test:security`: pruebas Node de seguridad, catálogo, métricas y migración.
- `npm run test:rules`: Firestore y Storage en emuladores con `firebase.security-tests.json` y proyecto `demo-edupro-security`; requiere Firebase CLI y Java compatibles.
- `npm run audit:secrets`: búsqueda de secretos, incluido historial; redacta los valores sensibles al informar resultados.
- `flutter build web --no-wasm-dry-run`: compilación web cuando el cambio lo requiera; compilar no es publicar.
- No des por existentes pruebas E2E, dispositivos disponibles, CI, backups o monitoreo: inspecciona su configuración y reporta lo que falte.

Usa las skills locales de `.agents/skills/` cuando correspondan: `firebase-firestore`, `firestore-rules-creation`, `flutter-add-widget-test` y `flutter-add-integration-test`. Para reglas Firestore sigue la delegación que indique la skill si su especialista está disponible; si no, aplica la alternativa documentada.

## Entregables

Cada especialista entrega alcance, archivos, hallazgos con severidad y evidencia, comprobaciones ejecutadas con resultado, limitaciones y dictamen. El coordinador conserva la independencia entre quien implementa y quien audita. No publiques, despliegues ni alteres datos de producción como parte de una revisión.
