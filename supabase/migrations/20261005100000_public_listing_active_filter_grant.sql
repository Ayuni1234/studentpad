-- PostgREST checks privileges for columns used in filters as well as the
-- returned projection. The flag is safe to expose; RLS still hides inactive
-- rows from anonymous visitors.
grant select (is_active) on public.listings to anon;
