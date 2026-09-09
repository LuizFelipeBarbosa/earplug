import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";
import { randomHexToken } from "./tokens";

export const INVITE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;

type InviteTable = "bandInvites" | "organizationMemberInvites";
type InviteFields = {
  bandInvites: Pick<Doc<"bandInvites">, "bandId" | "createdBy">;
  organizationMemberInvites: Pick<
    Doc<"organizationMemberInvites">,
    "organizationId" | "createdBy" | "role"
  >;
};
type ScheduleExpire = (expiresAt: number, token: string) => Promise<void>;

export async function uniqueInviteToken(
  ctx: MutationCtx,
  table: InviteTable,
): Promise<string> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const token = randomHexToken(32);
    const collision = await ctx.db
      .query(table)
      .withIndex("by_token", (q) => q.eq("token", token))
      .first();
    if (collision === null) return token;
  }
  throw new Error("Could not issue invitation token");
}

export async function insertInvite<Table extends InviteTable>(
  ctx: MutationCtx,
  table: Table,
  fields: InviteFields[Table],
  scheduleExpire: ScheduleExpire,
): Promise<Doc<Table>> {
  const token = await uniqueInviteToken(ctx, table);
  const expiresAt = Date.now() + INVITE_LIFETIME_MS;
  const inviteId = await ctx.db.insert<InviteTable>(table, {
    ...fields,
    token,
    expiresAt,
    revoked: false,
    expired: false,
  });
  await scheduleExpire(expiresAt, token);
  const invite = await ctx.db.get(inviteId as Id<Table>);
  if (invite === null) throw new Error("Created invitation not found");
  return invite;
}

export async function refreshInvite<Table extends InviteTable>(
  ctx: MutationCtx,
  table: Table,
  inviteId: Id<Table>,
  fields: InviteFields[Table],
  scheduleExpire: ScheduleExpire,
): Promise<Doc<Table>> {
  const replacement = {
    ...fields,
    token: await uniqueInviteToken(ctx, table),
    expiresAt: Date.now() + INVITE_LIFETIME_MS,
    revoked: false,
    expired: false,
  };
  await ctx.db.replace<InviteTable>(inviteId, replacement);
  await scheduleExpire(replacement.expiresAt, replacement.token);
  // Existing payload builders accept Doc but read no system fields. Preserve
  // the replacement-only result without fetching the document after replace.
  return replacement as unknown as Doc<Table>;
}
