// What the mod decides at each end of a turn, what becomes of the bell, and
// what the push's wait does at each tick and at a turn's start, case by case
// (the diagrams at the top of register.ts and push.ts). Nothing sits beneath
// the mod in a test: engine() stands for the machine's environment, the
// clock, the event log, the notification channel, engine-bell-off.sh,
// tmux_watched.sh's answers and ntfy, and keeps what the mod asked of each.
// The two scripts themselves are scripts/tests/engine_bell_off_test.sh's and
// scripts/tests/tmux_watched_test.sh's.

import type { TestBody } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';

// exited(1, 'no client attached'): what $.process.run answers for a program
// that printed that and left with that status; `stderr` for one that
// complained.
const exited = (exitCode: number, stdout = '', stderr = '') => ({
  value: { exitCode, stdout: `${stdout}\n`, stderr, isStdoutTruncated: false, isStderrTruncated: false },
});

// The session the tests play: its folder and id, "bench 4f1c9a2e" in the log.
const SESSION = { cwd: '/home/u/work/bench', session_id: '4f1c9a2e-0000-4000-8000-000000000000' };
const WHO = 'bench 4f1c9a2e';

// tmux_watched.sh pane's answers: exit status and what it prints.
type Look = [number, string];
const WATCHED: Look = [0, 'pts/1 focused, input 3s ago'];
const NOBODY: Look = [1, 'no client attached'];
const AWAY: Look = [1, 'pts/1 not focused, input 41s ago'];
const GONE: Look = [2, ''];
const BROKEN: Look = [3, 'tmux: protocol version mismatch (client 8, server 9)'];
// No answer in the time it is given: the call rejects.
const HUNG: Look = [-1, ''];

type Engine = {
  // The answers of `pane`, in the order asked; the last one repeats.
  looks?: Look[];
  env?: Record<string, string>;
  // false: no topic file.
  topic?: false;
  // The POST's answer: a status, or no answer at all (ntfy unreachable).
  post?: 'unreachable' | number;
  sessionGone?: true;
  // engine-bell-off.sh's answer; the bell off already unless given.
  engineBell?: ReturnType<typeof exited>;
  // What the notification channel answers; the terminal bell unless given.
  // 'broken': the call rejects.
  channel?: 'broken' | { isSent: false; reason: 'disabled' | 'no-channel' | 'no-surface' | 'refused' };
};

// A claude outside tmux: the rule and the bell alone, and no push to wait for.
const BARE: Engine = { env: { TMUX: '' } };

