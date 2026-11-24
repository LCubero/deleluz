import test from 'node:test';
import assert from 'node:assert/strict';
import { formatRemaining, fadeBrightness } from './timer.js';

test('remaining time is mm:ss, supports long timers and clamps at zero', () => {
  for (const [remaining, expected] of [[125, '02:05'], [7200, '120:00'], [0.1, '00:01'], [-1, '00:00']]) {
    assert.equal(formatRemaining(remaining), expected);
  }
});

test('fade takes one step per five seconds in the last minute', () => {
  for (const [remaining, expected] of [[61, null], [60, null], [56, null], [55, 73], [30, 40], [29, 40], [5, 7], [0, null]]) {
    assert.equal(fadeBrightness(80, remaining, true), expected);
  }
  assert.equal(fadeBrightness(1, 5, true), 1);
});

test('disabled fade never schedules a brightness command', () => {
  assert.equal(fadeBrightness(80, 30, false), null);
});

test('custom timer takes minutes and seconds, from 1 second to 720 minutes', async () => {
  const { parseTimerDuration } = await import('./timer.js');
  for (const [min, sec, expected] of [['0', '10', 10], ['', '30', 30], ['5', '', 300], ['1', '30', 90], ['720', '0', 43200], ['0', '59', 59]]) {
    assert.equal(parseTimerDuration(min, sec), expected, `${min}:${sec}`);
  }
  for (const [min, sec] of [['', ''], ['0', '0'], ['0', '60'], ['720', '1'], ['721', ''], ['1.5', ''], ['', '-1'], ['abc', '5']]) {
    assert.equal(parseTimerDuration(min, sec), null, `${min}:${sec}`);
  }
});
