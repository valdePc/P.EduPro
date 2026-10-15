# Agentes de EduPro

El proyecto dispone de doce perfiles de agentes para Codex en `.codex/agents/` y un flujo común en `AGENTS.md`. Cada perfil contiene su nombre, especialidad e instrucciones en español. Se adaptan a Flutter, Cloud Functions, Firestore y Storage y reutilizan las skills y pruebas existentes.

## Uso

Abre una sesión nueva de Codex en este proyecto para que lea los perfiles y `AGENTS.md`. La configuración local debe estar habilitada para el proyecto según los controles de confianza del cliente. Los perfiles heredan el modelo y los permisos de la sesión; hay un límite configurado de tres subagentes simultáneos, además del principal. Los doce roles pueden trabajar por tandas.

Ejemplos de solicitudes:

- «Usa edupro-ciberseguridad para revisar los permisos de equipo_edupro_access.dart y su validación en el backend».
- «Usa edupro-dominio-academico para revisar la coherencia entre calificaciones, recuperación y promoción, y preparar casos de aceptación para QA».
- «Usa edupro-facturacion-conciliacion para revisar cómo un pago confirmado actualiza la renovación y cómo se evitan duplicados».
- «Implementa esta funcionalidad con edupro-arquitecto y edupro-fullstack; después delega la revisión a edupro-auditor-codigo y las pruebas a edupro-qa».
- «Coordina una revisión previa a publicación con los agentes de EduPro y entrega el informe final para mi autorización».

Los especialistas se activan cuando Codex les delega una tarea. Estos archivos no ejecutan vigilancia permanente, pruebas automáticas en cada guardado ni bloqueos técnicos en Firebase/GitHub. Los controles de CI y protección de ramas se configuran como tareas separadas cuando se soliciten; instalar los perfiles no los crea.

Si el cliente no permite cargar agentes personalizados, Codex puede leer sus instrucciones y trabajar por roles secuencialmente, indicando que falta revisión independiente. El agente previo `.github/agents/edupro-architect.agent.md` se conserva; es una configuración distinta de estos perfiles de Codex.

## Publicación

El flujo exige revisión de ciberseguridad para cambios sensibles y un informe del coordinador final con evidencias, riesgos, versión y destino. La autorización final de cada publicación corresponde al usuario. Usa [la plantilla de publicación](plantilla-publicacion.md); crear un informe no acredita que se hayan ejecutado sus verificaciones.

Los agentes de revisión tienen instrucciones de no editar código; esto no constituye un sandbox independiente. Los permisos efectivos son los de la sesión y los del entorno.

## Archivos

- `AGENTS.md`: contexto, matriz de roles, delegación, comprobaciones y condiciones de publicación.
- `.codex/config.toml`: habilitación y concurrencia de agentes del proyecto.
- `.codex/agents/*.toml`: doce perfiles especializados.
- `docs/agentes/plantilla-publicacion.md`: evidencia requerida antes de solicitar autorización.

Formato comprobado contra la [documentación oficial de subagentes de Codex](https://learn.chatgpt.com/docs/agent-configuration/subagents). Los perfiles no fijan un modelo concreto para respetar la selección y disponibilidad de la sesión.
