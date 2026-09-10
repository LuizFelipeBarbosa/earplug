import { env } from "../_generated/server";

export const PRODUCTION_DEPLOYMENT = "decisive-iguana-759";

export function deploymentName(): string | null {
  try {
    return new URL(env.CONVEX_CLOUD_URL).hostname.split(".")[0] || null;
  } catch {
    return null;
  }
}

export function assertStripeKeyAllowed(
  key: string | undefined,
  deployment: string | null,
): void {
  if (key?.startsWith("sk_live_") && deployment !== PRODUCTION_DEPLOYMENT) {
    throw new Error(
      "A live Stripe key is only allowed on the production deployment",
    );
  }
}

export function stripeSecretKey(): string {
  const key = env.STRIPE_SECRET_KEY;
  assertStripeKeyAllowed(key, deploymentName());
  if (!key) throw new Error("STRIPE_SECRET_KEY is not configured");
  return key;
}

type FeatureFlag = "RESEND_SEND_ENABLED";

export function flag(name: FeatureFlag, defaultValue: boolean): boolean {
  const value = env[name];
  if (value === "true" || value === "1") return true;
  if (value === "false" || value === "0") return false;
  return defaultValue;
}

type BasisPointSetting = "BOOKING_COMMISSION_BPS" | "TICKETING_FEE_BPS";

export function bpsSetting(
  name: BasisPointSetting,
  defaultValue: number,
): number {
  const rawValue = env[name];
  const value =
    rawValue === undefined || rawValue.trim() === "" ? NaN : Number(rawValue);
  return Number.isInteger(value) && value >= 0 && value <= 10_000
    ? value
    : defaultValue;
}

export function appBaseUrl(): string {
  return env.APP_BASE_URL || "https://earplug.app";
}

export type MinorUnitSetting = "TICKETING_FEE_FIXED_MINOR";

export function minorSetting(name: MinorUnitSetting): number | undefined {
  const rawValue = env[name];
  if (rawValue === undefined || rawValue.trim() === "") return undefined;

  const value = Number(rawValue);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`Invalid ${name}: ${rawValue}`);
  }
  return value;
}
