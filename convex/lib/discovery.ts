import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { assertUploadAcceptable } from "./helpers";

type ReadCtx = QueryCtx | MutationCtx;

export type DiscoveryListingFlags = {
  publishedShowReady: boolean;
  venuePosterReady: boolean;
  publishedRevisionCurrent: boolean;
};

export function performerLineupReady(
  bandId: Doc<"bands">["_id"],
  performers: Doc<"gigProjectPerformers">[],
): boolean {
  return (
    performers.some(
      (performer) => performer.kind === "band" && performer.bandId === bandId,
    ) && performers.every((performer) => performer.kind !== "invited")
  );
}

export async function venuePosterReady(
  ctx: ReadCtx,
  project: Doc<"gigProjects">,
): Promise<boolean> {
  if (project.venueId === undefined || !(await ctx.db.get(project.venueId))) {
    return false;
  }
  if (project.flyKey !== "custom") return true;
  if (!project.overlay || project.flyStorageId === undefined) return false;

  const upload = await ctx.db.system.get("_storage", project.flyStorageId);
  if (!upload) return false;
  try {
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
    return true;
  } catch {
    return false;
  }
}

/** Evaluates one public/project pair. Callers decide which candidate is the
 * band's relevant show; this function never reads a clock. */
export async function discoveryListingFlags(
  ctx: ReadCtx,
  project: Doc<"gigProjects">,
  gig: Doc<"gigs"> | null,
  performers: Doc<"gigProjectPerformers">[],
): Promise<DiscoveryListingFlags> {
  const isPublished =
    project.status === "published" &&
    gig !== null &&
    (gig.lifecycle ?? "published") === "published";
  return {
    publishedShowReady:
      isPublished &&
      gig.createdByBand === project.bandId &&
      gig.lineup.includes(project.bandId) &&
      performerLineupReady(project.bandId, performers),
    venuePosterReady: await venuePosterReady(ctx, project),
    publishedRevisionCurrent:
      isPublished && project.publishedRevision === project.revision,
  };
}

export function isDiscoveryListingReady(flags: DiscoveryListingFlags): boolean {
  return (
    flags.publishedShowReady &&
    flags.venuePosterReady &&
    flags.publishedRevisionCurrent
  );
}
