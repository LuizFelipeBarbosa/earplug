import { flag } from "./env";

export const BAND_GIG_WRITE_MESSAGE =
  "Bands now get booked through organizations. Find opportunities on your Gigs page.";

export function bandGigWritesEnabled(): boolean {
  return flag("BAND_GIG_WRITES", true);
}

export function assertBandGigWritesEnabled(): void {
  if (!bandGigWritesEnabled()) throw new Error(BAND_GIG_WRITE_MESSAGE);
}
