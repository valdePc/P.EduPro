# Filtro único de documentos internos

Admin General, Colegios, Red Escolar y la vista del equipo de facturación reciben sus colegios desde `TeamSchoolAccessService.watchSchools()`. Se retiraron las reglas locales duplicadas de las pantallas, incluida la comparación exacta con `ValMichapp_admin_` de Admin General.

El servicio utiliza `isInternalSchoolDocumentId` de `lib/utils/school_document_id.dart`: excluye documentos cuyo ID empieza por `valmichapp_admin_` o `eduproapp_admin_`, sin distinguir mayúsculas. Filtra tanto la suscripción de Firestore del superadministrador como las respuestas del catálogo de roles limitados. Los documentos internos se excluyen antes de calcular totales, aplicar búsquedas o construir puntos del mapa.

La normalización se usa exclusivamente para reconocer el prefijo. El ID original de cada colegio real se conserva al consultar su ficha, sus miembros y demás colecciones. Un ID que contiene esas palabras en otra posición no se descarta.

`listTeamSchools` ya utiliza ambos prefijos con una expresión regular sin distinción de mayúsculas. La prueba nueva recorre páginas de un documento para los cuatro roles internos: verifica que una página filtrada vacía no interrumpe el catálogo, que el cursor avanza y que los colegios reales posteriores siguen apareciendo. No fue necesario cambiar ni desplegar funciones o reglas, ni modificar documentos de Firebase.

Las 50 pruebas del servidor y la migración pasaron. La prueba del cliente incluye ambas marcas, mayúsculas mixtas, colegios reales con nombres parecidos y conservación del ID original. El análisis de los archivos afectados no encontró errores de compilación; conserva avisos previos de estilo y elementos sin uso.

Pasaron también las 59 pruebas de Flutter, con una omisión previa, y la compilación web. El cliente está compilado en `build/web`; no se publicó Hosting. En desarrollo hay que reiniciar la ejecución actual de Flutter y recargar el navegador.
