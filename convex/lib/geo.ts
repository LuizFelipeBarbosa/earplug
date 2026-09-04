export const SF_CENTER = { lat: 37.7599, lng: -122.4148 };
export const OAK_CENTER = { lat: 37.8378, lng: -122.2628 };

export type LatLng = { lat: number; lng: number };

export function milesBetween(from: LatLng, to: LatLng): number {
  const radians = (degrees: number) => (degrees * Math.PI) / 180;
  const earthMiles = 3958.7613;
  const dLat = radians(to.lat - from.lat);
  const dLng = radians(to.lng - from.lng);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(from.lat)) *
      Math.cos(radians(to.lat)) *
      Math.sin(dLng / 2) ** 2;
  return earthMiles * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function formatMiles(from: LatLng, to: LatLng): string {
  return `${milesBetween(from, to).toFixed(1)} mi`;
}

export type Neighborhood = {
  label: string;
  city: string;
  lat: number;
  lng: number;
};

export const NEIGHBORHOODS: readonly Neighborhood[] = [
  { label: "Mission", city: "San Francisco", lat: 37.7599, lng: -122.4148 },
  { label: "SoMa", city: "San Francisco", lat: 37.7785, lng: -122.395 },
  { label: "Tenderloin", city: "San Francisco", lat: 37.7847, lng: -122.4145 },
  {
    label: "Haight-Ashbury",
    city: "San Francisco",
    lat: 37.7692,
    lng: -122.4481,
  },
  { label: "Castro", city: "San Francisco", lat: 37.7609, lng: -122.435 },
  { label: "North Beach", city: "San Francisco", lat: 37.8061, lng: -122.4103 },
  {
    label: "Inner Richmond",
    city: "San Francisco",
    lat: 37.7807,
    lng: -122.4661,
  },
  {
    label: "Outer Richmond",
    city: "San Francisco",
    lat: 37.7799,
    lng: -122.4935,
  },
  {
    label: "Inner Sunset",
    city: "San Francisco",
    lat: 37.7609,
    lng: -122.4662,
  },
  { label: "Outer Sunset", city: "San Francisco", lat: 37.7534, lng: -122.495 },
  { label: "Bayview", city: "San Francisco", lat: 37.7298, lng: -122.392 },
  { label: "Dogpatch", city: "San Francisco", lat: 37.7596, lng: -122.388 },
  { label: "Potrero Hill", city: "San Francisco", lat: 37.756, lng: -122.4015 },
  { label: "Marina", city: "San Francisco", lat: 37.803, lng: -122.436 },
  { label: "Hayes Valley", city: "San Francisco", lat: 37.7764, lng: -122.424 },
  { label: "Lower Haight", city: "San Francisco", lat: 37.772, lng: -122.431 },
  { label: "Nob Hill", city: "San Francisco", lat: 37.793, lng: -122.416 },
  { label: "Chinatown", city: "San Francisco", lat: 37.7941, lng: -122.4078 },
  { label: "Excelsior", city: "San Francisco", lat: 37.721, lng: -122.431 },
  {
    label: "Bernal Heights",
    city: "San Francisco",
    lat: 37.739,
    lng: -122.415,
  },
  { label: "Fillmore", city: "San Francisco", lat: 37.783, lng: -122.432 },
  { label: "Downtown", city: "Oakland", lat: 37.8044, lng: -122.2711 },
  { label: "Uptown", city: "Oakland", lat: 37.8124, lng: -122.268 },
  { label: "Temescal", city: "Oakland", lat: 37.837, lng: -122.262 },
  { label: "Rockridge", city: "Oakland", lat: 37.8445, lng: -122.251 },
  { label: "Fruitvale", city: "Oakland", lat: 37.775, lng: -122.224 },
  { label: "Jack London", city: "Oakland", lat: 37.7955, lng: -122.277 },
  { label: "Grand Lake", city: "Oakland", lat: 37.811, lng: -122.247 },
  { label: "West Oakland", city: "Oakland", lat: 37.806, lng: -122.294 },
  { label: "Laurel", city: "Oakland", lat: 37.791, lng: -122.196 },
  { label: "Downtown", city: "Berkeley", lat: 37.8715, lng: -122.273 },
  { label: "Southside", city: "Berkeley", lat: 37.866, lng: -122.258 },
  { label: "North Berkeley", city: "Berkeley", lat: 37.883, lng: -122.278 },
  { label: "West Berkeley", city: "Berkeley", lat: 37.87, lng: -122.294 },
  { label: "Emeryville", city: "Emeryville", lat: 37.8313, lng: -122.2852 },
  { label: "Alameda", city: "Alameda", lat: 37.7652, lng: -122.2416 },
  { label: "Richmond", city: "Richmond", lat: 37.9358, lng: -122.3477 },
  { label: "Daly City", city: "Daly City", lat: 37.6879, lng: -122.4702 },
  { label: "San Mateo", city: "San Mateo", lat: 37.563, lng: -122.3255 },
  { label: "Palo Alto", city: "Palo Alto", lat: 37.4419, lng: -122.143 },
  { label: "Downtown", city: "San Jose", lat: 37.3355, lng: -121.889 },
  { label: "Hayward", city: "Hayward", lat: 37.6688, lng: -122.0808 },
  { label: "Fremont", city: "Fremont", lat: 37.5485, lng: -121.9886 },
  { label: "Walnut Creek", city: "Walnut Creek", lat: 37.9101, lng: -122.0652 },
  { label: "San Rafael", city: "San Rafael", lat: 37.9735, lng: -122.5311 },
];

export type ApproxLocation = {
  lat: number;
  lng: number;
  label: string;
  neighborhood: string | null;
  city: string | null;
};

export function approximateLocation(
  point: LatLng,
  fallbackLabel: string,
): ApproxLocation {
  let nearest = NEIGHBORHOODS[0];
  let nearestMiles = milesBetween(point, nearest);
  for (const neighborhood of NEIGHBORHOODS.slice(1)) {
    const distance = milesBetween(point, neighborhood);
    if (distance < nearestMiles) {
      nearest = neighborhood;
      nearestMiles = distance;
    }
  }

  if (nearestMiles <= 2.5) {
    return {
      lat: nearest.lat,
      lng: nearest.lng,
      label: `${nearest.label}, ${nearest.city}`,
      neighborhood: nearest.label,
      city: nearest.city,
    };
  }

  return {
    lat: Math.round(point.lat * 100) / 100,
    lng: Math.round(point.lng * 100) / 100,
    label: fallbackLabel.trim() || "Bay Area",
    neighborhood: null,
    city: null,
  };
}
