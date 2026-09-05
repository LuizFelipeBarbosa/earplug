import { v } from "convex/values";
import { env, internalAction } from "./_generated/server";
import { flag } from "./lib/env";

const emailKindValidator = v.union(
  v.literal("applicationReceived"),
  v.literal("applicationApproved"),
  v.literal("applicationNeedsInfo"),
  v.literal("applicationRejected"),
  v.literal("memberInvited"),
  v.literal("offerSent"),
  v.literal("offerAccepted"),
  v.literal("offerDeclined"),
  v.literal("offerExpired"),
  v.literal("offerWithdrawn"),
  v.literal("bookingConfirmed"),
  v.literal("bookingCancelled"),
  v.literal("reviewRequested"),
);

export function applicationEmail(
  kind:
    | "applicationReceived"
    | "applicationApproved"
    | "applicationNeedsInfo"
    | "applicationRejected",
  args: { orgName: string; note?: string },
): { subject: string; text: string } {
  if (kind === "applicationReceived") {
    return {
      subject: `We received your ${args.orgName} application`,
      text: `We received your application for ${args.orgName}. We'll email you when its status changes.`,
    };
  }
  if (kind === "applicationApproved") {
    return {
      subject: `${args.orgName} is approved on EarPlug`,
      text: `${args.orgName} has been approved. You can now open its organization dashboard on EarPlug.`,
    };
  }
  if (kind === "applicationNeedsInfo") {
    return {
      subject: `More information is needed for ${args.orgName}`,
      text: args.note
        ? `We need more information before reviewing ${args.orgName}. ${args.note}`
        : `We need more information before reviewing ${args.orgName}. Open your application to update it.`,
    };
  }
  return {
    subject: `${args.orgName} application update`,
    text: args.note
      ? `We couldn't approve the application for ${args.orgName}. ${args.note}`
      : `We couldn't approve the application for ${args.orgName}.`,
  };
}

export type BookingEmailKind =
  | "offerSent"
  | "offerAccepted"
  | "offerDeclined"
  | "offerExpired"
  | "offerWithdrawn"
  | "bookingConfirmed"
  | "bookingCancelled"
  | "reviewRequested";

function bookingDateLabel(timestamp: number): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(timestamp);
}

export function bookingEmail(
  kind: BookingEmailKind,
  input: {
    opportunityTitle: string;
    bandName: string;
    orgName: string;
    venueName: string;
    startsAt: number;
    grossLabel?: string;
    reason?: string;
    link: string;
  },
): { subject: string; text: string } {
  const performance = `${input.opportunityTitle} at ${input.venueName} on ${bookingDateLabel(input.startsAt)}`;
  let subject: string;
  let text: string;
  switch (kind) {
    case "offerSent":
      subject = `Offer from ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.orgName} sent ${input.bandName} an offer for ${performance}. Open the offer to respond.`;
      break;
    case "offerAccepted":
      subject = `Offer accepted at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.bandName} accepted ${input.orgName}'s offer for ${performance}.`;
      break;
    case "offerDeclined":
      subject = `Offer declined at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.bandName} declined ${input.orgName}'s offer for ${performance}.`;
      break;
    case "offerExpired":
      subject = `Offer expired at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.orgName}'s offer to ${input.bandName} for ${performance} expired before it was accepted.`;
      break;
    case "offerWithdrawn":
      subject = `Offer withdrawn at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.orgName} withdrew the offer to ${input.bandName} for ${performance}.`;
      break;
    case "bookingConfirmed":
      subject = `Booking confirmed at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.bandName}'s booking with ${input.orgName} for ${performance} is confirmed.`;
      break;
    case "bookingCancelled":
      subject = `Booking cancelled at ${input.venueName}: ${input.opportunityTitle}`;
      text = `${input.bandName}'s booking with ${input.orgName} for ${performance} was cancelled.`;
      break;
    case "reviewRequested":
      subject = `Review requested for ${input.venueName}: ${input.opportunityTitle}`;
      text = `Please leave a review of the booking between ${input.bandName} and ${input.orgName} for ${performance}.`;
      break;
  }
  if (input.grossLabel !== undefined) text += `\n\nFee: ${input.grossLabel}`;
  if (input.reason !== undefined) text += `\n\nReason: ${input.reason}`;
  return { subject, text: `${text}\n\n${input.link}` };
}

export const send = internalAction({
  args: {
    kind: emailKindValidator,
    to: v.string(),
    subject: v.string(),
    text: v.string(),
  },
  returns: v.null(),
  handler: async (_ctx, args) => {
    const key = env.RESEND_API_KEY;
    const enabled = flag("RESEND_SEND_ENABLED", false);
    if (!key || !enabled) {
      console.log(`email skipped (${args.kind}): ${args.subject}`);
      return null;
    }
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "EarPlug <no-reply@earplug.app>",
        to: [args.to],
        subject: args.subject,
        text: args.text,
      }),
    });
    if (!response.ok) {
      throw new Error(`Resend send failed: ${response.status}`);
    }
    return null;
  },
});
