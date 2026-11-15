-- JK TRADES marketplace hardening
-- Applied to Supabase project zrloxobjeetxtjpevthc after live schema preflight.
-- Keep the approved-trade helper outside the exposed public API schema.

create schema if not exists private;

create or replace function private.is_approved_trade(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trade_applications ta
    where ta.user_id = p_user_id
      and ta.status = 'approved'
  );
$$;

revoke all on function private.is_approved_trade(uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_approved_trade(uuid) to authenticated;

drop policy if exists "business profile public read approved" on public.business_profiles;
create policy "business profile public read approved" on public.business_profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_approved_trade(business_profiles.user_id))
);

drop policy if exists "job customer starts conversation" on public.conversations;
create policy "job customer starts conversation" on public.conversations
for insert to authenticated with check (
  customer_id = (select auth.uid())
  and exists (
    select 1 from public.jobs j
    where j.id = conversations.job_id
      and j.customer_id = (select auth.uid())
  )
  and exists (
    select 1 from public.quotes q
    where q.job_id = conversations.job_id
      and q.tradesperson_id = conversations.tradesperson_id
      and q.status = 'accepted'
  )
  and (select private.is_approved_trade(conversations.tradesperson_id))
);

create or replace function public.accept_job_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_customer_id uuid;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  select q.job_id into v_job_id
  from public.quotes q
  where q.id = p_quote_id;

  if not found then
    raise exception 'Quote not found';
  end if;

  select j.customer_id into v_customer_id
  from public.jobs j
  where j.id = v_job_id
  for update;

  if not found or v_customer_id <> auth.uid() then
    raise exception 'Quote not found';
  end if;

  select q.status into v_status
  from public.quotes q
  where q.id = p_quote_id
    and q.job_id = v_job_id
  for update;

  if not found or v_status <> 'sent' then
    raise exception 'This quote is no longer available';
  end if;

  update public.quotes
     set status = case when id = p_quote_id then 'accepted' else 'declined' end,
         updated_at = now()
   where job_id = v_job_id
     and status = 'sent';

  update public.jobs
     set status = 'assigned'
   where id = v_job_id
     and status = 'open';
end;
$$;

revoke all on function public.accept_job_quote(uuid) from public;
grant execute on function public.accept_job_quote(uuid) to authenticated;

-- Remove direct RPC access to the auth trigger; Auth invokes it internally.
revoke all on function public.create_user_profile() from public, anon, authenticated;

-- Supporting foreign-key indexes.
create index if not exists jobs_customer_id_idx on public.jobs(customer_id);
create index if not exists quotes_tradesperson_id_idx on public.quotes(tradesperson_id);
create index if not exists conversations_tradesperson_id_idx on public.conversations(tradesperson_id);
create index if not exists messages_sender_id_idx on public.messages(sender_id);
create index if not exists reviews_customer_id_idx on public.reviews(customer_id);
create index if not exists job_photos_customer_id_idx on public.job_photos(customer_id);

create index if not exists job_photos_job_id_idx on public.job_photos(job_id);
