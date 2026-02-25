-- Storage bucket + policies for quote images

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
using (
  bucket_id = 'quote-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
