import { flag, stripeSecretKey } from "./env";

// Pinned on purpose: do not "helpfully" bump this to "latest". Changing the
// Stripe API version is a deliberate, tested migration, not an incidental edit.
export const STRIPE_API_VERSION = "2024-06-20";

export class StripeApiError extends Error {
  status: number;
  type?: string;
  code?: string;
  param?: string;
  requestId?: string;

  constructor(
    message: string,
    fields: {
      status: number;
      type?: string;
      code?: string;
      param?: string;
      requestId?: string;
    },
  ) {
    super(message);
    this.name = "StripeApiError";
    this.status = fields.status;
    this.type = fields.type;
    this.code = fields.code;
    this.param = fields.param;
    this.requestId = fields.requestId;
  }
}

export type StripeParams = Record<string, unknown>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function encodeStripeForm(params: StripeParams): string {
  const pairs: string[] = [];

  function append(key: string, value: unknown): void {
    if (value === undefined) return;

    if (Array.isArray(value)) {
      value.forEach((item: unknown, index) => append(`${key}[${index}]`, item));
    } else if (isRecord(value)) {
      for (const [segment, nestedValue] of Object.entries(value)) {
        append(`${key}[${encodeURIComponent(segment)}]`, nestedValue);
      }
    } else {
      const encodedValue = encodeURIComponent(value === null ? "" : String(value));
      pairs.push(`${key}=${encodedValue}`);
    }
  }

  for (const [key, value] of Object.entries(params)) {
    append(encodeURIComponent(key), value);
  }

  return pairs.join("&");
}

export async function stripeRequest<T = Record<string, unknown>>(
  method: "GET" | "POST" | "DELETE",
  path: string,
  params?: StripeParams,
  options?: {
    idempotencyKey?: string;
    stripeAccount?: string;
    fetchImpl?: typeof fetch;
    secretKey?: string;
  },
): Promise<T> {
  if (method !== "GET" && !flag("PAYMENTS_ENABLED", false)) {
    throw new Error("Payments are not enabled");
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${options?.secretKey ?? stripeSecretKey()}`,
    "Stripe-Version": STRIPE_API_VERSION,
  };
  if (options?.idempotencyKey !== undefined) {
    headers["Idempotency-Key"] = options.idempotencyKey;
  }
  if (options?.stripeAccount !== undefined) {
    headers["Stripe-Account"] = options.stripeAccount;
  }
  if (method !== "GET") {
    headers["Content-Type"] = "application/x-www-form-urlencoded";
  }

  const form = encodeStripeForm(params ?? {});
  let url = `https://api.stripe.com${path}`;
  if (method === "GET" && form !== "") {
    url += `${url.includes("?") ? "&" : "?"}${form}`;
  }

  const fetchImpl = options?.fetchImpl ?? fetch;
  const response = await fetchImpl(url, {
    method,
    headers,
    body: method === "GET" ? undefined : form,
  });

  if (!response.ok) {
    const fallbackMessage = `Stripe request failed: ${response.status} ${response.statusText}`;
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new StripeApiError(fallbackMessage, { status: response.status });
    }

    if (isRecord(body) && isRecord(body.error)) {
      const error = body.error;
      throw new StripeApiError(
        typeof error.message === "string" ? error.message : fallbackMessage,
        {
          status: response.status,
          type: typeof error.type === "string" ? error.type : undefined,
          code: typeof error.code === "string" ? error.code : undefined,
          param: typeof error.param === "string" ? error.param : undefined,
          requestId: response.headers.get("Request-Id") ?? undefined,
        },
      );
    }

    throw new StripeApiError(fallbackMessage, { status: response.status });
  }

  const body: unknown = await response.json();
  return body as T;
}

export function stripeIdempotencyKey(...parts: (string | number)[]): string {
  return parts.join(":").slice(0, 255);
}
