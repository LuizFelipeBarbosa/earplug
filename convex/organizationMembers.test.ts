import { convexTest } from "convex-test";
import { describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { createInvite as createInviteMutation } from "./organizationMembers";
import schema from "./schema";

async function setupOrganization() {
  const t = convexTest(schema);
  const asOwner = t.withIdentity({
    subject: "membership_owner",
    email: "owner@membership.test",
    name: "Membership Owner",
  });
  const asSecondOwner = t.withIdentity({
    subject: "membership_second_owner",
    email: "second-owner@membership.test",
    name: "Second Owner",
  });
  const asInvitee = t.withIdentity({
    subject: "membership_invitee",
    email: "invitee@membership.test",
    name: "Invited Member",
  });
  const { userId: ownerId } = await asOwner.mutation(api.users.ensureUser, {});
  const { userId: secondOwnerId } = await asSecondOwner.mutation(
    api.users.ensureUser,
    {},
  );
  const { userId: inviteeId } = await asInvitee.mutation(
    api.users.ensureUser,
    {},
  );
  const organizationId = await t.run(async (ctx) => {
    const id = await ctx.db.insert("organizations", {
      name: "Membership Venue Group",
      slug: "membership-venue-group",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: 1,
      updatedAt: 1,
    });
    await ctx.db.insert("organizationMembers", {
      organizationId: id,
      userId: ownerId,
      role: "owner",
      createdAt: 1,
    });
    return id;
  });
  return {
    t,
    asOwner,
    asSecondOwner,
    asInvitee,
    ownerId,
    secondOwnerId,
    inviteeId,
    organizationId,
  };
}

describe("organization memberships and invitations", () => {
  test("invite links reuse, change role, rotate, resolve, accept, and revoke", async () => {
    const { t, asOwner, asInvitee, inviteeId, organizationId } =
      await setupOrganization();
    const first = await asOwner.mutation(
      api.organizationMembers.createInvite,
      { organizationId, role: "door" },
    );
    expect(first.token).toMatch(/^[0-9a-f]{64}$/);
    expect(first.revoked).toBe(false);
    expect(first.expired).toBe(false);
    expect(
      await asOwner.mutation(api.organizationMembers.createInvite, {
        organizationId,
        role: "door",
      }),
    ).toEqual(first);
    expect(
      await t.query(api.organizationMembers.resolveInvite, {
        token: first.token,
      }),
    ).toEqual({
      organizationId,
      organizationName: "Membership Venue Group",
      role: "door",
    });

    const changedRole = await asOwner.mutation(
      api.organizationMembers.createInvite,
      { organizationId, role: "finance" },
    );
    expect(changedRole.token).not.toBe(first.token);
    expect(changedRole.role).toBe("finance");
    expect(
      await t.query(api.organizationMembers.resolveInvite, {
        token: first.token,
      }),
    ).toBeNull();

    const rotated = await asOwner.mutation(
      api.organizationMembers.rotateInvite,
      { organizationId },
    );
    expect(rotated.token).not.toBe(first.token);
    expect(rotated.token).not.toBe(changedRole.token);
    expect(rotated.role).toBe("finance");
    expect(
      await t.query(api.organizationMembers.resolveInvite, {
        token: first.token,
      }),
    ).toBeNull();

    expect(
      await asInvitee.mutation(api.organizationMembers.acceptInvite, {
        token: rotated.token,
      }),
    ).toEqual({ organizationId, membershipCreated: true });
    expect(
      await asInvitee.mutation(api.organizationMembers.acceptInvite, {
        token: rotated.token,
      }),
    ).toEqual({ organizationId, membershipCreated: false });
    const membership = await t.run((ctx) =>
      ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q.eq("organizationId", organizationId).eq("userId", inviteeId),
        )
        .unique(),
    );
    expect(membership?.role).toBe("finance");

    await asOwner.mutation(api.organizationMembers.revokeInvite, {
      organizationId,
    });
    expect(
      await asOwner.query(api.organizationMembers.manageInvite, {
        organizationId,
      }),
    ).toEqual({ ...rotated, revoked: true });
    expect(
      await t.query(api.organizationMembers.resolveInvite, {
        token: rotated.token,
      }),
    ).toBeNull();
  });

  test("owner roles are rejected by invite validation and the handler guard", async () => {
    const { t, asOwner, organizationId } = await setupOrganization();
    await expect(
      asOwner.mutation(
        api.organizationMembers.createInvite,
        { organizationId, role: "owner" } as never,
      ),
    ).rejects.toThrow();

    const handler = (
      createInviteMutation as unknown as {
        _handler: (
          ctx: object,
          args: { organizationId: string; role: string },
        ) => Promise<unknown>;
      }
    )._handler;
    await expect(
      t.run((ctx) => handler(ctx, { organizationId, role: "owner" })),
    ).rejects.toThrow("Owners are added with setRole");
  });

  test("scheduled expiry materializes and hides an invitation", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-03T12:00:00Z"));
    try {
      const { t, asOwner, organizationId } = await setupOrganization();
      const invite = await asOwner.mutation(
        api.organizationMembers.createInvite,
        { organizationId, role: "manager" },
      );
      expect(
        await t.query(api.organizationMembers.resolveInvite, {
          token: invite.token,
        }),
      ).not.toBeNull();

      await t.finishAllScheduledFunctions(() => vi.runAllTimers());
      expect(
        await t.query(api.organizationMembers.resolveInvite, {
          token: invite.token,
        }),
      ).toBeNull();
      expect(
        await asOwner.query(api.organizationMembers.manageInvite, {
          organizationId,
        }),
      ).toEqual({ ...invite, expired: true });
    } finally {
      vi.useRealTimers();
    }
  });

  test("demoting or removing the last owner is blocked", async () => {
    const { asOwner, ownerId, organizationId } = await setupOrganization();
    await expect(
      asOwner.mutation(api.organizationMembers.setRole, {
        organizationId,
        userId: ownerId,
        role: "manager",
      }),
    ).rejects.toThrow("An organization needs at least one owner");
    await expect(
      asOwner.mutation(api.organizationMembers.remove, {
        organizationId,
        userId: ownerId,
      }),
    ).rejects.toThrow("An organization needs at least one owner");
  });

  test("an owner can be demoted or removed when another owner remains", async () => {
    const {
      t,
      asOwner,
      asSecondOwner,
      ownerId,
      secondOwnerId,
      organizationId,
    } = await setupOrganization();
    await t.run((ctx) =>
      ctx.db.insert("organizationMembers", {
        organizationId,
        userId: secondOwnerId,
        role: "owner",
        addedBy: ownerId,
        createdAt: 2,
      }),
    );
    await asOwner.mutation(api.organizationMembers.setRole, {
      organizationId,
      userId: ownerId,
      role: "manager",
    });
    await asSecondOwner.mutation(api.organizationMembers.setRole, {
      organizationId,
      userId: ownerId,
      role: "owner",
    });
    await asSecondOwner.mutation(api.organizationMembers.remove, {
      organizationId,
      userId: ownerId,
    });
    const memberships = await t.run((ctx) =>
      ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .take(10),
    );
    expect(memberships).toHaveLength(1);
    expect(memberships[0]).toMatchObject({
      userId: secondOwnerId,
      role: "owner",
    });
  });
});
