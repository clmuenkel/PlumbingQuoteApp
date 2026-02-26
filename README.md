# PlumbQuote iOS

Production-focused iOS app for on-site plumbing estimates using photos + voice notes, backed by Supabase and an AI edge function.

## Architecture

- iOS SwiftUI app in `PlumbingQuoteApp/`
- Supabase SQL migrations in `supabase/migrations/`
- Edge function in `supabase/functions/analyze-issue/`
- Xcode project generated via `xcodegen` from `project.yml`

## Prerequisites

- Xcode 15+
- Homebrew
- XcodeGen (`brew install xcodegen`)
- Supabase CLI (for backend deploys)

## iOS Setup

1. Copy `PlumbingQuoteApp/Secrets.swift.example` to `PlumbingQuoteApp/Secrets.swift`.
2. Fill in:
   - `supabaseURL`
   - `supabaseAnonKey`
3. Generate project:

```bash
xcodegen generate
```

4. Open `PlumbingQuoteApp.xcodeproj` in Xcode.
5. Set signing team and bundle identifier for your org.

## Backend Setup

1. Link your Supabase project:

```bash
supabase link --project-ref <project-ref>
```

2. Apply migrations:

```bash
supabase db push
```

3. Set secrets:

```bash
supabase secrets set OPENAI_API_KEY=<key>
```

4. Deploy function:

```bash
supabase functions deploy analyze-issue
```

## Key Production Hardening Included

- Single-query quote history loading (no N+1 queries)
- Per-technician quote history filtering
- Request timeout + cancellation support for quote generation
- Structured error codes from edge function
- Company-configurable tax and labor rates via `company_settings`
- Explicit enum-safe status/tier values
- Storage RLS tightened to owner folder reads
- Quote reference number returned to app and shown in share output
- Dedicated `Secrets.swift` file (gitignored) for client config
- Image preview, haptics, and improved offline error handling

## Security

- `PlumbingQuoteApp/Secrets.swift` is gitignored.
- `.env.local` is gitignored.
- Rotate exposed credentials immediately if they were ever shared externally.
