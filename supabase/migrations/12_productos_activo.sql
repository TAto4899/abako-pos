-- "Eliminar" un producto en realidad lo desactiva (no se borra la fila) —
-- movimientos_stock.producto_id referencia productos(id), y borrar de verdad
-- un producto con historial de ventas rompería esas referencias. Con activo
-- en false, el producto deja de aparecer en Inventario/Punto de venta/
-- Órdenes de compra, pero su nombre se sigue viendo bien en ventas viejas.
alter table productos add column if not exists activo boolean not null default true;
