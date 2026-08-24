import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const TEST_SECRET = "whsec_" + btoa("earplug-test-signing-key-32bytes!");

async function signed(
  body: string,
  opts: { id?: string; timestampSec?: number; corrupt?: boolean } = {},
): Promise<HeadersInit> {
  const id = opts.id ?? "msg_test";
  const timestampSec = opts.timestampSec ?? Math.floor(Date.now() / 1000);
  const keyBytes = Uint8Array.from(
    atob(TEST_SECRET.slice("whsec_".length)),
    (character) => character.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${id}.${timestampSec}.${body}`),
  );
  const signature = opts.corrupt
    ? "corrupt"
    : btoa(String.fromCharCode(...new Uint8Array(signatureBytes)));
  return {
    "content-type": "application/json",
    "svix-id": id,
    "svix-timestamp": String(timestampSec),
    "svix-signature": `v1,${signature}`,
  };
}

function eventBody(type: string, data: unknown): string {
  return JSON.stringify({ object: "event", type, data });
}

function userData(
  id: string,
  options: {
    email?: string;
    verified?: boolean;
    firstName?: string | null;
    lastName?: string | null;
    updatedAt?: number;
  } = {},
) {
  const primaryId = "idn_primary";
  return {
    id,
    primary_email_address_id: primaryId,
    email_addresses:
      options.email === undefined
        ? []
        : [
            {
              id: primaryId,
              email_address: options.email,
              verification: {
                status: options.verified === false ? "unverified" : "verified",
              },
            },
          ],
    first_name: options.firstName ?? null,
    last_name: options.lastName ?? null,
    ...(options.updatedAt === undefined
      ? {}
      : { updated_at: options.updatedAt }),
  };
}

async function postEvent(
  t: ReturnType<typeof convexTest>,
  type: string,
  data: unknown,
) {
  const body = eventBody(type, data);
  return await t.fetch("/clerk-webhook", {
    method: "POST",
    headers: await signed(body),
    body,
  });
}

async function allUsers(t: ReturnType<typeof convexTest>) {
  return await t.run(async (ctx) => ctx.db.query("users").take(20));
}

beforeEach(() => {
  vi.stubEnv("CLERK_WEBHOOK_SECRET", TEST_SECRET);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("POST /clerk-webhook verification and routing", () => {
  test("rejects missing Svix headers without writes", async () => {
    const t = convexTest(schema);
    const response = await t.fetch("/clerk-webhook", {
      method: "POST",
      body: eventBody("user.created", userData("user_missing_headers")),
    });
    expect(response.status).toBe(400);
    expect(await allUsers(t)).toHaveLength(0);
  });

  test("rejects a corrupted signature without writes", async () => {
    const t = convexTest(schema);
    const body = eventBody(
      "user.created",
      userData("user_bad_signature", { email: "bad@example.com" }),
    );
    const response = await t.fetch("/clerk-webhook", {
      method: "POST",
      headers: await signed(body, { corrupt: true }),
      body,
    });
    expect(response.status).toBe(400);
    expect(await allUsers(t)).toHaveLength(0);
  });

  test("rejects a signature timestamp ten minutes old", async () => {
    const t = convexTest(schema);
    const body = eventBody("user.created", userData("user_old_signature"));
    const response = await t.fetch("/clerk-webhook", {
      method: "POST",
      headers: await signed(body, {
        timestampSec: Math.floor(Date.now() / 1000) - 10 * 60,
      }),
      body,
    });
    expect(response.status).toBe(400);
    expect(await allUsers(t)).toHaveLength(0);
  });

  test("returns 500 when the webhook secret is unset", async () => {
    vi.stubEnv("CLERK_WEBHOOK_SECRET", "");
    const t = convexTest(schema);
    const body = eventBody("user.created", userData("user_no_secret"));
    const response = await t.fetch("/clerk-webhook", {
      method: "POST",
      headers: await signed(body),
      body,
    });
    expect(response.status).toBe(500);
    expect(await allUsers(t)).toHaveLength(0);
  });

  test("returns 404 for an unrouted method or path", async () => {
    const t = convexTest(schema);
    expect((await t.fetch("/clerk-webhook", { method: "GET" })).status).toBe(
      404,
    );
    expect((await t.fetch("/nope", { method: "POST" })).status).toBe(404);
  });

  test("acknowledges an unrelated valid event without writes", async () => {
    const t = convexTest(schema);
    const response = await postEvent(t, "session.created", {
      id: "sess_ignored",
    });
    expect(response.status).toBe(200);
    expect(await allUsers(t)).toHaveLength(0);
  });
});

describe("Clerk user webhook synchronization", () => {
  test("creates a user from a verified primary email", async () => {
    const t = convexTest(schema);
    const response = await postEvent(
      t,
      "user.created",
      userData("user_created", {
        email: "mara@example.com",
        firstName: "Mara",
        lastName: "Kim",
      }),
    );
    expect(response.status).toBe(200);
    expect(await allUsers(t)).toMatchObject([
      {
        clerkId: "user_created",
        name: "Mara Kim",
        email: "mara@example.com",
        genres: [],
        attendedCount: 0,
      },
    ]);
  });

  test("delivering the same user.created twice remains one row", async () => {
    const t = convexTest(schema);
    const data = userData("user_replayed", { email: "replay@example.com" });
    expect((await postEvent(t, "user.created", data)).status).toBe(200);
    expect((await postEvent(t, "user.created", data)).status).toBe(200);
    expect(await allUsers(t)).toHaveLength(1);
  });

  test("ensureUser first preserves its id when user.created arrives", async () => {
    const t = convexTest(schema);
    const asUser = t.withIdentity({
      subject: "user_ensure_first",
      email: "ensure-first@example.com",
    });
    const ensured = await asUser.mutation(api.users.ensureUser, {});
    expect(
      (
        await postEvent(
          t,
          "user.created",
          userData("user_ensure_first", {
            email: "ensure-first@example.com",
          }),
        )
      ).status,
    ).toBe(200);
    const rows = await allUsers(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]._id).toBe(ensured.userId);
  });

  test("user.created first is returned later by ensureUser", async () => {
    const t = convexTest(schema);
    await postEvent(
      t,
      "user.created",
      userData("user_webhook_first", { email: "webhook-first@example.com" }),
    );
    const created = (await allUsers(t))[0];
    const ensured = await t
      .withIdentity({
        subject: "user_webhook_first",
        email: "webhook-first@example.com",
      })
      .mutation(api.users.ensureUser, {});
    expect(ensured.userId).toBe(created._id);
    expect(await allUsers(t)).toHaveLength(1);
  });

  test("adopts the unique legacy row matching a verified email", async () => {
    const t = convexTest(schema);
    const legacyId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_old_clerk",
        name: "Legacy",
        email: "legacy@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );
    await postEvent(
      t,
      "user.created",
      userData("user_new_clerk", { email: "legacy@example.com" }),
    );
    const rows = await allUsers(t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      _id: legacyId,
      clerkId: "user_new_clerk",
    });
  });

  test("does not adopt a legacy row through an unverified primary email", async () => {
    const t = convexTest(schema);
    const legacyId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_unverified_old",
        name: "Legacy",
        email: "unverified@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );
    await postEvent(
      t,
      "user.created",
      userData("user_unverified_new", {
        email: "unverified@example.com",
        verified: false,
      }),
    );
    const rows = await allUsers(t);
    expect(rows).toHaveLength(2);
    expect(rows.find((row) => row._id === legacyId)?.clerkId).toBe(
      "user_unverified_old",
    );
  });

  test("does not adopt when two legacy rows match the email", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      for (const clerkId of ["user_ambiguous_a", "user_ambiguous_b"]) {
        await ctx.db.insert("users", {
          clerkId,
          name: clerkId,
          email: "ambiguous@example.com",
          genres: [],
          attendedCount: 0,
        });
      }
    });
    await postEvent(
      t,
      "user.created",
      userData("user_ambiguous_new", { email: "ambiguous@example.com" }),
    );
    const rows = await allUsers(t);
    expect(rows).toHaveLength(3);
    expect(
      rows.filter((row) => row.clerkId === "user_ambiguous_new"),
    ).toHaveLength(1);
  });

  test("user.updated treats a changed verified email as authoritative", async () => {
    const t = convexTest(schema);
    await postEvent(
      t,
      "user.created",
      userData("user_email_change", { email: "old@example.com" }),
    );
    await postEvent(
      t,
      "user.updated",
      userData("user_email_change", { email: "new@example.com" }),
    );
    expect((await allUsers(t))[0].email).toBe("new@example.com");
  });

  test("an older user.updated cannot overwrite a newer email", async () => {
    const t = convexTest(schema);
    await postEvent(
      t,
      "user.created",
      userData("user_ordered_update", {
        email: "initial@example.com",
        updatedAt: 1_000,
      }),
    );
    await postEvent(
      t,
      "user.updated",
      userData("user_ordered_update", {
        email: "newer@example.com",
        updatedAt: 3_000,
      }),
    );
    await postEvent(
      t,
      "user.updated",
      userData("user_ordered_update", {
        email: "stale@example.com",
        updatedAt: 2_000,
      }),
    );

    expect((await allUsers(t))[0]).toMatchObject({
      email: "newer@example.com",
      clerkUpdatedAt: 3_000,
    });
  });

  test("user.updated refuses an email held by another row", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "user_email_change_collision",
        name: "Changing",
        email: "old-change@example.com",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("users", {
        clerkId: "user_collision_owner",
        name: "Owner",
        email: "owned@example.com",
        genres: [],
        attendedCount: 0,
      });
    });
    const result = await t.mutation(internal.users.syncFromClerk, {
      clerkId: "user_email_change_collision",
      email: "owned@example.com",
      emailVerified: true,
      emailIsAuthoritative: true,
    });
    expect(result.emailConflict).toBe(true);
    const rows = await allUsers(t);
    expect(
      rows.find((row) => row.clerkId === "user_email_change_collision")?.email,
    ).toBe("old-change@example.com");
    expect(
      rows.find((row) => row.clerkId === "user_collision_owner")?.email,
    ).toBe("owned@example.com");
  });

  test("user.updated does not overwrite a non-empty stored name", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "user_named",
        name: "Chosen Name",
        email: "named@example.com",
        genres: [],
        attendedCount: 0,
      });
    });
    await postEvent(
      t,
      "user.updated",
      userData("user_named", {
        email: "named@example.com",
        firstName: "Clerk",
        lastName: "Name",
      }),
    );
    expect((await allUsers(t))[0].name).toBe("Chosen Name");
  });
});

describe("Clerk user deletion tombstones", () => {
  test("soft-deletes the user while preserving joins and counters", async () => {
    const t = convexTest(schema);
    const fixture = await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", {
        clerkId: "user_delete",
        name: "Keep For Now",
        email: "delete@example.com",
        genres: [],
        attendedCount: 1,
      });
      const bandId = await ctx.db.insert("bands", {
        name: "Still Counted",
        genres: [],
        area: "Oakland",
        colorHex: "#000000",
        initials: "SC",
        followerCount: 1,
        pastShows: [],
        slug: "still-counted",
      });
      const venueId = await ctx.db.insert("venues", {
        name: "Room",
        area: "Oakland",
        addr: "1 Main St",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 0,
        lng: 0,
      });
      const gigId = await ctx.db.insert("gigs", {
        title: "History",
        venueId,
        price: 0,
        startsAt: 1,
        doorsTime: "8PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: [],
        desc: "",
        ticketing: "rsvp",
        cap: "100",
        goingCount: 1,
      });
      await ctx.db.insert("follows", { userId, bandId });
      await ctx.db.insert("bandMembers", {
        userId,
        bandId,
        role: "admin",
      });
      await ctx.db.insert("gigRsvps", { userId, gigId });
      await ctx.db.insert("gigSaves", { userId, gigId });
      return { userId, bandId, gigId };
    });

    const response = await postEvent(t, "user.deleted", {
      id: "user_delete",
      object: "user",
      deleted: true,
    });
    expect(response.status).toBe(200);

    const state = await t.run(async (ctx) => ({
      user: await ctx.db.get(fixture.userId),
      follows: await ctx.db.query("follows").take(10),
      members: await ctx.db.query("bandMembers").take(10),
      rsvps: await ctx.db.query("gigRsvps").take(10),
      saves: await ctx.db.query("gigSaves").take(10),
      band: await ctx.db.get(fixture.bandId),
      gig: await ctx.db.get(fixture.gigId),
    }));
    expect(state.user?.email).toBe("");
    expect(state.user?.deletedAt).toEqual(expect.any(Number));
    expect(state.follows).toHaveLength(1);
    expect(state.members).toHaveLength(1);
    expect(state.rsvps).toHaveLength(1);
    expect(state.saves).toHaveLength(1);
    expect(state.band?.followerCount).toBe(1);
    expect(state.gig?.goingCount).toBe(1);
  });

  test("acknowledges deletion of an unknown Clerk id without creating a row", async () => {
    const t = convexTest(schema);
    expect(
      (
        await postEvent(t, "user.deleted", {
          id: "user_unknown_delete",
          object: "user",
          deleted: true,
        })
      ).status,
    ).toBe(200);
    expect(await allUsers(t)).toHaveLength(0);
  });

  test("treats a tombstoned Clerk identity as permanently deleted", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_resurrect",
        name: "Resurrect",
        email: "",
        genres: [],
        attendedCount: 0,
        deletedAt: 1,
      }),
    );
    const asDeletedUser = t.withIdentity({
      subject: "user_resurrect",
      email: "resurrect@example.com",
    });
    await expect(
      asDeletedUser.mutation(api.users.ensureUser, {}),
    ).rejects.toThrow("Account deleted");
    expect(await asDeletedUser.query(api.users.me, {})).toBeNull();
    await expect(
      asDeletedUser.mutation(api.users.setGenres, { genres: ["punk"] }),
    ).rejects.toThrow("Account deleted");
    const row = await t.run(async (ctx) => ctx.db.get(userId));
    expect(row?.deletedAt).toBe(1);
    expect(row?.email).toBe("");
  });

  test("ignores a late user.updated webhook for a tombstoned identity", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_late_update",
        name: "Deleted Name",
        email: "",
        genres: [],
        attendedCount: 0,
        deletedAt: 10,
        clerkUpdatedAt: 20,
      }),
    );

    expect(
      (
        await postEvent(
          t,
          "user.updated",
          userData("user_late_update", {
            email: "restored@example.com",
            firstName: "Restored",
            updatedAt: 30,
          }),
        )
      ).status,
    ).toBe(200);

    expect(await t.run(async (ctx) => ctx.db.get(userId))).toMatchObject({
      deletedAt: 10,
      email: "",
      name: "Deleted Name",
      clerkUpdatedAt: 20,
    });
  });

  test("excludes a tombstoned row from verified-email adoption", async () => {
    const t = convexTest(schema);
    const tombstoneId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_dead_instance",
        name: "Dead",
        email: "dead@example.com",
        genres: [],
        attendedCount: 0,
        deletedAt: 1,
      }),
    );
    await postEvent(
      t,
      "user.created",
      userData("user_live_instance", { email: "dead@example.com" }),
    );
    const rows = await allUsers(t);
    expect(rows).toHaveLength(2);
    expect(rows.find((row) => row._id === tombstoneId)?.clerkId).toBe(
      "user_dead_instance",
    );
    expect(rows.some((row) => row.clerkId === "user_live_instance")).toBe(true);
  });
});
