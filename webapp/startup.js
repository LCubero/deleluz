// Sends the frames that prepare a mode (power, brightness) in order.
// Returns false when the start was superseded (frames canceled or a newer run began).
// A 'replaced' frame is not a failure: a newer frame with the same key (e.g. the user
// dragging brightness) takes its place in the queue and is sent instead.
export async function runStartup(send, frames, isCurrent) {
  for (const { bytes, key } of frames) {
    if (await send(bytes, key) === 'canceled' || !isCurrent()) return false;
  }
  return true;
}
