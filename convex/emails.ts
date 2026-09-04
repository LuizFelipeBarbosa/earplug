import { v } from "convex/values";
import { env, internalAction } from "./_generated/server";
import { flag } from "./lib/env";

const emailKindValidator = v.union(
  v.literal("applicationReceived"),
  v.literal("applicationApproved"),
  v.literal("applicationNeedsInfo"),
  v.literal("applicationRejected"),
  v.literal("memberInvited"),
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
      console.log(`email skipped (${args.kind}) to ${args.to}: ${args.subject}`);
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
