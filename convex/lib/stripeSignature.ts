export type StripeSignatureHeader = {
  timestamp: number;
  signatures: string[];
};

export function parseStripeSignatureHeader(
  header: string | null,
): StripeSignatureHeader | null {
  if (header === null || header.trim() === "") return null;

  let timestamp: number | undefined;
  const signatures: string[] = [];

  for (const component of header.split(",")) {
    const trimmed = component.trim();
    if (trimmed.startsWith("t=") && timestamp === undefined) {
      const value = trimmed.slice(2);
      if (!/^-?\d+$/.test(value)) return null;

      const parsed = Number(value);
      if (!Number.isSafeInteger(parsed)) return null;
      timestamp = parsed;
    } else if (trimmed.startsWith("v1=")) {
      signatures.push(trimmed.slice(3));
    }
  }

  if (timestamp === undefined || signatures.length === 0) return null;
  return { timestamp, signatures };
}

export async function computeStripeSignature(
  secret: string,
  timestamp: number,
  payload: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${payload}`),
  );

  return Array.from(new Uint8Array(signature), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  const lengthsEqual = left.length === right.length;
  const maximumLength = Math.max(left.length, right.length);
  let difference = 0;

  for (let index = 0; index < maximumLength; index += 1) {
    const leftMissing = index >= left.length;
    const rightMissing = index >= right.length;
    const leftCode = leftMissing ? 0 : left.charCodeAt(index);
    const rightCode = rightMissing ? 0 : right.charCodeAt(index);
    difference |= leftCode ^ rightCode;
    difference |= leftMissing || rightMissing ? 1 : 0;
  }

  return difference === 0 && lengthsEqual;
}

export async function verifyStripeSignature(args: {
  payload: string;
  header: string | null;
  secret: string;
  nowSeconds: number;
  toleranceSeconds?: number;
}): Promise<"ok" | "missing" | "malformed" | "expired" | "mismatch"> {
  if (args.header === null || args.header.trim() === "") return "missing";

  const parsed = parseStripeSignatureHeader(args.header);
  if (parsed === null) return "malformed";

  const toleranceSeconds = args.toleranceSeconds ?? 300;
  if (Math.abs(args.nowSeconds - parsed.timestamp) > toleranceSeconds) {
    return "expired";
  }

  const expected = await computeStripeSignature(
    args.secret,
    parsed.timestamp,
    args.payload,
  );
  let matches = false;
  for (const signature of parsed.signatures) {
    matches = constantTimeEqual(signature, expected) || matches;
  }

  return matches ? "ok" : "mismatch";
}
