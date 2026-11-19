// ntfy-stop -- push to ntfy.sh when a session is done -- its turn ended with
// no background task left to wake it -- and nobody comes to look within the
// debounce (CLAUDE_NTFY_DEBOUNCE_SECONDS, default 10 minutes).
//
//   classic.Stop --> background tasks running? --yes--> no push
//                       | no
//                       v
//                    watched now? --yes--> no push
//                       | no
//                       v
//                    wait: asks tmux every 5 s
//                       |-- seen, or the pane gone --------> no push
//                       |-- turn.start (a prompt, a task's
//                       |   notification, a cron) ---------> no push; that
//                       |                                    turn's Stop decides
//                       '-- 10 min unwatched --------------> push
//
// Watched means a tmux client shows claude's pane, is focused, and gave
// input lately; tmux-watch.sh beside this folder's hooks/ asks tmux and says
// which (its header has the rule and why focus alone is not believed). This
// channel is a deliberate backup to Claude Code's own mobile push: it goes
// by tmux's client focus, not by claude's idea of presence, and waits out a
// debounce the native push does not have.
//
// One wait at a time, kept in this module's own variables with its timer:
// it lives and dies with the claude process, so quitting claude drops a
// pending push (whoever quit it was there), and so does a crash, which the
// shell hook this replaced outlived (its waiter was a process of its own;
// home/.claude/ntfy-stop.sh until 2026-11-19). What that bought back: no
// process at every prompt to cancel a waiter, no lock directory or pid file,
// and a wait that a new turn ends directly instead of by watching the
// transcript's mtime. Editing this file while a wait is pending drops it
// too: a reload stops the timer.
//
// The topic is the first line of ~/.config/claude-ntfy/topic, which stays
// OUTSIDE this repo on purpose: an ntfy.sh topic is a capability -- anyone
// who knows it can subscribe, and this repo is public. Each machine has its
// own, kept in the private repo (scripts/setup_user_symlinks.sh links it).
// No topic file, or a claude outside tmux: this mod does nothing, by design.
//
// Every decision is a line in the day's log, so a push that did or did not
// arrive can be explained afterwards:
//   tail -f ~/.dotfiles/.logs/*_claude_ntfy/events.log
//   2026-09-23T13:40:02Z backend ($3) stop: unwatched, waiter armed (debounce 600s; pts/1 not focused, input 41s ago)
//   2026-09-23T13:41:10Z backend ($3) wait: seen after 65s, no push
// Events: stop (not done, background tasks running | watched now | session
// or pane gone | waiter armed | FAILED: no $TMUX_PANE, no background_tasks,
// tmux failing), prompt (user replied, pending push cancelled), turn (started
// with no prompt, pending push cancelled), wait (seen | session or claude's
// pane gone | FAILED), push (sent | FAILED). The topic is
// never logged. A FAILED at a Stop is a toast too; under a wait there is
// nobody to show one to, and the log is where it is said.
//
// Loaded by CLAUDE_CODE_PLUGIN_DIRS in home/.claude/settings.json.
import type { EngineInterface, Register } from 'claude-code';

const POLL_MS = 5000;

// Where this claude runs ($TMUX, handed to tmux-watch.sh as it is) and where
// its pushes go, read at each Stop.
type Here = { tmux: string; topic: string; debounce: number; url: string };

// tmux-watch.sh's answer, by its exit status 0 to 3, and what it printed:
//   watched   yes | no (said: the clients it saw) | gone | failed (said: why)
//   session   yes (said: the pane's session)      | gone | failed
//   who       yes (said: "backend ($3)")
const ANSWERS = ['yes', 'no', 'gone', 'failed'] as const;
type Answer = { is: (typeof ANSWERS)[number]; said: string };

// The pending push: who it is for in the log, claude's pane, when the turn
// ended (ms), and whether tmux is being asked now.
type Wait = { who: string; pane: string; since: number; isAsking: boolean; timer: { cancel: () => void } };

let wait: Wait | null = null;

const end = (it: Wait): void => {
  it.timer.cancel();
  if (wait === it) wait = null;
};

// The repo's scripts, from this mod's folder (home/.claude/mods/ntfy-stop/):
// four folders up.
const script = ($: EngineInterface, name: string): string => `${$.plugin.root}/../../../../scripts/${name}`;

