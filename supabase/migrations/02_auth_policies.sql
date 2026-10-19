-- Reemplazo de las políticas RLS temporales (dev_temporal_todo_acceso, rol anon)
-- por políticas basadas en autenticación real (rol authenticated).
-- Correr en el SQL Editor de Supabase.

-- 1. Borrar las políticas temporales de acceso anónimo total.
drop policy if exists dev_temporal_todo_acceso on depositos;
drop policy if exists dev_temporal_todo_acceso on productos;
drop policy if exists dev_temporal_todo_acceso on movimientos_stock;
drop policy if exists dev_temporal_todo_acceso on ventas;

-- 2. depositos: acceso completo para cualquier usuario autenticado.
create policy depositos_authenticated_all
    on depositos
    for all
    to authenticated
    using (true)
    with check (true);

-- 3. productos: acceso completo para cualquier usuario autenticado.
create policy productos_authenticated_all
    on productos
    for all
    to authenticated
    using (true)
    with check (true);

-- 4. ventas: acceso completo para cualquier usuario autenticado
--    (necesita UPDATE más adelante para marcar estado = 'pendiente_revision').
create policy ventas_authenticated_all
    on ventas
    for all
    to authenticated
    using (true)
    with check (true);

-- 5. movimientos_stock: SOLO select + insert. Nunca update/delete,
--    reforzando la regla append-only también a nivel de base de datos.
create policy movimientos_stock_authenticated_select
    on movimientos_stock
    for select
    to authenticated
    using (true);

create policy movimientos_stock_authenticated_insert
    on movimientos_stock
    for insert
    to authenticated
    with check (true);
