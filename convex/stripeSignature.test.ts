import { describe, expect, test } from "vitest";
import {
  computeStripeSignature,
  parseStripeSignatureHeader,
  verifyStripeSignature,
} from "./lib/stripeSignature";

describe("parseStripeSignatureHeader", () => {
  test("parses a timestamp and one v1 signature", () => {
    expect(parseStripeSignatureHeader("t=123,v1=abc123")).toEqual({
      timestamp: 123,
      signatures: ["abc123"],
    });
  });

  test("collects multiple v1 signatures in header order", () => {
    expect(parseStripeSignatureHeader("t=123,v1=first,v1=second")).toEqual({
      timestamp: 123,
      signatures: ["first", "second"],
    });
  });

  test("returns null without a timestamp", () => {
    expect(parseStripeSignatureHeader("v1=abc123")).toBeNull();
  });

  test("returns null without a v1 signature", () => {
    expect(parseStripeSignatureHeader("t=123,v0=legacy")).toBeNull();
  });

  test("returns null for a garbage header", () => {
    expect(parseStripeSignatureHeader("not-a-stripe-signature")).toBeNull();
  });

  test("ignores v0 signatures", () => {
    expect(
      parseStripeSignatureHeader("t=123,v0=legacy,v1=current"),
    ).toEqual({
      timestamp: 123,
      signatures: ["current"],
    });
  });
});

describe("verifyStripeSignature", () => {
  const secret = "whsec_unit_test";
  const payload = '{"id":"evt_unit"}';
  const timestamp = 1_000;

  async function validHeader(): Promise<string> {
    const signature = await computeStripeSignature(
      secret,
      timestamp,
      payload,
    );
    return `t=${timestamp},v1=${signature}`;
  }

  test("accepts a correct signature within tolerance", async () => {
    expect(
      await verifyStripeSignature({
        payload,
        header: await validHeader(),
        secret,
        nowSeconds: timestamp + 100,
      }),
    ).toBe("ok");
  });

  test("rejects a wrong signature", async () => {
    expect(
      await verifyStripeSignature({
        payload,
        header: `t=${timestamp},v1=${"0".repeat(64)}`,
        secret,
        nowSeconds: timestamp,
      }),
    ).toBe("mismatch");
  });

  test("rejects a timestamp older than the tolerance", async () => {
    expect(
      await verifyStripeSignature({
        payload,
        header: await validHeader(),
        secret,
        nowSeconds: timestamp + 301,
      }),
    ).toBe("expired");
  });

  test("reports a missing header", async () => {
    expect(
      await verifyStripeSignature({
        payload,
        header: null,
        secret,
        nowSeconds: timestamp,
      }),
    ).toBe("missing");
  });

  test("reports a malformed header", async () => {
    expect(
      await verifyStripeSignature({
        payload,
        header: "garbage",
        secret,
        nowSeconds: timestamp,
      }),
    ).toBe("malformed");
  });

  test("rejects a candidate signature with a different length", async () => {
    const expected = await computeStripeSignature(secret, timestamp, payload);
    expect(
      await verifyStripeSignature({
        payload,
        header: `t=${timestamp},v1=${expected.slice(1)}`,
        secret,
        nowSeconds: timestamp,
      }),
    ).toBe("mismatch");
  });
});
