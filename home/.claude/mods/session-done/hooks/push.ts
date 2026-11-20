// The push to ntfy.sh for a session that is waiting for the person
// (register.ts decides when) and that nobody comes to look at within the
// debounce (CLAUDE_NTFY_DEBOUNCE_SECONDS, default 10 minutes).
//
//   armPush (the session is waiting)
//     |
//     v
//   watched now? --yes--> no push
//     | no
//     v
//   wait: asks tmux every 5 s
//     |-- seen, or the pane gone -------------> no push
//     |-- cancelPush (a turn started: a prompt,
//     |   a task's notification, a cron) -----> no push; that turn's end
//     |                                         decides
//     '-- 10 min unwatched -------------------> push
//
// Watched means a terminal shows claude's pane, is focused, and gave input
// lately: scripts/tmux_watched.sh asks tmux and says which. Its header has
// the rule, which the bell marker on tmux's bars goes by too, for a session
// whole (home/.config/tmux/bell-elsewhere.sh). This
// channel is a deliberate backup to Claude Code's own mobile push: it goes
// by tmux's client focus, not by claude's idea of presence, and waits out a
// debounce the native push does not have.
//
// One wait at a time, kept in this module's own variables with its timer:
// it lives and dies with the claude process, so quitting claude drops a
// pending push (whoever quit it was there), and so does a crash. Editing
// this mod while a wait is pending drops it too: a reload stops the timer.
//
// The topic is the first line of ~/.config/claude-ntfy/topic, which stays
// OUTSIDE this repo on purpose: an ntfy.sh topic is a capability -- anyone
// who knows it can subscribe, and this repo is public. Each machine has its
// own, kept in the private repo (scripts/setup_user_symlinks.sh links it).
// No topic file, or a claude outside tmux: nothing is pushed, by design,
// and the log says which. The topic is never logged.
import type { EngineInterface } from 'claude-code';
import { fail, note, script, seconds, words } from './log';

const POLL_MS = 5000;
// tmux answers in about 20 ms. One that does not within this has hung, and
// the turn's end is not held for the 30 s a process is given by default.
const TMUX_MS = 3000;

// Where this claude runs (its tmux pane; tmux_watched.sh finds the server by
// $TMUX, which it inherits) and where its pushes go, read each time the
// session is waiting.
type Here = { pane: string; topic: string; debounce: number; url: string };

// tmux_watched.sh's answer, by its exit status 0 to 3, and what it printed:
//   pane           yes | no (said: the clients it saw) | gone | failed (said: why)
//   session-name   yes (said: the pane's session)      | gone | failed
const ANSWERS = ['yes', 'no', 'gone', 'failed'] as const;
type Answer = { is: (typeof ANSWERS)[number]; said: string };

// The pending push: where from and to, how the session came to wait in
// register.ts's words ("done", "went quiet with ..."), when (ms), and
// whether tmux is being asked now.
type Wait = { here: Here; how: string; since: number; isAsking: boolean; timer: { cancel: () => void } };

let wait: Wait | null = null;

const end = (it: Wait): void => {
  it.timer.cancel();
  if (wait === it) wait = null;
};

// An error from the fetch quotes its URL, and the URL ends in the topic.
const redacted = (here: Here, err: unknown): string => String(err).replaceAll(here.topic, '<topic>');

// where($) -> where from and to; or, where there is nowhere to push from or
// to by design, the words for that: 'not in tmux', 'no topic file'. A setup
// that is neither is thrown, in words for the log.
async function where($: EngineInterface): Promise<Here | string> {
  const tmux = await $.env.get('TMUX');
  if (tmux === undefined || tmux === '') return 'not in tmux';

  const home = await $.env.get('HOME');
  if (home === undefined) throw new Error('HOME is not set, so ~/.config/claude-ntfy/topic cannot be found');
  // No file is a choice (a machine that pushes nowhere); a file that is
  // there and cannot be read is a finding, and the read says so.
  const file = `${home}/.config/claude-ntfy/topic`;
  if (!(await $.fs.exists(file))) return 'no topic file';
  const topic = ((await $.fs.read(file)).split('\n')[0] ?? '').trim();
  if (topic === '') return 'no topic in the topic file';

  // tmux sets $TMUX_PANE beside $TMUX in every pane; without it there is no
  // telling whether claude's window is the one in view, and a guess either
  // way pushes wrongly or never.
  const pane = await $.env.get('TMUX_PANE');
  if (pane === undefined || pane === '') {
    throw new Error(
      '$TMUX is set but $TMUX_PANE is not, so the pane claude runs in is unknown; start claude in a tmux pane, or unset TMUX if it is not in one',
    );
  }

  const debounce = seconds('CLAUDE_NTFY_DEBOUNCE_SECONDS', await $.env.get('CLAUDE_NTFY_DEBOUNCE_SECONDS'), 600);
  const url = (await $.env.get('CLAUDE_NTFY_URL')) ?? 'https://ntfy.sh';

  return { pane, topic, debounce, url };
}

