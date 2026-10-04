-- Keep the private reviewer roster unreadable even if table grants change later.
create policy "Reviewer roster has no direct access"
  on app_private.verification_reviewers
  for all
  to authenticated
  using (false)
  with check (false);
