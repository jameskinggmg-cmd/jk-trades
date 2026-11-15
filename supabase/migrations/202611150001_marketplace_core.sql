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
drop policy if exists "conversation participant update" on public.conversations;
create policy "conversation participant update" on public.conversations
for update to authenticated using (customer_id = auth.uid() or tradesperson_id = auth.uid())
with check (customer_id = auth.uid() or tradesperson_id = auth.uid());

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
drop policy if exists "recipient mark message read" on public.messages;
create policy "recipient mark message read" on public.messages
for update to authenticated using (
  exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.customer_id = auth.uid() or c.tradesperson_id = auth.uid())
      and messages.sender_id <> auth.uid()
  )
) with check (
  exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.customer_id = auth.uid() or c.tradesperson_id = auth.uid())
  )
);

-- Notifications: each user can only read/update their own notifications.
drop policy if exists "notification owner read" on public.notifications;
create policy "notification owner read" on public.notifications
for select to authenticated using (user_id = auth.uid());
drop policy if exists "notification owner update" on public.notifications;
create policy "notification owner update" on public.notifications
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

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

grant select, insert, update on public.business_profiles to authenticated;
grant select, insert, delete on public.job_photos to authenticated;
grant select, insert, update on public.quotes to authenticated;
grant select, insert, update on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select, update on public.notifications to authenticated;
grant select, insert on public.reviews to authenticated;
