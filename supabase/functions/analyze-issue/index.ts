import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

type TierKey = "good" | "better" | "best";

type AnalyzeRequest = {
  images: string[];
  voiceTranscript?: string;
  additionalNotes?: string;
  customerName?: string;
  customerPhone?: string;
  customerAddress?: string;
  allowOverride?: boolean;
};

type AiDiagnosis = {
  category: string;
  subcategory: string;
  description: string;
  severity: "Minor" | "Moderate" | "Major" | "Emergency";
  confidence: number;
  recommended_solutions?: Record<TierKey, string>;
};

type PricingConfig = {
  laborRatePerHour: number;
  taxRate: number;
};

type GateStatus = "pass" | "warning" | "blocked";

class AppError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const openAiKey = Deno.env.get("OPENAI_API_KEY");

if (!supabaseUrl || !serviceRoleKey || !openAiKey) {
  throw new Error("Missing required env vars");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const MIN_TEXT_SIGNAL_LEN = 12;
const MIN_CONFIDENCE = 0.75;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function loadPricingConfig(): Promise<PricingConfig> {
  const { data, error } = await admin
    .from("company_settings")
    .select("labor_rate_per_hour, tax_rate")
    .eq("id", "default")
    .limit(1)
    .maybeSingle();
  if (error) {
    return { laborRatePerHour: 95, taxRate: 0.08 };
  }
  return {
    laborRatePerHour: Number(data?.labor_rate_per_hour ?? 95),
    taxRate: Number(data?.tax_rate ?? 0.08),
  };
}

function createId(prefix: string): string {
  const token = crypto.randomUUID().replace(/-/g, "");
  return `${prefix}_${token}`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function hasMeaningfulTextSignal(voiceTranscript?: string, additionalNotes?: string): boolean {
  const transcript = (voiceTranscript ?? "").trim();
  const notes = (additionalNotes ?? "").trim();
  return transcript.length >= MIN_TEXT_SIGNAL_LEN || notes.length >= MIN_TEXT_SIGNAL_LEN;
}

function base64ToBytes(base64OrDataUrl: string): Uint8Array {
  const payload = base64OrDataUrl.includes(",") ? base64OrDataUrl.split(",")[1] : base64OrDataUrl;
  const decoded = atob(payload);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i += 1) bytes[i] = decoded.charCodeAt(i);
  return bytes;
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
    await new Promise((resolve) => setTimeout(resolve, 500 * attempt));
  }
  return { ok: false, error: "Retry attempts exhausted" };
}

