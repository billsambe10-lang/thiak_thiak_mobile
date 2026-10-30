alter table public.courses
  add column assigned_motorist_id uuid references public.profiles (id);

create index courses_assigned_motorist_idx
  on public.courses (assigned_motorist_id, created_at desc);

create table public.motorist_presence (
  motorist_id uuid primary key references public.profiles (id) on delete cascade,
  is_available boolean not null default false,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz not null default now(),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180)
);

create table public.motorist_course_offers (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  motorist_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'offered'
    check (status in ('offered', 'accepted', 'declined', 'expired')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (course_id, motorist_id)
);

create index motorist_course_offers_motorist_idx
  on public.motorist_course_offers (motorist_id, status, created_at desc);

alter table public.motorist_presence enable row level security;
alter table public.motorist_course_offers enable row level security;

grant select, insert, update on public.motorist_presence to authenticated;
grant select on public.motorist_course_offers to authenticated;

create policy "Approved motor drivers can read their presence"
  on public.motorist_presence for select to authenticated
  using (motorist_id = (select auth.uid()) or (select public.is_admin()));

create policy "Approved motor drivers can create their presence"
  on public.motorist_presence for insert to authenticated
  with check (
    motorist_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      join public.motorist_applications a on a.user_id = p.id
      where p.id = (select auth.uid())
        and p.role = 'motard'
        and a.status = 'approved'
    )
  );

create policy "Approved motor drivers can update their presence"
  on public.motorist_presence for update to authenticated
  using (
    motorist_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      join public.motorist_applications a on a.user_id = p.id
      where p.id = (select auth.uid())
        and p.role = 'motard'
        and a.status = 'approved'
    )
  )
  with check (
    motorist_id = (select auth.uid())
    and exists (
      select 1
      from public.profiles p
      join public.motorist_applications a on a.user_id = p.id
      where p.id = (select auth.uid())
        and p.role = 'motard'
        and a.status = 'approved'
    )
  );

create policy "Drivers can read their course offers"
  on public.motorist_course_offers for select to authenticated
  using (motorist_id = (select auth.uid()) or (select public.is_admin()));

create policy "Drivers can read courses offered to them"
  on public.courses for select to authenticated
  using (
    assigned_motorist_id = (select auth.uid())
    or exists (
      select 1
      from public.motorist_course_offers o
      where o.course_id = id
        and o.motorist_id = (select auth.uid())
        and o.status = 'offered'
    )
  );

create or replace function public.respond_to_motorist_offer(
  p_offer_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_course_id uuid;
begin
  if v_user_id is null or not exists (
    select 1
    from public.profiles p
    join public.motorist_applications a on a.user_id = p.id
    where p.id = v_user_id
      and p.role = 'motard'
      and a.status = 'approved'
  ) then
    raise exception 'Seuls les motards approuvés peuvent répondre aux offres.';
  end if;

  select course_id into v_course_id
  from public.motorist_course_offers
  where id = p_offer_id
    and motorist_id = v_user_id
    and status = 'offered'
  for update;

  if v_course_id is null then
    raise exception 'Cette proposition n’est plus disponible.';
  end if;

  if p_accept then
    update public.courses
    set assigned_motorist_id = v_user_id,
        status = 'Acceptée par un motard'
    where id = v_course_id
      and assigned_motorist_id is null
      and status = 'En recherche d’un motard';

    if not found then
      update public.motorist_course_offers
      set status = 'expired', responded_at = now()
      where id = p_offer_id;
      raise exception 'Cette course a déjà été attribuée.';
    end if;
  end if;

  update public.motorist_course_offers
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now()
  where id = p_offer_id;

  if p_accept then
    update public.motorist_course_offers
    set status = 'expired', responded_at = now()
    where course_id = v_course_id
      and id <> p_offer_id
      and status = 'offered';
  end if;
end;
$$;

revoke all on function public.respond_to_motorist_offer(uuid, boolean)
  from public;
grant execute on function public.respond_to_motorist_offer(uuid, boolean)
  to authenticated;

alter table public.motorist_course_offers replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'motorist_course_offers'
  ) then
    alter publication supabase_realtime
      add table public.motorist_course_offers;
  end if;
end;
$$;
