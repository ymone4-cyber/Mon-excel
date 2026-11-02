-- Moné Excel — schéma initial Supabase
-- Les tables sont privées par défaut ; seuls les droits nécessaires à l'API sont accordés.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  role text not null default 'member' check (role in ('member', 'owner')),
  access_tier text not null default 'free' check (access_tier in ('free', 'premium')),
  created_at timestamptz not null default now()
);

create table if not exists public.access_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_reference text not null check (char_length(transaction_reference) between 3 and 100),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null)
    or (status in ('approved', 'rejected') and reviewed_at is not null and reviewed_by is not null)
  )
);

create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  certification_id text not null check (char_length(certification_id) between 1 and 80),
  mode text not null check (mode in ('practice', 'exam')),
  score integer not null check (score between 0 and 1000),
  total_questions integer not null check (total_questions > 0),
  correct_answers integer not null check (correct_answers between 0 and total_questions),
  duration_seconds integer not null check (duration_seconds >= 0),
  details jsonb not null default '[]'::jsonb check (jsonb_typeof(details) = 'array' and pg_column_size(details) <= 65536),
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create table if not exists public.scores (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null,
  user_id uuid not null,
  skill text not null check (char_length(skill) between 1 and 80),
  score integer not null check (score between 0 and 1000),
  created_at timestamptz not null default now(),
  foreign key (attempt_id, user_id) references public.attempts(id, user_id) on delete cascade
);

create index if not exists access_requests_user_created_idx
  on public.access_requests (user_id, created_at desc);
create index if not exists access_requests_pending_idx
  on public.access_requests (status, created_at desc) where status = 'pending';
create index if not exists attempts_user_created_idx
  on public.attempts (user_id, created_at desc);
create index if not exists scores_user_created_idx
  on public.scores (user_id, created_at desc);
create index if not exists scores_attempt_idx on public.scores (attempt_id);

-- La création du profil est la seule opération nécessitant un contexte privilégié.
-- Cette fonction est dans un schéma non exposé à l'API et utilise un search_path vide.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Apprenant'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_mone on auth.users;
create trigger on_auth_user_created_mone
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Fonction de lecture minimale utilisée par les politiques RLS et l'approbation.
create or replace function private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'owner'
  );
$$;

revoke all on function private.is_owner() from public, anon, authenticated;
grant execute on function private.is_owner() to authenticated;

alter table public.profiles enable row level security;
alter table public.access_requests enable row level security;
alter table public.attempts enable row level security;
alter table public.scores enable row level security;

drop policy if exists "profiles are visible to their owner" on public.profiles;
create policy "profiles are visible to their owner"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_owner()));

drop policy if exists "owners can update premium access" on public.profiles;
create policy "owners can update premium access"
  on public.profiles for update to authenticated
  using ((select private.is_owner()))
  with check ((select private.is_owner()));

drop policy if exists "members can create their own payment request" on public.access_requests;
create policy "members can create their own payment request"
  on public.access_requests for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    and reviewed_at is null
    and reviewed_by is null
  );

drop policy if exists "members and owners can read payment requests" on public.access_requests;
create policy "members and owners can read payment requests"
  on public.access_requests for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_owner()));

drop policy if exists "owners can review payment requests" on public.access_requests;
create policy "owners can review payment requests"
  on public.access_requests for update to authenticated
  using ((select private.is_owner()))
  with check ((select private.is_owner()));

drop policy if exists "members can read their own attempts" on public.attempts;
create policy "members can read their own attempts"
  on public.attempts for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "members can save their own attempts" on public.attempts;
create policy "members can save their own attempts"
  on public.attempts for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "members can read their own scores" on public.scores;
create policy "members can read their own scores"
  on public.scores for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "members can save scores for their own attempts" on public.scores;
create policy "members can save scores for their own attempts"
  on public.scores for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.attempts a
      where a.id = attempt_id
        and a.user_id = (select auth.uid())
    )
  );

-- Les GRANT contrôlent l'accès à l'API ; RLS contrôle ensuite les lignes accessibles.
-- Aucun droit anonyme, aucune mise à jour de score ou de profil par un membre.
revoke all on public.profiles, public.access_requests, public.attempts, public.scores from anon, authenticated;
grant select on public.profiles to authenticated;
grant select, insert on public.access_requests to authenticated;
grant update (status, reviewed_at, reviewed_by) on public.access_requests to authenticated;
grant update (access_tier) on public.profiles to authenticated;
grant select, insert on public.attempts to authenticated;
grant select, insert on public.scores to authenticated;

-- SECURITY INVOKER : l'approbation reste soumise aux GRANT et aux politiques RLS des owners.
create or replace function public.approve_access_request(p_request_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_user uuid;
  current_status text;
begin
  if not (select private.is_owner()) then
    raise exception 'owner_required' using errcode = '42501';
  end if;

  select ar.user_id, ar.status
    into target_user, current_status
  from public.access_requests ar
  where ar.id = p_request_id
  for update;

  if target_user is null then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
  if current_status <> 'pending' then
    raise exception 'request_already_reviewed' using errcode = '23514';
  end if;

  update public.access_requests
  set status = 'approved', reviewed_at = now(), reviewed_by = (select auth.uid())
  where id = p_request_id;

  update public.profiles
  set access_tier = 'premium'
  where id = target_user;
end;
$$;

revoke all on function public.approve_access_request(uuid) from public, anon, authenticated;
grant execute on function public.approve_access_request(uuid) to authenticated;

-- Nettoie les fonctions du premier brouillon, si celui-ci a déjà été copié manuellement.
drop function if exists public.is_owner();
drop function if exists public.handle_new_user();

-- Après création du compte propriétaire, récupérer son UUID dans Authentication > Users,
-- puis exécuter dans le SQL Editor :
-- update public.profiles set role = 'owner', access_tier = 'premium'
-- where id = '<AUTH_USER_UUID>'::uuid;
