-- Pozvánky pro /kolega/. Spusť celé v Supabase SQL editoru (účet Martina).
-- Aplikace tuhle bránu ještě nevolá. Dokud se to nenasadí v kódu, /kolega/ zůstává otevřená.
-- Anon klíč smí jen zavolat activate_invite a check_invite. Řádky invites nevidí.

create extension if not exists pgcrypto;

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid(),
  name text not null,
  token_hash text not null unique,
  device_id text,
  device_label text,
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  revoked_at timestamptz
);

alter table public.invites enable row level security;

drop policy if exists invites_owner_all on public.invites;
create policy invites_owner_all on public.invites
  for all
  to authenticated
  using (owner = auth.uid())
  with check (owner = auth.uid());

revoke all on table public.invites from anon;
revoke all on table public.invites from public;
grant select, insert, update, delete on table public.invites to authenticated;

create or replace function public.activate_invite(p_token text, p_device_id text, p_device_label text default '')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  h text;
  rec public.invites%rowtype;
begin
  if p_token is null or length(trim(p_token)) < 16 or p_device_id is null or length(trim(p_device_id)) < 8 then
    return 'invalid';
  end if;
  h := encode(digest(trim(p_token), 'sha256'), 'hex');
  select * into rec from public.invites where token_hash = h;
  if not found then
    return 'invalid';
  end if;
  if rec.status <> 'active' then
    return 'revoked';
  end if;
  if rec.device_id is null then
    update public.invites
      set device_id = trim(p_device_id),
          device_label = nullif(left(trim(coalesce(p_device_label, '')), 80), ''),
          activated_at = coalesce(activated_at, now())
      where id = rec.id and device_id is null;
    if found then
      return 'ok';
    end if;
    select * into rec from public.invites where id = rec.id;
  end if;
  if rec.device_id = trim(p_device_id) then
    return 'ok';
  end if;
  return 'used';
end;
$$;

create or replace function public.check_invite(p_token text, p_device_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  h text;
  rec public.invites%rowtype;
begin
  if p_token is null or p_device_id is null then
    return 'invalid';
  end if;
  h := encode(digest(trim(p_token), 'sha256'), 'hex');
  select * into rec from public.invites where token_hash = h;
  if not found then
    return 'invalid';
  end if;
  if rec.status <> 'active' then
    return 'revoked';
  end if;
  if rec.device_id is null then
    return 'pending';
  end if;
  if rec.device_id = trim(p_device_id) then
    return 'ok';
  end if;
  return 'used';
end;
$$;

revoke all on function public.activate_invite(text, text, text) from public;
revoke all on function public.check_invite(text, text) from public;
grant execute on function public.activate_invite(text, text, text) to anon, authenticated;
grant execute on function public.check_invite(text, text) to anon, authenticated;
