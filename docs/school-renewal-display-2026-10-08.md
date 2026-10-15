# Renovación y pagos en la ficha del colegio

La ficha maestra y su etiqueta «Renueva» ahora dan prioridad a `billingNextDueAt`, la fecha que actualiza la transacción de confirmación de pagos en Facturación. `renewalAt` queda como respaldo de presentación si todavía no hay una fecha de facturación, para conservar la fecha inicial de los colegios antiguos.

`SchoolBillingDates` centraliza la lectura de las fechas de colegios. La vista del equipo de facturación utiliza el mismo criterio de presentación. Facturación sigue calculando el vencimiento y el estado con `billingNextDueAt`, sin convertir una renovación inicial en un pago confirmado. El calendario de cobro, la suma mensual y la transacción de revisión de pagos conservan su comportamiento.

La ficha separa ahora:

- «Estado del último reporte» y «Fecha del último reporte»: estado y fecha de creación del reporte consultado en el resumen operativo.
- «Último pago confirmado»: `billingLastPaidAt` del documento principal del colegio. La fecha del reporte no se utiliza como fecha de confirmación.

Se retiró «Observación»: su contenido era una explicación de desarrollo y no una nota registrada. No se inventó un campo de observaciones ni un historial.

Las fechas de renovación y pago confirmado se obtienen del registro principal recibido por el flujo existente del catálogo. Para el superadministrador, los cambios del documento llegan mediante la suscripción de Firestore; las fechas no dependen de la caché de dos minutos del resumen operativo. El catálogo del rol de facturación conserva su botón «Actualizar» y la lista de campos permitidos.

No se duplicó `billingNextDueAt` en `renewalAt`, no se migraron documentos y no se cambiaron reglas o funciones de Firebase. Esta corrección corresponde al cliente.

## Validación

58 pruebas de Flutter aprobadas y una previamente omitida. Las pruebas nuevas cubren la actualización de las dos fechas de facturación conservando una renovación inicial antigua, colegios sin confirmación, formatos Timestamp/DateTime/milisegundos y valores ausentes o inválidos. El análisis de los archivos afectados no encontró errores; permanecen avisos de estilo y elementos sin uso anteriores.

La compilación web terminó correctamente en `build/web`. No se publicó Hosting. Para ver el cambio en desarrollo hay que reiniciar la ejecución actual de Flutter y recargar el navegador.
