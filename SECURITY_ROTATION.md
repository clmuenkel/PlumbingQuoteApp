# Credential Rotation Runbook

Use this checklist to rotate credentials after exposure.

## 1) Rotate OpenAI API Key

1. Create a new API key in OpenAI dashboard.
2. Revoke the old key.
3. Update Supabase secret:

```bash
supabase secrets set OPENAI_API_KEY=<new-openai-key>
```

## 2) Rotate Supabase Service Role Key

1. In Supabase dashboard, rotate JWT secret / service key (Project Settings).
2. Update local `.env.local`.
3. Confirm edge functions still run.

## 3) Rotate Database Password

1. In Supabase dashboard, rotate database password.
2. Update local `.env.local` values for:
   - `DATABASE_URL`
   - `DIRECT_URL`
3. Validate connectivity:

```bash
supabase db push
```

## 4) Verify After Rotation

```bash
supabase functions deploy analyze-issue
supabase functions list
```

Run one end-to-end quote in the app to verify auth, image upload, and estimate writes.
