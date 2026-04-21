-- ═══════════════════════════════════════════════════════════════
-- SusaRest — Supabase Setup
-- Run this in: Supabase Dashboard > SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── Enable UUID extension ──
create extension if not exists "uuid-ossp";

-- ══════════════════════════
-- TENANTS
-- ══════════════════════════
create table if not exists public.tenants (
  id             text primary key,               -- e.g. 'steakhouse1'
  name           text not null,
  emoji          text not null default '🍽️',
  initials       text,
  phone          text,
  email          text,
  address        text,
  ig             text,
  fb             text,
  currency       text not null default 'MXN',
  tax            numeric not null default 16,
  plan           text not null default 'free',   -- free | pro | enterprise
  primary_color  text not null default '#1a472a',
  primary_light  text not null default '#e8f0ea',
  fc_meta        numeric not null default 28,
  fc_alert       numeric not null default 32,
  fc_crit        numeric not null default 35,
  margin_goal    numeric not null default 68,
  created_at     timestamptz default now()
);

-- ══════════════════════════
-- USERS  (extends auth.users)
-- ══════════════════════════
create table if not exists public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  tenant_id  text references public.tenants(id) on delete cascade,
  role       text not null default 'tenant',  -- tenant | susazon_admin
  created_at timestamptz default now()
);

-- ══════════════════════════
-- INGREDIENTS (inventory)
-- ══════════════════════════
create table if not exists public.ingredients (
  id          serial primary key,
  tenant_id   text not null references public.tenants(id) on delete cascade,
  name        text not null,
  cat         text not null default 'seco',
  unit        text not null default 'kg',
  buy_unit    text,
  stock       numeric not null default 0,
  min_stock   numeric not null default 0,
  cost        numeric not null default 0,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);
create index if not exists idx_ingredients_tenant on public.ingredients(tenant_id);

-- ══════════════════════════
-- RECIPES
-- ══════════════════════════
create table if not exists public.recipes (
  id          serial primary key,
  tenant_id   text not null references public.tenants(id) on delete cascade,
  name        text not null,
  cat         text not null default 'plato_fuerte',
  portions    numeric not null default 1,
  price       numeric,
  margin_goal numeric,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);
create index if not exists idx_recipes_tenant on public.recipes(tenant_id);

-- Recipe ingredients (junction)
create table if not exists public.recipe_ingredients (
  id          serial primary key,
  recipe_id   integer not null references public.recipes(id) on delete cascade,
  ingredient_id integer not null references public.ingredients(id) on delete cascade,
  qty         numeric not null,
  unit        text not null default 'kg'
);
create index if not exists idx_ri_recipe on public.recipe_ingredients(recipe_id);

-- ══════════════════════════
-- ORDERS  (órdenes de compra)
-- ══════════════════════════
create table if not exists public.orders (
  id          text primary key,               -- e.g. 'OC-0038'
  tenant_id   text not null references public.tenants(id) on delete cascade,
  date        date not null,
  supplier    text not null default 'SusaRest Supply',
  status      text not null default 'pendiente',  -- pendiente | enviada | recibida
  items_count integer not null default 0,
  total       numeric not null default 0,
  delivery    date,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);
create index if not exists idx_orders_tenant on public.orders(tenant_id);

-- Order line items
create table if not exists public.order_items (
  id            serial primary key,
  order_id      text not null references public.orders(id) on delete cascade,
  ingredient_id integer references public.ingredients(id),
  name          text not null,
  cat           text,
  qty           numeric not null,
  unit          text not null,
  unit_cost     numeric not null,
  subtotal      numeric not null
);

-- ══════════════════════════
-- ALERTS
-- ══════════════════════════
create table if not exists public.alerts (
  id          serial primary key,
  tenant_id   text not null references public.tenants(id) on delete cascade,
  type        text not null,   -- stock | fc | order
  title       text not null,
  description text,
  severity    text not null default 'warning',  -- info | warning | danger
  resolved    boolean not null default false,
  created_at  timestamptz default now()
);
create index if not exists idx_alerts_tenant on public.alerts(tenant_id);

-- ══════════════════════════
-- PRICE HISTORY
-- ══════════════════════════
create table if not exists public.price_history (
  id              serial primary key,
  tenant_id       text not null references public.tenants(id) on delete cascade,
  ingredient_id   integer not null references public.ingredients(id) on delete cascade,
  ingredient_name text not null,
  old_cost        numeric not null,
  new_cost        numeric not null,
  pct_change      numeric not null,
  changed_at      date not null default current_date,
  created_at      timestamptz default now()
);
create index if not exists idx_ph_tenant on public.price_history(tenant_id);

