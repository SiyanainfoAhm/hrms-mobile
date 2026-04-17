# Supabase Edge Functions (mobile)

This Flutter app is intended to call Supabase **Edge Functions** directly.

## Prerequisites

- Install Supabase CLI
- Link this repo to your Supabase project

## Deploy functions from this repo

From repo root:

```powershell
supabase link --project-ref <your-project-ref>
supabase functions deploy send-hrms-invite-email
```

## Create a new function (template)

```powershell
supabase functions new hrms-example
supabase functions deploy hrms-example
```

## Mobile runtime config

Run Flutter with:

```powershell
flutter run --dart-define=SUPABASE_URL=https://<your-project>.supabase.co --dart-define=SUPABASE_ANON_KEY=<your_anon_key>
```