async function identifyIssueWithAi(
  categoryList: string[],
  images: string[],
  voiceTranscript?: string,
  additionalNotes?: string,
): Promise<AiDiagnosis> {
  const systemPrompt = `You are a plumbing diagnosis AI for a field service quoting app.
Pricing context: downstream quote pricing is derived from Angi, HomeGuide, and Housecall Pro 2026 benchmark guides plus company price-book data.

Classify the issue into one of these categories:
${categoryList.join("\n")}

Return JSON only:
{
  "category": "exact category",
  "subcategory": "exact subcategory",
  "description": "1-2 sentence customer-friendly diagnosis",
  "severity": "Minor|Moderate|Major|Emergency",
  "confidence": 0.0,
  "recommended_solutions": {
    "good": "good option explanation",
    "better": "better option explanation",
    "best": "best option explanation"
  }
}`;

  const content = [
    ...images.map((image) => ({
      type: "image_url",
      image_url: {
        url: image.startsWith("data:image") ? image : `data:image/jpeg;base64,${image}`,
        detail: "low",
      },
    })),
    {
      type: "text",
      text: `Voice transcript: ${voiceTranscript ?? "N/A"}\nAdditional notes: ${additionalNotes ?? "N/A"}`,
    },
  ];

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      temperature: 0.2,
      max_tokens: 450,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI failed: ${response.status} ${await response.text()}`);
  }

  const json = await response.json();
  const raw = json?.choices?.[0]?.message?.content;
  if (!raw || typeof raw !== "string") {
    throw new Error("OpenAI returned invalid content");
  }

  const parsed = JSON.parse(raw) as AiDiagnosis;
  return {
    category: parsed.category,
    subcategory: parsed.subcategory,
    description: parsed.description ?? "Plumbing issue identified.",
    severity: parsed.severity ?? "Moderate",
    confidence: Number(parsed.confidence ?? 0.7),
    recommended_solutions: parsed.recommended_solutions ?? {
      good: "Standard repair with essential scope.",
      better: "Recommended repair with stronger long-term value.",
      best: "Premium future-proof solution.",
    },
  };
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

  if (!inserted.error && inserted.data?.id) {
    return { id: inserted.data.id as string };
  }

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      throw new AppError(401, "missing_bearer_token", "Missing bearer token");
    }
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");

    const body = (await req.json()) as AnalyzeRequest;
    const allowOverride = body.allowOverride === true;
    const images = body.images ?? [];
    if (!Array.isArray(images) || images.length === 0) throw new AppError(400, "image_required", "At least one image required");
    if (images.length > 5) throw new AppError(400, "too_many_images", "Maximum 5 images allowed");

    const authUser = userData.user;
    const appUser = await ensureUserRow(
      authUser.id,
      authUser.email ?? null,
      (authUser.user_metadata?.name as string | undefined) ?? null,
    );

    const { data: industryRows } = await admin
      .from("industry_rates")
      .select("id, category, subcategory, display_name, description, price_good, price_better, price_best, labor_hours_good, labor_hours_better, labor_hours_best, warranty_months_good, warranty_months_better, warranty_months_best, solution_good, solution_better, solution_best, source, source_urls")
      .eq("is_active", true);

    if (!industryRows || industryRows.length === 0) {
      throw new AppError(503, "industry_rates_empty", "industry_rates is empty. Run seed migration first.");
    }

    const categoryList = industryRows.map((r) => `${r.category} > ${r.subcategory}`);
    const diagnosis = await identifyIssueWithAi(categoryList, images, body.voiceTranscript, body.additionalNotes);

    const gateReasons: string[] = [];
    if (!hasMeaningfulTextSignal(body.voiceTranscript, body.additionalNotes)) {
      gateReasons.push("Description is too short. Add more detail by voice or notes.");
    }
    if (Number(diagnosis.confidence ?? 0) < MIN_CONFIDENCE) {
      gateReasons.push(`Low diagnosis confidence (${round2(Number(diagnosis.confidence ?? 0))}). Retake photo or add details.`);
    }

    const exactMatch = industryRows.find((r) => r.category === diagnosis.category && r.subcategory === diagnosis.subcategory);
    const fuzzyQuery = `${diagnosis.category} ${diagnosis.subcategory}`.toLowerCase();
    const fuzzyMatch = industryRows.find((r) => fuzzyQuery.includes(String(r.subcategory).toLowerCase()));
    const matched = exactMatch ?? fuzzyMatch ?? null;

    if (!matched) {
      return jsonResponse({
        error: "Could not confidently match this issue to a pricing category.",
        code: "category_match_failed",
        gateStatus: "blocked" as GateStatus,
        gateReasons: ["Issue could not be mapped to a supported plumbing category. Retake photo and provide clearer details."],
        canOverride: false,
      }, 422);
    }

    if (gateReasons.length > 0 && !allowOverride) {
      return jsonResponse({
        error: "Input quality is too weak for a reliable quote.",
        code: "input_quality_warning",
        gateStatus: "warning" as GateStatus,
        gateReasons,
        canOverride: true,
      }, 422);
    }

    const mapRowsRes = await admin
      .from("industry_pricebook_map")
      .select("price_book_item_id, fallback_line_item_name, quantity, tier_minimum")
      .eq("industry_rate_id", matched.id);
    const mapRows = mapRowsRes.data ?? [];

    let priceBookItems: Array<{ id: string; name: string; unitPrice: number; unit: string; description: string | null }> = [];
    if (mapRows.length > 0) {
      const ids = mapRows.map((r) => r.price_book_item_id).filter(Boolean) as string[];
      if (ids.length > 0) {
        const { data } = await admin.from("PriceBookItem")
          .select("id, name, unitPrice, unit, description")
          .in("id", ids)
          .eq("active", true);
        priceBookItems = (data ?? []) as Array<{ id: string; name: string; unitPrice: number; unit: string; description: string | null }>;
      }
    }

    if (priceBookItems.length === 0) {
      const fallback = await admin
        .from("PriceBookItem")
        .select("id, name, unitPrice, unit, description")
        .eq("name", matched.subcategory)
        .eq("active", true)
        .limit(1);
      priceBookItems = (fallback.data ?? []) as Array<{ id: string; name: string; unitPrice: number; unit: string; description: string | null }>;
    }

    const customerId = createId("cus");
    const customerInsert = await admin.from("Customer").insert({
      id: customerId,
      firstName: body.customerName?.split(" ")[0] ?? "On-Site",
      lastName: body.customerName?.split(" ").slice(1).join(" ") || "Customer",
      email: null,
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

    const pricingConfig = await loadPricingConfig();
    const estimateId = createId("est");
    const publicToken = crypto.randomUUID().replace(/-/g, "");
    const firstImagePath = `${authUser.id}/${estimateId}/1.jpg`;
    const estimateInsert = await admin.from("Estimate").insert({
      id: estimateId,
      customerId,
      createdById: appUser.id,
      status: DB_ENUMS.estimateStatusDraft,
      aiDiagnosisNote: diagnosis.description,
      aiPhotoUrl: `quote-images:${firstImagePath}`,
      voiceTranscript: body.voiceTranscript ?? null,
      customerNote: body.additionalNotes ?? null,
      internalNote: `Severity: ${diagnosis.severity}. Confidence: ${round2(diagnosis.confidence)}`,
      depositPercent: null,
      publicToken,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }).select("estimateNumber").single();
    if (estimateInsert.error) throw new Error(`Estimate insert failed: ${estimateInsert.error.message}`);
    const estimateNumber = Number(estimateInsert.data?.estimateNumber ?? 0) || null;

    const baseLine = priceBookItems.length > 0
      ? round2(priceBookItems.reduce((sum, i) => sum + Number(i.unitPrice ?? 0), 0))
      : round2(Number(matched.price_better));

    const tierConfigs: Array<{ key: TierKey; name: string; multiplier: number; recommended: boolean }> = [
      { key: "good", name: "Good", multiplier: 0.85, recommended: false },
      { key: "better", name: "Better", multiplier: 1.00, recommended: true },
      { key: "best", name: "Best", multiplier: 1.28, recommended: false },
    ];

    const quotesPayload: Record<TierKey, unknown> = { good: {}, better: {}, best: {} };

    for (let i = 0; i < tierConfigs.length; i += 1) {
      const cfg = tierConfigs[i];
      const optionId = createId("opt");
      const targetIndustryPrice = Number(matched[`price_${cfg.key}` as keyof typeof matched] ?? baseLine);
      const mergedTotal = round2(Math.max(baseLine * cfg.multiplier, targetIndustryPrice));
      const lineItems = priceBookItems.length > 0
        ? priceBookItems
        : [{
            id: null as string | null,
            name: matched.display_name,
            unitPrice: round2(mergedTotal * 0.65),
            unit: "each",
            description: matched.description,
          }];

      const subtotal = round2(lineItems.reduce((s, it) => s + Number(it.unitPrice), 0));
      const serviceAdjustment = round2(Math.max(0, mergedTotal - subtotal));
      const total = round2(subtotal + serviceAdjustment);

      const optionInsert = await admin.from("EstimateOption").insert({
        id: optionId,
        estimateId,
        tier: DB_ENUMS.estimateTier[cfg.key],
        name: `${cfg.name} Option`,
        description: diagnosis.recommended_solutions?.[cfg.key] ?? matched[`solution_${cfg.key}` as keyof typeof matched] ?? null,
        subtotal,
        total,
        recommended: cfg.recommended,
        sortOrder: i,
      });
      if (optionInsert.error) throw new Error(`EstimateOption insert failed: ${optionInsert.error.message}`);

      const lineRows = lineItems.map((it, idx) => ({
        id: createId("li"),
        optionId,
        priceBookItemId: it.id,
        name: it.name,
        description: it.description,
        unitPrice: round2(Number(it.unitPrice)),
        quantity: 1,
        unit: it.unit ?? "each",
        total: round2(Number(it.unitPrice)),
        sortOrder: idx,
      }));

      if (serviceAdjustment > 0) {
        lineRows.push({
          id: createId("li"),
          optionId,
          priceBookItemId: null,
          name: "Service/Labor Adjustment",
          description: "Labor, diagnostics, warranty, and workmanship coverage",
          unitPrice: serviceAdjustment,
          quantity: 1,
          unit: "each",
          total: serviceAdjustment,
          sortOrder: lineRows.length,
        });
      }

      const lineInsert = await admin.from("LineItem").insert(lineRows);
      if (lineInsert.error) throw new Error(`LineItem insert failed: ${lineInsert.error.message}`);

      const warranty = Number(matched[`warranty_months_${cfg.key}` as keyof typeof matched] ?? (cfg.key === "good" ? 3 : cfg.key === "better" ? 12 : 24));
      const laborHours = Number(matched[`labor_hours_${cfg.key}` as keyof typeof matched] ?? 1.2);
      const laborRate = pricingConfig.laborRatePerHour;
      const partsTotal = round2(lineRows.filter((r) => r.name !== "Service/Labor Adjustment").reduce((s, r) => s + Number(r.total), 0));
      const laborTotal = serviceAdjustment;
      const tax = round2(partsTotal * pricingConfig.taxRate);
      const quoteTotal = round2(partsTotal + laborTotal + tax);

      quotesPayload[cfg.key] = {
        optionId,
        tier: cfg.name,
        lineItems: lineRows.map((r) => ({
          partName: r.name,
          partNumber: r.priceBookItemId ?? "",
          brand: cfg.name,
          unitPrice: Number(r.unitPrice),
          quantity: Number(r.quantity),
          category: r.name === "Service/Labor Adjustment" ? "labor" : "part",
        })),
        laborHours,
        laborRate,
        laborTotal,
        partsTotal,
        tax,
        total: quoteTotal,
        warrantyMonths: warranty,
        solutionDescription: diagnosis.recommended_solutions?.[cfg.key] ?? matched[`solution_${cfg.key}` as keyof typeof matched] ?? "",
        notes: `EstimateOptionId: ${optionId}`,
      };
    }

    const uploadedPaths: string[] = [];
    const failedUploads: string[] = [];
    for (let i = 0; i < images.length; i += 1) {
      const path = `${authUser.id}/${estimateId}/${i + 1}.jpg`;
      const bytes = base64ToBytes(images[i]);
      const upload = await uploadWithRetry(path, bytes, "image/jpeg");
      if (upload.ok) {
        uploadedPaths.push(path);
      } else {
        failedUploads.push(path);
      }
    }

    return jsonResponse({
      quoteId: estimateId,
      estimateNumber,
      estimateId,
      gateStatus: gateReasons.length > 0 ? ("warning" as GateStatus) : ("pass" as GateStatus),
      gateReasons,
      canOverride: gateReasons.length > 0,
      pricingSource: {
        benchmark: matched.source ?? null,
        benchmarkUrls: Array.isArray(matched.source_urls) ? matched.source_urls : [],
      },
      customerName: body.customerName ?? null,
      customerPhone: body.customerPhone ?? null,
      customerAddress: body.customerAddress ?? null,
      imagePaths: uploadedPaths,
      failedUploads,
      issue: {
        category: matched.category,
        subcategory: matched.subcategory,
        description: diagnosis.description,
        severity: diagnosis.severity,
        confidence: Math.max(0, Math.min(1, diagnosis.confidence)),
        recommendedSolutions: diagnosis.recommended_solutions ?? {},
      },
      quotes: quotesPayload,
    });
  } catch (error) {
    await admin.from("error_logs").insert({
      id: createId("err"),
      source: "edge_function",
      severity: "error",
      message: error instanceof Error ? error.message : "Unknown error",
      context: { function: "analyze-issue" },
      device_info: "server",
      app_version: "edge",
    });
    if (error instanceof AppError) {
      return jsonResponse({ error: error.message, code: error.code }, error.status);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message, code: "upstream_failure" }, 502);
  }
});
