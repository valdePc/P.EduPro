# Colegios y Análisis en pantallas estrechas

Ambas vistas utilizan `SchoolMasterDetailLayout`. El diseño se decide por el ancho disponible del panel después del menú lateral, con `LayoutBuilder`, en lugar del ancho completo del navegador.

- A partir de 960 px disponibles se muestran lista y detalle juntos. La lista utiliza una proporción del espacio, limitada entre 280 y 380 px.
- Con menos espacio se muestra primero la lista a todo el ancho. Pulsar un colegio abre su detalle a todo el ancho, con «Volver a la lista de colegios».
- El botón de regreso y el regreso del sistema recuperan la lista. La búsqueda y el identificador seleccionado se conservan. El controlador de búsqueda pertenece a Admin General y se libera al salir de la pantalla.
- El buscador limita su ancho al espacio disponible. El encabezado de la lista puede desplazarse cuando hay poca altura, sin expulsar sus resultados fuera de la pantalla.
- La ficha no consulta el resumen mientras está oculta en el flujo móvil. Al volver a abrirla utiliza la caché existente por cuenta, rol y colegio; cambiar el tamaño no inicia consultas por cada reconstrucción.

Los campos de la ficha colocan el valor debajo de su etiqueta en anchos menores de 480 px. El aviso del resumen y su botón de actualización se reorganizan en columnas y pueden desplazarse con poca altura o texto ampliado.

En Análisis se corrigió la cabecera que colocaba `Expanded` dentro de una columna sin altura limitada. Sus grupos de indicadores ahora distribuyen de una a tres columnas según ancho y escala de texto. Los datos consultados y los controles de permisos conservan su funcionamiento.

## Validación

Pasaron 66 pruebas de Flutter, con una omisión previa. Las siete pruebas nuevas utilizan el componente real de ambas vistas, el cargador real del resumen y la cabecera real de Análisis. Cubren 320 y 360 px de ancho, orientación horizontal con cabecera de aplicación, texto ampliado, cambio de tamaño de ventana con menú lateral, regreso de botón y sistema, búsqueda conservada, ausencia de selección, campos estrechos y grupos de métricas.

La compilación web terminó correctamente y el análisis no encontró errores en los archivos afectados. Permanecen avisos de estilo y elementos sin uso anteriores. El cliente está compilado en `build/web`; no se publicó Hosting. No se modificaron funciones, reglas ni documentos de Firebase.

Para ver el cambio en desarrollo hay que reiniciar la ejecución actual de Flutter y recargar el navegador.