// engine(on, {...}) -> { log, toasts, rung, posts, ran, clock }: the events
// handed to the event log (less the log's name and "bench 4f1c9a2e", which
// every line must carry), the toasts shown, the notifications raised
// ("<title>: <text>"), the POSTs made ("<url> <title> | <tags> | <body>"),
// every program run (by its last path part and arguments), and the clock to
// move.
const engine = (on: Parameters<TestBody>[1], how: Engine = {}) => {
  const log: string[] = [];
  const toasts: string[] = [];
  const rung: string[] = [];
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

    switch (name === 'tmux_watched.sh' ? `${name} ${args[0]}` : name) {
      case 'tmux_watched.sh pane': {
        if (e.init?.timeoutMs !== 3000) throw new Error('tmux asked with no 3 s limit');
        const look = (looks.length > 1 ? looks.shift() : looks[0]) as Look;
        if (look === HUNG) throw new Error('tmux_watched.sh: timed out after 3000ms');

        return exited(...look);
      }
      case 'tmux_watched.sh session-name':
        return how.sessionGone ? exited(2) : exited(0, 'backend');
      case 'machine_name.sh':
        return exited(0, 'mbp');
      case 'engine-bell-off.sh':
        return how.engineBell ?? exited(0);
      case 'event_log_note.sh': {
        const [name, who, event = ''] = args;
        if (name !== 'claude_session_done' || who !== WHO) throw new Error(`a line for another log: ${args.join(' ')}`);
        log.push(event);

        return exited(0);
      }
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
  on('ui.notify', (_, e) => {
    rung.push(`${e.title}: ${e.text}`);
    if (how.channel === 'broken') throw new Error('broken');

    return { value: how.channel ?? { isSent: true, channel: 'terminal_bell' } };
  });
  on('ui.toast', (_, e) => {
    toasts.push(e.text);

    return { value: undefined };
  });
  on('session.id', () => ({ value: SESSION.session_id }));
  on('session.cwd', () => ({ value: SESSION.cwd }));
  on('session.start', (_, e) => ({ cwd: e.cwd }));
  on('classic.Stop', () => ({}));
  on('turn.start', (_, e) => ({ turnId: e.turnId }));
  on('prompt.submit', (_, e) => ({ text: e.text }));
  on('turn.complete', (_, e) => ({ text: e.answer }));

  return { log, toasts, rung, posts, ran, clock };
};

type Engine$ = Parameters<TestBody>[0];
type Task = { id: string; type: string; status: string; description: string };
type Cron = { id: string; schedule: string; recurring: boolean; prompt: string };

// stop($): the Stop of a turn of the main loop, with these background tasks
// and scheduled wakeups left (none unless given). Not yet the turn's end.
const stop = ($: Engine$, tasks: Task[] = [], crons: Cron[] = []) =>
  $.classic.Stop({ ...SESSION, stop_hook_active: false, background_tasks: tasks, session_crons: crons });

// over($): the end of a turn, the main loop's unless an agent is named.
const over = ($: Engine$, reason: 'answer' | 'aborted' | 'error' = 'answer', agentId?: string) =>
  $.turn.complete({ answer: 'ok', durationMs: 900, isAborted: reason === 'aborted', turnId: 't1', reason, agentId });

// ends($): a turn of the main loop as the engine plays it: its Stop, then
// its end.
const ends = async ($: Engine$, tasks: Task[] = [], crons: Cron[] = []) => {
  await stop($, tasks, crons);
  await over($);
};

// prompts($): a prompt submitted while the session is idle, the person's
// unless another origin is named, and the turn it starts.
const prompts = async (
  $: Engine$,
  kind: 'composer' | 'bridge' | 'task-notification' | 'scheduled-trigger' = 'composer',
) => {
  await $.prompt.submit({ text: 'go on', wait: false, origin: { kind } });
  await $.turn.start({ text: 'go on', turnId: 't2' });
};

const starts = ($: Engine$) => $.session.start({ cwd: SESSION.cwd, surface: 'terminal', isInteractive: true });

const MONITOR = { id: 'b5o4', type: 'monitor', status: 'running', description: 'stages' };
const SHELL = { id: 'bq2x', type: 'shell', status: 'pending', description: 'wait' };
const BUILD = { id: 'bz7k', type: 'shell', status: 'running', description: 'build' };
const WAKEUP = { id: 'c1', schedule: '31 2 20 11 *', recurring: false, prompt: '/loop check the run' };
const BELL = 'Claude Code: Claude is waiting for your input';
const RUNG = 'stop: done, bell rung via terminal_bell';
const ARMED = 'push: unwatched, waiter armed (debounce 600s; no client attached)';
const OUTSIDE = 'push: none, not in tmux';
// notDone('monitor'): the line of a turn's end that those tasks hold back.
const notDone = (tasks: string) => `stop: not done, background tasks running (${tasks}), no bell, no push`;
const HELD = `${notDone('shell')}; 600s with no turn rings`;
const SERVED = 'stop: done beside 1 shell(s) from before the last prompt, bell rung via terminal_bell';
const QUIET =
  'quiet: no turn for 600s with background tasks running (shell), taken for waiting, bell rung via terminal_bell';
// pushed('done 600s ago ...'): the POST of a push with that body.
const pushed = (body: string) => `POST http://ntfy.test/testtopic CC: mbp/backend | speech_balloon | ${body}`;
// asked(ran): what the mod asked tmux_watched.sh, of all it ran.
const asked = (ran: string[]) => ran.filter((r) => r.startsWith('tmux_watched.sh'));

// --- the rule: when a session is waiting for the person -----------------------

test('a turn that ended with nothing left rings at once', async ($, on) => {
  const { log, toasts, rung, ran } = engine(on, BARE);

  await ends($);

  expect(rung).toEqual([BELL]);
  expect(toasts).toEqual([]);
  // Outside tmux nothing but the log is run: tmux is asked nothing.
  expect(ran).toEqual([
    `event_log_note.sh claude_session_done ${WHO} ${RUNG}`,
    `event_log_note.sh claude_session_done ${WHO} ${OUTSIDE}`,
  ]);
  expect(log).toEqual([RUNG, OUTSIDE]);
});

// The complaint this mod answers: the engine's own bell rang a minute after
// each of a monitor's events (2026-11-19).
test('a turn that ended with a monitor or a shell still running is not done', async ($, on) => {
  const { log, rung, ran, clock } = engine(on);

  await ends($, [SHELL, MONITOR]);
  await clock.advance(600_000);

  expect(rung).toEqual([]);
  expect(log).toEqual([notDone('shell, monitor')]);
  // Neither tmux nor ntfy is asked anything.
  expect(ran.length).toBe(1);
});

test('a turn that ended with a wakeup scheduled is not done', async ($, on) => {
  const { log, rung, posts, clock } = engine(on);

  await ends($, [], [WAKEUP]);
  await clock.advance(600_000);

  expect(rung).toEqual([]);
  expect(posts).toEqual([]);
  expect(log).toEqual(['stop: not done, 1 wakeup(s) scheduled, no bell, no push']);
});

test('the last event of a monitor rings: the turn after the task is gone', async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await ends($, [MONITOR]);
  await $.turn.start({ text: '', turnId: 't2' });
  await ends($);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([notDone('monitor'), RUNG, OUTSIDE]);
});

