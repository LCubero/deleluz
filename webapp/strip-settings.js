export function stripPixels(density, meters) {
  if (!Number.isFinite(density) || density <= 0 || !Number.isFinite(meters) || meters <= 0) return null;
  const pixels = Math.round(density * meters);
  return pixels >= 1 && pixels <= 1024 ? pixels : null;
}