-- ══════════════════════════
-- OP COSTS
-- ══════════════════════════
create table if not exists public.op_costs (
  id          serial primary key,
  tenant_id   text not null references public.tenants(id) on delete cascade,
  name        text not null,
  cat         text not null default 'operacion',
  amount      numeric not null default 0,
  fixed       boolean not null default true,
  created_at  timestamptz default now()
);

create table if not exists public.op_cost_config (
  tenant_id   text primary key references public.tenants(id) on delete cascade,
  ventas      numeric not null default 0,
  period      text not null default 'mes'
);

-- ══════════════════════════
-- ROW LEVEL SECURITY
-- ══════════════════════════
alter table public.tenants          enable row level security;
alter table public.users            enable row level security;
alter table public.ingredients      enable row level security;
alter table public.recipes          enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.orders           enable row level security;
alter table public.order_items      enable row level security;
alter table public.alerts           enable row level security;
alter table public.price_history    enable row level security;
alter table public.op_costs         enable row level security;
alter table public.op_cost_config   enable row level security;

-- Helper: get current user's tenant_id
create or replace function public.my_tenant_id()
returns text language sql stable as $$
  select tenant_id from public.users where id = auth.uid()
$$;

-- Helper: is current user a Susazón admin?
create or replace function public.is_susazon_admin()
returns boolean language sql stable as $$
  select exists(select 1 from public.users where id = auth.uid() and role = 'susazon_admin')
$$;

-- TENANTS — tenants see only themselves; admins see all
create policy "tenant_select" on public.tenants for select
  using (id = my_tenant_id() or is_susazon_admin());

create policy "admin_all_tenants" on public.tenants for all
  using (is_susazon_admin()) with check (is_susazon_admin());

-- USERS — users see only their own row; admins see all
create policy "user_select_own" on public.users for select
  using (id = auth.uid() or is_susazon_admin());

-- Generic per-tenant policy factory for the remaining tables
-- INGREDIENTS
create policy "ing_select" on public.ingredients for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ing_insert" on public.ingredients for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ing_update" on public.ingredients for update
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ing_delete" on public.ingredients for delete
  using (tenant_id = my_tenant_id() or is_susazon_admin());

-- RECIPES
create policy "rec_select" on public.recipes for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "rec_insert" on public.recipes for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "rec_update" on public.recipes for update
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "rec_delete" on public.recipes for delete
  using (tenant_id = my_tenant_id() or is_susazon_admin());

-- RECIPE_INGREDIENTS (via join to recipes)
create policy "ri_select" on public.recipe_ingredients for select
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and (r.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "ri_insert" on public.recipe_ingredients for insert
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and (r.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "ri_update" on public.recipe_ingredients for update
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and (r.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "ri_delete" on public.recipe_ingredients for delete
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and (r.tenant_id = my_tenant_id() or is_susazon_admin())
  ));

-- ORDERS
create policy "ord_select" on public.orders for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ord_insert" on public.orders for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ord_update" on public.orders for update
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ord_delete" on public.orders for delete
  using (tenant_id = my_tenant_id() or is_susazon_admin());

-- ORDER_ITEMS (via join)
create policy "oi_select" on public.order_items for select
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "oi_insert" on public.order_items for insert
  with check (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "oi_update" on public.order_items for update
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.tenant_id = my_tenant_id() or is_susazon_admin())
  ));
create policy "oi_delete" on public.order_items for delete
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and (o.tenant_id = my_tenant_id() or is_susazon_admin())
  ));

-- ALERTS
create policy "alert_select" on public.alerts for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "alert_insert" on public.alerts for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "alert_update" on public.alerts for update
  using (tenant_id = my_tenant_id() or is_susazon_admin());

-- PRICE_HISTORY
create policy "ph_select" on public.price_history for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "ph_insert" on public.price_history for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());

