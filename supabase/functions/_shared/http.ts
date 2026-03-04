export class AppError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function createId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, "")}`;
}

const defaultAllowedOrigin = "https://app.plumbingquote.com";
const configuredOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? defaultAllowedOrigin)
  .split(",")
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

function resolvedAllowedOrigin(req: Request): string {
  const origin = (req.headers.get("origin") ?? "").trim();
  if (origin && configuredOrigins.includes(origin)) return origin;
  return configuredOrigins[0] ?? defaultAllowedOrigin;
}

export function corsHeaders(req: Request, allowedMethods: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": resolvedAllowedOrigin(req),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": allowedMethods,
    "Vary": "Origin",
  };
}

export function jsonResponse(
  req: Request,
  body: unknown,
  status = 200,
  allowedMethods = "POST, OPTIONS",
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req, allowedMethods), "Content-Type": "application/json" },
  });
}

export function requireBearerToken(req: Request): string {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new AppError(401, "missing_bearer_token", "Missing bearer token");
  }
  return authHeader.replace("Bearer ", "");
}

function isPrivateIpv4(host: string): boolean {
  const parts = host.split(".").map((part) => Number(part));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;

  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  return false;
}

export function isAllowedPublicUrl(rawUrl: string, allowedHosts: Set<string>): boolean {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return false;
  }

  if (parsed.protocol !== "https:") return false;

  const host = parsed.hostname.toLowerCase();
  if (!host) return false;
  if (host === "localhost" || host.endsWith(".local")) return false;
  if (isPrivateIpv4(host)) return false;

  if (allowedHosts.size === 0) return true;
  for (const allowed of allowedHosts) {
    if (host === allowed || host.endsWith(`.${allowed}`)) return true;
  }
  return false;
}
