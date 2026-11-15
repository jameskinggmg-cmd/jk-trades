-- JK TRADES private job-photo storage
-- Object path convention: <job_uuid>/<customer_user_uuid>/<filename>
-- Keep job images private; access is controlled by Storage RLS.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-photos',
  'job-photos',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "job photo customer upload" on storage.objects;
create policy "job photo customer upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'job-photos'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.jobs j
    where j.id::text = (storage.foldername(name))[1]
      and j.customer_id = (select auth.uid())
  )
);

drop policy if exists "job photo participants read" on storage.objects;
create policy "job photo participants read"
on storage.objects for select to authenticated
using (
  bucket_id = 'job-photos'
  and (
    (storage.foldername(name))[2] = (select auth.uid())::text
    or exists (
      select 1
      from public.jobs j
      join public.trade_applications ta
        on ta.user_id = (select auth.uid())
       and ta.status = 'approved'
      where j.id::text = (storage.foldername(name))[1]
        and j.status = 'open'
    )
  )
);

drop policy if exists "job photo customer delete" on storage.objects;
create policy "job photo customer delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'job-photos'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.jobs j
    where j.id::text = (storage.foldername(name))[1]
      and j.customer_id = (select auth.uid())
  )
);
