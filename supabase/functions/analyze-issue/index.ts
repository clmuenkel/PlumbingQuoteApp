import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AppError, corsHeaders, createId, jsonResponse, requireBearerToken } from "../_shared/http.ts";

type TierKey = "good" | "better" | "best";
type GateStatus = "pass" | "warning" | "blocked";

type AnalyzeRequest = {
  images: string[];
  audioBase64?: string;
  audioMimeType?: string;
  voiceTranscript?: string;
  additionalNotes?: string;
  customerName?: string;
  customerPhone?: string;
  customerEmail?: string;
  customerAddress?: string;
  allowOverride?: boolean;
};

type PricingConfig = {
  laborRatePerHour: number;
  taxRate: number;
};

type InputProcessingResult = {
  transcript: string;
  imageAnalysis: string;
  unifiedDescription: string;
};

type IssueClassification = {
  category: string;
  subcategory: string;
  description: string;
  equipmentMakeModel: string;
  complexity: number;
  requiredParts: string[];
  estimatedLaborHours: number;
  severity: "Minor" | "Moderate" | "Major" | "Emergency";
  confidence: number;
};

type PriceBookMatch = {
  id: string;
  serviceName: string;
  description: string;
  flatRate: number;
  hourlyRate: number;
  estimatedLaborHours: number;
  partsList: Array<{ name: string; cost: number; quantity: number }>;
  similarity: number;
};

type CompetitorPriceRange = {
  priceLow: number;
  priceAvg: number;
  priceHigh: number;
  confidence: number;
  sources: Array<{ source: string; url?: string }>;
};

type PartsCatalogMatch = {
  id: string;
  sku: string | null;
  brand: string;
  name: string;
  category: string;
  subcategory: string;
  wholesalePrice: number;
  retailPrice: number | null;
  similarity: number;
};

type IndustryRateRow = {
  id: string;
  category: string;
  subcategory: string;
  display_name?: string;
  source?: string;
  source_urls?: string[];
  price_good?: number;
  price_better?: number;
  price_best?: number;
  labor_hours_good?: number;
  labor_hours_better?: number;
  labor_hours_best?: number;
};

type MarketDataBundle = {
  industryRate: IndustryRateRow | null;
  dfwContext: typeof DFW_CONTEXT;
  companyLaborRate: number;
  taxRate: number;
  emergencyMultiplier: number;
};

type SynthesisPart = {
  name: string;
  partNumber?: string;
  brand?: string;
  unitPrice: number;
  quantity: number;
  category: "part" | "labor";
};

type SynthesisTier = {
  total: number;
  laborHours: number;
  laborRate: number;
  warrantyMonths: number;
  solutionDescription: string;
  notes: string;
  parts: SynthesisPart[];
};

type PricingSynthesis = {
  recommendedPrice: number;
  priceBookPrice: number;
  marketAverage: number;
  marketRange: { low: number; high: number };
  confidence: number;
  reasoning: string;
  validationFlags: string[];
  good: SynthesisTier;
  better: SynthesisTier;
  best: SynthesisTier;
};

type TraceStep = {
  name: string;
  durationMs: number;
  metadata?: Record<string, unknown>;
};

class TraceCollector {
  traceId = crypto.randomUUID();
  private starts = new Map<string, number>();
  steps: TraceStep[] = [];
  inputTokens = 0;
  outputTokens = 0;
  totalCostUsd = 0;
  startedAt = Date.now();

  start(name: string) {
    this.starts.set(name, Date.now());
  }

  end(name: string, metadata?: Record<string, unknown>) {
    const start = this.starts.get(name) ?? Date.now();
    this.steps.push({ name, durationMs: Date.now() - start, metadata });
    this.starts.delete(name);
  }

  addUsage(inputTokens = 0, outputTokens = 0, costUsd = 0) {
    this.inputTokens += Math.max(0, Math.round(inputTokens));
    this.outputTokens += Math.max(0, Math.round(outputTokens));
    this.totalCostUsd = round2(this.totalCostUsd + costUsd);
  }

  get durationMs() {
    return Date.now() - this.startedAt;
  }
}


const DB_ENUMS = {
  userRoleTechnician: "technician",
  estimateStatusDraft: "draft",
  estimateTier: {
    good: "good",
    better: "better",
    best: "best",
  } as Record<TierKey, string>,
};

const DFW_CONTEXT = {
  region: "Dallas-Fort Worth, TX",
  avgServiceCallRate: { low: 125, avg: 321, high: 469 },
  hourlyRates: {
    masterPlumber: { low: 22, avg: 29.62, high: 40 },
    journeymanPlumber: { low: 20, avg: 25, high: 35 },
    plumberHelper: { low: 15, avg: 19.86, high: 27 },
    hvacTechnician: { low: 17, avg: 23.49, high: 34 },
  },
  emergencyMultiplier: 1.75,
  regionalCostIndex: 0.97,
  commonFactors: [
    "Clay soil increases foundation and pipe stress.",
    "Hard water accelerates fixture wear and mineral buildup.",
    "Temperature extremes stress plumbing and HVAC systems.",
    "Large installed base of aging residential infrastructure.",
  ],
  lastUpdated: "2026-Q1",
};

const MIN_TEXT_SIGNAL_LEN = 12;
const MIN_CONFIDENCE = 0.70;
const CLAUDE_MODEL = "claude-sonnet-4-6";

const CORS_METHODS = "POST, OPTIONS";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const openAiKey = Deno.env.get("OPENAI_API_KEY");
const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
const tavilyKey = Deno.env.get("TAVILY_API_KEY");
const langfuseSecret = Deno.env.get("LANGFUSE_SECRET_KEY");
const langfusePublic = Deno.env.get("LANGFUSE_PUBLIC_KEY");
const langfuseHost = Deno.env.get("LANGFUSE_HOST") ?? "https://cloud.langfuse.com";

if (!supabaseUrl || !serviceRoleKey || !openAiKey || !anthropicKey) {
  throw new Error("Missing required env vars");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function base64Payload(value: string): string {
  return value.includes(",") ? value.split(",")[1] : value;
}

function base64ToBytes(base64OrDataUrl: string): Uint8Array {
  const decoded = atob(base64Payload(base64OrDataUrl));
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i += 1) bytes[i] = decoded.charCodeAt(i);
  return bytes;
}

function stripJsonFences(value: string): string {
  const trimmed = value.trim();
  if (trimmed.startsWith("```")) {
    return trimmed.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  }
  return trimmed;
}

