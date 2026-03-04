create extension if not exists vector with schema extensions;

create table if not exists public.price_book_vectors (
  id text primary key,
  category text not null,
  subcategory text,
  service_name text not null,
  description text,
  flat_rate decimal(10,2),
  hourly_rate decimal(10,2),
  estimated_labor_hours decimal(4,1),
  parts_list jsonb not null default '[]'::jsonb,
  unit_of_measure text not null default 'each',
  cost decimal(10,2),
  taxable boolean not null default true,
  warranty_tier text,
  tags text[] not null default '{}',
  embedding extensions.vector(1536),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_price_book_vectors_embedding
  on public.price_book_vectors
  using hnsw (embedding extensions.vector_cosine_ops);

create index if not exists idx_price_book_vectors_active
  on public.price_book_vectors (is_active, category, subcategory);

create table if not exists public.competitor_pricing (
  id text primary key,
  service_type text not null,
  source text not null,
  source_url text,
  region text not null default 'DFW',
  price_low decimal(10,2),
  price_avg decimal(10,2),
  price_high decimal(10,2),
  data_type text not null default 'crawled',
  raw_text text,
  date_scraped timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  is_active boolean not null default true
);

create index if not exists idx_competitor_pricing_service
  on public.competitor_pricing (service_type, region, is_active);

create index if not exists idx_competitor_pricing_expiry
  on public.competitor_pricing (expires_at);

create table if not exists public.pipeline_runs (
  id text primary key,
  estimate_id text references public."Estimate"(id),
  langfuse_trace_id text,
  steps jsonb not null default '[]'::jsonb,
  total_input_tokens int not null default 0,
  total_output_tokens int not null default 0,
  total_cost_usd decimal(8,6) not null default 0,
  duration_ms int,
  created_at timestamptz not null default now()
);

create or replace function public.match_price_book_vectors(
  query_embedding extensions.vector(1536),
  match_count int default 5
)
returns table (
  id text,
  category text,
  subcategory text,
  service_name text,
  description text,
  flat_rate decimal(10,2),
  hourly_rate decimal(10,2),
  estimated_labor_hours decimal(4,1),
  parts_list jsonb,
  unit_of_measure text,
  cost decimal(10,2),
  taxable boolean,
  warranty_tier text,
  similarity float
)
language sql
stable
as $$
  select
    pbv.id,
    pbv.category,
    pbv.subcategory,
    pbv.service_name,
    pbv.description,
    pbv.flat_rate,
    pbv.hourly_rate,
    pbv.estimated_labor_hours,
    pbv.parts_list,
    pbv.unit_of_measure,
    pbv.cost,
    pbv.taxable,
    pbv.warranty_tier,
    1 - (pbv.embedding operator(extensions.<=>) query_embedding) as similarity
  from public.price_book_vectors pbv
  where pbv.is_active = true
    and pbv.embedding is not null
  order by pbv.embedding operator(extensions.<=>) query_embedding
  limit greatest(match_count, 1);
$$;
