-- Avoid per-row re-evaluation of auth.uid() in public RLS policies.
-- This preserves each policy's roles and logic while allowing PostgreSQL to
-- evaluate the stable auth.uid() result once per statement.
do $$
declare
  p record;
  v_sql text;
  v_using text;
  v_check text;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        coalesce(qual, '') like '%auth.uid()%'
        or coalesce(with_check, '') like '%auth.uid()%'
      )
  loop
    v_sql := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if p.qual is not null then
      v_using := replace(p.qual, 'auth.uid()', '(select auth.uid())');
      v_sql := v_sql || format(' using (%s)', v_using);
    end if;
    if p.with_check is not null then
      v_check := replace(p.with_check, 'auth.uid()', '(select auth.uid())');
      v_sql := v_sql || format(' with check (%s)', v_check);
    end if;
    execute v_sql;
  end loop;
end $$;
