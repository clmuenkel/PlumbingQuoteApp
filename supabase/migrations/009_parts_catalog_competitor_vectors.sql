create table if not exists public.parts_catalog (
  id text primary key,
  sku text,
  brand text not null,
  name text not null,
  description text,
  category text not null,
  subcategory text,
  wholesale_price decimal(10,2),
  retail_price decimal(10,2),
  unit_of_measure text not null default 'each',
  specifications jsonb not null default '{}'::jsonb,
  source text not null default 'supplyhouse',
  source_url text,
  embedding extensions.vector(1536),
  is_active boolean not null default true,
  date_scraped timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_parts_catalog_embedding
  on public.parts_catalog
  using hnsw (embedding extensions.vector_cosine_ops);

create index if not exists idx_parts_catalog_active
  on public.parts_catalog (is_active, category, subcategory, brand);

alter table public.competitor_pricing
  add column if not exists embedding extensions.vector(1536);

create index if not exists idx_competitor_pricing_embedding
  on public.competitor_pricing
  using hnsw (embedding extensions.vector_cosine_ops);

create unique index if not exists idx_competitor_pricing_dedupe
  on public.competitor_pricing (lower(service_type), source, region);

create or replace function public.match_parts_catalog(
  query_embedding extensions.vector(1536),
  match_count int default 10
)
returns table (
  id text,
  sku text,
  brand text,
  name text,
  description text,
  category text,
  subcategory text,
  wholesale_price decimal(10,2),
  retail_price decimal(10,2),
  unit_of_measure text,
  specifications jsonb,
  source text,
  source_url text,
  similarity float
)
language sql
stable
as $$
  select
    pc.id,
    pc.sku,
    pc.brand,
    pc.name,
    pc.description,
    pc.category,
    pc.subcategory,
    pc.wholesale_price,
    pc.retail_price,
    pc.unit_of_measure,
    pc.specifications,
    pc.source,
    pc.source_url,
    1 - (pc.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.parts_catalog pc
  where pc.is_active = true
    and pc.embedding is not null
  order by pc.embedding operator(extensions.<=>) query_embedding
  limit greatest(match_count, 1);
$$;

create or replace function public.match_competitor_pricing(
  query_embedding extensions.vector(1536),
  match_count int default 20,
  match_region text default 'DFW'
)
returns table (
  id text,
  service_type text,
  source text,
  source_url text,
  region text,
  price_low decimal(10,2),
  price_avg decimal(10,2),
  price_high decimal(10,2),
  data_type text,
  raw_text text,
  date_scraped timestamptz,
  expires_at timestamptz,
  similarity float
)
language sql
stable
as $$
  select
    cp.id,
    cp.service_type,
    cp.source,
    cp.source_url,
    cp.region,
    cp.price_low,
    cp.price_avg,
    cp.price_high,
    cp.data_type,
    cp.raw_text,
    cp.date_scraped,
    cp.expires_at,
    1 - (cp.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.competitor_pricing cp
  where cp.is_active = true
    and cp.region = match_region
    and cp.expires_at > now()
    and cp.embedding is not null
  order by cp.embedding operator(extensions.<=>) query_embedding
  limit greatest(match_count, 1);
$$;
