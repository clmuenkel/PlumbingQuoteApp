## refresh-competitor-pricing

Scheduled crawler function for competitor pricing ingestion (DFW market).

### Trigger Options

1. Supabase Scheduled Functions / Cron (recommended)
2. External scheduler (n8n, GitHub Actions, or any cron runner)

### Example Weekly Trigger

Run every Sunday at 2:00 AM CST:

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/refresh-competitor-pricing" \
  -H "Authorization: Bearer <service-role-key>" \
  -H "Content-Type: application/json" \
  -d '{"urls":["https://www.angi.com/articles/how-much-will-plumbing-repair-cost.htm"]}'
```

### Required Secrets

- `FIRECRAWL_API_KEY`
- `ANTHROPIC_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`

### Security Controls

- Requires either:
  - `REFRESH_COMPETITOR_PRICING_SECRET` via `x-refresh-token` header, or
  - a valid Supabase Bearer token.
- `COMPETITOR_SOURCE_ALLOWLIST` limits crawl targets to approved domains.
  - Default: `angi.com,fixr.com,homeguide.com`
- Non-HTTPS URLs, localhost/private-network URLs, and non-allowlisted domains are rejected.
