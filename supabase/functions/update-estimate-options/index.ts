import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { computeOptionTotals, round2 } from "./pricing.ts";
import { AppError, corsHeaders, createId, jsonResponse, requireBearerToken } from "../_shared/http.ts";

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

type UpdatedOptionBreakdown = {
  id: string;
  tier: string;
  subtotal: number;
  laborTotal: number;
  tax: number;
  total: number;
  laborHours: number;
  laborRate: number;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required env vars");
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS_METHODS = "PUT, OPTIONS";
const MAX_LINE_ITEM_NAME_LENGTH = 120;
const MAX_LINE_ITEM_DESCRIPTION_LENGTH = 500;
const MAX_LINE_ITEM_COUNT = 50;
const MAX_UNIT_PRICE = 100_000;
const MAX_QUANTITY = 1_000;
const MAX_LABOR_HOURS = 100;

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
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req, CORS_METHODS) });
  if (req.method !== "PUT") return jsonResponse(req, { error: "Method not allowed", code: "method_not_allowed" }, 405, CORS_METHODS);

  try {
    const token = requireBearerToken(req);
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");
    const authUser = userData.user;

    const body = (await req.json()) as UpdateEstimateOptionsRequest;
    if (!body.estimateId || !Array.isArray(body.options) || body.options.length === 0) {
      throw new AppError(400, "invalid_payload", "estimateId and options are required");
    }
    if (body.options.length > 3) {
      throw new AppError(400, "too_many_options", "Maximum of 3 options can be updated at once");
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

    const updatedOptions: UpdatedOptionBreakdown[] = [];

    for (const option of body.options) {
      if (!option.optionId || option.optionId.trim().length === 0) {
        throw new AppError(400, "invalid_option", "Each option requires a valid optionId");
      }
      if (!Array.isArray(option.lineItems) || option.lineItems.length > MAX_LINE_ITEM_COUNT) {
        throw new AppError(400, "invalid_line_items", `Each option must include 0-${MAX_LINE_ITEM_COUNT} line items`);
      }

      const laborHours = Number(option.laborHours);
      if (!Number.isFinite(laborHours) || laborHours < 0 || laborHours > MAX_LABOR_HOURS) {
        throw new AppError(400, "invalid_labor_hours", `Labor hours must be between 0 and ${MAX_LABOR_HOURS}`);
      }

      const existingOption = await admin
        .from("EstimateOption")
        .select("id, tier, recommended")
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
        const name = String(line.name ?? "").trim();
        if (!name || name.length > MAX_LINE_ITEM_NAME_LENGTH) {
          throw new AppError(400, "invalid_line_item_name", `Line item name is required and must be <= ${MAX_LINE_ITEM_NAME_LENGTH} characters`);
        }

        const description = String(line.description ?? "").trim();
        if (description.length > MAX_LINE_ITEM_DESCRIPTION_LENGTH) {
          throw new AppError(400, "invalid_line_item_description", `Line item description must be <= ${MAX_LINE_ITEM_DESCRIPTION_LENGTH} characters`);
        }

        const validatedUnitPrice = Number(line.unitPrice);
        if (!Number.isFinite(validatedUnitPrice) || validatedUnitPrice < 0 || validatedUnitPrice > MAX_UNIT_PRICE) {
          throw new AppError(400, "invalid_unit_price", `Line item unit price must be between 0 and ${MAX_UNIT_PRICE}`);
        }

        const validatedQuantity = Number(line.quantity);
        if (!Number.isFinite(validatedQuantity) || validatedQuantity <= 0 || validatedQuantity > MAX_QUANTITY) {
          throw new AppError(400, "invalid_quantity", `Line item quantity must be > 0 and <= ${MAX_QUANTITY}`);
        }

        const unit = String(line.unit || "each").trim();
        if (!unit) {
          throw new AppError(400, "invalid_unit", "Line item unit is required");
        }

        const unitPrice = round2(validatedUnitPrice);
        const quantity = validatedQuantity;
        return {
          id: createId("li"),
          optionId: option.optionId,
          priceBookItemId: null as string | null,
          name,
          description: description || null,
          unitPrice,
          quantity,
          unit,
          total: round2(unitPrice * quantity),
          sortOrder: index,
        };
      });

      if (lineRows.length > 0) {
        const insertRes = await admin.from("LineItem").insert(lineRows);
        if (insertRes.error) throw new Error(`Could not insert line items: ${insertRes.error.message}`);
      }

      const { subtotal, laborTotal, tax, total } = computeOptionTotals(
        lineRows.map((row) => ({ name: String(row.name ?? ""), total: Number(row.total) })),
        laborHours,
        pricingConfig,
      );
      const optionUpdateRes = await admin
        .from("EstimateOption")
        .update({
          subtotal,
          total,
        })
        .eq("id", option.optionId);
      if (optionUpdateRes.error) throw new Error(`Could not update option totals: ${optionUpdateRes.error.message}`);

      updatedOptions.push({
        id: option.optionId,
        tier: String(existingOption.data.tier ?? ""),
        subtotal,
        laborTotal,
        tax,
        total,
        laborHours,
        laborRate: pricingConfig.laborRatePerHour,
      });
    }

    const estimateUpdateRes = await admin
      .from("Estimate")
      .update({ updatedAt: new Date().toISOString() })
      .eq("id", body.estimateId);
    if (estimateUpdateRes.error) throw new Error(`Could not update estimate timestamp: ${estimateUpdateRes.error.message}`);

    return jsonResponse(req, {
      ok: true,
      estimateId: body.estimateId,
      options: updatedOptions,
    }, 200, CORS_METHODS);
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
      return jsonResponse(req, { error: error.message, code: error.code }, error.status, CORS_METHODS);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse(req, { error: message, code: "update_options_failed" }, 500, CORS_METHODS);
  }
});
