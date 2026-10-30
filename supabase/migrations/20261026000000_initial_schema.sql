create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text unique,
  full_name text,
  role text not null default 'client'
    check (role in ('client', 'motard', 'admin')),
  created_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in ('moto', 'livraison')),
  departure text not null,
  destination text not null,
  estimated_price integer not null check (estimated_price >= 0),
  status text not null default 'En recherche d’un motard',
  departure_lat double precision,
  departure_lng double precision,
  destination_lat double precision,
  destination_lng double precision,
  distance_km double precision check (distance_km is null or distance_km >= 0),
  created_at timestamptz not null default now()
);

create table public.motorist_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  full_name text not null,
  phone text not null,
  license_plate text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);

create index courses_user_created_idx
  on public.courses (user_id, created_at desc);
create index motorist_applications_user_created_idx
  on public.motorist_applications (user_id, created_at desc);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'admin'
  );
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, phone)
  values (new.id, new.phone)
  on conflict (id) do update set phone = excluded.phone;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.motorist_applications enable row level security;

grant select on public.profiles to authenticated;
grant select, insert, update on public.courses to authenticated;
grant select, insert, update on public.motorist_applications to authenticated;

create policy "Clients can read their own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

create policy "Clients can read their own courses"
  on public.courses for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "Clients can create their own courses"
  on public.courses for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'En recherche d’un motard'
  );

create policy "Admins can update courses"
  on public.courses for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "Clients can read their own motorist applications"
  on public.motorist_applications for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "Clients can create their own motorist applications"
  on public.motorist_applications for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
  );

create policy "Admins can update motorist applications"
  on public.motorist_applications for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