// ask($, here, 'pane') -> { is: 'no', said: 'pts/1 not focused, input 41s ago' }
// No socket is passed: the script's tmux reads $TMUX, as any tmux command
// typed in claude's pane does, and $TMUX's layout stays tmux's own.
async function ask($: EngineInterface, here: Here, what: 'pane' | 'session-name'): Promise<Answer> {
  const ran = await $.process.run([script($, 'tmux_watched.sh'), what, here.pane], { timeoutMs: TMUX_MS });
  const is = ANSWERS[ran.exitCode];
  if (is === undefined) throw new Error(`tmux_watched.sh ${what}: exit ${ran.exitCode}: ${ran.stderr.trim()}`);

  return { is, said: ran.stdout.trim() };
}

// The line a wait ends on when tmux has no pane left to judge, or cannot
// say; null for any other answer. A failure is never read as "gone": that
// would drop the push without a word.
const lost = (here: Here, answer: Answer): string | null => {
  if (answer.is === 'gone') return `wait: session or claude's pane ${here.pane} gone, no push`;
  if (answer.is === 'failed') return `wait: FAILED, ${answer.said}; no push`;

  return null;
};

// The window passed unwatched: name the session as claude's own goes by,
// <machine>/<tmux session>, and post. The name is asked only now, from the
// pane: a /rename may have labelled the session since, or the pane moved.
//   "CC: mbp/backend" / "done 600s ago and is still unwatched"
async function push($: EngineInterface, it: Wait, waited: number, evidence: string): Promise<void> {
  const { here } = it;
  const session = await ask($, here, 'session-name');
  const over = lost(here, session);
  if (over !== null) return note($, over);
  const machine = await $.process.run([script($, 'machine_name.sh')]);
  if (machine.exitCode !== 0) return note($, `wait: FAILED, ${machine.stderr.trim()}; no push`);
  const name = `${machine.stdout.trim()}/${session.said}`;

  let failed = '';
  try {
    const sent = await $.http.fetch(`${here.url}/${here.topic}`, {
      method: 'POST',
      headers: { Title: `CC: ${name}`, Tags: 'speech_balloon' },
      body: `${it.how} ${here.debounce}s ago and is still unwatched`,
    });
    if (!sent.ok) failed = `HTTP ${sent.status}`;
  } catch (err) {
    failed = redacted(here, err);
  }

  return failed === ''
    ? note($, `push: sent via ${here.url} as ${name} after ${waited}s unwatched (${evidence})`)
    : note($, `push: FAILED, ${failed} (${here.url}; ${evidence})`);
}

// One tick of a wait. A turn may start while tmux is asked, and a slow tmux
// may outlast the tick, so each await is followed by "is this wait still the
// one". Nothing may escape: the timer's callback has no caller to tell, and
// under a wait there is nobody to show a toast to, so the log is where a
// failure is said.
async function poll($: EngineInterface, it: Wait): Promise<void> {
  if (wait !== it || it.isAsking) return;
  it.isAsking = true;

  try {
    const seen = await ask($, it.here, 'pane');
    if (wait !== it) return;
    const waited = Math.round(((await $.clock.now()) - it.since) / 1000);

    // The wait is over when the turn was seen, when there is no pane left
    // to judge, or when the debounce has passed with nobody there.
    const over = seen.is === 'yes' ? `wait: seen after ${waited}s, no push` : lost(it.here, seen);
    if (over === null && waited < it.here.debounce) return;
    end(it);
    await (over === null ? push($, it, waited, seen.said) : note($, over));
  } catch (err) {
    end(it);
    await note($, `wait: FAILED, ${redacted(it.here, err)}; no push`);
  } finally {
    it.isAsking = false;
  }
}

// The pending push advertises a turn that is no longer the last: one
// started, or another ended. Nothing but a comparison when none is pending,
// which is every prompt but a few.
//   cancelPush($, 'prompt: user replied') -> "prompt: user replied, pending push cancelled"
export async function cancelPush($: EngineInterface, why: string): Promise<void> {
  if (wait === null) return;
  end(wait);
  await note($, `${why}, pending push cancelled`);
}

// The session is waiting for the person: start the wait, unless claude's
// pane is being looked at already. `how` is how it came to wait, the push's
// opening words: "done", "went quiet with background tasks running (shell)".
// What cannot be judged here is said on screen too, for whoever is there.
export async function armPush($: EngineInterface, how: string): Promise<void> {
  if (wait !== null) throw new Error('armPush: a push is pending already; cancelPush comes first');

  let here: Here | string;
  let seen: Answer;
  try {
    here = await where($);
    if (typeof here === 'string') return note($, `push: none, ${here}`);
    seen = await ask($, here, 'pane');
  } catch (err) {
    return fail($, 'push', words(err));
  }
  if (seen.is === 'yes') return note($, 'push: none, watched now');
  if (seen.is === 'gone') return note($, `push: none, session or claude's pane ${here.pane} gone`);
  if (seen.is === 'failed') return fail($, 'push', `${seen.said}, so whether the turn was seen is unknown`);

  const it: Wait = {
    here,
    how,
    since: await $.clock.now(),
    isAsking: false,
    timer: $.clock.every(POLL_MS, () => void poll($, it)),
  };
  wait = it;
  await note($, `push: unwatched, waiter armed (debounce ${here.debounce}s; ${seen.said})`);
}