function looksLikeCompleteJson(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  const startsValid = trimmed.startsWith("{") || trimmed.startsWith("[");
  const endsValid = trimmed.endsWith("}") || trimmed.endsWith("]");
  return startsValid && endsValid;
}

function parseNumbersFromText(text: string): number[] {
  const matches = text.match(/\$?\d{2,5}(?:,\d{3})?(?:\.\d{1,2})?/g) ?? [];
  return matches
    .map((raw) => Number(raw.replace("$", "").replaceAll(",", "")))
    .filter((n) => Number.isFinite(n) && n >= 30 && n <= 25000);
}

function average(values: number[]): number {
  if (!values.length) return 0;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function clampAroundAnchor(value: number, anchor: number, toleranceRatio: number): number {
  if (!Number.isFinite(anchor) || anchor <= 0) return value;
  const tolerance = Math.max(0, toleranceRatio);
  const minAllowed = anchor * (1 - tolerance);
  const maxAllowed = anchor * (1 + tolerance);
  return Math.max(minAllowed, Math.min(maxAllowed, value));
}

function normalizeTier(tier: SynthesisTier, fallbackLaborRate: number): SynthesisTier {
  const parts = Array.isArray(tier.parts) && tier.parts.length
    ? tier.parts
    : [{ name: "Primary Repair Scope", unitPrice: Math.max(50, tier.total * 0.35), quantity: 1, category: "part" as const }];
  return {
    total: Math.max(0, Number(tier.total ?? 0)),
    laborHours: Math.max(0.5, Number(tier.laborHours ?? 1)),
    laborRate: Math.max(50, Number(tier.laborRate ?? fallbackLaborRate)),
    warrantyMonths: Math.max(1, Number(tier.warrantyMonths ?? 12)),
    solutionDescription: tier.solutionDescription?.trim() || "Recommended service scope for this tier.",
    notes: tier.notes?.trim() ?? "",
    parts: parts.map((p) => ({
      name: p.name || "Line Item",
      partNumber: p.partNumber ?? "",
      brand: p.brand ?? "",
      unitPrice: Math.max(0, Number(p.unitPrice ?? 0)),
      quantity: Math.max(1, Number(p.quantity ?? 1)),
      category: p.category === "labor" ? "labor" : "part",
    })),
  };
}

async function loadPricingConfig(): Promise<PricingConfig> {
  const { data } = await admin
    .from("company_settings")
    .select("labor_rate_per_hour, tax_rate")
    .eq("id", "default")
    .limit(1)
    .maybeSingle();
  return {
    laborRatePerHour: Number(data?.labor_rate_per_hour ?? 95),
    taxRate: Number(data?.tax_rate ?? 0.08),
  };
}

async function uploadWithRetry(
  path: string,
  bytes: Uint8Array,
  contentType: string,
  maxAttempts = 3,
): Promise<{ ok: boolean; error?: string }> {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const upload = await admin.storage.from("quote-images").upload(path, bytes, {
      contentType,
      upsert: true,
    });
    if (!upload.error) return { ok: true };
    if (attempt === maxAttempts) return { ok: false, error: upload.error.message };
    await new Promise((resolve) => setTimeout(resolve, 350 * attempt));
  }
  return { ok: false, error: "Retry attempts exhausted" };
}

async function callClaudeJson<T>(
  systemPrompt: string,
  content: Array<Record<string, unknown>>,
  trace: TraceCollector,
  stepName: string,
  maxTokens = 1200,
  temperature = 0.2,
): Promise<T> {
  trace.start(stepName);
  const requestClaude = async (tokens: number) => {
    let response: Response;
    try {
      response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: AbortSignal.timeout(55_000),
        headers: {
          "x-api-key": anthropicKey!,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: CLAUDE_MODEL,
          max_tokens: tokens,
          temperature,
          system: systemPrompt,
          messages: [{ role: "user", content }],
        }),
      });
    } catch (e) {
      const name = (e as Error)?.name ?? "";
      if (name === "TimeoutError" || name === "AbortError") {
        throw new Error(`Claude API timed out during ${stepName}`);
      }
      throw e;
    }

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Claude failed: ${response.status} ${text}`);
    }

    const json = await response.json();
    const textBlock = Array.isArray(json?.content)
      ? json.content.find((entry: Record<string, unknown>) => entry.type === "text")
      : null;
    const raw = typeof textBlock?.text === "string" ? textBlock.text : "";
    if (!raw) throw new Error("Claude returned empty content");

    const usageInput = Number(json?.usage?.input_tokens ?? 0);
    const usageOutput = Number(json?.usage?.output_tokens ?? 0);
    const estimatedCost = ((usageInput / 1_000_000) * 3) + ((usageOutput / 1_000_000) * 15);
    trace.addUsage(usageInput, usageOutput, estimatedCost);

    const cleaned = stripJsonFences(raw);
    if (!looksLikeCompleteJson(cleaned)) throw new Error("Claude returned truncated JSON");
    return cleaned;
  };

  try {
    const primary = await requestClaude(maxTokens);
    try {
      const parsed = JSON.parse(primary) as T;
      trace.end(stepName, { ok: true, usageInput: trace.inputTokens, usageOutput: trace.outputTokens });
      return parsed;
    } catch {
      throw new Error("Claude returned truncated JSON");
    }
  } catch (error) {
    trace.end(stepName, { ok: false });
    throw error;
  }
}

async function transcribeWithWhisper(audioBase64: string, audioMimeType: string, trace: TraceCollector): Promise<string> {
  trace.start("step1_whisper");
  const bytes = base64ToBytes(audioBase64);
  const ext = audioMimeType.includes("wav") ? "wav" : audioMimeType.includes("m4a") ? "m4a" : "wav";
  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("response_format", "json");
  form.append("file", new Blob([bytes], { type: audioMimeType }), `voice.${ext}`);

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      signal: AbortSignal.timeout(25_000),
      headers: { Authorization: `Bearer ${openAiKey}` },
      body: form,
    });
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    trace.end("step1_whisper", { ok: false });
    if (name === "TimeoutError" || name === "AbortError") {
      throw new Error(`Whisper API timed out`);
    }
    throw e;
  }

  if (!response.ok) {
    const text = await response.text();
    trace.end("step1_whisper", { ok: false });
    throw new Error(`Whisper failed: ${response.status} ${text}`);
  }

  const payload = await response.json();
  const transcript = String(payload?.text ?? "").trim();
  trace.end("step1_whisper", { ok: true });
  return transcript;
}

async function processInput(
  images: string[],
  audioBase64: string | undefined,
  audioMimeType: string | undefined,
  voiceTranscript: string | undefined,
  additionalNotes: string | undefined,
  trace: TraceCollector,
): Promise<InputProcessingResult> {
  const fallbackTranscript = (voiceTranscript ?? "").trim();

  const visionPrompt = `You are analyzing images for Brooks Plumbing, a residential plumbing service company in Garland, Texas (DFW).
