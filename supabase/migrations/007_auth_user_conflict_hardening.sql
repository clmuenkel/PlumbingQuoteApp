-- Harden auth user sync against race conditions and duplicate inserts.

create unique index if not exists idx_user_authid_unique
  on public."User" ("authId");

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public."User" ("id", "authId", "name", "email", "role", "active", "createdAt", "updatedAt")
  values (
    coalesce(new.raw_user_meta_data->>'id', concat('mob_', replace(new.id::text, '-', ''))),
    new.id::text,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'technician')::"UserRole",
    true,
    now(),
    now()
  )
  on conflict ("authId") do update
  set "email" = excluded."email",
      "name" = excluded."name",
      "updatedAt" = now();

  return new;
end;
$$;
