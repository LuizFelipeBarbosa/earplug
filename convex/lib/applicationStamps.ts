import type { Doc } from "../_generated/dataModel";
import type { ArtistApplicationStatus } from "./opportunityStatus";

export function applicationStatusPatch(
  doc: Doc<"artistApplications">,
  status: ArtistApplicationStatus,
  now: number,
) {
  const impliesViewed =
    status === "under_review" ||
    status === "shortlisted" ||
    status === "declined" ||
    status === "offered" ||
    status === "booked";

  return {
    status,
    updatedAt: now,
    ...(status === "shortlisted" && doc.shortlistedAt === undefined
      ? { shortlistedAt: now }
      : {}),
    ...(impliesViewed && doc.viewedAt === undefined ? { viewedAt: now } : {}),
  };
}
