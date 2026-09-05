import { afterEach, describe, expect, test, vi } from "vitest";
import {
  encodeStripeForm,
  STRIPE_API_VERSION,
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
});

describe("encodeStripeForm", () => {
  test("encodes nested objects with bracketed keys", () => {
    expect(
      encodeStripeForm({ transfer_data: { destination: "acct_1" } }),
    ).toBe("transfer_data[destination]=acct_1");
  });

  test("encodes arrays with numeric indices", () => {
    expect(encodeStripeForm({ items: ["a", "b"] })).toBe(
      "items[0]=a&items[1]=b",
    );
  });

  test("recurses through objects and arrays inside arrays", () => {
    expect(
      encodeStripeForm({ items: [{ name: "x", tags: ["a", "b"] }, ["y"]] }),
    ).toBe(
      "items[0][name]=x&items[0][tags][0]=a&items[0][tags][1]=b&items[1][0]=y",
    );
  });

  test("encodes booleans as literal strings", () => {
    expect(encodeStripeForm({ enabled: true, disabled: false })).toBe(
      "enabled=true&disabled=false",
    );
  });

  test("encodes numbers using their string form", () => {
    expect(encodeStripeForm({ amount: 1234, zero: 0, decimal: -1.25 })).toBe(
      "amount=1234&zero=0&decimal=-1.25",
    );
  });

  test("omits undefined and preserves null as empty at every depth", () => {
    const form = new URLSearchParams(
      encodeStripeForm({
        omitted: undefined,
        cleared: null,
        metadata: { omitted: undefined, cleared: null },
        items: [undefined, null, { omitted: undefined, cleared: null }, "kept"],
      }),
    );

    expect(Object.fromEntries(form)).toEqual({
      cleared: "",
      "metadata[cleared]": "",
      "items[1]": "",
      "items[2][cleared]": "",
      "items[3]": "kept",
    });
  });

  test("percent-encodes individual key segments and values", () => {
    const encoded = encodeStripeForm({
      "meta data": { "key&[]": "a+b & café/雪?=" },
    });

    expect(encoded).toBe(
      "meta%20data[key%26%5B%5D]=a%2Bb%20%26%20caf%C3%A9%2F%E9%9B%AA%3F%3D",
    );
    expect(Object.fromEntries(new URLSearchParams(encoded))).toEqual({
      "meta data[key&[]]": "a+b & café/雪?=",
    });
  });

  test("returns an empty string when there are no pairs", () => {
    expect(encodeStripeForm({})).toBe("");
    expect(encodeStripeForm({ omitted: undefined, items: [], metadata: {} })).toBe(
      "",
    );
  });
});

