import { describe, expect, test } from "vitest";
import {
  approximateLocation,
  formatMiles,
  NEIGHBORHOODS,
  OAK_CENTER,
  SF_CENTER,
} from "./lib/geo";

describe("geo helpers", () => {
  test("snaps a Mission point to the Mission centroid", () => {
    const result = approximateLocation(
      { lat: 37.7599, lng: -122.4148 },
      "San Francisco",
    );
    const mission = NEIGHBORHOODS.find(
      (entry) => entry.label === "Mission" && entry.city === "San Francisco",
    );

    expect(mission).toBeDefined();
    expect(result).toEqual({
      lat: mission!.lat,
      lng: mission!.lng,
      label: "Mission, San Francisco",
      neighborhood: "Mission",
      city: "San Francisco",
    });
  });

  test("rounds a point far from every known centroid", () => {
    expect(
      approximateLocation(
        { lat: 35.12345, lng: -120.67891 },
        "Remote California",
      ),
    ).toEqual({
      lat: 35.12,
      lng: -120.68,
      label: "Remote California",
      neighborhood: null,
      city: null,
    });
  });

  test("never exposes exact unrounded fallback coordinates", () => {
    const point = { lat: 35.12345, lng: -120.67891 };
    const result = approximateLocation(point, "Remote California");

    expect(result.lat).not.toBe(point.lat);
    expect(result.lng).not.toBe(point.lng);
  });

  test("formats a known distance with one decimal place", () => {
    expect(formatMiles(SF_CENTER, OAK_CENTER)).toBe("9.9 mi");
  });
});
