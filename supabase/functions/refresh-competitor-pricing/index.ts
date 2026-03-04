import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AppError, corsHeaders, isAllowedPublicUrl, jsonResponse, requireBearerToken } from "../_shared/http.ts";

type FirecrawlResult = {
  markdown?: string;
  url?: string;
};

const CORS_METHODS = "POST, OPTIONS";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const firecrawlKey = Deno.env.get("FIRECRAWL_API_KEY");
const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
const openAiKey = Deno.env.get("OPENAI_API_KEY");
const refreshSecret = Deno.env.get("REFRESH_COMPETITOR_PRICING_SECRET");

const defaultAllowedHosts = [
  "angi.com",
  "fixr.com",
  "homeguide.com",
];
const allowedHosts = new Set(
  (Deno.env.get("COMPETITOR_SOURCE_ALLOWLIST") ?? defaultAllowedHosts.join(","))
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter((host) => host.length > 0),
);

if (!supabaseUrl || !serviceRoleKey || !firecrawlKey || !anthropicKey || !openAiKey) {
  throw new Error("Missing required env vars for refresh-competitor-pricing");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function crawlUrl(url: string): Promise<FirecrawlResult | null> {
  const response = await fetch("https://api.firecrawl.dev/v1/scrape", {
    method: "POST",
    signal: AbortSignal.timeout(30_000),
    headers: {
      Authorization: `Bearer ${firecrawlKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      url,
      formats: ["markdown"],
      onlyMainContent: true,
    }),
  });

  if (!response.ok) return null;
  const payload = await response.json();
  return payload?.data
    ? { markdown: String(payload.data.markdown ?? ""), url }
    : null;
}

async function parsePricingWithClaude(rawText: string) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    signal: AbortSignal.timeout(40_000),
    headers: {
      "x-api-key": anthropicKey!,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      temperature: 0,
      max_tokens: 3000,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `Extract DFW home-service pricing entries from this text.
Return strict JSON array:
[
  {
    "service_type": "string",
    "price_low": 0,
    "price_avg": 0,
    "price_high": 0,
    "source": "string"
  }
]
Text:
${rawText.slice(0, 60000)}`,
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) return [];
  const payload = await response.json();
  const textBlock = Array.isArray(payload?.content) ? payload.content.find((c: Record<string, unknown>) => c.type === "text") : null;
  const text = String(textBlock?.text ?? "").trim();
  if (!text) return [];
  const clean = text.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
  try {
    const parsed = JSON.parse(clean);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function generateEmbedding(input: string): Promise<number[] | null> {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    signal: AbortSignal.timeout(20_000),
    headers: {
      Authorization: `Bearer ${openAiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "text-embedding-3-small",
      dimensions: 1536,
      input,
    }),
  });
  if (!response.ok) return null;
  const payload = await response.json();
  return Array.isArray(payload?.data?.[0]?.embedding) ? payload.data[0].embedding as number[] : null;
}

function deterministicId(serviceType: string, source: string, region: string): string {
  const raw = `${serviceType.toLowerCase()}|${source.toLowerCase()}|${region.toLowerCase()}`;
  let hash = 0;
  for (let i = 0; i < raw.length; i += 1) {
    hash = ((hash << 5) - hash) + raw.charCodeAt(i);
    hash |= 0;
  }
  return `cmp_${Math.abs(hash).toString(16).padStart(8, "0")}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req, CORS_METHODS) });
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Method not allowed" }, 405, CORS_METHODS);
  }

  try {
    if (refreshSecret) {
      const providedSecret = req.headers.get("x-refresh-token");
      if (!providedSecret || providedSecret !== refreshSecret) {
        throw new AppError(401, "unauthorized", "Invalid refresh token");
      }
    } else {
      const token = requireBearerToken(req);
      const { data: userData, error: userError } = await admin.auth.getUser(token);
      if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");
    }

    const body = await req.json().catch(() => ({}));
    const targetUrls = Array.isArray(body?.urls) && body.urls.length
      ? body.urls as string[]
      : [
        "https://www.angi.com/articles/plumber-cost/tx/dallas",
        "https://www.angi.com/articles/how-much-does-water-heater-installation-cost/tx/dallas",
        "https://www.angi.com/articles/how-much-does-installing-sewer-line-cost/tx/dallas",
        "https://www.angi.com/articles/cost-to-unclog-a-drain/tx/dallas",
        "https://www.angi.com/articles/how-much-does-toilet-installation-cost/tx/dallas",
        "https://www.angi.com/articles/how-much-does-faucet-repair-cost/tx/dallas",
        "https://www.fixr.com/costs/plumbing",
        "https://www.fixr.com/costs/water-heater-installation",
        "https://www.fixr.com/costs/sewer-line-installation",
        "https://www.fixr.com/costs/drain-cleaning",
        "https://www.fixr.com/costs/toilet-installation",
        "https://www.fixr.com/costs/faucet-installation",
        "https://www.fixr.com/costs/garbage-disposal-installation",
        "https://www.fixr.com/costs/emergency-plumber",
        "https://homeguide.com/costs/plumber-cost",
        "https://homeguide.com/costs/water-heater-installation-cost",
        "https://homeguide.com/costs/sewer-line-replacement-cost",
        "https://homeguide.com/costs/drain-cleaning-cost",
        "https://homeguide.com/costs/toilet-repair-cost",
        "https://homeguide.com/costs/faucet-installation-cost",
        "https://homeguide.com/costs/garbage-disposal-installation-cost",
        "https://homeguide.com/costs/emergency-plumber-cost",
      ];

    const sanitizedUrls = targetUrls
      .map((url) => String(url).trim())
      .filter((url) => url.length > 0);

    if (!sanitizedUrls.length) {
      throw new AppError(400, "invalid_urls", "At least one URL is required");
    }
    if (sanitizedUrls.length > 50) {
      throw new AppError(400, "too_many_urls", "Maximum 50 URLs allowed");
    }
    for (const url of sanitizedUrls) {
      if (!isAllowedPublicUrl(url, allowedHosts)) {
        throw new AppError(400, "invalid_url", `URL is not allowed: ${url}`);
      }
    }

    const crawled = await Promise.all(sanitizedUrls.map((url) => crawlUrl(url)));
    const usable = crawled.filter((entry): entry is FirecrawlResult => Boolean(entry?.markdown));

    const records: Array<Record<string, unknown>> = [];
    for (const entry of usable) {
      const parsed = await parsePricingWithClaude(entry.markdown ?? "");
      for (const row of parsed) {
        const serviceType = String(row.service_type ?? "General Service");
        const source = String(row.source ?? "firecrawl_angi_dfw");
        const region = "DFW";
        const embeddingText = `${serviceType} ${region} plumbing price range ${String(row.price_low ?? "")} ${String(row.price_avg ?? "")} ${String(row.price_high ?? "")}`;
        const embedding = await generateEmbedding(embeddingText);
        records.push({
          id: deterministicId(serviceType, source, region),
          service_type: serviceType,
          source,
          source_url: entry.url ?? null,
          region,
          price_low: Number(row.price_low ?? 0) || null,
          price_avg: Number(row.price_avg ?? 0) || null,
          price_high: Number(row.price_high ?? 0) || null,
          data_type: "crawled",
          raw_text: null,
          date_scraped: new Date().toISOString(),
          expires_at: new Date(Date.now() + (7 * 24 * 60 * 60 * 1000)).toISOString(),
          is_active: true,
          embedding,
        });
      }
    }

    if (records.length) {
      const dedupedById = new Map<string, Record<string, unknown>>();
      for (const record of records) {
        const id = String(record.id ?? "");
        if (id) dedupedById.set(id, record);
      }
      await admin.from("competitor_pricing").upsert(Array.from(dedupedById.values()), { onConflict: "id" });
    }

    return jsonResponse(req, {
      ok: true,
      crawledUrls: usable.length,
      insertedRecords: records.length,
      runAt: new Date().toISOString(),
    }, 200, CORS_METHODS);
  } catch (error) {
    if (error instanceof AppError) {
      return jsonResponse(req, { error: error.message, code: error.code }, error.status, CORS_METHODS);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse(req, { error: message, code: "refresh_failed" }, 500, CORS_METHODS);
  }
});
