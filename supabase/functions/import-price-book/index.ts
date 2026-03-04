import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AppError, createId, jsonResponse, requireBearerToken } from "../_shared/http.ts";

const CORS_METHODS = "POST, OPTIONS";

type ImportRequest = {
  fileName: string;
  fileBase64: string;
};

function parseCsv(text: string): Array<Record<string, string>> {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return [];
  const headers = lines[0].split(",").map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const cols = line.split(",").map((c) => c.trim());
    const row: Record<string, string> = {};
    headers.forEach((key, idx) => {
      row[key] = cols[idx] ?? "";
    });
    return row;
  });
}

async function embeddingFor(text: string): Promise<number[]> {
  const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
  if (!OPENAI_API_KEY) throw new AppError(500, "missing_openai_key", "Missing OPENAI_API_KEY");

  const res = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "text-embedding-3-small",
      input: text.slice(0, 2000),
    }),
  });
  if (!res.ok) {
    throw new AppError(502, "embedding_error", "Failed to generate embeddings");
  }
  const json = await res.json();
  return json.data?.[0]?.embedding ?? [];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse(req, { ok: true }, 200, CORS_METHODS);

  try {
    const token = requireBearerToken(req);
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new AppError(500, "missing_supabase_env", "Supabase env vars missing");
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) throw new AppError(401, "unauthorized", "Unauthorized");

    const body = await req.json() as ImportRequest;
    if (!body.fileName || !body.fileBase64) throw new AppError(400, "invalid_payload", "fileName and fileBase64 are required");
    if (!(body.fileName.endsWith(".csv") || body.fileName.endsWith(".xlsx"))) {
      throw new AppError(400, "unsupported_file_type", "Only CSV/XLSX files are supported");
    }
    if (body.fileName.endsWith(".xlsx")) {
      throw new AppError(400, "xlsx_not_yet_supported", "XLSX import requires conversion to CSV in this version");
    }

    const fileBytes = Uint8Array.from(atob(body.fileBase64), (c) => c.charCodeAt(0));
    const csvText = new TextDecoder().decode(fileBytes);
    const rows = parseCsv(csvText);
    if (rows.length === 0) throw new AppError(400, "empty_file", "No rows found in CSV");

    const upserts: Array<Record<string, unknown>> = [];
    for (const row of rows.slice(0, 500)) {
      const serviceName = row.service_name || row.ServiceName || row.name || "Unknown Service";
      const category = row.category || "General";
      const subcategory = row.subcategory || "General";
      const description = row.description || "";
      const flatRate = Number(row.flat_rate || row.flatRate || row.price || 0) || 0;
      const hourlyRate = Number(row.hourly_rate || row.hourlyRate || 0) || 0;
      const laborHours = Number(row.estimated_labor_hours || row.labor_hours || 0) || 0;
      const embedding = await embeddingFor([serviceName, description, category, subcategory].join(" | "));

      upserts.push({
        id: createId("pbv"),
        category,
        subcategory,
        service_name: serviceName,
        description,
        flat_rate: flatRate,
        hourly_rate: hourlyRate,
        estimated_labor_hours: laborHours,
        parts_list: [],
        unit_of_measure: "job",
        cost: flatRate > 0 ? flatRate : hourlyRate * laborHours,
        taxable: true,
        warranty_tier: null,
        tags: [],
        embedding,
        is_active: true,
        updated_at: new Date().toISOString(),
      });
    }

    const { error } = await admin.from("price_book_vectors").upsert(upserts);
    if (error) throw new AppError(500, "upsert_failed", error.message);

    return jsonResponse(req, { ok: true, importedRows: upserts.length }, 200, CORS_METHODS);
  } catch (error) {
    if (error instanceof AppError) {
      return jsonResponse(req, { error: error.message, code: error.code }, error.status, CORS_METHODS);
    }
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse(req, { error: message, code: "import_failed" }, 500, CORS_METHODS);
  }
});
