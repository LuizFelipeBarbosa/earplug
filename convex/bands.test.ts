import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

describe("bands: slugs and profile updates", () => {
  async function setup() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    return { t, asAdmin };
  }

  const bandArgs = { genres: ["punk"], bio: "", inviteHandles: [] };

  test("createBand issues unique slugs and bySlug resolves them", async () => {
    const { t, asAdmin } = await setup();
    const first = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });
    const second = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom!",
      ...bandArgs,
    });
    expect(first.slug).toBe("static-bloom");
    expect(second.slug).toBe("static-bloom-2");

    const resolved = await t.query(api.bands.bySlug, {
      slug: "static-bloom-2",
    });
    expect(resolved?._id).toBe(second.bandId);
    expect(await t.query(api.bands.bySlug, { slug: "nobody" })).toBeNull();
  });

  test("updateProfile edits the same band and keeps its slug", async () => {
    const { t, asAdmin } = await setup();
    const { bandId, slug } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });

    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      name: "Static Gloom",
      genres: ["punk", "shoegaze"],
      area: "Berkeley",
      inviteHandles: ["@mara.k"],
      linkIg: "@staticgloom",
    });

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.name).toBe("Static Gloom");
    expect(doc?.initials).toBe("SG");
    expect(doc?.genres).toEqual(["punk", "shoegaze"]);
    expect(doc?.area).toBe("Berkeley");
    expect(doc?.inviteHandles).toEqual(["@mara.k"]);
    expect(doc?.linkIg).toBe("@staticgloom");
    // Shared links must survive a rename.
    expect(doc?.slug).toBe(slug);

    const resolved = await t.query(api.bands.bySlug, { slug });
    expect(resolved?.name).toBe("Static Gloom");
  });

  test("updateProfile rejects non-admins", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });

    const asStranger = t.withIdentity({
      subject: "user_stranger",
      email: "s@x.com",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.bands.updateProfile, {
        bandId,
        name: "Hijacked",
      }),
    ).rejects.toThrow();
  });
});
