export function persistState(key, snapshot, getStorage = () => localStorage) {
  try {
    getStorage().setItem(key, JSON.stringify(snapshot));
  } catch {
    // Storage is optional; keep the in-memory state and let strip commands proceed.
  }
}
