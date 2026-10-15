# Indicadores de la ficha del colegio

La ficha del superadministrador ya no descarga completas las colecciones de docentes, alumnos, miembros, asignaturas, grados y planificaciones. Utiliza `getTeamSchoolSummary`, que mantiene los controles vigentes de rol, App Check, horario y segundo factor. Los roles operativos y soporte siguen recibiendo únicamente su resumen limitado.

## Lecturas y contadores

- Los seis totales utilizan consultas `count()` en el servidor. Firestore devuelve resultados agregados en lugar de los documentos; estas consultas siguen consumiendo recursos según los índices examinados. [Documentación de agregaciones](https://firebase.google.com/docs/firestore/query-data/aggregation-queries).
- Los indicadores que dependen de campos o listas se calculan al cambiar el registro original y se guardan como booleanos en cinco colecciones privadas `_operational_*`, dentro del colegio. El resumen cuenta esas marcas con índices simples. No se duplican nombres, correos, salud, notas ni contenidos de las planificaciones.
- Una consulta completa del superadministrador utiliza 19 agregaciones y hasta cuatro documentos proyectados: el último acceso, el último login, la membresía del UID del administrador principal y el último pago. La consulta de roles limitados utiliza solamente las seis agregaciones originales. No se solicita el comprobante de pago ni expedientes de alumnos.
- Los eventos leen el estado actual del registro en una transacción, en lugar de aplicar diferencias del evento recibido. Así, un evento repetido o entregado fuera de orden no duplica ni retrocede las cifras. Se conservan las reglas anteriores de `enabled`/`active` y de completitud de unidades. Las colecciones derivadas no generan nuevos eventos sobre las colecciones de origen. [Comportamiento de eventos de Firestore](https://firebase.google.com/docs/functions/firestore-events).
- Si la cantidad de filas derivadas todavía no coincide con el total de su colección, el indicador se devuelve como `null` y la interfaz explica que está pendiente de cálculo. Los eventos son asíncronos: una edición puede tardar unos instantes en reflejarse, incluso si ya coinciden las cantidades de documentos.

Las cinco funciones de eventos tienen CPU `gcf_gen1`, memoria de 256 MiB, una solicitud simultánea por instancia y el máximo global existente de tres instancias. Los reintentos están habilitados para recuperar fallos temporales. Este diseño incorpora lecturas y escrituras al actualizar registros, pero elimina las descargas completas por cada apertura o reconstrucción de la ficha y evita un contador central que reciba todas las escrituras del colegio.

## Caché y errores

`SchoolSummaryLoader` inicia la consulta en su ciclo de vida, no en `build`. Las búsquedas, cambios visuales y reconstrucciones del padre reutilizan el mismo Future. La caché existe únicamente en memoria, contiene como máximo 20 entradas y separa cuenta, rol y colegio. Al volver a abrir una ficha reutiliza la entrada durante dos minutos; la ficha abierta ofrece «Actualizar» para consultar cambios posteriores. Salir de la pantalla de Admin General elimina su caché.

Una consulta tiene un límite de espera de 30 segundos. Un fallo muestra una explicación y «Reintentar», sin iniciar un bucle automático ni dejar indicadores indefinidamente en puntos suspensivos. Cambiar de colegio no muestra los resultados de una solicitud lenta del colegio anterior. La respuesta se valida dentro del Future para que los datos malformados utilicen el mismo tratamiento de error.

## Inicialización y validación

`scripts/backfill-school-metrics.cjs` consulta identificadores en páginas de 200 registros y puede inicializar o reconciliar las filas derivadas con `--apply`. Sin ese parámetro es de solo lectura. Reutiliza la sesión existente de Firebase CLI en memoria; no crea claves de cuentas de servicio ni archivos con credenciales. No modifica los registros originales ni imprime datos personales.

La inspección inicial de `edupro-8c4fd` encontró siete colegios y dos registros de origen pendientes de inicialización. Las pruebas utilizan datos sintéticos, incluyendo 1.200 alumnos para comprobar que el resumen no descarga documentos de esa colección.

- Servidor: 39 pruebas aprobadas, incluyendo compatibilidad de datos antiguos, eventos repetidos, borrados, proyección de campos, cobertura incompleta y aislamiento de roles.
- Flutter: 51 pruebas aprobadas y una omitida previamente; caché, expiración, límite de memoria, reconstrucciones, actualización explícita, error, reintento, selección de colegio y móvil.
- Reglas Firestore/Storage: 26 pruebas aprobadas. Ningún cliente, incluido el superadministrador, puede leer o falsificar las colecciones derivadas directamente.
- Compilación web de producción correcta. El análisis no encontró errores de compilación; Admin General conserva avisos previos de estilo y miembros sin uso.

## Publicación comprobada

Se publicaron `getTeamSchoolSummary` y las cinco funciones `syncSchool*Metrics` en `edupro-8c4fd`. Firebase confirmó las seis funciones activas, las últimas revisiones listas y los cinco eventos de Eventarc presentes. El primer intento de eventos recibió un error de propagación de permisos del agente administrado de Google. La consulta de IAM confirmó que su rol estándar ya estaba asignado: no se modificaron permisos de usuarios ni del proyecto. El reintento terminó correctamente.

Tras activar los eventos se reconciliaron las filas derivadas y se verificaron las consultas limitadas en los siete colegios existentes: dos registros de origen, dos filas derivadas y ningún colegio con cobertura incompleta. No se modificaron documentos originales ni se usaron datos de prueba en producción. Los ocho endpoints revisados sin sesión devolvieron HTTP 401, incluido el resumen optimizado.

El cliente actualizado está compilado en `build/web`; no se publicó Hosting. En desarrollo hay que reiniciar Flutter y recargar el navegador para cargar la nueva ficha.
