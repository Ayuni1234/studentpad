insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'student-verification',
  'student-verification',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "Students upload their own verification image"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'student-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Students read their own verification image"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'student-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Students remove their own verification image"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'student-verification'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
