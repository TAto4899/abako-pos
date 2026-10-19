-- Guarda el costo unitario de cada línea al momento de crear la orden, para
-- poder mostrar "importe a pagar" sin que se mueva si después se edita el
-- costo del producto en Inventario (mismo criterio que el resto de la app:
-- una venta vieja no cambia si el precio del producto cambia después).
alter table orden_compra_items add column if not exists costo_unitario numeric;

-- Columna en una tabla ya publicada: no hace falta tocar el stream de
-- PowerSync (mismo caso que productos.costo/productos.activo).
