-- PlumbQuote Phase 1 schema (aligned to existing Prisma tables)
-- This migration is additive only and does not create parallel quote/user tables.

create extension if not exists pgcrypto;

create table if not exists public.industry_rates (
  id text primary key,
  category text not null,
  subcategory text not null,
  display_name text not null,
  description text,
  price_good decimal(10,2) not null,
  price_better decimal(10,2) not null,
  price_best decimal(10,2) not null,
  labor_hours_good decimal(4,1),
  labor_hours_better decimal(4,1),
  labor_hours_best decimal(4,1),
  labor_rate_per_hour decimal(8,2) not null default 85.00,
  warranty_months_good int not null default 3,
  warranty_months_better int not null default 12,
  warranty_months_best int not null default 24,
  solution_good text,
  solution_better text,
  solution_best text,
  tags text[] not null default '{}',
  source text,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (category, subcategory)
);

create index if not exists idx_industry_rates_category_subcategory
  on public.industry_rates (category, subcategory);
create index if not exists idx_industry_rates_tags_gin
  on public.industry_rates using gin (tags);

create table if not exists public.industry_pricebook_map (
  id text primary key,
  industry_rate_id text not null references public.industry_rates(id) on delete cascade,
  price_book_item_id text references public."PriceBookItem"(id),
  price_book_category_id text references public."PriceBookCategory"(id),
  fallback_line_item_name text,
  is_required boolean not null default true,
  quantity numeric not null default 1,
  tier_minimum text,
  created_at timestamptz not null default now()
);

create index if not exists idx_industry_pricebook_map_rate
  on public.industry_pricebook_map (industry_rate_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public."User"
    set "email" = new.email,
        "name" = coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
        "updatedAt" = now()
  where "authId" = new.id::text;

  if not found then
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
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();