// note($, "backend ($3)", "stop: watched now, no push"): that line in the
// day's log. A log that cannot be written, or kept in bounds, is a toast:
// the one thing left to say it with.
const note = async ($: EngineInterface, who: string, event: string): Promise<void> => {
  const logged = await $.process.run([script($, 'event_log_note.sh'), 'claude_ntfy', who, event]);
  if (logged.exitCode !== 0) $.ui.toast(`${logged.stderr.trim()} (at "${event}")`, { timeoutMs: 15000 });
};

// A Stop that cannot be judged: said in the log and on screen, where the
// person who has just finished the turn is.
const fail = async ($: EngineInterface, who: string, what: string, so: string): Promise<void> => {
  await note($, who, `stop: FAILED, ${what}`);
  $.ui.toast(`${what}, ${so}`, { timeoutMs: 15000 });
};

// An error from the fetch quotes its URL, and the URL ends in the topic.
const redacted = (here: Here, err: unknown): string => String(err).replaceAll(here.topic, '<topic>');

// where($) -> null where this mod has nothing to do: a claude outside tmux,
// or a machine with no topic.
const where = async ($: EngineInterface): Promise<Here | null> => {
  const tmux = await $.env.get('TMUX');
  if (tmux === undefined || tmux === '') return null;

  const home = await $.env.get('HOME');
  if (home === undefined) throw new Error('HOME is not set, so ~/.config/claude-ntfy/topic cannot be found');
  // No file is a choice (a machine that pushes nowhere); a file that is
  // there and cannot be read is a finding, and the read says so.
  const file = `${home}/.config/claude-ntfy/topic`;
  if (!(await $.fs.exists(file))) return null;
  const topic = ((await $.fs.read(file)).split('\n')[0] ?? '').trim();
  if (topic === '') return null;

  const debounce = (await $.env.get('CLAUDE_NTFY_DEBOUNCE_SECONDS')) ?? '600';
  if (!/^[1-9][0-9]*$/.test(debounce)) {
    throw new Error(`CLAUDE_NTFY_DEBOUNCE_SECONDS is "${debounce}", not a whole number of seconds above 0`);
  }

  return { tmux, topic, debounce: Number(debounce), url: (await $.env.get('CLAUDE_NTFY_URL')) ?? 'https://ntfy.sh' };
};

// ask($, here, 'watched', '%4') -> { is: 'no', said: 'pts/1 not focused, input 41s ago' }
const ask = async (
  $: EngineInterface,
  here: Here,
  what: 'who' | 'watched' | 'session',
  ...pane: string[]
): Promise<Answer> => {
  const ran = await $.process.run([`${$.plugin.root}/tmux-watch.sh`, what, here.tmux, ...pane]);
  const is = ANSWERS[ran.exitCode];
  if (is === undefined) throw new Error(`tmux-watch.sh ${what}: exit ${ran.exitCode}: ${ran.stderr.trim()}`);

  return { is, said: ran.stdout.trim() };
};

// The line a wait ends on when tmux has no pane left to judge, or cannot
// say; null for any other answer. A failure is never read as "gone": that
// would drop the push without a word.
const lost = (pane: string, answer: Answer): string | null => {
  if (answer.is === 'gone') return `wait: session or claude's pane ${pane} gone, no push`;
  if (answer.is === 'failed') return `wait: FAILED, ${answer.said}; no push`;

  return null;
};

// The window passed unwatched: name the session as claude's own goes by,
// <machine>/<tmux session>, and post. The name is asked only now, from the
// pane: a /rename may have labelled the session since, or the pane moved.
const push = async ($: EngineInterface, here: Here, it: Wait, waited: number, evidence: string): Promise<void> => {
  const session = await ask($, here, 'session', it.pane);
  const over = lost(it.pane, session);
  if (over !== null) return note($, it.who, over);
  const machine = await $.process.run([script($, 'machine_name.sh')]);
  if (machine.exitCode !== 0) return note($, it.who, `wait: FAILED, ${machine.stderr.trim()}; no push`);

  let failed = '';
  try {
    const sent = await $.http.fetch(`${here.url}/${here.topic}`, {
      method: 'POST',
      headers: { Title: `CC: ${machine.stdout.trim()}/${session.said}`, Tags: 'speech_balloon' },
      body: `finished a turn ${here.debounce}s ago and is still unwatched`,
    });
    if (!sent.ok) failed = `HTTP ${sent.status}`;
  } catch (err) {
    failed = redacted(here, err);
  }

  return failed === ''
    ? note($, it.who, `push: sent via ${here.url} after ${waited}s unwatched (${evidence})`)
    : note($, it.who, `push: FAILED, ${failed} (${here.url}; ${evidence})`);
};

