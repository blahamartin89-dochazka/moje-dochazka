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

-- Další přihlášený uživatel si nesmí vložit vlastní řádek, jakmile už tabulku vlastní Martin.
create or replace function public.allowed_emails_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  boss uuid;
begin
  if auth.uid() is null then
    raise exception 'not allowed';
  end if;
  if new.owner is null then
    new.owner := auth.uid();
  end if;
  if new.owner <> auth.uid() then
    raise exception 'not allowed';
  end if;
  select e.owner into boss from public.allowed_emails e limit 1;
  if boss is not null and boss <> auth.uid() then
    raise exception 'not allowed';
  end if;
  if new.email is not null then
    new.email := lower(trim(new.email::text))::citext;
  end if;
  return new;
end;
$$;

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

-- Docházka Martina: kolega se přihlásí vlastním účtem a nesmí číst cizí řádky.
-- Živé politiky odtud nešly přečíst. Tohle smaže stávající politiky na public.user_data
-- a na objektech bucketu stazky a nasadí přístup jen pro auth.uid().
do $$
declare
  r record;
begin
  if to_regclass('public.user_data') is not null
     and exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'user_data' and column_name = 'user_id'
     ) then
    execute 'alter table public.user_data enable row level security';
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'user_data'
    loop
      execute format('drop policy if exists %I on public.user_data', r.policyname);
    end loop;
    execute 'create policy user_data_owner_all on public.user_data for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())';
    execute 'revoke all on table public.user_data from anon, public';
    execute 'grant select, insert, update, delete on table public.user_data to authenticated';
    raise notice 'user_data: politiky nahrazeny pravidlem user_id = auth.uid()';
  else
    raise notice 'user_data: tabulka nebo sloupec user_id chybí, politika se neměnila';
  end if;
end $$;

do $$
declare
  r record;
  expr text;
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage.objects chybí';
    return;
  end if;
  for r in
    select pol.polname as policyname,
           pg_get_expr(pol.polqual, pol.polrelid) as qual,
           pg_get_expr(pol.polwithcheck, pol.polrelid) as chk
    from pg_policy pol
    join pg_class cls on cls.oid = pol.polrelid
    join pg_namespace nsp on nsp.oid = cls.relnamespace
    where nsp.nspname = 'storage' and cls.relname = 'objects'
  loop
    expr := lower(coalesce(r.qual, '') || ' ' || coalesce(r.chk, ''));
    if expr like '%stazky%' or expr ~ '(^|[^a-z])true([^a-z]|$)' then
      execute format('drop policy if exists %I on storage.objects', r.policyname);
      raise notice 'storage.objects: zrušena politika %', r.policyname;
    end if;
  end loop;

  execute 'create policy stazky_owner_select on storage.objects for select to authenticated using (bucket_id = ''stazky'' and (storage.foldername(name))[1] = auth.uid()::text)';
  execute 'create policy stazky_owner_insert on storage.objects for insert to authenticated with check (bucket_id = ''stazky'' and (storage.foldername(name))[1] = auth.uid()::text)';
  execute 'create policy stazky_owner_update on storage.objects for update to authenticated using (bucket_id = ''stazky'' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = ''stazky'' and (storage.foldername(name))[1] = auth.uid()::text)';
  execute 'create policy stazky_owner_delete on storage.objects for delete to authenticated using (bucket_id = ''stazky'' and (storage.foldername(name))[1] = auth.uid()::text)';
end $$;
