-- Detección de sobregiro de stock (paso 8 del plan).
-- No se previene la venta en el momento (dos ventas offline pueden coincidir
-- sin que ningún dispositivo se entere). En cambio, se detecta post-sync:
-- apenas un movimiento de venta hace que el stock quede negativo, se marca
-- la venta como pendiente_revision para que un humano decida qué hacer.
-- Correr en el SQL Editor de Supabase.

create or replace function fn_check_sobregiro()
returns trigger as $$
declare
    v_stock numeric;
begin
    -- Solo nos importan movimientos de venta (los de 'ajuste'/'compra' son
    -- entradas manuales deliberadas del staff, no hay nada que revisar ahí).
    if new.motivo = 'venta' and new.venta_id is not null then
        select coalesce(sum(cantidad), 0) into v_stock
        from movimientos_stock
        where producto_id = new.producto_id
          and deposito_id = new.deposito_id;

        if v_stock < 0 then
            update ventas
            set estado = 'pendiente_revision'
            where id = new.venta_id;
        end if;
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_check_sobregiro on movimientos_stock;

create trigger trg_check_sobregiro
after insert on movimientos_stock
for each row
execute function fn_check_sobregiro();
