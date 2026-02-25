## Supabase Setup (Phase 1)

This project uses Supabase for auth, storage, database, and edge functions.

### 1) Create Project

1. Create a new Supabase project.
2. Copy `Project URL` and `anon public` key.
3. Add them to `PlumbingQuoteApp/Config.swift` (local only).

### 2) Auth

1. Enable Email provider.
2. Disable self-serve sign-up if you only want admin-created technician accounts.

### 3) Storage

Create a bucket named `quote-images` with:
- Public bucket: `false`
- Max file size: `5 MB`
- Allowed MIME: `image/jpeg`, `image/png`, `image/heic`

Run this SQL for storage policies:

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'quote-images',
  'quote-images',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do nothing;

create policy "Authenticated users can upload quote images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'quote-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Authenticated users can read quote images"
on storage.objects for select to authenticated
using (bucket_id = 'quote-images');
```

### 4) Edge Function Secrets

Set secrets in Supabase dashboard:

- `OPENAI_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

If you already have these in `.env.local`, use those exact values when setting Supabase Edge Function secrets.

### 5) Run Migrations

Apply:

1. `supabase/migrations/001_schema.sql`
2. `supabase/migrations/002_seed_industry.sql`
3. `supabase/migrations/003_storage_quote_images.sql`
4. `supabase/migrations/004_production_hardening.sql`

### 6) Deploy Edge Function

Deploy `supabase/functions/analyze-issue`.
