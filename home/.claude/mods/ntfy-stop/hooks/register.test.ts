// What the mod decides at each Stop, at each tick of a wait, and at a turn's
// start, case by case (the diagram at the top of register.ts). Nothing sits
// beneath the mod in a test: engine() stands for the machine's environment,
// tmux-watch.sh's answers, the event log, the clock and ntfy, and keeps what
// the mod asked of each. tmux itself is scripts/tests/ntfy_watch_test.sh's.

import type { TestBody } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';

// exited(1, 'no client attached'): what $.process.run answers for a program
// that printed that and left with that status.
const exited = (exitCode: number, stdout = '') => ({
  value: { exitCode, stdout: `${stdout}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
});

// tmux-watch.sh watched's answers: exit status and what it prints.
const WATCHED: Look = [0, ''];
const NOBODY: Look = [1, 'no client attached'];
const AWAY: Look = [1, 'pts/1 not focused, input 41s ago'];
const GONE: Look = [2, ''];
const BROKEN: Look = [3, 'tmux -S /tmp/tmux-1/default: protocol version mismatch (client 8, server 9)'];

type Look = [number, string];
type Engine = {
  // The answers of `watched`, in the order asked; the last one repeats.
  looks?: Look[];
  env?: Record<string, string>;
  // false: no topic file.
  topic?: false;
  // The POST's answer: a status, or no answer at all (ntfy unreachable).
  post?: 'unreachable' | number;
  sessionGone?: true;
};

// engine(on, {...}) -> { log, toasts, posts, ran, clock }: the lines handed
// to the event log, the toasts shown, the POSTs made ("<url> <title> |
// <tags> | <body>"), every program run (by its last path part and
// arguments), and the clock to move.
const engine = (on: Parameters<TestBody>[1], how: Engine = {}) => {
  const log: string[] = [];
  const toasts: string[] = [];
  const posts: string[] = [];
  const ran: string[] = [];
  const looks = [...(how.looks ?? [NOBODY])];

  const clock = mock.clock(on, { now: 1_000_000 });
  mock.env(on, {
    HOME: '/home/u',
    TMUX: '/tmp/tmux-1/default,4242,3',
    TMUX_PANE: '%4',
    CLAUDE_NTFY_URL: 'http://ntfy.test',
    ...how.env,
  });
  on('fs.exists', () => ({ value: how.topic !== false }));
  on('fs.read', (_, e) => {
    if (e.path !== '/home/u/.config/claude-ntfy/topic') throw new Error(`a file the mod should not read: ${e.path}`);

    return { value: 'testtopic\n' };
  });
  on('process.run', (_, e) => {
    const [program = '', ...args] = e.argv;
    const name = program.slice(program.lastIndexOf('/') + 1);
    ran.push([name, ...args].join(' '));

    switch (name === 'tmux-watch.sh' ? `${name} ${args[0]}` : name) {
      case 'tmux-watch.sh who':
        return exited(0, 'backend ($3)');
      case 'tmux-watch.sh watched':
        return exited(...((looks.length > 1 ? looks.shift() : looks[0]) ?? NOBODY));
      case 'tmux-watch.sh session':
        return how.sessionGone ? exited(2) : exited(0, 'backend');
      case 'machine_name.sh':
        return exited(0, 'mbp');
      case 'event_log_note.sh':
        log.push(args.slice(1).join(' '));

        return exited(0);
    }
    throw new Error(`a program the mod should not run: ${program}`);
  });
  on('http.fetch', (_, e) => {
    posts.push(`${e.init?.method} ${e.url} ${e.init?.headers?.Title} | ${e.init?.headers?.Tags} | ${e.init?.body}`);
    // A hook of the test's that throws is skipped, and with nothing beneath
    // it the mod's call rejects: the one way a test makes a `$` call fail.
    if (how.post === 'unreachable') throw new Error('unreachable');
    const status = how.post ?? 200;

    return { value: { status, ok: status < 300, headers: {}, text: '' } };
  });
  on('ui.toast', (_, e) => {
    toasts.push(e.text);

    return { value: undefined };
  });
  on('classic.Stop', () => ({}));
  on('turn.start', (_, e) => ({ turnId: e.turnId }));

  return { log, toasts, posts, ran, clock };
};

// stop($): a turn of the main loop ends, with these background tasks left
// (none unless given).
const stop = (
  $: Parameters<TestBody>[0],
  tasks: { id: string; type: string; status: string; description: string }[] = [],
) => $.classic.Stop({ stop_hook_active: false, background_tasks: tasks, session_crons: [] });

const MONITOR = { id: 'b5o4', type: 'monitor', status: 'running', description: 'stages' };
const SHELL = { id: 'bq2x', type: 'shell', status: 'pending', description: 'wait' };

test('a turn nobody comes to look at is pushed once the debounce has passed', async ($, on) => {
  const { log, toasts, posts, clock } = engine(on, { looks: [NOBODY, AWAY] });

  await stop($);
  await clock.advance(595_000);
  expect(posts).toEqual([]);
  await clock.advance(5_000);

  expect(posts).toEqual([
    'POST http://ntfy.test/testtopic CC: mbp/backend | speech_balloon | finished a turn 600s ago and is still unwatched',
  ]);
  expect(log).toEqual([
    'backend ($3) stop: unwatched, waiter armed (debounce 600s; no client attached)',
    'backend ($3) push: sent via http://ntfy.test after 600s unwatched (pts/1 not focused, input 41s ago)',
  ]);
  expect(toasts).toEqual([]);

  // The wait is over: nothing more is asked or sent.
  await clock.advance(600_000);
  expect(posts.length).toBe(1);
});

test('tmux is asked with the $TMUX and the pane claude runs in', async ($, on) => {
  const { ran, clock } = engine(on);

  await stop($);
  await clock.advance(5_000);

  expect(ran).toEqual([
    'tmux-watch.sh who /tmp/tmux-1/default,4242,3',
    'tmux-watch.sh watched /tmp/tmux-1/default,4242,3 %4',
    'event_log_note.sh claude_ntfy backend ($3) stop: unwatched, waiter armed (debounce 600s; no client attached)',
    'tmux-watch.sh watched /tmp/tmux-1/default,4242,3 %4',
  ]);
});

test('a prompt cancels the pending push', async ($, on) => {
  const { log, posts, clock } = engine(on);

  await stop($);
  await clock.advance(60_000);
  await $.turn.start({ text: 'and the tests?', turnId: 't2' });
  await clock.advance(600_000);

  expect(log[1]).toBe('backend ($3) prompt: user replied, pending push cancelled');
  expect(log.length).toBe(2);
  expect(posts).toEqual([]);
});

test("a turn that starts by itself cancels it too, a subagent's does not", async ($, on) => {
  const { log, clock } = engine(on);

  await stop($);
  await $.turn.start({ text: 'look at the logs', turnId: 't2', agentId: 'a1' });
  expect(log.length).toBe(1);
  await $.turn.start({ text: '', turnId: 't3' });
  await clock.advance(600_000);

  expect(log).toEqual([
    'backend ($3) stop: unwatched, waiter armed (debounce 600s; no client attached)',
    'backend ($3) turn: started with no prompt, pending push cancelled',
  ]);
});

test('with no push pending, a prompt runs nothing', async ($, on) => {
  const { ran } = engine(on);

  await $.turn.start({ text: 'hello', turnId: 't1' });

  expect(ran).toEqual([]);
});

test('watched at the Stop: no wait', async ($, on) => {
  const { log, ran, clock } = engine(on, { looks: [WATCHED] });

  await stop($);
  await clock.advance(600_000);

  expect(log).toEqual(['backend ($3) stop: watched now, no push']);
  expect(ran.filter((r) => r.startsWith('tmux-watch.sh watched')).length).toBe(1);
});

test('seen during the wait: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { looks: [NOBODY, AWAY, WATCHED] });

  await stop($);
  await clock.advance(600_000);

  expect(log[1]).toBe('backend ($3) wait: seen after 10s, no push');
  expect(posts).toEqual([]);
});

test('the pane gone at the Stop, or during the wait: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { looks: [NOBODY, GONE] });

  await stop($);
  await clock.advance(5_000);
  await stop($);
  await clock.advance(600_000);

  expect(log.slice(1)).toEqual([
    "backend ($3) wait: session or claude's pane %4 gone, no push",
    "backend ($3) stop: session or claude's pane %4 gone, no push",
  ]);
  expect(posts).toEqual([]);
});

test('unwatched to the end, and the pane gone when its name is asked for the title: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { sessionGone: true });

  await stop($);
  await clock.advance(600_000);

  expect(log[1]).toBe("backend ($3) wait: session or claude's pane %4 gone, no push");
  expect(posts).toEqual([]);
});

test('tmux failing is said, at the Stop on screen too, and never read as gone', async ($, on) => {
  const { log, toasts, posts, clock } = engine(on, { looks: [BROKEN, NOBODY, BROKEN] });

  await stop($);
  expect(log).toEqual([
    'backend ($3) stop: FAILED, tmux -S /tmp/tmux-1/default: protocol version mismatch (client 8, server 9)',
  ]);
  expect(toasts).toEqual([
    'tmux -S /tmp/tmux-1/default: protocol version mismatch (client 8, server 9), so whether the turn was seen is unknown',
  ]);

  await stop($);
  await clock.advance(600_000);
  expect(log[2]).toBe(
    'backend ($3) wait: FAILED, tmux -S /tmp/tmux-1/default: protocol version mismatch (client 8, server 9); no push',
  );
  expect(log.length).toBe(3);
  expect(posts).toEqual([]);
});

test('a Stop with background tasks running is not done, and cancels a pending push', async ($, on) => {
  const { log, posts, clock } = engine(on);

  await stop($, [MONITOR, SHELL]);
  expect(log).toEqual(['backend ($3) stop: not done, background tasks running (monitor, shell), no push']);

  await stop($);
  await stop($, [MONITOR]);
  await clock.advance(600_000);

  expect(log[2]).toBe(
    'backend ($3) stop: not done, background tasks running (monitor), no push; pending push cancelled',
  );
  expect(posts).toEqual([]);
});

test('a Stop input with no background_tasks fails loudly', async ($, on) => {
  const { log, toasts, clock } = engine(on);

  // What a Claude Code before 2.1.327 sends.
  await $.classic.Stop({ stop_hook_active: false });
  await clock.advance(600_000);

  expect(log).toEqual(['backend ($3) stop: FAILED, the Stop input has no background_tasks']);
  expect(toasts).toEqual([
    'the Stop input has no background_tasks, so whether the session is done is unknown; update Claude Code (2.1.327 sends it)',
  ]);
});

test('$TMUX with no $TMUX_PANE fails loudly', async ($, on) => {
  const { log, toasts } = engine(on, { env: { TMUX_PANE: '' } });

  await stop($);

  expect(log).toEqual(['backend ($3) stop: FAILED, $TMUX is set but $TMUX_PANE is not']);
  expect(toasts.length).toBe(1);
});

test('outside tmux the mod does nothing', async ($, on) => {
  const { ran, log } = engine(on, { env: { TMUX: '' } });

  await stop($);

  expect(ran).toEqual([]);
  expect(log).toEqual([]);
});

test('with no topic file the mod does nothing', async ($, on) => {
  const { ran, log } = engine(on, { topic: false });

  await stop($);

  expect(ran).toEqual([]);
  expect(log).toEqual([]);
});

// The real failure names the URL, topic and all, and the mod writes
// "<topic>" for it. A stand-in cannot fail in the engine's words, so that
// part was checked in a real session against a closed port (2026-11-19):
//   push: FAILED, HooksError: ntfy-stop: $.http.fetch(http://127.0.0.1:9/<topic>)
//   failed: ECONNREFUSED: ... (http://127.0.0.1:9; no client attached)
test('a push that cannot be sent is logged, and the topic never is', async ($, on) => {
  const { log, posts, clock } = engine(on, { post: 'unreachable', env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10' } });

  await stop($);
  await clock.advance(10_000);

  expect(posts.length).toBe(1);
  expect(log[1]).toMatch(/^backend \(\$3\) push: FAILED, .+ \(http:\/\/ntfy\.test; no client attached\)$/);
  expect(log.join('\n')).not.toContain('testtopic');
});

test('a debounce that is not a number of seconds stops the mod, and arms nothing', async ($, on) => {
  const { ran, posts, clock } = engine(on, { env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10m' } });

  await stop($);
  await clock.advance(600_000);

  expect(ran).toEqual([]);
  expect(posts).toEqual([]);
});

test('a push ntfy refuses is logged with its status', async ($, on) => {
  const { log, clock } = engine(on, { post: 429, env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10' } });

  await stop($);
  await clock.advance(10_000);

  expect(log[1]).toBe('backend ($3) push: FAILED, HTTP 429 (http://ntfy.test; no client attached)');
});