Focus on residential plumbing and water heater service only.
Identify what matters for accurate quoting:
- water heater type (tank or tankless), fuel type (gas or electric), approximate size/capacity, visible brand/model, age/condition clues (rust, corrosion, sediment, leaks), pilot/flue/vent clues
- fixture type and condition (faucet, toilet, shower valve/head, disposal), visible leak origin, wear, corrosion, cracked components
- plumbing context (pipe material, shutoff valve condition, access constraints, visible code-risk issues)
- urgency/risk clues (active leak, water damage, gas-related indicators, safety hazards)

Return strict JSON:
{
  "imageAnalysis": "concise technical visual findings",
  "equipmentMakeModel": "if visible, else unknown",
  "locationContext": "where issue appears located",
  "riskNotes": "safety or urgency clues"
}`;

  const content: Array<Record<string, unknown>> = [
    ...images.map((image) => ({
      type: "image",
      source: {
        type: "base64",
        media_type: "image/jpeg",
        data: base64Payload(image),
      },
    })),
    {
      type: "text",
      text: `Voice transcript: ${fallbackTranscript || "N/A"}\nAdditional notes: ${additionalNotes ?? "N/A"}`,
    },
  ];

  const shouldRunWhisper = Boolean(
    audioBase64
      && audioBase64.length > 30
      && fallbackTranscript.length < MIN_TEXT_SIGNAL_LEN,
  );

  const whisperPromise = shouldRunWhisper
    ? transcribeWithWhisper(audioBase64!, audioMimeType ?? "audio/wav", trace)
    : Promise.resolve(fallbackTranscript);

  const visionPromise = callClaudeJson<{
    imageAnalysis: string;
    equipmentMakeModel?: string;
    locationContext?: string;
    riskNotes?: string;
  }>(visionPrompt, content, trace, "step1_claude_vision", 1200, 0.2);

  const [whisperResult, visionResult] = await Promise.allSettled([whisperPromise, visionPromise]);
  const transcript = whisperResult.status === "fulfilled" && whisperResult.value.trim().length
    ? whisperResult.value.trim()
    : fallbackTranscript;

  if (visionResult.status !== "fulfilled") {
    throw visionResult.reason instanceof Error
      ? visionResult.reason
      : new Error("Vision analysis failed");
  }
  const vision = visionResult.value;

  const imageAnalysis = vision.imageAnalysis?.trim() || "No clear visual details extracted.";
  const unifiedDescription = [
    transcript ? `Transcript: ${transcript}` : "",
    `Visual analysis: ${imageAnalysis}`,
    vision.equipmentMakeModel ? `Equipment: ${vision.equipmentMakeModel}` : "",
    vision.locationContext ? `Location: ${vision.locationContext}` : "",
    vision.riskNotes ? `Risk notes: ${vision.riskNotes}` : "",
    additionalNotes?.trim() ? `Notes: ${additionalNotes.trim()}` : "",
  ].filter(Boolean).join("\n");

  return { transcript, imageAnalysis, unifiedDescription };
}

async function classifyIssue(
  jobDescription: string,
  categories: string[],
  trace: TraceCollector,
): Promise<IssueClassification> {
  const classificationPrompt = `Classify this plumbing job and return strict JSON only:
{
  "category": "exact category",
  "subcategory": "exact subcategory",
  "description": "customer-friendly diagnosis summary",
  "equipmentMakeModel": "string",
  "complexity": 1,
  "requiredParts": ["part names"],
  "estimatedLaborHours": 1.5,
  "severity": "Minor|Moderate|Major|Emergency",
  "confidence": 0.0
}

Use one of these category/subcategory pairs when possible:
${categories.join("\n")}`;

  const parsed = await callClaudeJson<IssueClassification>(
    classificationPrompt,
    [{ type: "text", text: jobDescription }],
    trace,
    "step2_classification",
    1200,
    0,
  );

  return {
    category: parsed.category || "General Plumbing",
    subcategory: parsed.subcategory || "General Repair",
    description: parsed.description || "Plumbing issue identified from photos and technician notes.",
    equipmentMakeModel: parsed.equipmentMakeModel || "Unknown",
    complexity: Math.max(1, Math.min(5, Number(parsed.complexity ?? 3))),
    requiredParts: Array.isArray(parsed.requiredParts) ? parsed.requiredParts.slice(0, 10) : [],
    estimatedLaborHours: Math.max(0.5, Number(parsed.estimatedLaborHours ?? 1.5)),
    severity: (["Minor", "Moderate", "Major", "Emergency"].includes(parsed.severity) ? parsed.severity : "Moderate") as IssueClassification["severity"],
    confidence: clamp01(Number(parsed.confidence ?? 0.75)),
  };
}

async function generateEmbedding(input: string, trace: TraceCollector): Promise<number[] | null> {
  trace.start("step3_embedding");
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: {
      Authorization: `Bearer ${openAiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "text-embedding-3-small",
      input,
      dimensions: 1536,
    }),
  });
  if (!response.ok) {
    trace.end("step3_embedding", { ok: false });
    return null;
  }
  const payload = await response.json();
  const tokens = Number(payload?.usage?.total_tokens ?? 0);
  trace.addUsage(tokens, 0, (tokens / 1_000_000) * 0.02);
  trace.end("step3_embedding", { ok: true, tokens });
  return Array.isArray(payload?.data?.[0]?.embedding) ? payload.data[0].embedding as number[] : null;
}

