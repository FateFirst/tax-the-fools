-- Tax The Fools: device sync schema.
-- Run once: Supabase dashboard -> SQL Editor -> New query -> paste this whole file -> Run.
-- Safe to run again (tables use "if not exists", functions use "create or replace").
--
-- Access model: RLS is on with no policies and anon/authenticated have no table
-- privileges, so the anon key alone can read nothing. All access goes through the
-- ttf_* functions (security definer), which check the sync key (stored as sha256 hex).

create extension if not exists pgcrypto;

create table if not exists accounts (
  id uuid primary key default gen_random_uuid(),
  key_hash text unique not null,
  created_at timestamptz default now()
);
create table if not exists state (
  account uuid primary key references accounts(id) on delete cascade,
  version bigint not null default 0,
  blob text not null default '',
  updated_at timestamptz default now(),
  updated_by text
);
create table if not exists devices (
  account uuid references accounts(id) on delete cascade,
  device text,
  last_sync timestamptz,
  primary key (account, device)
);

alter table accounts enable row level security;
alter table state enable row level security;
alter table devices enable row level security;
revoke all on table accounts, state, devices from anon, authenticated;

-- Internal helper: key -> account id, or raise. Not callable by anon.
create or replace function ttf_account_of(p_key text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'invalid sync key';
  end if;
  select id into v_id from accounts
   where key_hash = encode(extensions.digest(p_key, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'invalid sync key';
  end if;
  return v_id;
end $$;
revoke all on function ttf_account_of(text) from public, anon, authenticated;

create or replace function ttf_create_account(p_key text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if p_key is null or length(p_key) < 32 then
    raise exception 'sync key too short';
  end if;
  insert into accounts (key_hash)
  values (encode(extensions.digest(p_key, 'sha256'), 'hex'))
  returning id into v_id;
  insert into state (account) values (v_id);
end $$;

create or replace function ttf_pull(p_key text)
returns table(version bigint, blob text, updated_at timestamptz, updated_by text)
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := ttf_account_of(p_key);
begin
  return query select s.version, s.blob, s.updated_at, s.updated_by
                 from state s where s.account = v_id;
end $$;

-- Compare-and-swap: one atomic UPDATE; returns the new version or -1 on mismatch.
create or replace function ttf_push(p_key text, p_expected bigint, p_blob text, p_device text)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := ttf_account_of(p_key);
        v_new bigint;
begin
  update state
     set version = state.version + 1, blob = p_blob, updated_at = now(), updated_by = p_device
   where account = v_id and state.version = p_expected
  returning state.version into v_new;
  if v_new is null then
    return -1;
  end if;
  insert into devices (account, device, last_sync) values (v_id, p_device, now())
  on conflict (account, device) do update set last_sync = excluded.last_sync;
  return v_new;
end $$;

create or replace function ttf_devices(p_key text)
returns table(device text, last_sync timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := ttf_account_of(p_key);
begin
  return query select d.device, d.last_sync from devices d
                where d.account = v_id order by d.last_sync desc;
end $$;

grant execute on function ttf_create_account(text), ttf_pull(text),
  ttf_push(text, bigint, text, text), ttf_devices(text) to anon;
