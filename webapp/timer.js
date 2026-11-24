// Custom off timer: whole minutes (0-720) and seconds (0-59); blank counts as 0.
// Returns total seconds from 1 s to 720 min, or null when invalid.
export function parseTimerDuration(minutes, seconds) {
  const field = value => (value.trim() === '' ? 0 : /^\d+$/.test(value.trim()) ? Number(value) : NaN);
  const min = field(minutes);
  const sec = field(seconds);
  if (Number.isNaN(min) || Number.isNaN(sec) || sec > 59) return null;
  const total = min * 60 + sec;
  return total >= 1 && total <= 720 * 60 ? total : null;
}

export function formatRemaining(seconds) {
  const rounded = Math.max(0, Math.ceil(seconds));
  return [Math.floor(rounded / 60), rounded % 60].map(value => String(value).padStart(2, '0')).join(':');
}

// Null means no brightness write; callers deduplicate each five-second step.
export function fadeBrightness(brightness, remaining, enabled) {
  if (!enabled || remaining > 55 || remaining <= 0) return null;
  return Math.max(1, Math.round(brightness * Math.ceil(remaining / 5) / 12));
}