async function lookupPriceBook(classification: IssueClassification, trace: TraceCollector): Promise<PriceBookMatch[]> {
  trace.start("step3_pricebook_lookup");
  const query = `${classification.category} ${classification.subcategory} ${classification.description} ${classification.requiredParts.join(" ")}`.trim();

  const embedding = await generateEmbedding(query, trace);
  if (embedding) {
    const rpc = await admin.rpc("match_price_book_vectors", {
      query_embedding: embedding,
      match_count: 5,
    });

    if (!rpc.error && Array.isArray(rpc.data) && rpc.data.length) {
      const mapped = rpc.data.map((row: Record<string, unknown>) => ({
        id: String(row.id ?? createId("pbv")),
        serviceName: String(row.service_name ?? "Service"),
        description: String(row.description ?? ""),
        flatRate: Number(row.flat_rate ?? 0),
        hourlyRate: Number(row.hourly_rate ?? 0),
        estimatedLaborHours: Number(row.estimated_labor_hours ?? classification.estimatedLaborHours),
        partsList: Array.isArray(row.parts_list) ? row.parts_list as Array<{ name: string; cost: number; quantity: number }> : [],
        similarity: Number(row.similarity ?? 0),
      }));
      trace.end("step3_pricebook_lookup", { matches: mapped.length, source: "pgvector" });
      return mapped;
    }
  }

  const fallback = await admin
    .from("PriceBookItem")
    .select("id, name, description, unitPrice")
    .ilike("name", `%${classification.subcategory}%`)
    .eq("active", true)
    .limit(5);

  const rows = (fallback.data ?? []) as Array<{ id: string; name: string; description: string | null; unitPrice: number }>;
  const mapped = rows.map((row) => ({
    id: row.id,
    serviceName: row.name,
    description: row.description ?? "",
    flatRate: Number(row.unitPrice ?? 0),
    hourlyRate: 0,
    estimatedLaborHours: classification.estimatedLaborHours,
    partsList: [],
    similarity: 0.4,
  }));
  trace.end("step3_pricebook_lookup", { matches: mapped.length, source: "fallback_pricebookitem" });
  return mapped;
}

async function fetchTavilyPrices(classification: IssueClassification, trace: TraceCollector): Promise<{ values: number[]; sources: Array<{ source: string; url?: string }> }> {
  if (!tavilyKey) return { values: [], sources: [] };
  trace.start("step4_tavily");
  const query = `${classification.subcategory} repair cost Dallas Fort Worth 2026`;
  const response = await fetch("https://api.tavily.com/search", {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: tavilyKey,
      query,
      search_depth: "advanced",
      max_results: 6,
    }),
  });
  if (!response.ok) {
    trace.end("step4_tavily", { ok: false });
    return { values: [], sources: [] };
  }
  const payload = await response.json();
  const results = Array.isArray(payload?.results) ? payload.results as Array<Record<string, unknown>> : [];
  const values: number[] = [];
  const sources: Array<{ source: string; url?: string }> = [];
  for (const result of results) {
    const text = `${String(result.content ?? "")} ${String(result.title ?? "")}`;
    values.push(...parseNumbersFromText(text));
    sources.push({ source: "tavily_live", url: String(result.url ?? "") });
  }
  trace.end("step4_tavily", { ok: true, resultCount: results.length });
  return { values, sources };
}

async function lookupPartsCatalog(classification: IssueClassification, trace: TraceCollector): Promise<PartsCatalogMatch[]> {
  trace.start("step3_parts_catalog_lookup");
  const query = [
    classification.category,
    classification.subcategory,
    classification.description,
    classification.equipmentMakeModel,
    classification.requiredParts.join(" "),
  ].filter(Boolean).join(" ");

  const embedding = await generateEmbedding(query, trace);
  if (embedding) {
    const rpc = await admin.rpc("match_parts_catalog", {
      query_embedding: embedding,
      match_count: 10,
    });
    if (!rpc.error && Array.isArray(rpc.data) && rpc.data.length) {
      const mapped = rpc.data.map((row: Record<string, unknown>) => ({
        id: String(row.id ?? createId("prt")),
        sku: row.sku ? String(row.sku) : null,
        brand: String(row.brand ?? "Unknown"),
        name: String(row.name ?? "Part"),
        category: String(row.category ?? "Plumbing Supplies"),
        subcategory: String(row.subcategory ?? ""),
        wholesalePrice: Number(row.wholesale_price ?? 0),
        retailPrice: row.retail_price === null || row.retail_price === undefined ? null : Number(row.retail_price),
        similarity: Number(row.similarity ?? 0),
      }));
      trace.end("step3_parts_catalog_lookup", { source: "pgvector", matches: mapped.length });
      return mapped;
    }
  }

  const fallback = await admin
    .from("parts_catalog")
    .select("id, sku, brand, name, category, subcategory, wholesale_price, retail_price")
    .eq("is_active", true)
    .or(`name.ilike.%${classification.subcategory}%,category.ilike.%${classification.category}%`)
    .limit(10);

  const rows = (fallback.data ?? []) as Array<Record<string, unknown>>;
  const mapped = rows.map((row) => ({
    id: String(row.id ?? createId("prt")),
    sku: row.sku ? String(row.sku) : null,
    brand: String(row.brand ?? "Unknown"),
    name: String(row.name ?? "Part"),
    category: String(row.category ?? "Plumbing Supplies"),
    subcategory: String(row.subcategory ?? ""),
    wholesalePrice: Number(row.wholesale_price ?? 0),
    retailPrice: row.retail_price === null || row.retail_price === undefined ? null : Number(row.retail_price),
    similarity: 0.3,
  }));
  trace.end("step3_parts_catalog_lookup", { source: "fallback_table", matches: mapped.length });
  return mapped;
}

async function lookupMarketData(
  classification: IssueClassification,
  pricingConfig: PricingConfig,
  industryRows: IndustryRateRow[],
): Promise<MarketDataBundle> {
  const industryRate = industryRows.find((row) => row.category === classification.category && row.subcategory === classification.subcategory)
    ?? industryRows.find((row) => `${classification.category} ${classification.subcategory}`.toLowerCase().includes(String(row.subcategory).toLowerCase()))
    ?? null;
  return {
    industryRate,
    dfwContext: DFW_CONTEXT,
    companyLaborRate: pricingConfig.laborRatePerHour,
    taxRate: pricingConfig.taxRate,
    emergencyMultiplier: classification.severity === "Emergency" ? DFW_CONTEXT.emergencyMultiplier : 1,
  };
}