// A session that kept a dev server running never rang at all (2026-11-20):
// nothing tells a server from a build but whether the person has prompted
// since it started.
test('a shell holds until the person prompts again: from then on it is a server', async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await prompts($);
  await ends($, [SHELL]);
  expect(rung).toEqual([]);

  await prompts($);
  await ends($, [SHELL]);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([HELD, SERVED, OUTSIDE]);
});

test('a prompt over Remote Control is the person too', async ($, on) => {
  const { log } = engine(on, BARE);

  await ends($, [SHELL]);
  await prompts($, 'bridge');
  await ends($, [SHELL]);

  expect(log).toEqual([HELD, SERVED, OUTSIDE]);
});

// Both are prompts to the engine (seen live, 2026-11-20), and neither is the
// person: the build they report on is still the turn's own.
test("a task's notification and a wakeup draw no line: the shell still holds", async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await ends($, [SHELL]);
  await prompts($, 'task-notification');
  await ends($, [SHELL]);
  await prompts($, 'scheduled-trigger');
  await ends($, [SHELL]);

  expect(rung).toEqual([]);
  expect(log).toEqual([HELD, HELD, HELD]);
});

test('a shell started since the prompt holds beside a server', async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await ends($, [SHELL]);
  await prompts($);
  await ends($, [SHELL, BUILD]);
  expect(rung).toEqual([]);

  // The build's exit starts a turn, and the server alone is left.
  await prompts($, 'task-notification');
  await ends($, [SHELL]);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([HELD, HELD, SERVED, OUTSIDE]);
});

// Only a shell can be a server: a monitor or a wakeup taken for one would
// ring at each of its events.
test('a monitor and a wakeup from before the prompt still hold', async ($, on) => {
  const { log, rung, clock } = engine(on, BARE);

  await ends($, [MONITOR, SHELL], [WAKEUP]);
  await prompts($);
  await ends($, [MONITOR, SHELL]);
  await prompts($);
  await ends($, [SHELL], [WAKEUP]);
  await clock.advance(600_000);

  expect(rung).toEqual([]);
  expect(log).toEqual([
    notDone('monitor, shell'),
    notDone('monitor'),
    'stop: not done, 1 wakeup(s) scheduled, no bell, no push',
  ]);
});

