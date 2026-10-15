# Catálogo de colegios paginado y métricas agregadas

Implementado el 9 de octubre de 2026 en Panel, Análisis, Colegios, Red Escolar y
Facturación del equipo. Estas pantallas comparten el catálogo de la sesión y
ya no escuchan ni descargan toda la colección `schools` para construir sus listas.

## Consultas y navegación

- La interfaz solicita 25 colegios por página, con Anterior y Siguiente. El
  servidor admite entre 1 y 100 por solicitud y obtiene un registro adicional
  del índice para determinar si existe otra página. No descarga las demás páginas.
- La búsqueda se ejecuta en el servidor por inicio de nombre, palabra o código,
  ignorando mayúsculas y acentos. No es una búsqueda de subcadenas arbitrarias.
- Provincia también se filtra en el servidor. Facturación no recibe ese filtro.
- Los totales generales se calculan mediante una sola consulta agregada de
  conteo y sumas al índice. Permanecen independientes del buscador, la provincia
  y la página visible. El total de resultados filtrados se consulta por separado.
- Red Escolar muestra únicamente los marcadores de la página actual y lo indica
  en pantalla. Los contadores de colegios ubicados y sin ubicación son globales.
  Buscar, filtrar o avanzar permite consultar los otros colegios del mapa.
- La caché compartida conserva como máximo cinco páginas y vence a los dos
  minutos. Se invalida al cambiar de cuenta o rol. Actualizar fuerza otra lectura
  de la primera página y sus métricas; las acciones de modificación actualizan
  el catálogo compartido.
- Las consultas tienen una espera máxima de 30 segundos, error visible y
  reintento. Respuestas tardías de otra búsqueda, intento o sesión se descartan.

Las métricas agregadas evitan descargar documentos completos, pero siguen
consumiendo lecturas del índice: su coste no es constante al crecer el catálogo.
La caché reduce su repetición entre pantallas. No hay una suscripción global en
tiempo real; cambios realizados desde otra sesión aparecen al actualizar o al
vencer la caché.

## Permisos y datos

`listTeamSchools` conserva las comprobaciones de usuario, rol habilitado,
horario, App Check, verificación en dos pasos y cuota. El servidor selecciona
los campos que lee y vuelve a filtrar los campos que devuelve.

| Rol | Identidad y plan/límites | Contacto y ubicación | Facturación |
| --- | --- | --- | --- |
| Superadministrador | Sí | Sí | Sí |
| Operaciones | Sí | Sí | No |
| Soporte | Sí | Sí | No |
| Facturación | Sí | No | Sí |

Estos roles del equipo consultan el catálogo de la red con la proyección de
datos correspondiente. Los administradores escolares, docentes, alumnos y
usuarios sin autorización no obtienen acceso al catálogo del equipo. Esta
implementación no amplía sus permisos sobre `schools` ni sus subcolecciones.

Las colecciones auxiliares `team_school_catalog` y `team_catalog_meta` rechazan
lecturas y escrituras directas de clientes, incluso del superadministrador.
Solo el servidor accede a ellas. El índice no contiene correos de administradores,
contactos, contraseñas, datos de pagos ni información individual de alumnos.
Los documentos internos se excluyen antes de paginar y contar.

## Sincronización y despliegue

- `createSchool` crea el colegio y su entrada de catálogo en el mismo lote.
- `updateSchoolLocation` actualiza ubicación e índice en la misma transacción.
- `syncTeamSchoolCatalog` reconcilia otros cambios del documento del colegio.
  Relee el estado actual dentro de una transacción para tolerar eventos repetidos,
  atrasados y eliminaciones. Estos cambios se reflejan en el índice de forma
  eventual, según la entrega del evento.
- La inicialización controlada solo escribió el índice derivado, su marca de
  disponibilidad y una auditoría. No modificó los documentos de colegios ni las
  credenciales. Se verificaron siete colegios: siete indexados, cero faltantes,
  desactualizados, huérfanos o fallos.
- Se desplegaron las reglas, los tres índices necesarios y las funciones
  `listTeamSchools`, `createSchool`, `updateSchoolLocation` y
  `syncTeamSchoolCatalog` en `edupro-8c4fd`. Se conservaron los índices existentes
  de calendario y notificaciones. La inspección posterior confirmó las funciones,
  el disparador y las revisiones de los servicios operativos.

Para revisar sin escribir: `node scripts/backfill-team-school-catalog.cjs --verify-queries`.
La opción `--apply` es una inicialización administrativa
explícita y auditable; no se ejecuta al abrir la interfaz.

## Verificación

- Flutter: 86 pruebas aprobadas y una omisión previa; incluye once pruebas del
  catálogo, caché, paginación, búsqueda, cambio de sesión/rol y pantalla pequeña.
- Servidor: 58 pruebas aprobadas, incluyendo consultas limitadas, filtrado por
  rol, búsqueda fuera de la primera página y sincronización transaccional.
- Reglas en emuladores: 27 pruebas aprobadas; ningún rol cliente puede leer o
  modificar directamente el índice privado ni su configuración.
- Firebase después del despliegue: 14 comprobaciones de consultas reales por
  rol, filtros y métricas, con índice listo y sin discrepancias. Son lecturas
  administrativas del ayudante de consultas, no una prueba de login interactivo.
- Nueve endpoints desplegados respondieron HTTP 401 a solicitudes sin sesión.
- Compilación web correcta. El análisis de los archivos modificados no encontró
  errores; permanecen 40 advertencias y avisos en código previo de las pantallas.

La versión web compilada está en `build/web`; no se publicó Hosting en este
cambio. Para cargar el cliente nuevo en una sesión de `flutter run`, usar `R`
(reinicio completo) en esa terminal y recargar el navegador.

Documentación de Firebase: [paginación con cursores](https://firebase.google.com/docs/firestore/query-data/query-cursors),
[consultas agregadas](https://firebase.google.com/docs/firestore/query-data/aggregation-queries)
y [índices](https://firebase.google.com/docs/firestore/query-data/index-overview).
