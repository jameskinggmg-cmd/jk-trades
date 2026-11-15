-- JK TRADES marketplace migration preflight (read-only)
-- Run this in the Supabase SQL Editor before applying marketplace_core.sql.
-- It reports the live schema; it does not change any data or permissions.

-- 1) Confirm the existing columns and data types used by the migration.
select
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('jobs', 'trade_applications', 'profiles', 'admin_users')
order by table_name, ordinal_position;

-- 2) Inspect existing CHECK constraints, especially jobs.status.
select
  c.table_name,
  c.constraint_name,
  c.constraint_type,
  pg_get_constraintdef(pc.oid) as definition
from information_schema.table_constraints c
left join pg_constraint pc
  on pc.conname = c.constraint_name
 and pc.conrelid = (quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass
where c.table_schema = 'public'
  and c.table_name in ('jobs', 'trade_applications')
  and c.constraint_type in ('CHECK', 'FOREIGN KEY', 'PRIMARY KEY', 'UNIQUE')
order by c.table_name, c.constraint_type, c.constraint_name;

-- 3) Show current job/application status values (counts only).
select 'jobs.status' as field, status::text as value, count(*) as row_count
from public.jobs
group by status
union all
select 'trade_applications.status', status::text, count(*)
from public.trade_applications
group by status
order by field, value;

-- 4) Confirm existing RLS state on the source tables.
select
  schemaname,
  tablename,
  rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('jobs', 'trade_applications', 'profiles', 'admin_users')
order by tablename;