// The turn that started the server and then asked something: time is all
// that tells it from a build.
test('shells alone and ten quiet minutes: taken for waiting, the bell and the push', async ($, on) => {
  const { log, rung, posts, clock } = engine(on);

  await ends($, [SHELL]);
  await clock.advance(599_000);
  expect(rung).toEqual([]);

  await clock.advance(1_000);
  expect(rung).toEqual([BELL]);
  expect(log).toEqual([HELD, QUIET, ARMED]);

  await clock.advance(600_000);
  expect(posts).toEqual([pushed('went quiet with background tasks running (shell) 600s ago and is still unwatched')]);
  expect(rung).toEqual([BELL]);
});

// One of two shells exits after the quiet wait: its notification's turn ends
// beside the other, which is a server by now, and not ten more minutes on.
test('the shells of a quiet wait are servers after it: a later end beside one rings at once', async ($, on) => {
  const { log, rung, clock } = engine(on, BARE);

  await ends($, [SHELL, BUILD]);
  await clock.advance(600_000);
  expect(rung).toEqual([BELL]);

  await prompts($, 'task-notification');
  await ends($, [SHELL]);

  expect(rung).toEqual([BELL, BELL]);
  expect(log).toEqual([
    `${notDone('shell, shell')}; 600s with no turn rings`,
    'quiet: no turn for 600s with background tasks running (shell, shell), taken for waiting, bell rung via terminal_bell',
    OUTSIDE,
    SERVED,
    OUTSIDE,
  ]);
});

test('a turn that starts ends the quiet wait, and its end starts another', async ($, on) => {
  const { log, rung, clock } = engine(on, BARE);

  await ends($, [SHELL]);
  await clock.advance(400_000);
  await prompts($, 'task-notification');
  await clock.advance(400_000);
  expect(rung).toEqual([]);

  await ends($, [SHELL]);
  await clock.advance(599_000);
  expect(rung).toEqual([]);
  await clock.advance(1_000);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([HELD, HELD, QUIET, OUTSIDE]);
});

test('the quiet wait is as long as CLAUDE_SESSION_QUIET_SECONDS says', async ($, on) => {
  const { log, rung, clock } = engine(on, { env: { TMUX: '', CLAUDE_SESSION_QUIET_SECONDS: '30' } });

  await ends($, [SHELL]);
  await clock.advance(30_000);

  expect(rung).toEqual([BELL]);
  expect(log[0]).toBe('stop: not done, background tasks running (shell), no bell, no push; 30s with no turn rings');
});

test('a CLAUDE_SESSION_QUIET_SECONDS that is no number is a failure said aloud', async ($, on) => {
  const { log, toasts, rung, clock } = engine(on, { env: { TMUX: '', CLAUDE_SESSION_QUIET_SECONDS: '10m' } });

  await ends($, [SHELL]);
  await clock.advance(600_000);

  const what =
    'CLAUDE_SESSION_QUIET_SECONDS is "10m", not a whole number of seconds above 0; background tasks running (shell): no bell, no push';
  expect(log).toEqual([`stop: FAILED, ${what}`]);
  expect(toasts).toEqual([`session-done: ${what}`]);
  expect(rung).toEqual([]);
});

// A Stop hook that blocks (a /goal, a plugin's) sends the same turn on, with
// no turn.start, and the Stop fires again when it is over.
test('a Stop is not the end: a blocked one decides nothing, and the last one is what counts', async ($, on) => {
  const { log, rung, ran } = engine(on);

  await stop($);
  expect(ran).toEqual([]);

  await ends($, [SHELL]);

  expect(rung).toEqual([]);
  expect(log).toEqual([HELD]);
});

test("a subagent's end decides nothing, and leaves what the main loop's Stop said", async ($, on) => {
  const { log, rung, ran } = engine(on, BARE);

  await over($, 'answer', 'a1');
  await over($, 'error', 'a1');
  expect(ran).toEqual([]);

  await stop($, [MONITOR]);
  await over($, 'answer', 'a1');
  await over($);

  expect(rung).toEqual([]);
  expect(log).toEqual([notDone('monitor')]);
});

