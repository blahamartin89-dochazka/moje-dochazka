-- Přístup do /kolega/ podle e-mailu.
-- Idempotentní. Spusť celé v SQL editoru Supabase (účet Martina).
-- Aplikace má zámek vypnutý, dokud v index.html není window.KOLEGA_ACCESS=true.
--
-- Pořadí:
-- 1. Spusť tento soubor.
-- 2. Authentication > Hooks > Before user created: zapni funkci public.hook_kolega_before_user_created.
--    Bez hooku si kdokoli může založit účet (shouldCreateUser). Aplikace ho pak odhlásí,
--    ale účet v Auth už existuje. Hook vznik účtu rovnou odmítne, pokud e-mail není aktivní v allowed_emails.
--    Martinův už existující účet hook neblokuje (hook běží jen před vytvořením nového uživatele).
-- 3. V aplikaci (po přepnutí příznaku) přidej e-maily kolegů dřív, než jim pošleš odkaz.
-- 4. Authentication > Emails > Templates > Magic Link: šablona musí obsahovat {{ .Token }},
--    aby přišel šestimístný kód. Samotné {{ .ConfirmationURL }} posílá jen odkaz.
-- 5. Vestavěná pošta Supabase posílá jen 2 e-maily za hodinu a jen na adresy členů organizace
--    (jinak email_address_not_authorized). Na kolegy je potřeba vlastní SMTP
--    (Authentication > Emails > SMTP). Po vlastním SMTP je výchozí strop často 30 e-mailů za hodinu.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- Starý návrh s jednorázovým odkazem. V aplikaci se nepoužíval.
drop function if exists public.activate_invite(text, text, text);
drop function if exists public.check_invite(text, text);
drop table if exists public.invites;

create table if not exists public.allowed_emails (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid(),
  email citext not null,
  name text,
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);

alter table public.allowed_emails add column if not exists owner uuid;
alter table public.allowed_emails add column if not exists email citext;
alter table public.allowed_emails add column if not exists name text;
alter table public.allowed_emails add column if not exists status text;
alter table public.allowed_emails add column if not exists created_at timestamptz default now();
alter table public.allowed_emails add column if not exists last_seen_at timestamptz;
alter table public.allowed_emails add column if not exists revoked_at timestamptz;

create unique index if not exists allowed_emails_email_key on public.allowed_emails (email);

alter table public.allowed_emails enable row level security;

drop policy if exists allowed_emails_owner_all on public.allowed_emails;
create policy allowed_emails_owner_all on public.allowed_emails
  for all
  to authenticated
  using (owner = auth.uid())
  with check (owner = auth.uid());

revoke all on table public.allowed_emails from anon, public;
grant select, insert, update, delete on table public.allowed_emails to authenticated;

-- Vlastník seznamu je napevno Martin (jediný řádek v public.user_data v okamžiku spuštění).
-- Nikdo jiný nemůže vložit řádek, ani když Martin smaže všechny e-maily.
do $mig$
declare
  v_owner uuid;
  v_cnt int;
begin
  select count(*), min(user_id::text)::uuid into v_cnt, v_owner from public.user_data;
  if v_cnt <> 1 or v_owner is null then
    raise exception 'Čekal jsem přesně jeden řádek v user_data (Martin), našel %', v_cnt;
  end if;
  execute format($f$
    create or replace function public.allowed_emails_guard()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    begin
      if auth.uid() is null or auth.uid() <> %L::uuid then
        raise exception 'not allowed';
      end if;
      new.owner := auth.uid();
      if new.email is not null then
        new.email := lower(trim(new.email::text))::citext;
      end if;
      return new;
    end;
    $body$
  $f$, v_owner);
end
$mig$;

revoke all on function public.allowed_emails_guard() from public, anon, authenticated;

drop trigger if exists allowed_emails_guard on public.allowed_emails;
create trigger allowed_emails_guard
  before insert on public.allowed_emails
  for each row execute function public.allowed_emails_guard();

create or replace function public.check_access()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  em text;
  rec public.allowed_emails%rowtype;
begin
  em := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if em = '' then
    return 'denied';
  end if;
  select * into rec from public.allowed_emails where email = em::citext;
  if not found then
    return 'denied';
  end if;
  if rec.status <> 'active' then
    return 'revoked';
  end if;
  update public.allowed_emails set last_seen_at = now() where id = rec.id;
  return 'ok';
end;
$$;

revoke all on function public.check_access() from public, anon;
grant execute on function public.check_access() to authenticated;

-- Hook se sám nezapne. Martin ho vybere v Authentication > Hooks > Before user created.
create or replace function public.hook_kolega_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  em text;
begin
  em := lower(trim(coalesce(event -> 'user' ->> 'email', '')));
  if exists (
    select 1 from public.allowed_emails
    where email = em::citext and status = 'active'
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'error', jsonb_build_object(
      'message', 'Tento e-mail nemá přístup. Požádej Martina.',
      'http_code', 403
    )
  );
end;
$$;

revoke all on function public.hook_kolega_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.hook_kolega_before_user_created(jsonb) to supabase_auth_admin;
