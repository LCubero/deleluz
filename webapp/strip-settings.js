export function validPixels(pixels) {
  return Number.isInteger(pixels) && pixels >= 1 && pixels <= 1024 ? pixels : null;
}

export function stripPixels(density, meters) {
  if (!Number.isFinite(density) || density <= 0 || !Number.isFinite(meters) || meters <= 0) return null;
  return validPixels(Math.round(density * meters));
}