// Such a turn has no Stop (seen live, 2026-11-20), so nothing says what is
// left; whatever is, claude is stuck until the person looks.
test('a turn an API error ended rings, with no Stop to say what is left', async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await over($, 'error');

  expect(rung).toEqual([BELL]);
  expect(log).toEqual(['stop: ended on an API error, bell rung via terminal_bell', OUTSIDE]);
});

test('a turn the model refused rings', async ($, on) => {
  const { log, rung } = engine(on, BARE);

  await $.turn.complete({
    answer: '',
    durationMs: 900,
    isAborted: false,
    turnId: 't1',
    reason: 'refusal',
    refusal: { category: null, explanation: null },
  });

  expect(rung).toEqual([BELL]);
  expect(log).toEqual(['stop: refused, bell rung via terminal_bell', OUTSIDE]);
});

test('an interrupted turn decides nothing', async ($, on) => {
  const { rung, ran } = engine(on);

  await over($, 'aborted');

  expect(rung).toEqual([]);
  expect(ran).toEqual([]);
});

test('an end that cannot be judged is a failure said aloud: no bell, no push', async ($, on) => {
  const { log, toasts, rung, posts, clock } = engine(on);

  // No Stop before the end; a Stop without each list in turn; and a reason
  // for the end that a later Claude Code might give.
  await over($);
  await $.classic.Stop({ ...SESSION, stop_hook_active: false, session_crons: [] });
  await over($);
  await $.classic.Stop({ ...SESSION, stop_hook_active: false, background_tasks: [] });
  await over($);
  await over($, 'paused' as 'answer');
  await clock.advance(600_000);

  const so = ', so whether the session is done is unknown: no bell, no push';
  expect(log).toEqual([
    `stop: FAILED, the turn ended with no Stop before it${so}`,
    `stop: FAILED, the Stop input has no background_tasks (update Claude Code: 2.1.329 sends it)${so}`,
    `stop: FAILED, the Stop input has no session_crons (update Claude Code: 2.1.329 sends it)${so}`,
    `stop: FAILED, the turn ended for a reason this mod does not know ("paused")${so}`,
  ]);
  expect(toasts[0]).toBe(`session-done: the turn ended with no Stop before it${so}`);
  expect(toasts.length).toBe(4);
  expect(rung).toEqual([]);
  expect(posts).toEqual([]);
});

// A turn interrupted after a blocked Stop never comes to its end, and what
// that Stop left is not the next turn's.
test('what a Stop said is for its own turn: the next end with no Stop is not judged by it', async ($, on) => {
  const { log } = engine(on, BARE);

  await stop($, [MONITOR]);
  await $.turn.start({ text: 'never mind', turnId: 't2' });
  await over($);

  expect(log.length).toBe(1);
  expect(log[0]?.startsWith('stop: FAILED, the turn ended with no Stop before it')).toBe(true);
});

// --- the bell ----------------------------------------------------------------

test('notifications turned off: the bell is not sent, and the log says so', async ($, on) => {
  const { log, toasts } = engine(on, { ...BARE, channel: { isSent: false, reason: 'disabled' } });

  await ends($);

  expect(log).toEqual(['stop: done, bell not sent (disabled)', OUTSIDE]);
  expect(toasts).toEqual([]);
});

test('a channel that fails is said in the log and on screen, and the push is still decided', async ($, on) => {
  const { log, toasts } = engine(on, { channel: 'broken' });

  await ends($);

  expect(log[0]?.startsWith('stop: done, bell FAILED, ')).toBe(true);
  expect(toasts.length).toBe(1);
  expect(toasts[0]?.startsWith('session-done: the bell could not be rung: ')).toBe(true);
  expect(log.slice(1)).toEqual([ARMED]);
});

// loaded-check.sh, a SessionStart hook of settings.json, runs beneath the mod
// and reads the mark from claude's environment
// (scripts/tests/session_done_loaded_check_test.sh has its half).
test("a SessionStart carries the mod's mark to the hooks beneath it, and no further", async ($, on) => {
  const seen: string[] = [];
  on('env.set', (_, e) => {
    seen.push(`${e.name}=${e.value ?? '(unset)'}`);

    return { value: {} };
  });
  on('classic.SessionStart', () => {
    seen.push('the hooks beneath');

    return {};
  });

  await $.classic.SessionStart({ source: 'clear', ...SESSION });

  expect(seen).toEqual([
    `SESSION_DONE_MOD_SESSION=${SESSION.session_id}`,
    'the hooks beneath',
    'SESSION_DONE_MOD_SESSION=(unset)',
  ]);
});

