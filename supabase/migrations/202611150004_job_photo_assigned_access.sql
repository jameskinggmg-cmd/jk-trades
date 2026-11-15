-- Allow the successful tradesperson to keep viewing job photos after a quote is accepted.
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
      where j.id::text = (storage.foldername(name))[1]
        and (
          (
            j.status = 'open'
            and exists (
              select 1 from public.trade_applications ta
              where ta.user_id = (select auth.uid())
                and ta.status = 'approved'
            )
          )
          or exists (
            select 1 from public.quotes q
            where q.job_id = j.id
              and q.tradesperson_id = (select auth.uid())
              and q.status = 'accepted'
          )
        )
    )
  )
);
