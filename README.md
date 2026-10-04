# StudentPad Ghana

StudentPad helps university students in Ghana find off-campus housing and compatible roommates. It is a Flutter web app backed by Supabase Auth, Postgres, Storage, and Realtime.

## MVP features

- Email/password sign-up, sign-in, password reset, session handling, and profile setup.
- Private student-ID uploads submitted for manual reviewer approval. Uploading an ID does not automatically verify a student.
- Verified-student Explore feed for `has_space` and `needs_space` listings, with private listing photos, filters, and listing details.
- Listing creation and editing, plus pause/reactivate controls in **Profile → My listings**.
- Lifestyle profiles with university, GHS budget range, cleanliness preference, sleep schedule, and an optional roommate introduction.
- Compatibility-ranked verified students with “Say hello” in-app chat.
- Realtime inbox and messages, with database-enforced peer blocking and a private conversation-report workflow.
- Reviewer screens for pending student IDs and peer reports.

## Run the web app

1. Install Flutter and fetch packages:

   ```sh
   flutter pub get
   ```

2. Run the app locally:

   ```sh
   flutter run -d chrome
   ```

3. Build a release web bundle:

   ```sh
   flutter build web --release
   ```

The app currently has a Flutter web target. Android and iOS runner projects have not been generated yet.

## Supabase configuration

The app is configured for the connected StudentPad project. The project URL and public publishable/anon key are supplied in `lib/core/services/supabase_service.dart`; build-time values can override them with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.

In Supabase Auth settings:

1. Enable Email and Password authentication.
2. Choose whether new accounts must confirm their email.
3. Set the Site URL to the deployed Flutter web origin. Add local development and deployed callback URLs to the redirect allow list when using password-reset links or email callbacks.

The schema and security changes are in timestamped SQL files under `supabase/migrations/`. The connected project has the schema and security migrations through `20261004141907_peer_report_queue_rpc`; the profile upsert permission fix is captured in `20261004150000_profiles_upsert_permissions.sql`. When setting up a separate project, apply every migration in timestamp order.

All exposed application tables use Row Level Security. Student-ID images are in the private `student-verification` bucket and are reviewed through restricted server-side functions. Listing images are in the private `listing-photos` bucket, limited to 5 MB JPG, PNG, or WebP files. Do not put a service-role or other secret key in the Flutter app.

## First reviewer setup

Reviewer membership is deliberately managed outside the client app. To enable ID reviews and the peer-report queue:

1. Create a normal StudentPad Auth account for the trusted reviewer and complete email confirmation if it is enabled.
2. In Supabase Dashboard → **Authentication → Users**, copy that account’s Auth user UUID.
3. As the Supabase project owner, add that UUID in the SQL Editor:

   ```sql
   insert into app_private.verification_reviewers (user_id)
   values ('AUTH_USER_UUID'::uuid)
   on conflict do nothing;
   ```

The reviewer roster is private and is not writable from the app. Never promote an account unless its owner is trusted to inspect student IDs and review safety reports. Reviewer access is managed directly in the private roster, outside the client app.

## App structure

- `lib/features/auth/` — onboarding, verification, reviewer tools, account profile, and safety information.
- `lib/features/listings/` — Explore feed, listing publishing, editing, and owner management.
- `lib/features/matching/` — student setup, lifestyle preferences, and compatibility results.
- `lib/features/chat/` — inbox, realtime chat, peer blocking, and reporting.
- `lib/core/` — Supabase client configuration, app shell, shared widgets, and routing.
- `supabase/migrations/` — schema, indexes, policies, functions, storage, and realtime setup.
