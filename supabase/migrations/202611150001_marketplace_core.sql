-- JK TRADES marketplace backend foundation
-- Review and apply in Supabase SQL Editor only after checking existing schema.
-- This migration is additive: it does not alter or delete existing customer jobs.

create extension if not exists pgcrypto;

-- Public-facing trade business profile. Approval remains controlled by trade_applications.
create table if not exists public.business_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null,
  trade text not null,
  bio text,
  phone text,
  postcode text,
  service_area text,
  website_url text,
  logo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Photo metadata; actual image bytes belong in a private Supabase Storage bucket.
create table if not exists public.job_photos (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  caption text,
  created_at timestamptz not null default now()
);

-- One quote per trade business per job; amounts are stored in GBP pence.
create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  tradesperson_id uuid not null references auth.users(id) on delete cascade,
  amount_pence bigint not null check (amount_pence > 0),
  message text,
  estimated_start date,
  estimated_duration text,
  status text not null default 'sent'
    check (status in ('sent','accepted','declined','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id, tradesperson_id)
);

-- A conversation is attached to a job and has an explicit customer/tradesperson pair.
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  tradesperson_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(job_id, customer_id, tradesperson_id),
  check (customer_id <> tradesperson_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 5000),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  link_path text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  tradesperson_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique(job_id, customer_id),
  check (customer_id <> tradesperson_id)
);

create index if not exists jobs_status_created_idx on public.jobs(status, created_at desc);
create index if not exists quotes_job_created_idx on public.quotes(job_id, created_at desc);
create index if not exists conversations_participants_idx on public.conversations(customer_id, tradesperson_id);
create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);
create index if not exists reviews_trade_created_idx on public.reviews(tradesperson_id, created_at desc);

alter table public.business_profiles enable row level security;
alter table public.job_photos enable row level security;
alter table public.quotes enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.reviews enable row level security;

-- Business profile: owner manages their record; approved profiles are publicly readable.
drop policy if exists "business profile public read approved" on public.business_profiles;
create policy "business profile public read approved" on public.business_profiles
for select using (
  user_id = auth.uid()
  or exists (
    select 1 from public.trade_applications ta
    where ta.user_id = business_profiles.user_id and ta.status = 'approved'
  )
);
drop policy if exists "business profile owner insert" on public.business_profiles;
create policy "business profile owner insert" on public.business_profiles
for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "business profile owner update" on public.business_profiles;
create policy "business profile owner update" on public.business_profiles
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Job photos: only the owning customer may manage metadata; approved trades may view photos on open jobs.
drop policy if exists "job photo read participants" on public.job_photos;
create policy "job photo read participants" on public.job_photos
for select to authenticated using (
  customer_id = auth.uid()
  or exists (
    select 1 from public.jobs j
    join public.trade_applications ta on ta.user_id = auth.uid() and ta.status = 'approved'
    where j.id = job_photos.job_id and j.status = 'open'
  )
);
drop policy if exists "job photo owner insert" on public.job_photos;
create policy "job photo owner insert" on public.job_photos
for insert to authenticated with check (
  customer_id = auth.uid()
  and exists (select 1 from public.jobs j where j.id = job_photos.job_id and j.customer_id = auth.uid())
);
drop policy if exists "job photo owner delete" on public.job_photos;
create policy "job photo owner delete" on public.job_photos
for delete to authenticated using (customer_id = auth.uid());

-- Quotes: customer sees quotes on own jobs; tradesperson sees and manages their own quotes.
drop policy if exists "quote participant read" on public.quotes;
create policy "quote participant read" on public.quotes
for select to authenticated using (
  tradesperson_id = auth.uid()
  or exists (select 1 from public.jobs j where j.id = quotes.job_id and j.customer_id = auth.uid())
);
drop policy if exists "approved trade send quote" on public.quotes;
create policy "approved trade send quote" on public.quotes
for insert to authenticated with check (
  tradesperson_id = auth.uid()
  and exists (select 1 from public.trade_applications ta where ta.user_id = auth.uid() and ta.status = 'approved')
  and exists (select 1 from public.jobs j where j.id = quotes.job_id and j.status = 'open' and j.customer_id <> auth.uid())
);
drop policy if exists "quote owner update" on public.quotes;
create policy "quote owner update" on public.quotes
for update to authenticated using (tradesperson_id = auth.uid())
with check (tradesperson_id = auth.uid());

