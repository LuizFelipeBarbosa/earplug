import { convexTest } from "convex-test";
import { describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

async function setupBand() {
  const t = convexTest(schema);
  const asAdmin = t.withIdentity({
    subject: "invite_admin",
    email: "admin@invite.test",
    name: "Invite Admin",
  });
  await asAdmin.mutation(api.users.ensureUser, {});
  const { bandId } = await asAdmin.mutation(api.bands.createBand, {
    name: "Invitation Band",
    genres: ["punk"],
    area: "Oakland",
    bio: "",
  });
  return { t, asAdmin, bandId };
}

describe("band invitations", () => {
  test("admins create one reusable unguessable seven-day link", async () => {
    const { asAdmin, bandId } = await setupBand();
    const before = Date.now();
    const first = await asAdmin.mutation(api.bandInvites.create, { bandId });
    const second = await asAdmin.mutation(api.bandInvites.create, { bandId });

    expect(first).toEqual(second);
    expect(first.token).toMatch(/^[0-9a-f]{64}$/);
    expect(first.expiresAt).toBeGreaterThanOrEqual(
      before + 7 * 24 * 60 * 60 * 1000,
    );
    expect(first.revoked).toBe(false);
    expect(first.expired).toBe(false);
    expect(await asAdmin.query(api.bandInvites.manage, { bandId })).toEqual(
      first,
    );
  });

  test("resolve is public, minimal, and ignores caller-supplied time", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const invite = await asAdmin.mutation(api.bandInvites.create, { bandId });
    expect(
      await t.query(api.bandInvites.resolve, {
        token: invite.token,
        now: invite.expiresAt + 1,
      }),
    ).toEqual({
      bandId,
      bandName: "Invitation Band",
      initials: "IB",
      colorHex: expect.stringMatching(/^#[0-9A-F]{6}$/),
    });
    expect(
      await t.query(api.bandInvites.resolve, {
        token: "unknown",
      }),
    ).toBeNull();
  });

  test("server expiration hides identity and stale rotation jobs are harmless", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const original = await asAdmin.mutation(api.bandInvites.create, { bandId });
    const replacement = await asAdmin.mutation(api.bandInvites.rotate, {
      bandId,
    });

    await t.mutation(internal.bandInvites.expire, {
      bandId,
      token: original.token,
    });
    expect(
      await t.query(api.bandInvites.resolve, { token: replacement.token }),
    ).not.toBeNull();

    await t.mutation(internal.bandInvites.expire, {
      bandId,
      token: replacement.token,
    });
    expect(await asAdmin.query(api.bandInvites.manage, { bandId })).toEqual({
      ...replacement,
      expired: true,
    });
    expect(
      await t.query(api.bandInvites.resolve, {
        token: replacement.token,
        now: 0,
      }),
    ).toBeNull();
  });

  test("creation schedules server-authoritative expiry", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-24T12:00:00Z"));
    try {
      const { t, asAdmin, bandId } = await setupBand();
      const invite = await asAdmin.mutation(api.bandInvites.create, { bandId });
      expect(
        await t.query(api.bandInvites.resolve, { token: invite.token }),
      ).not.toBeNull();

      await t.finishAllScheduledFunctions(() => vi.runAllTimers());
      expect(
        await t.query(api.bandInvites.resolve, {
          token: invite.token,
          now: 0,
        }),
      ).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  test("accept is authenticated, idempotent, and increments followers once", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const invite = await asAdmin.mutation(api.bandInvites.create, { bandId });
    await expect(
      t.mutation(api.bandInvites.accept, { token: invite.token }),
    ).rejects.toThrow("Not signed in");

    const asMember = t.withIdentity({
      subject: "invite_member",
      email: "member@invite.test",
      name: "Accepted Member",
    });
    await asMember.mutation(api.users.ensureUser, {});
    expect(
      await asMember.mutation(api.bandInvites.accept, { token: invite.token }),
    ).toEqual({ bandId, membershipCreated: true });
    expect(
      await asMember.mutation(api.bandInvites.accept, { token: invite.token }),
    ).toEqual({ bandId, membershipCreated: false });

    const state = await t.run(async (ctx) => ({
      band: await ctx.db.get(bandId),
      memberships: await ctx.db
        .query("bandMembers")
        .withIndex("by_band", (q) => q.eq("bandId", bandId))
        .take(10),
    }));
    expect(state.band?.followerCount).toBe(2);
    expect(state.memberships).toHaveLength(2);
    expect(state.memberships.map((membership) => membership.role)).toEqual([
      "admin",
      "member",
    ]);
  });

  test("rotation revokes the previous token and the replacement stays active", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const original = await asAdmin.mutation(api.bandInvites.create, { bandId });
    const replacement = await asAdmin.mutation(api.bandInvites.rotate, {
      bandId,
    });
    expect(replacement.token).not.toBe(original.token);
    expect(
      await t.query(api.bandInvites.resolve, {
        token: original.token,
        now: Date.now(),
      }),
    ).toBeNull();
    expect(
      await t.query(api.bandInvites.resolve, {
        token: replacement.token,
        now: Date.now(),
      }),
    ).not.toBeNull();
  });

  test("revocation blocks resolution and acceptance", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const invite = await asAdmin.mutation(api.bandInvites.create, { bandId });
    await asAdmin.mutation(api.bandInvites.revoke, { bandId });
    expect(await asAdmin.query(api.bandInvites.manage, { bandId })).toEqual({
      ...invite,
      revoked: true,
    });
    expect(
      await t.query(api.bandInvites.resolve, {
        token: invite.token,
        now: Date.now(),
      }),
    ).toBeNull();

    const asMember = t.withIdentity({
      subject: "revoked_member",
      email: "revoked@invite.test",
    });
    await asMember.mutation(api.users.ensureUser, {});
    await expect(
      asMember.mutation(api.bandInvites.accept, { token: invite.token }),
    ).rejects.toThrow("no longer active");

    const refreshed = await asAdmin.mutation(api.bandInvites.create, {
      bandId,
    });
    expect(refreshed.token).not.toBe(invite.token);
    expect(refreshed.revoked).toBe(false);
  });

  test("expired invitations cannot be accepted", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const invite = await asAdmin.mutation(api.bandInvites.create, { bandId });
    await t.run(async (ctx) => {
      const row = await ctx.db
        .query("bandInvites")
        .withIndex("by_token", (q) => q.eq("token", invite.token))
        .unique();
      await ctx.db.patch(row!._id, { expiresAt: Date.now() - 1 });
    });
    const asMember = t.withIdentity({
      subject: "late_member",
      email: "late@invite.test",
    });
    await asMember.mutation(api.users.ensureUser, {});
    await expect(
      asMember.mutation(api.bandInvites.accept, { token: invite.token }),
    ).rejects.toThrow("no longer active");

    const refreshed = await asAdmin.mutation(api.bandInvites.create, {
      bandId,
    });
    expect(refreshed.token).not.toBe(invite.token);
    expect(refreshed.expiresAt).toBeGreaterThan(Date.now());
  });

  test("only admins can manage, create, rotate, or revoke links", async () => {
    const { t, bandId } = await setupBand();
    const asStranger = t.withIdentity({
      subject: "invite_stranger",
      email: "stranger@invite.test",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.query(api.bandInvites.manage, { bandId }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asStranger.mutation(api.bandInvites.create, { bandId }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asStranger.mutation(api.bandInvites.rotate, { bandId }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asStranger.mutation(api.bandInvites.revoke, { bandId }),
    ).rejects.toThrow("Not an admin");
  });
});