-- OP_COSTS
create policy "opc_select" on public.op_costs for select
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "opc_insert" on public.op_costs for insert
  with check (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "opc_update" on public.op_costs for update
  using (tenant_id = my_tenant_id() or is_susazon_admin());
create policy "opc_delete" on public.op_costs for delete
  using (tenant_id = my_tenant_id() or is_susazon_admin());

create policy "opcfg_all" on public.op_cost_config for all
  using (tenant_id = my_tenant_id() or is_susazon_admin())
  with check (tenant_id = my_tenant_id() or is_susazon_admin());

-- ══════════════════════════
-- UPDATED_AT TRIGGER
-- ══════════════════════════
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger trg_ingredients_updated before update on public.ingredients
  for each row execute function public.set_updated_at();
create trigger trg_recipes_updated before update on public.recipes
  for each row execute function public.set_updated_at();
create trigger trg_orders_updated before update on public.orders
  for each row execute function public.set_updated_at();

-- ══════════════════════════
-- SEED DATA
-- ══════════════════════════
-- Tenants
insert into public.tenants (id,name,emoji,initials,phone,email,address,ig,fb,currency,tax,plan,primary_color,primary_light,fc_meta,fc_alert,fc_crit,margin_goal)
values
  ('steakhouse1','La Fogata','🥩','LF','(461)123-4567','hola@lafogata.mx','Av. Insurgentes 234, Celaya','@lafogata_mx','/lafogata','MXN',16,'pro','#1a472a','#e8f0ea',28,32,35,68),
  ('sushi1','Sushi Nori','🍣','SN','(461)987-6543','info@sushinori.mx','Blvd. López Mateos 88','@sushinori','/sushinori','MXN',16,'pro','#1a3a5c','#e6edf6',30,34,38,65),
  ('mexicano1','El Tlayudero','🌮','ET','(461)555-1234','contacto@eltlayudero.mx','Jardín Principal 12','@eltlayudero','/eltlayudero','MXN',16,'enterprise','#7b2d00','#fdf0e6',26,30,33,70)
on conflict(id) do nothing;

-- Op cost config
insert into public.op_cost_config(tenant_id, ventas, period) values
  ('steakhouse1', 380000, 'mes'),
  ('sushi1',      210000, 'mes'),
  ('mexicano1',   145000, 'mes')
on conflict(tenant_id) do nothing;

-- Ingredients — steakhouse1
insert into public.ingredients (tenant_id,name,cat,unit,buy_unit,stock,min_stock,cost) values
  ('steakhouse1','Filete de res','proteina','kg','kg',18.5,10,320),
  ('steakhouse1','Costilla corta','proteina','kg','kg',22,12,185),
  ('steakhouse1','Camarón U-15','proteina','kg','kg',8,15,420),
  ('steakhouse1','Salmón lomo','proteina','kg','kg',6.5,8,380),
  ('steakhouse1','Papa cambray','vegetal','kg','kg',30,10,28),
  ('steakhouse1','Espárragos','vegetal','kg','kg',4,5,95),
  ('steakhouse1','Mantequilla','lacteo','kg','kg',5,3,145),
  ('steakhouse1','Aceite de oliva','seco','litro','litro',8,4,280),
  ('steakhouse1','Sal de grano','seco','kg','kg',12,2,35),
  ('steakhouse1','Vino tinto','bebida','litro','litro',15,6,180);

-- Ingredients — sushi1
insert into public.ingredients (tenant_id,name,cat,unit,buy_unit,stock,min_stock,cost) values
  ('sushi1','Salmón sashimi','proteina','kg','kg',5,8,520),
  ('sushi1','Atún bluefin','proteina','kg','kg',3,5,680),
  ('sushi1','Camarón tigre','proteina','kg','kg',7,6,350),
  ('sushi1','Arroz sushi','seco','kg','kg',25,10,42),
  ('sushi1','Alga nori','seco','pieza','pieza',200,100,3.5),
  ('sushi1','Aguacate','vegetal','pieza','pieza',40,20,18);

-- Ingredients — mexicano1
insert into public.ingredients (tenant_id,name,cat,unit,buy_unit,stock,min_stock,cost) values
  ('mexicano1','Res molida','proteina','kg','kg',20,8,145),
  ('mexicano1','Pollo entero','proteina','kg','kg',15,10,72),
  ('mexicano1','Tortillas maíz','seco','pieza','pieza',500,200,1.2),
  ('mexicano1','Chile pasilla','vegetal','kg','kg',3,1,85),
  ('mexicano1','Queso Oaxaca','lacteo','kg','kg',8,4,160),
  ('mexicano1','Tomate rojo','vegetal','kg','kg',12,5,22);

-- NOTE: After inserting ingredients, look up their generated IDs and create recipes.
-- The script below uses a subquery approach for portability.

-- Recipes — steakhouse1
with s1 as (select id,name from public.ingredients where tenant_id='steakhouse1')
insert into public.recipes(tenant_id,name,cat,portions,price) values
  ('steakhouse1','Chuletón a la Brasa','plato_fuerte',1,480),
  ('steakhouse1','Costilla BBQ','plato_fuerte',1,380),
  ('steakhouse1','Camarones al Ajillo','plato_fuerte',1,360),
  ('steakhouse1','Salmón Teriyaki','plato_fuerte',1,420),
  ('steakhouse1','Espárragos Grillados','entrada',2,130);

-- Recipes — sushi1
insert into public.recipes(tenant_id,name,cat,portions,price) values
  ('sushi1','Sashimi Mix 12pzas','plato_fuerte',1,340),
  ('sushi1','Roll Spicy Tuna','plato_fuerte',1,185);

-- Recipes — mexicano1
insert into public.recipes(tenant_id,name,cat,portions,price) values
  ('mexicano1','Tlayuda Completa','plato_fuerte',1,160),
  ('mexicano1','Pollo en Mole','plato_fuerte',1,145),
  ('mexicano1','Tacos de res x3','plato_fuerte',1,75);

-- Recipe ingredients — linked by name lookup
-- steakhouse1: Chuletón a la Brasa
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Filete de res',0.35,'kg'),('Papa cambray',0.2,'kg'),('Mantequilla',0.03,'kg'),('Sal de grano',0.01,'kg')) as v(iname,qty,unit)
where r.name='Chuletón a la Brasa' and r.tenant_id='steakhouse1' and i.name=v.iname and i.tenant_id='steakhouse1';

-- steakhouse1: Costilla BBQ
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Costilla corta',0.4,'kg'),('Papa cambray',0.15,'kg'),('Sal de grano',0.01,'kg')) as v(iname,qty,unit)
where r.name='Costilla BBQ' and r.tenant_id='steakhouse1' and i.name=v.iname and i.tenant_id='steakhouse1';

-- steakhouse1: Camarones al Ajillo
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Camarón U-15',0.2,'kg'),('Aceite de oliva',0.05,'litro'),('Sal de grano',0.005,'kg')) as v(iname,qty,unit)
where r.name='Camarones al Ajillo' and r.tenant_id='steakhouse1' and i.name=v.iname and i.tenant_id='steakhouse1';

-- steakhouse1: Salmón Teriyaki
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Salmón lomo',0.22,'kg'),('Aceite de oliva',0.04,'litro'),('Sal de grano',0.005,'kg')) as v(iname,qty,unit)
where r.name='Salmón Teriyaki' and r.tenant_id='steakhouse1' and i.name=v.iname and i.tenant_id='steakhouse1';

-- steakhouse1: Espárragos Grillados
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Espárragos',0.3,'kg'),('Mantequilla',0.02,'kg')) as v(iname,qty,unit)
where r.name='Espárragos Grillados' and r.tenant_id='steakhouse1' and i.name=v.iname and i.tenant_id='steakhouse1';

-- sushi1: Sashimi Mix
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Salmón sashimi',0.12,'kg'),('Atún bluefin',0.06,'kg')) as v(iname,qty,unit)
where r.name='Sashimi Mix 12pzas' and r.tenant_id='sushi1' and i.name=v.iname and i.tenant_id='sushi1';

-- sushi1: Roll Spicy Tuna
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Atún bluefin',0.08,'kg'),('Arroz sushi',0.12,'kg'),('Alga nori',2,'pieza'),('Aguacate',0.25,'pieza')) as v(iname,qty,unit)
where r.name='Roll Spicy Tuna' and r.tenant_id='sushi1' and i.name=v.iname and i.tenant_id='sushi1';

-- mexicano1: Tlayuda Completa
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Tortillas maíz',2,'pieza'),('Res molida',0.18,'kg'),('Queso Oaxaca',0.12,'kg'),('Tomate rojo',0.08,'kg')) as v(iname,qty,unit)
where r.name='Tlayuda Completa' and r.tenant_id='mexicano1' and i.name=v.iname and i.tenant_id='mexicano1';

-- mexicano1: Pollo en Mole
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Pollo entero',0.22,'kg'),('Chile pasilla',0.05,'kg'),('Tomate rojo',0.1,'kg')) as v(iname,qty,unit)
where r.name='Pollo en Mole' and r.tenant_id='mexicano1' and i.name=v.iname and i.tenant_id='mexicano1';

-- mexicano1: Tacos de res x3
insert into public.recipe_ingredients(recipe_id,ingredient_id,qty,unit)
select r.id, i.id, v.qty, v.unit from public.recipes r, public.ingredients i,
  (values ('Res molida',0.12,'kg'),('Tortillas maíz',3,'pieza'),('Tomate rojo',0.06,'kg')) as v(iname,qty,unit)
where r.name='Tacos de res x3' and r.tenant_id='mexicano1' and i.name=v.iname and i.tenant_id='mexicano1';

-- Orders
insert into public.orders(id,tenant_id,date,supplier,status,items_count,total,delivery) values
  ('OC-0038','steakhouse1','2026-03-14','SusaRest Supply','recibida',6,22800,'2026-03-15'),
  ('OC-0037','steakhouse1','2026-03-10','SusaRest Supply','recibida',4,15600,'2026-03-11'),
  ('OC-0040','sushi1','2026-03-17','SusaRest Supply','enviada',5,18700,'2026-03-19'),
  ('OC-0041','mexicano1','2026-03-17','SusaRest Supply','pendiente',8,12400,'2026-03-19'),
  ('OC-0039','mexicano1','2026-03-16','SusaRest Supply','enviada',3,6200,'2026-03-18')
on conflict(id) do nothing;

-- Price history
insert into public.price_history(tenant_id,ingredient_id,ingredient_name,old_cost,new_cost,pct_change,changed_at)
select 'steakhouse1', i.id, 'Filete de res', 295, 320, 8.5, '2026-03-10'
  from public.ingredients i where i.name='Filete de res' and i.tenant_id='steakhouse1';
insert into public.price_history(tenant_id,ingredient_id,ingredient_name,old_cost,new_cost,pct_change,changed_at)
select 'steakhouse1', i.id, 'Camarón U-15', 380, 420, 10.5, '2026-03-12'
  from public.ingredients i where i.name='Camarón U-15' and i.tenant_id='steakhouse1';
insert into public.price_history(tenant_id,ingredient_id,ingredient_name,old_cost,new_cost,pct_change,changed_at)
select 'steakhouse1', i.id, 'Aceite de oliva', 260, 280, 7.7, '2026-03-05'
  from public.ingredients i where i.name='Aceite de oliva' and i.tenant_id='steakhouse1';
insert into public.price_history(tenant_id,ingredient_id,ingredient_name,old_cost,new_cost,pct_change,changed_at)
select 'sushi1', i.id, 'Salmón sashimi', 480, 520, 8.3, '2026-03-11'
  from public.ingredients i where i.name='Salmón sashimi' and i.tenant_id='sushi1';

-- Op costs
insert into public.op_costs(tenant_id,name,cat,amount,fixed) values
  ('steakhouse1','Sueldos y salarios','mano_obra',62000,true),
  ('steakhouse1','IMSS / prestaciones','mano_obra',14000,true),
  ('steakhouse1','Renta del local','servicios',28000,true),
  ('steakhouse1','Luz y gas','servicios',9500,false),
  ('steakhouse1','Internet y telefonía','servicios',1800,true),
  ('steakhouse1','Publicidad y redes','marketing',4500,false),
  ('steakhouse1','Empaques y desechables','operacion',3200,false),
  ('steakhouse1','Mantenimiento y limpieza','operacion',2800,false),
  ('steakhouse1','Contabilidad y admin','admin',3500,true),
  ('steakhouse1','Seguros','admin',1500,true),
  ('sushi1','Sueldos y salarios','mano_obra',38000,true),
  ('sushi1','IMSS / prestaciones','mano_obra',8500,true),
  ('sushi1','Renta del local','servicios',22000,true),
  ('sushi1','Luz y gas','servicios',6800,false),
  ('sushi1','Empaques y desechables','operacion',2100,false),
  ('sushi1','Contabilidad y admin','admin',2800,true),
  ('mexicano1','Sueldos y salarios','mano_obra',24000,true),
  ('mexicano1','IMSS / prestaciones','mano_obra',5400,true),
  ('mexicano1','Renta del local','servicios',12000,true),
  ('mexicano1','Luz y gas','servicios',4200,false),
  ('mexicano1','Empaques y desechables','operacion',1800,false),
  ('mexicano1','Publicidad','marketing',1500,false);

-- ══════════════════════════
-- CREATE USER ACCOUNTS
-- (Run AFTER creating users in Auth > Users in Supabase Dashboard)
-- Replace the UUIDs with the actual UUIDs from Auth > Users
-- ══════════════════════════

-- Example (run after creating users in Auth dashboard):
-- insert into public.users(id, tenant_id, role) values
--   ('uuid-of-lafogata-user',    'steakhouse1',  'tenant'),
--   ('uuid-of-sushinori-user',   'sushi1',        'tenant'),
--   ('uuid-of-tlayudero-user',   'mexicano1',     'tenant'),
--   ('uuid-of-susazon-admin',    'steakhouse1',   'susazon_admin');
-- Note: susazon_admin needs a tenant_id but can see all data via RLS policy.
