import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

type LineItemInput = {
  id?: string;
  name: string;
  description?: string;
  unitPrice: number;
  quantity: number;
  unit: string;
};

type OptionInput = {
  optionId: string;
  lineItems: LineItemInput[];
  laborHours: number;
};

type UpdateEstimateOptionsRequest = {
  estimateId: string;
  options: OptionInput[];
};

type PricingConfig = {
  laborRatePerHour: number;
  taxRate: number;
};

class AppError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "PUT, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required env vars");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function createId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, "")}`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "PUT") return jsonResponse({ error: "Method not allowed", code: "method_not_allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      throw new AppError(401, "missing_bearer_token", "Missing bearer token");
    }
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");
    const authUser = userData.user;

    const body = (await req.json()) as UpdateEstimateOptionsRequest;
    if (!body.estimateId || !Array.isArray(body.options) || body.options.length === 0) {
      throw new AppError(400, "invalid_payload", "estimateId and options are required");
    }

    const userRes = await admin
      .from("User")
      .select("id")
      .eq("authId", authUser.id)
      .limit(1)
      .maybeSingle();
    if (!userRes.data?.id) throw new AppError(403, "user_not_found", "Technician profile not found");
    const appUserId = userRes.data.id as string;

    const estimateRes = await admin
      .from("Estimate")
      .select("id, createdById")
      .eq("id", body.estimateId)
      .limit(1)
      .maybeSingle();
    if (!estimateRes.data?.id) throw new AppError(404, "estimate_not_found", "Estimate not found");
    if (estimateRes.data.createdById !== appUserId) throw new AppError(403, "forbidden", "Forbidden");

    const pricingConfig = await loadPricingConfig();

    for (const option of body.options) {
      const existingOption = await admin
        .from("EstimateOption")
        .select("id, recommended")
        .eq("id", option.optionId)
        .eq("estimateId", body.estimateId)
        .limit(1)
        .maybeSingle();
      if (!existingOption.data?.id) {
        throw new AppError(400, "invalid_option", `Option ${option.optionId} does not belong to estimate`);
      }

      const deleteRes = await admin
        .from("LineItem")
        .delete()
        .eq("optionId", option.optionId);
      if (deleteRes.error) throw new Error(`Could not delete old line items: ${deleteRes.error.message}`);

      const lineRows = option.lineItems.map((line, index) => {
        const unitPrice = round2(Number(line.unitPrice || 0));
        const quantity = Number(line.quantity || 0);
        return {
          id: createId("li"),
          optionId: option.optionId,
          priceBookItemId: null as string | null,
          name: line.name,
          description: line.description ?? null,
          unitPrice,
          quantity,
          unit: line.unit || "each",
          total: round2(unitPrice * quantity),
          sortOrder: index,
        };
      });

      if (lineRows.length > 0) {
        const insertRes = await admin.from("LineItem").insert(lineRows);
        if (insertRes.error) throw new Error(`Could not insert line items: ${insertRes.error.message}`);
      }

      const subtotal = round2(lineRows.reduce((sum, row) => sum + Number(row.total), 0));
      const laborHours = Math.max(0, Number(option.laborHours || 0));
      const laborTotal = round2(laborHours * pricingConfig.laborRatePerHour);
      const tax = round2(subtotal * pricingConfig.taxRate);
      const total = round2(subtotal + laborTotal + tax);
      const optionUpdateRes = await admin
        .from("EstimateOption")
        .update({
          subtotal,
          total,
        })
        .eq("id", option.optionId);
      if (optionUpdateRes.error) throw new Error(`Could not update option totals: ${optionUpdateRes.error.message}`);
    }

    const estimateUpdateRes = await admin
      .from("Estimate")
      .update({ updatedAt: new Date().toISOString() })
      .eq("id", body.estimateId);
    if (estimateUpdateRes.error) throw new Error(`Could not update estimate timestamp: ${estimateUpdateRes.error.message}`);

    const optionsRes = await admin
      .from("EstimateOption")
      .select("id, tier, name, total, recommended")
      .eq("estimateId", body.estimateId)
      .order("sortOrder", { ascending: true });
    if (optionsRes.error) throw new Error(`Could not fetch updated options: ${optionsRes.error.message}`);

    return jsonResponse({
      ok: true,
      estimateId: body.estimateId,
      options: optionsRes.data ?? [],
    });
  } catch (error) {
    await admin.from("error_logs").insert({
      id: createId("err"),
      source: "edge_function",
      severity: "error",
      message: error instanceof Error ? error.message : "Unknown error",
      context: { function: "update-estimate-options" },
      device_info: "server",
      app_version: "edge",
    });
    if (error instanceof AppError) {
      return jsonResponse({ error: error.message, code: error.code }, error.status);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message, code: "update_options_failed" }, 500);
  }
});
