/** Small response helpers shared by every route. */

export type JsonObject = Record<string, unknown>;

export function json(body: unknown, status = 200, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...extra },
  });
}

export function errorResponse(status: number, type: string, message: string): Response {
  return json({ type: "error", error: { type, message } }, status);
}

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const MAX_BODY_BYTES = 4 * 1024 * 1024;

export async function readJsonBody(request: Request): Promise<JsonObject | Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return errorResponse(413, "request_too_large", "Request body exceeds 4 MB.");
  }
  const raw = await request.arrayBuffer();
  if (raw.byteLength > MAX_BODY_BYTES) {
    return errorResponse(413, "request_too_large", "Request body exceeds 4 MB.");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return errorResponse(400, "invalid_request_error", "Body must be valid JSON.");
  }
  if (!isJsonObject(parsed)) {
    return errorResponse(400, "invalid_request_error", "Body must be a JSON object.");
  }
  return parsed;
}

export function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
