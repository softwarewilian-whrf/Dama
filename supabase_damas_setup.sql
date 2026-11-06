-- Execute este script no SQL Editor do Supabase.
-- Antes, habilite Authentication > Providers > Anonymous Sign-Ins.

create table if not exists public.damas_salas (
  code text primary key check (code ~ '^[A-Z0-9]{6}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  guest_id uuid references auth.users(id) on delete set null,
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  state jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint damas_salas_different_players check (guest_id is null or guest_id <> host_id)
);

alter table public.damas_salas enable row level security;

-- Um usuário pode localizar salas aguardando adversário e ler salas das quais participa.
drop policy if exists "damas_select_waiting_or_member" on public.damas_salas;
create policy "damas_select_waiting_or_member"
on public.damas_salas for select to authenticated
using (status = 'waiting' or host_id = auth.uid() or guest_id = auth.uid());

-- O usuário autenticado só pode criar sala em seu próprio nome.
drop policy if exists "damas_insert_own_room" on public.damas_salas;
create policy "damas_insert_own_room"
on public.damas_salas for insert to authenticated
with check (host_id = auth.uid() and guest_id is null and status = 'waiting');

-- Só o criador ou o jogador que entrou na sala pode atualizar a partida.
-- O convidado só consegue ocupar uma sala ainda livre; ambos podem sincronizar o estado.
drop policy if exists "damas_update_room_members" on public.damas_salas;
create policy "damas_update_room_members"
on public.damas_salas for update to authenticated
using (host_id = auth.uid() or guest_id = auth.uid() or (guest_id is null and status = 'waiting'))
with check (host_id = auth.uid() or guest_id = auth.uid());

-- Habilita eventos Postgres Changes para a sincronização em tempo real.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'damas_salas'
  ) then
    alter publication supabase_realtime add table public.damas_salas;
  end if;
end $$;

-- Permissões de tabela para usuários autenticados (inclui sessões anônimas do Supabase).
grant select, insert, update on public.damas_salas to authenticated;