test('a mark the engine would not set is a failure said aloud', async ($, on) => {
  const { log, toasts } = engine(on, BARE);
  on('env.set', () => ({ value: { deny: 'held by managed settings' } }));
  on('classic.SessionStart', () => ({}));

  await $.classic.SessionStart({ source: 'startup', ...SESSION });

  const said =
    'the mark loaded-check.sh goes by could not be set (held by managed settings), so it warns of a mod that is running';
  expect(log).toEqual([`session: FAILED, ${said}`]);
  expect(toasts).toEqual([`session-done: ${said}`]);
});

test("a session's start turns the engine's own bell off, and says what it was", async ($, on) => {
  const { log, toasts, ran } = engine(on, { engineBell: exited(0, 'was 60000') });

  await starts($);

  expect(ran[0]).toBe('engine-bell-off.sh');
  expect(log).toEqual([
    "session: started, turned Claude Code's own idle bell off (messageIdleNotifThresholdMs was 60000)",
  ]);
  expect(toasts).toEqual([]);
});

// The line a mod that still loads leaves at every start.
test("a session's start with the engine's bell off already says so", async ($, on) => {
  const { log } = engine(on);

  await starts($);

  expect(log).toEqual(["session: started, Claude Code's own idle bell is off"]);
});

test("the engine's bell that cannot be turned off is a failure said aloud", async ($, on) => {
  const { log, toasts } = engine(on, {
    engineBell: exited(1, '', 'engine-bell-off.sh: no /home/u/.claude.json\n'),
  });

  await starts($);

  const said =
    "Claude Code's own idle bell could not be turned off, so it rings beside this one: engine-bell-off.sh: no /home/u/.claude.json";
  expect(log).toEqual([`session: FAILED, ${said}`]);
  expect(toasts).toEqual([`session-done: ${said}`]);
});

// --- the push ------------------------------------------------------------------

test('a session that is done and nobody comes to look at is pushed once the debounce has passed', async ($, on) => {
  const { log, toasts, rung, posts, clock } = engine(on, { looks: [NOBODY, AWAY] });

  await ends($);
  await clock.advance(595_000);
  expect(posts).toEqual([]);
  await clock.advance(5_000);

  expect(posts).toEqual([pushed('done 600s ago and is still unwatched')]);
  expect(log).toEqual([
    RUNG,
    ARMED,
    'push: sent via http://ntfy.test as mbp/backend after 600s unwatched (pts/1 not focused, input 41s ago)',
  ]);
  expect(toasts).toEqual([]);

  // The wait is over: nothing more is asked or sent, and the bell rang once.
  await clock.advance(600_000);
  expect(posts.length).toBe(1);
  expect(rung).toEqual([BELL]);
});

// No socket is passed: tmux_watched.sh's tmux finds the server by $TMUX, which
// it inherits, so $TMUX's layout is read by tmux alone.
test('tmux is asked about the pane claude runs in, and is not told which server', async ($, on) => {
  const { ran, clock } = engine(on);

  await ends($);
  await clock.advance(5_000);

  expect(ran).toEqual([
    `event_log_note.sh claude_session_done ${WHO} ${RUNG}`,
    'tmux_watched.sh pane %4',
    `event_log_note.sh claude_session_done ${WHO} ${ARMED}`,
    'tmux_watched.sh pane %4',
  ]);
});