async function fetchCompetitorPricing(
  classification: IssueClassification,
  tavily: { values: number[]; sources: Array<{ source: string; url?: string }> },
  trace: TraceCollector,
): Promise<CompetitorPriceRange> {
  trace.start("step4_competitor");
  const query = `${classification.category} ${classification.subcategory} ${classification.description}`.trim();
  const embedding = await generateEmbedding(query, trace);
  let dbRows: Array<{
    price_low: number | null;
    price_avg: number | null;
    price_high: number | null;
    source: string | null;
    source_url: string | null;
  }> = [];
  let source = "pgvector";
  if (embedding) {
    const rpc = await admin.rpc("match_competitor_pricing", {
      query_embedding: embedding,
      match_count: 30,
      match_region: "DFW",
    });
    if (!rpc.error && Array.isArray(rpc.data) && rpc.data.length) {
      dbRows = rpc.data as typeof dbRows;
    }
  }

  if (!dbRows.length) {
    source = "fallback_ilike";
    const dbRowsRes = await admin
      .from("competitor_pricing")
      .select("price_low, price_avg, price_high, source, source_url")
      .eq("region", "DFW")
      .eq("is_active", true)
      .gt("expires_at", new Date().toISOString())
      .ilike("service_type", `%${classification.subcategory}%`)
      .limit(30);
    dbRows = (dbRowsRes.data ?? []) as typeof dbRows;
  }

  const dbValues: number[] = [];
  const dbSources = dbRows.map((row) => ({ source: row.source ?? "competitor_db", url: row.source_url ?? undefined }));
  for (const row of dbRows) {
    if (row.price_low) dbValues.push(Number(row.price_low));
    if (row.price_avg) dbValues.push(Number(row.price_avg));
    if (row.price_high) dbValues.push(Number(row.price_high));
  }

  const useTavilyValues = dbValues.length < 5;
  const allValues = (useTavilyValues ? [...dbValues, ...tavily.values] : dbValues)
    .filter((v) => Number.isFinite(v) && v > 0);
  if (!allValues.length) {
    trace.end("step4_competitor", { values: 0, source });
    return {
      priceLow: 0,
      priceAvg: 0,
      priceHigh: 0,
      confidence: 0.35,
      sources: [...dbSources, ...tavily.sources].slice(0, 10),
    };
  }

  const sorted = allValues.sort((a, b) => a - b);
  const low = sorted[0];
  const high = sorted[sorted.length - 1];
  const avg = round2(average(sorted));
  const confidence = clamp01(0.45 + Math.min(0.45, sorted.length * 0.03));
  trace.end("step4_competitor", {
    source,
    values: sorted.length,
    low,
    high,
    avg,
    tavilyIncluded: useTavilyValues,
    dbValues: dbValues.length,
    tavilyValues: tavily.values.length,
  });

  return {
    priceLow: round2(low),
    priceAvg: avg,
    priceHigh: round2(high),
    confidence,
    sources: [...dbSources, ...tavily.sources].slice(0, 12),
  };
}

