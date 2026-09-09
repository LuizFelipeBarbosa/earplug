export function randomHexToken(bytes: number = 16): string {
  const randomBytes = new Uint8Array(bytes);
  crypto.getRandomValues(randomBytes);
  return Array.from(randomBytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}