describe("stripeRequest", () => {
  test("puts GET params in the query string without a request body", async () => {
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(Response.json({}));

    await stripeRequest(
      "GET",
      "/v1/accounts",
      { limit: 2, expand: ["data.customer"], metadata: { note: "a+b & café" } },
      { fetchImpl, secretKey: "sk_test_injected" },
    );

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe(
      "https://api.stripe.com/v1/accounts?limit=2&expand[0]=data.customer&metadata[note]=a%2Bb%20%26%20caf%C3%A9",
    );
    expect(Object.fromEntries(new URL(String(url)).searchParams)).toEqual({
      limit: "2",
      "expand[0]": "data.customer",
      "metadata[note]": "a+b & café",
    });
    expect(init?.method).toBe("GET");
    expect(init?.body).toBeUndefined();
  });

  test("preserves an existing GET query string", async () => {
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(Response.json({}));

    await stripeRequest(
      "GET",
      "/v1/accounts?limit=2",
      { starting_after: "acct_1" },
      { fetchImpl, secretKey: "sk_test_injected" },
    );

    expect(fetchImpl.mock.calls[0][0]).toBe(
      "https://api.stripe.com/v1/accounts?limit=2&starting_after=acct_1",
    );
  });

  test.each([undefined, {}, { omitted: undefined }])(
    "omits optional headers and an empty GET query for params %j",
    async (params) => {
      const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(Response.json({}));

      await stripeRequest("GET", "/v1/balance", params, {
        fetchImpl,
        secretKey: "sk_test_injected",
      });

      const [url, init] = fetchImpl.mock.calls[0];
      const headers = new Headers(init?.headers);
      expect(url).toBe("https://api.stripe.com/v1/balance");
      expect(init?.body).toBeUndefined();
      expect(headers.get("Authorization")).toBe("Bearer sk_test_injected");
      expect(headers.get("Stripe-Version")).toBe(STRIPE_API_VERSION);
      expect(headers.has("Idempotency-Key")).toBe(false);
      expect(headers.has("Stripe-Account")).toBe(false);
      expect(headers.has("Content-Type")).toBe(false);
    },
  );

  test("sends POST headers and form body and returns typed JSON", async () => {
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    vi.stubEnv("STRIPE_SECRET_KEY", undefined);
    const payload = { id: "pi_1", amount: 1234 };
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValue(Response.json(payload, { status: 201 }));

    const result = await stripeRequest<{ id: string; amount: number }>(
      "POST",
      "/v1/payment_intents",
      {
        amount: 1234,
        transfer_data: { destination: "acct_1" },
        description: "a+b & café",
      },
      {
        fetchImpl,
        secretKey: "sk_test_injected",
        idempotencyKey: "booking:123:payment",
        stripeAccount: "acct_connected",
      },
    );

    expect(result).toEqual(payload);
    const amount: number = result.amount;
    expect(amount).toBe(1234);
    expect(STRIPE_API_VERSION).toBe("2024-06-20");
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe("https://api.stripe.com/v1/payment_intents");
    expect(init?.method).toBe("POST");
    expect(Object.fromEntries(new Headers(init?.headers))).toEqual({
      authorization: "Bearer sk_test_injected",
      "stripe-version": STRIPE_API_VERSION,
      "idempotency-key": "booking:123:payment",
      "stripe-account": "acct_connected",
      "content-type": "application/x-www-form-urlencoded",
    });
    expect(init?.body).toBe(
      "amount=1234&transfer_data[destination]=acct_1&description=a%2Bb%20%26%20caf%C3%A9",
    );
    expect(Object.fromEntries(new URLSearchParams(String(init?.body)))).toEqual({
      amount: "1234",
      "transfer_data[destination]": "acct_1",
      description: "a+b & café",
    });
  });

  test("sends DELETE params as a form body", async () => {
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    const payload = { id: "cus_1", deleted: true };
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValue(Response.json(payload));

    await expect(
      stripeRequest(
        "DELETE",
        "/v1/customers/cus_1",
        { metadata: { note: null } },
        { fetchImpl, secretKey: "sk_test_injected" },
      ),
    ).resolves.toEqual(payload);

    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe("https://api.stripe.com/v1/customers/cus_1");
    expect(init?.method).toBe("DELETE");
    expect(init?.body).toBe("metadata[note]=");
    expect(new Headers(init?.headers).get("Content-Type")).toBe(
      "application/x-www-form-urlencoded",
    );
  });

  test("maps a Stripe error and its Request-Id header into StripeApiError", async () => {
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json(
        {
          error: {
            type: "card_error",
            code: "card_declined",
            param: "payment_method",
            message: "Your card was declined.",
            request_log_url: "https://dashboard.stripe.com/test/logs/req_123",
          },
        },
        { status: 402, headers: { "Request-Id": "req_123" } },
      ),
    );

    const request = stripeRequest(
      "POST",
      "/v1/payment_intents",
      { amount: 1234 },
      { fetchImpl, secretKey: "sk_test_injected" },
    );

    await expect(request).rejects.toBeInstanceOf(StripeApiError);
    await expect(request).rejects.toMatchObject({
      name: "StripeApiError",
      status: 402,
      type: "card_error",
      code: "card_declined",
      param: "payment_method",
      message: "Your card was declined.",
      requestId: "req_123",
    });
  });

  test("allows a Stripe error to omit optional fields and Request-Id", async () => {
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({ error: { message: "No such account" } }, { status: 404 }),
    );

    const request = stripeRequest("GET", "/v1/accounts/acct_missing", undefined, {
      fetchImpl,
      secretKey: "sk_test_injected",
    });

    await expect(request).rejects.toBeInstanceOf(StripeApiError);
    await expect(request).rejects.toMatchObject({
      status: 404,
      message: "No such account",
      type: undefined,
      code: undefined,
      param: undefined,
      requestId: undefined,
    });
  });

  test("uses a fallback for a missing message and narrows optional error fields", async () => {
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json(
        { error: { type: "api_error", code: 42, param: null } },
        {
          status: 500,
          statusText: "Internal Server Error",
          headers: { "Request-Id": "req_456" },
        },
      ),
    );

    await expect(
      stripeRequest("GET", "/v1/balance", undefined, {
        fetchImpl,
        secretKey: "sk_test_injected",
      }),
    ).rejects.toMatchObject({
      status: 500,
      message: "Stripe request failed: 500 Internal Server Error",
      type: "api_error",
      code: undefined,
      param: undefined,
      requestId: "req_456",
    });
  });

  test.each([
    "<html>Bad Gateway</html>",
    JSON.stringify({ message: "Bad Gateway" }),
    JSON.stringify({ error: "Bad Gateway" }),
    JSON.stringify({ error: null }),
    JSON.stringify({ error: [] }),
    "null",
    "[]",
  ])("falls back for an invalid error body: %s", async (body) => {
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(body, {
        status: 502,
        statusText: "Bad Gateway",
        headers: { "Request-Id": "req_unstructured" },
      }),
    );

    const request = stripeRequest("GET", "/v1/balance", undefined, {
      fetchImpl,
      secretKey: "sk_test_injected",
    });

    await expect(request).rejects.toBeInstanceOf(StripeApiError);
    await expect(request).rejects.toMatchObject({
      status: 502,
      message: "Stripe request failed: 502 Bad Gateway",
      type: undefined,
      code: undefined,
      param: undefined,
      requestId: undefined,
    });
  });

  test("propagates network errors unchanged", async () => {
    const networkError = new TypeError("Network connection failed");
    const fetchImpl = vi.fn<typeof fetch>().mockRejectedValue(networkError);

    await expect(
      stripeRequest("GET", "/v1/balance", undefined, {
        fetchImpl,
        secretKey: "sk_test_injected",
      }),
    ).rejects.toBe(networkError);
  });
});