async function synthesizePrice(
  classification: IssueClassification,
  priceBookMatches: PriceBookMatch[],
  competitorRange: CompetitorPriceRange,
  partsCatalog: PartsCatalogMatch[],
  marketData: MarketDataBundle,
  tavilyValues: number[],
  pricingConfig: PricingConfig,
  trace: TraceCollector,
): Promise<PricingSynthesis> {
  const synthesisPrompt = `You are the pricing brain for Brooks Plumbing, a residential plumbing company in Garland, Texas (DFW).
Create customer-facing Good/Better/Best pricing using:
1) price book candidates
2) DFW competitor market range
3) parts catalog with wholesale prices
4) DFW labor and regional context
5) complexity and part requirements

Company context rules:
- This quote is for residential plumbing and water heater service only.
- Favor practical, code-compliant Texas residential scope over speculative or commercial scope.
- Better tier should generally be the recommended long-term fix.
- Each tier solutionDescription must be specific and concrete (2-3 sentences), not generic.
- Include realistic labor, parts, disposal, and permit/compliance scope where applicable.
- For water heater installs include permit/inspection, old unit disposal, connector updates, and expansion tank when required by code.
- For fixture replacements include shutoff and supply line considerations when aged/corroded components are visible.

Determinism and anchoring rules:
- If industryRateAnchor is present, anchor pricing to it.
- Good total MUST stay within +/-20% of industryRateAnchor.good.
- Better total MUST stay within +/-20% of industryRateAnchor.better.
- Best total MUST stay within +/-20% of industryRateAnchor.best.
- If industryRateAnchor is missing, set Better near marketRange median; keep Good at 60-70% of Better and Best at 150-170% of Better.
- Use competitorRange from database as primary signal. Treat tavilyPrices as supplemental and lower-weight.
- Use partsCatalog wholesalePrice when available and apply 1.5x-2.5x customer markup.
- Do not invent high-cost parts when partsCatalog provides matching alternatives.
- Keep labor hours/rates realistic for the classified scope and DFW context.

Return strict JSON:
{
  "recommendedPrice": 0,
  "priceBookPrice": 0,
  "marketAverage": 0,
  "marketRange": { "low": 0, "high": 0 },
  "confidence": 0.0,
  "reasoning": "brief rationale",
  "validationFlags": ["..."],
  "good": {
    "total": 0,
    "laborHours": 0,
    "laborRate": 0,
    "warrantyMonths": 0,
    "solutionDescription": "",
    "notes": "",
    "parts": [{ "name": "", "partNumber": "", "brand": "", "unitPrice": 0, "quantity": 1, "category": "part" }]
  },
  "better": { "...same shape..." },
  "best": { "...same shape..." }
}`;

  const industryRateAnchor = marketData.industryRate
    ? {
      good: Number(marketData.industryRate.price_good ?? 0),
      better: Number(marketData.industryRate.price_better ?? 0),
      best: Number(marketData.industryRate.price_best ?? 0),
      laborHours: {
        good: Number(marketData.industryRate.labor_hours_good ?? classification.estimatedLaborHours),
        better: Number(marketData.industryRate.labor_hours_better ?? classification.estimatedLaborHours),
        best: Number(marketData.industryRate.labor_hours_best ?? classification.estimatedLaborHours),
      },
      sourceUrls: Array.isArray(marketData.industryRate.source_urls) ? marketData.industryRate.source_urls : [],
    }
    : null;

  const payload = {
    classification,
    priceBookMatches,
    competitorRange,
    industryRateAnchor,
    partsCatalog: partsCatalog.map((p) => ({
      sku: p.sku,
      brand: p.brand,
      name: p.name,
      category: p.category,
      subcategory: p.subcategory,
      wholesalePrice: p.wholesalePrice,
      retailPrice: p.retailPrice,
      similarity: p.similarity,
    })),
    marketData: {
      industryBaseline: marketData.industryRate,
      dfwLaborRates: marketData.dfwContext.hourlyRates,
      companyLaborRate: marketData.companyLaborRate,
      taxRate: marketData.taxRate,
      emergencyMultiplier: marketData.emergencyMultiplier,
    },
    tavilyPrices: tavilyValues,
    laborRatePerHour: pricingConfig.laborRatePerHour,
    taxRate: pricingConfig.taxRate,
    dfwContext: marketData.dfwContext,
    rules: {
      useRealPartsFromCatalog: true,
      applyStandardMarkup: "1.5x-2.5x wholesale for retail",
      tavilyPricesAreSupplemental: true,
      competitorDbWeightVsTavily: "3:1",
      goodBetterBestMustIncrease: true,
      includeReasoning: true,
      avoidSimpleMultiplierOnly: true,
      goodTierGuidance: "minimum viable fix with economy-grade parts and shortest scoped labor",
      betterTierGuidance: "long-term fix with OEM or mid-grade parts, root-cause scope",
      bestTierGuidance: "premium replacement/prevention scope with top-tier parts and longest warranty",
    },
  };

  const raw = await callClaudeJson<PricingSynthesis>(
    synthesisPrompt,
    [{ type: "text", text: JSON.stringify(payload) }],
    trace,
    "step5_synthesis",
    4096,
    0,
  );

  const marketAvg = Number(raw.marketAverage ?? competitorRange.priceAvg ?? 0);
  const bookAvg = priceBookMatches.length
    ? average(priceBookMatches.map((m) => m.flatRate || (m.hourlyRate * m.estimatedLaborHours)))
    : marketAvg;

  const base: PricingSynthesis = {
    recommendedPrice: Number(raw.recommendedPrice ?? marketAvg ?? bookAvg ?? 350),
    priceBookPrice: Number(raw.priceBookPrice ?? bookAvg ?? 0),
    marketAverage: Number(raw.marketAverage ?? marketAvg ?? 0),
    marketRange: {
      low: Number(raw.marketRange?.low ?? competitorRange.priceLow ?? 0),
      high: Number(raw.marketRange?.high ?? competitorRange.priceHigh ?? 0),
    },
    confidence: clamp01(Number(raw.confidence ?? 0.8)),
    reasoning: raw.reasoning?.trim() || "Balanced against local market range and service complexity.",
    validationFlags: Array.isArray(raw.validationFlags) ? raw.validationFlags : [],
    good: normalizeTier(raw.good, pricingConfig.laborRatePerHour),
    better: normalizeTier(raw.better, pricingConfig.laborRatePerHour),
    best: normalizeTier(raw.best, pricingConfig.laborRatePerHour),
  };

  base.good.total = Math.max(0, base.good.total);
  base.better.total = Math.max(base.good.total + 1, base.better.total);
  base.best.total = Math.max(base.better.total + 1, base.best.total);

  if (industryRateAnchor) {
    const clampTolerance = 0.25;
    const previous = {
      good: base.good.total,
      better: base.better.total,
      best: base.best.total,
    };
    base.good.total = round2(clampAroundAnchor(base.good.total, industryRateAnchor.good, clampTolerance));
    base.better.total = round2(clampAroundAnchor(base.better.total, industryRateAnchor.better, clampTolerance));
    base.best.total = round2(clampAroundAnchor(base.best.total, industryRateAnchor.best, clampTolerance));
    if (
      Math.abs(base.good.total - previous.good) >= 0.01
      || Math.abs(base.better.total - previous.better) >= 0.01
      || Math.abs(base.best.total - previous.best) >= 0.01
    ) {
      base.validationFlags.push("Tier totals were clamped to stay near industry anchor pricing.");
    }
  }

  base.good.total = Math.max(0, base.good.total);
  base.better.total = Math.max(base.good.total + 1, base.better.total);
  base.best.total = Math.max(base.better.total + 1, base.best.total);

  if (base.marketAverage > 0) {
    const ratio = base.better.total / base.marketAverage;
    if (ratio > 2) base.validationFlags.push("Recommended Better tier is more than 2x market average.");
    if (ratio < 0.5) base.validationFlags.push("Recommended Better tier is below 0.5x market average.");
  }
  if (base.confidence < 0.7) {
    base.validationFlags.push("Low confidence pricing recommendation.");
  }

  base.validationFlags = [...new Set(base.validationFlags)];
  return base;
}

async function ensureUserRow(authUserId: string, email: string | null, userName: string | null): Promise<{ id: string }> {
  const existing = await admin
    .from("User")
    .select("id")
    .eq("authId", authUserId)
    .limit(1)
    .maybeSingle();

  if (existing.data?.id) return { id: existing.data.id as string };

  const newUserId = createId("usr");
  const inserted = await admin
    .from("User")
    .insert({
      id: newUserId,
      authId: authUserId,
      name: userName ?? (email ? email.split("@")[0] : "Technician"),
      email: email ?? `${newUserId}@local.invalid`,
      role: DB_ENUMS.userRoleTechnician,
      active: true,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (!inserted.error && inserted.data?.id) return { id: inserted.data.id as string };

  const duplicateConflict = inserted.error?.code === "23505"
    || (inserted.error?.message ?? "").toLowerCase().includes("duplicate key")
    || (inserted.error?.message ?? "").toLowerCase().includes("unique constraint");

  if (duplicateConflict) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const retryExisting = await admin
        .from("User")
        .select("id")
        .eq("authId", authUserId)
        .limit(1)
        .maybeSingle();
      if (retryExisting.data?.id) return { id: retryExisting.data.id as string };
      await new Promise((resolve) => setTimeout(resolve, 250 * (attempt + 1)));
    }
  }

  throw new Error(`Could not create User row: ${inserted.error?.message ?? "unknown"}`);
}

