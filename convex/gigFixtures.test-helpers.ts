/** Test-only fixtures. The multi-dot filename keeps this module out of the
 * Convex bundle (the CLI skips `*.x.ts` files) while vitest's default include
 * pattern (`*.test.ts`) keeps it from being collected as a suite. */
import type { TestConvexForDataModel } from "convex-test";
import { api } from "./_generated/api";
import { DataModel, Id } from "./_generated/dataModel";
import type { KnownFlyKey } from "./lib/helpers";

type AdminCaller = Pick<TestConvexForDataModel<DataModel>, "mutation">;

export type PublishGigFields = {
  bandId: Id<"bands">;
  title: string;
  startsAt: number;
  doorsAt?: number;
  venueId: Id<"venues">;
  price: number;
  flyKey: KnownFlyKey;
  flyStorageId?: Id<"_storage">;
  ticketing: "rsvp" | "external";
  ageRequirement: "allAges" | "18Plus" | "21Plus";
  externalUrl?: string;
  cap: string;
  desc?: string;
};

/** Publishes one gig for a band the way the client does: create a draft, save
 * the public fields onto it, then publish. Rejects with `publishDraft`'s (or
 * `saveDraft`'s) error when the fields are not publishable. */
export async function publishGigAsAdmin(
  asAdmin: AdminCaller,
  fields: PublishGigFields,
): Promise<{ gigId: Id<"gigs">; slug: string; projectId: Id<"gigProjects"> }> {
  const draft = await asAdmin.mutation(api.gigs.createDraft, {
    bandId: fields.bandId,
  });
  await asAdmin.mutation(api.gigs.saveDraft, {
    projectId: draft._id,
    revision: draft.revision,
    title: fields.title,
    doorsAt: fields.doorsAt ?? fields.startsAt,
    startsAt: fields.startsAt,
    venueId: fields.venueId,
    price: fields.price,
    flyKey: fields.flyKey,
    flyStorageId: fields.flyStorageId ?? null,
    overlay: true,
    desc: fields.desc ?? "",
    ticketing: fields.ticketing,
    ageRequirement: fields.ageRequirement,
    externalUrl: fields.externalUrl ?? null,
    cap: fields.cap,
  });
  const { gigId, slug } = await asAdmin.mutation(api.gigs.publishDraft, {
    projectId: draft._id,
  });
  return { gigId, slug, projectId: draft._id };
}