describe("money gate", () => {
  test.each(["POST", "DELETE"] as const)(
    "blocks %s before fetching when payments are unset or disabled",
    async (method) => {
      const fetchImpl = vi.fn<typeof fetch>();

      for (const value of [undefined, "false", "0", "invalid"]) {
        vi.stubEnv("PAYMENTS_ENABLED", value);
        const request = stripeRequest(method, "/v1/accounts", {}, {
          fetchImpl,
          secretKey: "sk_test_injected",
        });

        await expect(request).rejects.toStrictEqual(
          new Error("Payments are not enabled"),
        );
        expect(fetchImpl).not.toHaveBeenCalled();
      }
    },
  );

  test.each([undefined, "false", "0", "invalid"])(
    "allows GET when PAYMENTS_ENABLED is %s",
    async (value) => {
      vi.stubEnv("PAYMENTS_ENABLED", value);
      const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(Response.json({}));

      await expect(
        stripeRequest("GET", "/v1/balance", undefined, {
          fetchImpl,
          secretKey: "sk_test_injected",
        }),
      ).resolves.toEqual({});
      expect(fetchImpl).toHaveBeenCalledTimes(1);
    },
  );

  test.each(["POST", "DELETE"] as const)(
    "allows %s when payments are explicitly enabled",
    async (method) => {
      vi.stubEnv("PAYMENTS_ENABLED", "true");
      const fetchImpl = vi
        .fn<typeof fetch>()
        .mockResolvedValue(Response.json({ id: "acct_1" }));

      await expect(
        stripeRequest(method, "/v1/accounts", undefined, {
          fetchImpl,
          secretKey: "sk_test_injected",
        }),
      ).resolves.toEqual({ id: "acct_1" });
      expect(fetchImpl).toHaveBeenCalledTimes(1);
    },
  );
});

describe("stripeIdempotencyKey", () => {
  test("joins string and number parts with colons", () => {
    expect(stripeIdempotencyKey("booking", 123, "payment")).toBe(
      "booking:123:payment",
    );
    expect(stripeIdempotencyKey()).toBe("");
  });

  test("truncates the joined key to exactly its first 255 characters", () => {
    const parts = ["booking", "a".repeat(300), 123, "payment"];
    const joined = parts.join(":");
    const result = stripeIdempotencyKey(...parts);

    expect(joined.length).toBeGreaterThan(255);
    expect(result.length).toBeLessThanOrEqual(255);
    expect(result).toHaveLength(255);
    expect(result).toBe(joined.slice(0, 255));
  });
});
