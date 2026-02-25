import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

type EstimateStatus = "draft" | "sent" | "accepted" | "rejected";

type UpdateEstimateRequest = {
  estimateId: string;
  status: EstimateStatus;
  selectedOptionId?: string;
  signatureBase64?: string;
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
  "Access-Control-Allow-Methods": "PATCH, OPTIONS",
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

function base64ToBytes(base64OrDataUrl: string): Uint8Array {
  const payload = base64OrDataUrl.includes(",") ? base64OrDataUrl.split(",")[1] : base64OrDataUrl;
  const decoded = atob(payload);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i += 1) bytes[i] = decoded.charCodeAt(i);
  return bytes;
}

function createId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, "")}`;
}

const allowedStatuses: EstimateStatus[] = ["draft", "sent", "accepted", "rejected"];
const allowedTransitions: Record<EstimateStatus, EstimateStatus[]> = {
  draft: ["draft", "sent"],
  sent: ["sent", "accepted", "rejected"],
  accepted: ["accepted"],
  rejected: ["rejected"],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "PATCH") return jsonResponse({ error: "Method not allowed", code: "method_not_allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      throw new AppError(401, "missing_bearer_token", "Missing bearer token");
    }
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new AppError(401, "unauthorized", "Unauthorized");
    const authUser = userData.user;

    const body = (await req.json()) as UpdateEstimateRequest;
    if (!body.estimateId) throw new AppError(400, "estimate_required", "estimateId is required");
    if (!body.status || !allowedStatuses.includes(body.status)) {
      throw new AppError(400, "invalid_status", "status must be draft, sent, accepted, or rejected");
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
      .select("id, createdById, status")
      .eq("id", body.estimateId)
      .limit(1)
      .maybeSingle();
    if (!estimateRes.data?.id) throw new AppError(404, "estimate_not_found", "Estimate not found");
    if (estimateRes.data.createdById !== appUserId) {
      throw new AppError(403, "forbidden", "You do not have access to this estimate");
    }
    const currentStatus = estimateRes.data.status as EstimateStatus;
    const nextAllowed = allowedTransitions[currentStatus] ?? [];
    if (!nextAllowed.includes(body.status)) {
      throw new AppError(
        409,
        "invalid_status_transition",
        `Cannot transition estimate from ${currentStatus} to ${body.status}`,
      );
    }

    if (body.selectedOptionId) {
      const optionRes = await admin
        .from("EstimateOption")
        .select("id")
        .eq("id", body.selectedOptionId)
        .eq("estimateId", body.estimateId)
        .limit(1)
        .maybeSingle();
      if (!optionRes.data?.id) {
        throw new AppError(400, "invalid_option", "selectedOptionId does not belong to estimate");
      }

      const unsetRes = await admin
        .from("EstimateOption")
        .update({ recommended: false })
        .eq("estimateId", body.estimateId);
      if (unsetRes.error) {
        throw new Error(`Could not clear recommended option: ${unsetRes.error.message}`);
      }

      const setRes = await admin
        .from("EstimateOption")
        .update({ recommended: true })
        .eq("id", body.selectedOptionId)
        .eq("estimateId", body.estimateId);
      if (setRes.error) {
        throw new Error(`Could not set recommended option: ${setRes.error.message}`);
      }
    }

    let signaturePath: string | null = null;
    if (body.signatureBase64 && body.signatureBase64.trim().length > 0) {
      const bytes = base64ToBytes(body.signatureBase64);
      signaturePath = `${authUser.id}/${body.estimateId}/signature.png`;
      const uploadRes = await admin.storage.from("quote-images").upload(signaturePath, bytes, {
        contentType: "image/png",
        upsert: true,
      });
      if (uploadRes.error) {
        throw new Error(`Could not upload signature image: ${uploadRes.error.message}`);
      }
    }

    const now = new Date().toISOString();
    const payload: Record<string, unknown> = {
      status: body.status,
      updatedAt: now,
    };
    if (body.status === "sent") payload.sentAt = now;
    if (body.status === "accepted") payload.signedAt = now;
    if (signaturePath) {
      payload.internalNote = `Signature captured: quote-images:${signaturePath}`;
    }

    const updateRes = await admin
      .from("Estimate")
      .update(payload)
      .eq("id", body.estimateId)
      .select("id, estimateNumber, status, sentAt, signedAt, updatedAt")
      .single();
    if (updateRes.error || !updateRes.data) {
      throw new Error(`Could not update estimate: ${updateRes.error?.message ?? "unknown"}`);
    }

    return jsonResponse({
      ok: true,
      estimate: updateRes.data,
      signaturePath,
    });
  } catch (error) {
    const logPayload = {
      id: createId("err"),
      source: "edge_function",
      severity: "error",
      message: error instanceof Error ? error.message : "Unknown error",
      context: { function: "update-estimate" },
      device_info: "server",
      app_version: "edge",
    };
    await admin.from("error_logs").insert(logPayload);

    if (error instanceof AppError) {
      return jsonResponse({ error: error.message, code: error.code }, error.status);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message, code: "update_failed" }, 500);
  }
});
