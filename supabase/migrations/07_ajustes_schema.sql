-- perfiles: 1 fila por usuario de auth.users, autocompletada por trigger.
create table perfiles (
  id uuid primary key references auth.users(id),
  email text not null,
  nombre text,
  creado_en timestamptz not null default now()
);

alter table perfiles enable row level security;
create policy "select perfiles" on perfiles for select to authenticated using (true);
create policy "update perfil propio" on perfiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
-- Sin policy de insert/delete: solo el trigger (security definer) escribe filas nuevas.

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, email, nombre)
  values (new.id, new.email, split_part(new.email, '@', 1));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill de los usuarios que ya existen (usuarios de prueba creados a mano).
insert into perfiles (id, email, nombre)
select id, email, split_part(email, '@', 1) from auth.users
on conflict (id) do nothing;

-- configuracion_tienda: fila única (se toma con ORDER BY creado_en LIMIT 1,
-- mismo patrón que el depósito implícito en Inventario/Punto de venta).
create table configuracion_tienda (
  id uuid primary key default gen_random_uuid(),
  nombre text not null default 'Tienda Centro',
  direccion text,
  horario_apertura text,
  horario_cierre text,
  moneda text not null default 'ARS',
  notif_banner_revision boolean not null default true,
  notif_stock_minimo_default numeric not null default 0,
  creado_en timestamptz not null default now()
);

alter table configuracion_tienda enable row level security;
create policy "select config tienda" on configuracion_tienda for select to authenticated using (true);
create policy "update config tienda" on configuracion_tienda for update to authenticated using (true) with check (true);

insert into configuracion_tienda (nombre) values ('Tienda Centro');

-- Publicación de PowerSync.
alter publication powersync add table perfiles, configuracion_tienda;
