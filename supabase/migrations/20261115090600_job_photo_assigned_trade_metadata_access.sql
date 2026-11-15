drop policy if exists "job photo read participants" on public.job_photos;
create policy "job photo read participants" on public.job_photos
for select to authenticated
using (
  customer_id = (select auth.uid())
  or exists (
    select 1
    from public.jobs j
    join public.trade_applications ta
      on ta.user_id = (select auth.uid())
     and ta.status = 'approved'
    where j.id = job_photos.job_id
      and j.status = 'open'
  )
  or exists (
    select 1
    from public.jobs j
    join public.quotes q on q.job_id = j.id
    join public.trade_applications ta
      on ta.user_id = (select auth.uid())
     and ta.status = 'approved'
    where j.id = job_photos.job_id
      and q.tradesperson_id = (select auth.uid())
      and q.status = 'accepted'
  )
);