-- Conversations: only the two named participants may read/create.
drop policy if exists "conversation participant read" on public.conversations;
create policy "conversation participant read" on public.conversations
for select to authenticated using (customer_id = auth.uid() or tradesperson_id = auth.uid());
drop policy if exists "job customer starts conversation" on public.conversations;
create policy "job customer starts conversation" on public.conversations
for insert to authenticated with check (
  customer_id = auth.uid()
  and exists (select 1 from public.jobs j where j.id = conversations.job_id and j.customer_id = auth.uid())
  and exists (select 1 from public.trade_applications ta where ta.user_id = conversations.tradesperson_id and ta.status = 'approved')
);
-- Messages: participants only; sender must be the signed-in user.
drop policy if exists "message participant read" on public.messages;
create policy "message participant read" on public.messages
for select to authenticated using (
  exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.customer_id = auth.uid() or c.tradesperson_id = auth.uid())
  )
);
drop policy if exists "participant send message" on public.messages;
create policy "participant send message" on public.messages
for insert to authenticated with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.customer_id = auth.uid() or c.tradesperson_id = auth.uid())
  )
);
-- Notifications: each user can only read/update their own notifications.
drop policy if exists "notification owner read" on public.notifications;
create policy "notification owner read" on public.notifications
for select to authenticated using (user_id = auth.uid());
-- Reviews: visible to all signed-in users; only the customer who owns the job can add one.
drop policy if exists "reviews visible" on public.reviews;
create policy "reviews visible" on public.reviews
for select to authenticated using (true);
drop policy if exists "customer review completed job" on public.reviews;
create policy "customer review completed job" on public.reviews
for insert to authenticated with check (
  customer_id = auth.uid()
  and exists (
    select 1 from public.jobs j
    where j.id = reviews.job_id
      and j.customer_id = auth.uid()
      and j.status in ('completed','complete','closed')
  )
  and exists (select 1 from public.trade_applications ta where ta.user_id = reviews.tradesperson_id and ta.status = 'approved')
);


-- Restrict quote state changes to validated RPCs. Direct client updates would let a
-- tradesperson change quote amounts or move a quote between jobs.
drop policy if exists "quote owner update" on public.quotes;
revoke update on public.quotes from authenticated;
grant select, insert on public.quotes to authenticated;

-- Customer accepts one quote. The function checks ownership and only permits a
-- still-pending quote; competing quotes on that same job are declined atomically.
create or replace function public.accept_job_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $
declare
  v_job_id uuid;
  v_customer_id uuid;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  select q.job_id, j.customer_id, q.status
    into v_job_id, v_customer_id, v_status
  from public.quotes q
  join public.jobs j on j.id = q.job_id
  where q.id = p_quote_id
  for update of q, j;

  if not found or v_customer_id <> auth.uid() then
    raise exception 'Quote not found';
  end if;
  if v_status <> 'sent' then
    raise exception 'This quote is no longer available';
  end if;

  update public.quotes
     set status = case when id = p_quote_id then 'accepted' else 'declined' end,
         updated_at = now()
   where job_id = v_job_id and status = 'sent';
end;
$;

-- A tradesperson may withdraw only their own quote while it is still awaiting a
-- customer decision. Amount, job and owner fields are never client-editable.
create or replace function public.withdraw_job_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  update public.quotes
     set status = 'withdrawn', updated_at = now()
   where id = p_quote_id
     and tradesperson_id = auth.uid()
     and status = 'sent';

  if not found then
    raise exception 'Quote not found or no longer withdrawable';
  end if;
end;
$;

-- Read receipts are updated through narrowly scoped functions rather than a
-- table-wide UPDATE grant that could expose participant or content fields.
create or replace function public.mark_conversation_message_read(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  update public.messages m
     set read_at = coalesce(m.read_at, now())
   where m.id = p_message_id
     and m.sender_id <> auth.uid()
     and exists (
       select 1 from public.conversations c
       where c.id = m.conversation_id
         and (c.customer_id = auth.uid() or c.tradesperson_id = auth.uid())
     );

  if not found then
    raise exception 'Message not found';
  end if;
end;
$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  update public.notifications
     set read_at = coalesce(read_at, now())
   where id = p_notification_id and user_id = auth.uid();

  if not found then
    raise exception 'Notification not found';
  end if;
end;
$;

revoke all on function public.accept_job_quote(uuid) from public;
revoke all on function public.withdraw_job_quote(uuid) from public;
revoke all on function public.mark_conversation_message_read(uuid) from public;
revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.accept_job_quote(uuid) to authenticated;
grant execute on function public.withdraw_job_quote(uuid) to authenticated;
grant execute on function public.mark_conversation_message_read(uuid) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- The current jobs table lifecycle values have not yet been verified. Keep review
-- creation disabled until the completed-job status and job-to-trade assignment
-- rules are confirmed against the live schema.
drop policy if exists "customer review completed job" on public.reviews;
revoke insert on public.reviews from authenticated;

grant select, insert, update on public.business_profiles to authenticated;
grant select, insert, delete on public.job_photos to authenticated;
grant select, insert on public.quotes to authenticated;
grant select, insert on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;
grant select on public.notifications to authenticated;
grant select on public.reviews to authenticated;
