-- Test del trigger de sobregiro (correr DESPUÉS de pos_stock_sobregiro_trigger.sql).
-- Simula dos ventas offline que "no se enteraron" una de la otra:
-- Venta A consume todo el stock disponible (queda en 0, no dispara nada).
-- Venta B vende 1 unidad más sobre ese mismo producto/depósito, quedando en -1
-- → el trigger debería marcarla como 'pendiente_revision'.
-- Usa el producto/depósito de prueba ya existentes en el proyecto y dos IDs de
-- venta fijos (no aleatorios) para poder consultarlos después sin copiar nada.

do $$
declare
    v_producto_id  uuid := 'f5f93ccc-a5a2-45cb-b782-bea20bbdb61d';
    v_deposito_id  uuid := 'dbc0dce3-33e9-4149-938e-c4034d2925c4';
    v_venta_a_id   uuid := 'a0000000-0000-0000-0000-000000000001';
    v_venta_b_id   uuid := 'a0000000-0000-0000-0000-000000000002';
    v_stock_actual numeric;
begin
    select coalesce(sum(cantidad), 0) into v_stock_actual
    from movimientos_stock
    where producto_id = v_producto_id
      and deposito_id = v_deposito_id;

    raise notice 'Stock actual antes del test: %', v_stock_actual;

    -- Venta A: consume todo el stock disponible, queda en 0 exacto (no dispara el trigger).
    insert into ventas (id, deposito_id, total, estado)
    values (v_venta_a_id, v_deposito_id, v_stock_actual, 'confirmada');

    insert into movimientos_stock (producto_id, deposito_id, cantidad, motivo, venta_id)
    values (v_producto_id, v_deposito_id, -v_stock_actual, 'venta', v_venta_a_id);

    -- Venta B: la "segunda" venta offline que choca con la primera.
    insert into ventas (id, deposito_id, total, estado)
    values (v_venta_b_id, v_deposito_id, 1, 'confirmada');

    insert into movimientos_stock (producto_id, deposito_id, cantidad, motivo, venta_id)
    values (v_producto_id, v_deposito_id, -1, 'venta', v_venta_b_id);
end $$;

-- Verificación 1: A debe seguir 'confirmada', B debe haber quedado 'pendiente_revision'.
select id, estado, total
from ventas
where id in (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
)
order by total;

-- Verificación 2: el stock quedó en -1 (el trigger detecta, no corrige ni previene).
select *
from stock_actual
where producto_id = 'f5f93ccc-a5a2-45cb-b782-bea20bbdb61d'
  and deposito_id = 'dbc0dce3-33e9-4149-938e-c4034d2925c4';

-- Cleanup opcional después de revisar (movimientos_stock NO se puede borrar, es
-- append-only a propósito — el -1 de sobregiro queda en el historial real. Esto
-- es consistente con las pruebas anteriores del proyecto, que también dejaron
-- movimientos reales de test en la tabla).
-- delete from ventas where id in (
--     'a0000000-0000-0000-0000-000000000001',
--     'a0000000-0000-0000-0000-000000000002'
-- );