async function persistLangfuseTrace(trace: TraceCollector, userId: string, estimateId: string | null) {
  if (!langfusePublic || !langfuseSecret) return;
  try {
    const auth = btoa(`${langfusePublic}:${langfuseSecret}`);
    await fetch(`${langfuseHost}/api/public/ingestion`, {
      method: "POST",
      signal: AbortSignal.timeout(5_000),
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        batch: [
          {
            id: createId("lf"),
            timestamp: new Date().toISOString(),
            type: "trace-create",
            body: {
              id: trace.traceId,
              name: "analyze-issue",
              userId,
              metadata: { estimateId },
            },
          },
        ],
      }),
    });
  } catch {
    // Non-blocking observability.
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req, CORS_METHODS) });
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405, CORS_METHODS);

  const trace = new TraceCollector();
  let estimateIdForTrace: string | null = null;
  let authUserId = "unknown";

  try {
    const token = requireBearerToken(req);
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");

    const body = (await req.json()) as AnalyzeRequest;
    const allowOverride = body.allowOverride === true;
    const images = body.images ?? [];
    if (!Array.isArray(images) || images.length === 0) throw new AppError(400, "image_required", "At least one image required");
    if (images.length > 5) throw new AppError(400, "too_many_images", "Maximum 5 images allowed");

    const authUser = userData.user;
    authUserId = authUser.id;
    const appUser = await ensureUserRow(
      authUser.id,
      authUser.email ?? null,
      (authUser.user_metadata?.name as string | undefined) ?? null,
    );

    const { data: industryRows } = await admin
      .from("industry_rates")
      .select("id, category, subcategory, display_name, description, price_good, price_better, price_best, labor_hours_good, labor_hours_better, labor_hours_best, warranty_months_good, warranty_months_better, warranty_months_best, solution_good, solution_better, solution_best, source, source_urls")
      .eq("is_active", true);
    if (!industryRows || !industryRows.length) {
      throw new AppError(503, "industry_rates_empty", "industry_rates is empty. Run seed migration first.");
    }

    const input = await processInput(
      images,
      body.audioBase64,
      body.audioMimeType,
      body.voiceTranscript,
      body.additionalNotes,
      trace,
    );

    const brooksCategories = new Set(["Fixtures", "Water Heater", "Pipe Repair", "Drain Services", "Emergency"]);
    const scopedIndustryRows = (industryRows as IndustryRateRow[]).filter((row) => brooksCategories.has(row.category));
    const categoryRows = scopedIndustryRows.length ? scopedIndustryRows : (industryRows as IndustryRateRow[]);
    const categoryList = categoryRows.map((row) => `${row.category} > ${row.subcategory}`);
    const classification = await classifyIssue(input.unifiedDescription, categoryList, trace);
    const pricingConfig = await loadPricingConfig();

    const gateReasons: string[] = [];
    if (input.transcript.trim().length < MIN_TEXT_SIGNAL_LEN && (body.additionalNotes ?? "").trim().length < MIN_TEXT_SIGNAL_LEN) {
      gateReasons.push("Description is too short. Add more detail by voice or notes.");
    }
    if (classification.confidence < MIN_CONFIDENCE) {
      gateReasons.push(`Low diagnosis confidence (${round2(classification.confidence)}). Retake photos or add detail.`);
    }
    if (gateReasons.length && !allowOverride) {
      return jsonResponse(req, {
        error: "Input quality is too weak for a reliable quote.",
        code: "input_quality_warning",
        gateStatus: "warning" as GateStatus,
        gateReasons,
        canOverride: true,
      }, 422, CORS_METHODS);
    }

    const [priceBookMatches, partsCatalog, tavilyData] = await Promise.all([
      lookupPriceBook(classification, trace),
      lookupPartsCatalog(classification, trace),
      fetchTavilyPrices(classification, trace),
    ]);
    const [competitorRange, marketData] = await Promise.all([
      fetchCompetitorPricing(classification, tavilyData, trace),
      lookupMarketData(classification, pricingConfig, categoryRows),
    ]);

    const synthesis = await synthesizePrice(
      classification,
      priceBookMatches,
      competitorRange,
      partsCatalog,
      marketData,
      tavilyData.values,
      pricingConfig,
      trace,
    );

    const matchedIndustry = marketData.industryRate ?? industryRows[0];

    const customerId = createId("cus");
    const customerInsert = await admin.from("Customer").insert({
      id: customerId,
      firstName: body.customerName?.split(" ")[0] ?? "On-Site",
      lastName: body.customerName?.split(" ").slice(1).join(" ") || "Customer",
      email: body.customerEmail ?? null,
      phone: body.customerPhone ?? null,
      address: body.customerAddress ?? null,
      city: null,
      state: null,
      zip: null,
      notes: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    if (customerInsert.error) throw new Error(`Customer insert failed: ${customerInsert.error.message}`);

    const estimateId = createId("est");
    estimateIdForTrace = estimateId;
    const publicToken = crypto.randomUUID().replace(/-/g, "");
    const firstImagePath = `${authUser.id}/${estimateId}/1.jpg`;
    const estimateInsert = await admin.from("Estimate").insert({
      id: estimateId,
      customerId,
      createdById: appUser.id,
      status: DB_ENUMS.estimateStatusDraft,
      aiDiagnosisNote: classification.description,
      aiPhotoUrl: `quote-images:${firstImagePath}`,
      voiceTranscript: input.transcript || null,
      customerNote: body.additionalNotes ?? null,
      internalNote: synthesis.reasoning,
      depositPercent: null,
      publicToken,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }).select("estimateNumber").single();
    if (estimateInsert.error) throw new Error(`Estimate insert failed: ${estimateInsert.error.message}`);
    const estimateNumber = Number(estimateInsert.data?.estimateNumber ?? 0) || null;

    const tierOrder: Array<{ key: TierKey; name: string; tier: SynthesisTier; recommended: boolean }> = [
      { key: "good", name: "Good", tier: synthesis.good, recommended: false },
      { key: "better", name: "Better", tier: synthesis.better, recommended: true },
      { key: "best", name: "Best", tier: synthesis.best, recommended: false },
    ];

    const quotesPayload: Record<TierKey, unknown> = { good: {}, better: {}, best: {} };
    const estimateOptionRows: Array<Record<string, unknown>> = [];
    const lineItemRows: Array<Record<string, unknown>> = [];

    for (let index = 0; index < tierOrder.length; index += 1) {
      const cfg = tierOrder[index];
      const optionId = createId("opt");
      const partsRows = cfg.tier.parts.filter((part) => part.category === "part");
      const partsTotal = round2(partsRows.reduce((sum, part) => sum + (part.unitPrice * part.quantity), 0));
      const laborTotal = round2(cfg.tier.laborHours * cfg.tier.laborRate);
      const tax = round2(partsTotal * pricingConfig.taxRate);
      let total = round2(cfg.tier.total || (partsTotal + laborTotal + tax));
      if (total < partsTotal + laborTotal + tax) {
        total = round2(partsTotal + laborTotal + tax);
      }
      const subtotal = round2(partsTotal + laborTotal);
      const adjustment = round2(total - (subtotal + tax));

      estimateOptionRows.push({
        id: optionId,
        estimateId,
        tier: DB_ENUMS.estimateTier[cfg.key],
        name: `${cfg.name} Option`,
        description: cfg.tier.solutionDescription,
        subtotal,
        total,
        recommended: cfg.recommended,
        sortOrder: index,
      });

      const lineRows = partsRows.map((part, idx) => ({
        id: createId("li"),
        optionId,
        priceBookItemId: null,
        name: part.name,
        description: part.brand || null,
        unitPrice: round2(part.unitPrice),
        quantity: round2(part.quantity),
        unit: "each",
        total: round2(part.unitPrice * part.quantity),
        sortOrder: idx,
      }));

      lineRows.push({
        id: createId("li"),
        optionId,
        priceBookItemId: null,
        name: "Labor",
        description: `${round2(cfg.tier.laborHours)} hours @ ${round2(cfg.tier.laborRate)}/hr`,
        unitPrice: round2(cfg.tier.laborRate),
        quantity: round2(cfg.tier.laborHours),
        unit: "hour",
        total: laborTotal,
        sortOrder: lineRows.length,
      });

      if (Math.abs(adjustment) >= 0.01) {
        lineRows.push({
          id: createId("li"),
          optionId,
          priceBookItemId: null,
          name: "Market Adjustment",
          description: "Adjustment to align with market triangulation",
          unitPrice: adjustment,
          quantity: 1,
          unit: "each",
          total: adjustment,
          sortOrder: lineRows.length,
        });
      }

      lineItemRows.push(...lineRows);

      const marketPositionPercent = synthesis.marketAverage > 0
        ? round2(((total - synthesis.marketAverage) / synthesis.marketAverage) * 100)
        : 0;

      quotesPayload[cfg.key] = {
        optionId,
        tier: cfg.name,
        lineItems: lineRows.map((r) => ({
          partName: r.name,
          partNumber: "",
          brand: String(r.description ?? ""),
          unitPrice: Number(r.unitPrice),
          quantity: Number(r.quantity),
          category: r.name === "Labor" ? "labor" : "part",
        })),
        laborHours: cfg.tier.laborHours,
        laborRate: cfg.tier.laborRate,
        laborTotal,
        partsTotal,
        tax,
        total,
        warrantyMonths: cfg.tier.warrantyMonths,
        solutionDescription: cfg.tier.solutionDescription,
        notes: cfg.tier.notes,
        priceBookPrice: round2(synthesis.priceBookPrice),
        marketAverage: round2(synthesis.marketAverage),
        marketRange: synthesis.marketRange,
        confidenceScore: round2(synthesis.confidence),
        reasoning: synthesis.reasoning,
        validationFlags: synthesis.validationFlags,
        marketPositionPercent,
      };
    }

    const optionInsert = await admin.from("EstimateOption").insert(estimateOptionRows);
    if (optionInsert.error) throw new Error(`EstimateOption insert failed: ${optionInsert.error.message}`);

    const lineInsert = await admin.from("LineItem").insert(lineItemRows);
    if (lineInsert.error) throw new Error(`LineItem insert failed: ${lineInsert.error.message}`);

    const uploadedPaths: string[] = [];
    const failedUploads: string[] = [];
    const uploadResults = await Promise.all(images.map(async (image, i) => {
      const path = `${authUser.id}/${estimateId}/${i + 1}.jpg`;
      const bytes = base64ToBytes(image);
      const upload = await uploadWithRetry(path, bytes, "image/jpeg");
      return { path, ok: upload.ok };
    }));
    for (const result of uploadResults) {
      if (result.ok) uploadedPaths.push(result.path);
      else failedUploads.push(result.path);
    }

    await admin.from("pipeline_runs").insert({
      id: createId("run"),
      estimate_id: estimateId,
      langfuse_trace_id: trace.traceId,
      steps: trace.steps,
      total_input_tokens: trace.inputTokens,
      total_output_tokens: trace.outputTokens,
      total_cost_usd: trace.totalCostUsd,
      duration_ms: trace.durationMs,
    });

    await persistLangfuseTrace(trace, authUser.id, estimateId);

    return jsonResponse(req, {
      quoteId: estimateId,
      estimateNumber,
      estimateId,
      gateStatus: gateReasons.length > 0 ? ("warning" as GateStatus) : ("pass" as GateStatus),
      gateReasons,
      canOverride: gateReasons.length > 0,
      pricingSource: {
        benchmark: matchedIndustry.source ?? null,
        benchmarkUrls: Array.isArray(matchedIndustry.source_urls) ? matchedIndustry.source_urls : [],
        competitorSources: competitorRange.sources,
      },
      customerName: body.customerName ?? null,
      customerPhone: body.customerPhone ?? null,
      customerEmail: body.customerEmail ?? null,
      customerAddress: body.customerAddress ?? null,
      imagePaths: uploadedPaths,
      failedUploads,
      issue: {
        category: classification.category,
        subcategory: classification.subcategory,
        description: classification.description,
        severity: classification.severity,
        confidence: clamp01(classification.confidence),
        recommendedSolutions: {
          good: synthesis.good.solutionDescription,
          better: synthesis.better.solutionDescription,
          best: synthesis.best.solutionDescription,
        },
      },
      quotes: quotesPayload,
    }, 200, CORS_METHODS);
  } catch (error) {
    await admin.from("error_logs").insert({
      id: createId("err"),
      source: "edge_function",
      severity: "error",
      message: error instanceof Error ? error.message : "Unknown error",
      context: { function: "analyze-issue", traceId: trace.traceId },
      device_info: "server",
      app_version: "edge",
    });
    await persistLangfuseTrace(trace, authUserId, estimateIdForTrace);
    if (error instanceof AppError) return jsonResponse(req, { error: error.message, code: error.code }, error.status, CORS_METHODS);
    const message = error instanceof Error ? error.message : "Unknown error";
    const lower = message.toLowerCase();
    const errName = error instanceof Error ? error.name.toLowerCase() : "";
    const isTimeout = errName === "timeouterror"
      || errName === "aborterror"
      || errName.includes("timeout")
      || errName.includes("abort")
      || lower.includes("timed out")
      || lower.includes("aborted")
      || lower.includes("signal timed out");
    let code = "upstream_failure";
    if (lower.includes("truncated json") || lower.includes("unexpected end of json input")) {
      code = "claude_truncated_json";
    } else if (isTimeout && lower.includes("whisper")) {
      code = "whisper_timeout";
    } else if (isTimeout && (lower.includes("claude") || lower.includes("anthropic"))) {
      code = "claude_timeout";
    } else if (isTimeout) {
      code = "upstream_timeout";
    }
    return jsonResponse(req, { error: message, code }, 502, CORS_METHODS);
  }
});