test('a turn an API error ended is pushed as such', async ($, on) => {
  const { posts, clock } = engine(on, { env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10' } });

  await over($, 'error');
  await clock.advance(10_000);

  expect(posts).toEqual([pushed('ended on an API error 10s ago and is still unwatched')]);
});

test('a prompt cancels the pending push', async ($, on) => {
  const { log, posts, clock } = engine(on);

  await ends($);
  await clock.advance(60_000);
  await $.turn.start({ text: 'and the tests?', turnId: 't2' });
  await clock.advance(600_000);

  expect(log).toEqual([RUNG, ARMED, 'prompt: user replied, pending push cancelled']);
  expect(posts).toEqual([]);
});

test("a turn that starts by itself cancels it too, a subagent's does not", async ($, on) => {
  const { log, clock } = engine(on);

  await ends($);
  await $.turn.start({ text: 'look at the logs', turnId: 't2', agentId: 'a1' });
  expect(log.length).toBe(2);
  await $.turn.start({ text: '', turnId: 't3' });
  await clock.advance(600_000);

  expect(log).toEqual([RUNG, ARMED, 'turn: started with no prompt, pending push cancelled']);
});

// A server's exit is a prompt too, a task's notification, and the log does
// not put it down to the person.
test("a task's notification cancels it, and is named as what started the turn", async ($, on) => {
  const { log, posts, clock } = engine(on);

  await ends($);
  await prompts($, 'task-notification');
  await clock.advance(600_000);

  expect(log).toEqual([RUNG, ARMED, 'turn: a task-notification started one, pending push cancelled']);
  expect(posts).toEqual([]);
});

// Typed over a running turn, a prompt starts none then: the origin kept is
// that of the prompt that does.
test('a prompt typed over a running turn draws the line, and names no turn', async ($, on) => {
  const { log } = engine(on);

  await ends($, [SHELL]);
  await prompts($, 'task-notification');
  await $.prompt.submit({ text: 'and commit it', wait: false, turnId: 't2', origin: { kind: 'composer' } });
  await ends($, [SHELL]);
  await prompts($, 'task-notification');

  expect(log).toEqual([HELD, SERVED, ARMED, 'turn: a task-notification started one, pending push cancelled']);
});

test('with no push pending, a prompt runs nothing', async ($, on) => {
  const { ran } = engine(on);

  await $.turn.start({ text: 'hello', turnId: 't1' });

  expect(ran).toEqual([]);
});

test('watched at the end: the bell, and no wait', async ($, on) => {
  const { log, rung, ran, clock } = engine(on, { looks: [WATCHED] });

  await ends($);
  await clock.advance(600_000);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([RUNG, 'push: none, watched now']);
  expect(ran.filter((r) => r.startsWith('tmux_watched.sh pane')).length).toBe(1);
});

test('seen during the wait: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { looks: [NOBODY, AWAY, WATCHED] });

  await ends($);
  await clock.advance(600_000);

  expect(log[2]).toBe('wait: seen after 10s, no push');
  expect(posts).toEqual([]);
});

test('the pane gone during the wait, or at the end: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { looks: [NOBODY, GONE] });

  await ends($);
  await clock.advance(5_000);
  await ends($);
  await clock.advance(600_000);

  expect(log).toEqual([
    RUNG,
    ARMED,
    "wait: session or claude's pane %4 gone, no push",
    RUNG,
    "push: none, session or claude's pane %4 gone",
  ]);
  expect(posts).toEqual([]);
});

test('unwatched to the end, and the pane gone when its name is asked for the title: no push', async ($, on) => {
  const { log, posts, clock } = engine(on, { sessionGone: true });

  await ends($);
  await clock.advance(600_000);

  expect(log[2]).toBe("wait: session or claude's pane %4 gone, no push");
  expect(posts).toEqual([]);
});

test('tmux failing is said, at the end on screen too, and never read as gone', async ($, on) => {
  const { log, toasts, posts, clock } = engine(on, { looks: [BROKEN, NOBODY, BROKEN] });
  const mismatch = BROKEN[1];

  await ends($);
  expect(log).toEqual([RUNG, `push: FAILED, ${mismatch}, so whether the turn was seen is unknown`]);
  expect(toasts).toEqual([`session-done: ${mismatch}, so whether the turn was seen is unknown`]);

  await ends($);
  await clock.advance(600_000);
  expect(log.slice(2)).toEqual([RUNG, ARMED, `wait: FAILED, ${mismatch}; no push`]);
  expect(toasts.length).toBe(1);
  expect(posts).toEqual([]);
});

