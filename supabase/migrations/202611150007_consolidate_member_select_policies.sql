-- Consolidate equivalent SELECT access paths to remove overlapping permissive RLS policies.
-- The OR conditions preserve the three existing jobs audiences and two application audiences.
drop policy if exists "Admins view all jobs" on public.jobs;
drop policy if exists "Approved trades can view open jobs" on public.jobs;
drop policy if exists "Customers can view their own jobs" on public.jobs;
create policy "jobs visible to authorized members" on public.jobs
for select to authenticated
using (
  exists (
    select 1 from public.admin_users au
    where au.user_id = (select auth.uid())
  )
  or (
    status = 'open'
    and exists (
      select 1 from public.trade_applications ta
      where ta.user_id = (select auth.uid())
        and ta.status = 'approved'
    )
  )
  or customer_id = (select auth.uid())
);

drop policy if exists "Admins view all applications" on public.trade_applications;
drop policy if exists "Users view own application" on public.trade_applications;
create policy "applications visible to authorized members" on public.trade_applications
for select to authenticated
using (
  exists (
    select 1 from public.admin_users au
    where au.user_id = (select auth.uid())
  )
  or user_id = (select auth.uid())
);