// One tick of a wait. A turn may start while tmux is asked, and a slow tmux
// may outlast the tick, so each await is followed by "is this wait still the
// one". Nothing may escape: the timer's callback has no caller to tell.
const poll = async ($: EngineInterface, here: Here, it: Wait): Promise<void> => {
  if (wait !== it || it.isAsking) return;
  it.isAsking = true;

  try {
    const seen = await ask($, here, 'watched', it.pane);
    if (wait !== it) return;
    const waited = Math.round(((await $.clock.now()) - it.since) / 1000);

    // The wait is over when the turn was seen, when there is no pane left
    // to judge, or when the debounce has passed with nobody there.
    const over = seen.is === 'yes' ? `wait: seen after ${waited}s, no push` : lost(it.pane, seen);
    if (over === null && waited < here.debounce) return;
    end(it);
    await (over === null ? push($, here, it, waited, seen.said) : note($, it.who, over));
  } catch (err) {
    end(it);
    await note($, it.who, `wait: FAILED, ${redacted(here, err)}; no push`);
  } finally {
    it.isAsking = false;
  }
};

// A turn ended. Each Stop decides afresh, so a wait still pending from an
// earlier one goes first (a turn's start has usually ended it already).
const stopped = async ($: EngineInterface, tasks: readonly { type: string }[] | undefined): Promise<void> => {
  const here = await where($);
  if (here === null) return;

  const also = wait === null ? '' : '; pending push cancelled';
  if (wait !== null) end(wait);

  const who = (await ask($, here, 'who')).said;

  // tmux sets $TMUX_PANE beside $TMUX in every pane; without it there is no
  // telling whether claude's window is the one in view, and a guess either
  // way pushes wrongly or never.
  const pane = await $.env.get('TMUX_PANE');
  if (pane === undefined || pane === '') {
    return fail(
      $,
      who,
      '$TMUX is set but $TMUX_PANE is not',
      'so the pane claude runs in is unknown; start claude in a tmux pane, or unset TMUX if it is not in one',
    );
  }

  // Push only once the session is done. A turn that leaves a Monitor or a
  // background task running ends in a Stop too ("Monitor re-armed; three
  // samples are left"), and the task's notification will start the next
  // turn; that one's Stop decides.
  if (tasks === undefined) {
    return fail(
      $,
      who,
      'the Stop input has no background_tasks',
      'so whether the session is done is unknown; update Claude Code (2.1.327 sends it)',
    );
  }
  if (tasks.length > 0) {
    const types = tasks.map((t) => t.type).join(', ');

    return note($, who, `stop: not done, background tasks running (${types}), no push${also}`);
  }

  const seen = await ask($, here, 'watched', pane);
  if (seen.is === 'yes') return note($, who, `stop: watched now, no push${also}`);
  if (seen.is === 'gone') return note($, who, `stop: session or claude's pane ${pane} gone, no push${also}`);
  if (seen.is === 'failed') return fail($, who, seen.said, 'so whether the turn was seen is unknown');

  const it: Wait = {
    who,
    pane,
    since: await $.clock.now(),
    isAsking: false,
    timer: $.clock.every(POLL_MS, () => void poll($, here, it)),
  };
  wait = it;
  await note($, who, `stop: unwatched, waiter armed (debounce ${here.debounce}s; ${seen.said})`);
};

export const register: Register = (on) => {
  // Any turn of the main loop: the person answered, from whatever channel,
  // or the session found more work by itself. Either way the pending push
  // advertises a turn that is no longer the last. Nothing but a comparison
  // when no push is pending, which is every prompt but a few.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined && wait !== null) {
      const it = wait;
      end(it);
      const how = e.text === '' ? 'turn: started with no prompt' : 'prompt: user replied';
      await note($, it.who, `${how}, pending push cancelled`);
    }

    return next(e);
  });

  on('classic.Stop', async ($, e, next) => {
    await stopped($, e.background_tasks);

    return next(e);
  });
};