// The stand-in refuses a question to tmux that carries no 3 s limit, so
// every test of the push holds the mod to it.
test('a tmux that does not answer in its 3 s fails the same way, and holds nothing up', async ($, on) => {
  const { log, toasts, posts, clock } = engine(on, { looks: [HUNG, NOBODY, HUNG] });

  await ends($);
  expect(log[1]?.startsWith('push: FAILED, ')).toBe(true);
  expect(log.length).toBe(2);
  expect(toasts.length).toBe(1);

  await ends($);
  await clock.advance(600_000);
  expect(log[4]).toMatch(/^wait: FAILED, .+; no push$/);
  expect(log.length).toBe(5);
  expect(posts).toEqual([]);
});

test('an end takes the push still pending from an earlier one, and decides afresh', async ($, on) => {
  const { log, posts, clock } = engine(on);
  const taken = 'turn: another ended, pending push cancelled';

  await ends($);
  await ends($, [MONITOR]);
  await ends($);
  await ends($);
  await clock.advance(5_000);

  expect(log).toEqual([RUNG, ARMED, taken, notDone('monitor'), RUNG, ARMED, taken, RUNG, ARMED]);

  // One wait is left of the three, and it pushes once.
  await clock.advance(600_000);
  expect(posts.length).toBe(1);
});

test('$TMUX with no $TMUX_PANE: the bell, and the push fails loudly', async ($, on) => {
  const { log, toasts, rung } = engine(on, { env: { TMUX_PANE: '' } });

  await ends($);

  expect(rung).toEqual([BELL]);
  expect(log[1]?.startsWith('push: FAILED, $TMUX is set but $TMUX_PANE is not, so ')).toBe(true);
  expect(log.length).toBe(2);
  expect(toasts.length).toBe(1);
});

test('with no topic file: the bell, the reason in the log, and tmux is asked nothing', async ($, on) => {
  const { log, ran, rung } = engine(on, { topic: false });

  await ends($);

  expect(rung).toEqual([BELL]);
  expect(log).toEqual([RUNG, 'push: none, no topic file']);
  expect(asked(ran)).toEqual([]);
});

// The real failure names the URL, topic and all, and the mod writes
// "<topic>" for it. A stand-in cannot fail in the engine's words, so that
// part was checked in a real session against a closed port (2026-11-20):
//   push: FAILED, HooksError: session-done: $.http.fetch(http://127.0.0.1:9/<topic>)
//   failed: ECONNREFUSED: ... (http://127.0.0.1:9; no client attached)
test('a push that cannot be sent is logged, and the topic never is', async ($, on) => {
  const { log, posts, clock } = engine(on, { post: 'unreachable', env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10' } });

  await ends($);
  await clock.advance(10_000);

  expect(posts.length).toBe(1);
  expect(log[2]).toMatch(/^push: FAILED, .+ \(http:\/\/ntfy\.test; no client attached\)$/);
  expect(log.join('\n')).not.toContain('testtopic');
});

test('a debounce that is not a number of seconds: the bell, and the push fails loudly', async ($, on) => {
  const { log, toasts, rung, posts, clock } = engine(on, { env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10m' } });

  await ends($);
  await clock.advance(600_000);

  const what = 'CLAUDE_NTFY_DEBOUNCE_SECONDS is "10m", not a whole number of seconds above 0';
  expect(rung).toEqual([BELL]);
  expect(log).toEqual([RUNG, `push: FAILED, ${what}`]);
  expect(toasts).toEqual([`session-done: ${what}`]);
  expect(posts).toEqual([]);
});

test('a push ntfy refuses is logged with its status', async ($, on) => {
  const { log, clock } = engine(on, { post: 429, env: { CLAUDE_NTFY_DEBOUNCE_SECONDS: '10' } });

  await ends($);
  await clock.advance(10_000);

  expect(log[2]).toBe('push: FAILED, HTTP 429 (http://ntfy.test; no client attached)');
});
