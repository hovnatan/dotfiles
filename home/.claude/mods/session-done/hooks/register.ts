// session-done -- push to the person's phone when a session is waiting for
// them and nobody is looking: its turn ended with nothing left that will
// start the next one (the rule is below), and no terminal showed claude's
// tmux pane for ten minutes after (push.ts).
//
// The bell is not this mod's: Claude Code rings its own, a minute after
// every turn end (its `idle_prompt` notification). For a day this mod rang
// in its place, at once and by the rule below (2026-11-19 to 2026-11-20);
// the person went back to the engine's.
//
//   prompt.submit, the person's --> the shells the last turn left are
//                                   servers from here on (see the rule)
//   classic.Stop ----> remember what is left: background tasks, wakeups
//
//   turn.complete (main loop), by its reason:
//     answer ---> anything left   --yes--> working: no push. The task's
//                 that holds?              notification or the wakeup starts
//                    | no                  a turn, and its end decides
//     refusal -------+                       |
//     error ---------+                       | only shells hold, and no turn
//     aborted        |                       | starts for ten minutes
//      (nothing: whoever pressed             v
//       Escape is at the keyboard)         quiet: taken for waiting
//                    v                       |
//          waiting for the person <----------'
//             '-- the push's wait (the diagram in push.ts)
//
//   turn.start (main loop) ----> a pending push and the quiet wait are
//                                cancelled
//
// The rule: what holds the push back at a turn's end.
//   - A monitor, a subagent, a workflow, any task that is not a shell: each
//     is there to wake the session, and its notification starts a turn.
//   - A scheduled wakeup (a /loop's next iteration, a ScheduleWakeup, a
//     cron): it starts a turn at its time.
//   - A background shell started since the person's last prompt: a build
//     the turn is waiting on. Its exit starts a turn.
//   A shell that was running already when the person last prompted does NOT
//   hold: it is taken for a server (a dev server, a log tail), which never
//   exits, and a session that kept one was never pushed at all (2026-11-20).
//
//     "start the dev server and fix the bug"  -> ends with the shell left,
//        new since the prompt: not done. Ten quiet minutes later: waiting.
//     "now commit it"   -> the shell is a server from here on: done
//
//   Only a shell can be a server. A monitor or a wakeup that predates the
//   prompt still holds: taken for furniture, each of its events would start
//   a push's wait for work that is not done. A shell notifies once, at its
//   exit, so nothing is pushed for it twice.
//
//   The person's prompt is one whose origin says so (IS_PERSONS below: typed,
//   Remote Control, a Slack ping), not a task's notification or a wakeup,
//   which are prompts to the engine as well (seen live on 2.1.329).
//
// The quiet wait is for the turn that started the server and then asked
// something: nothing tells a server from a build but time. It runs only
// while shells alone hold. A monitor or a wakeup wakes the session for
// certain, and a push ten minutes into each /loop iteration would be noise.
// Its price: a push's wait may start during a build that runs longer than
// CLAUDE_SESSION_QUIET_SECONDS (default 600) without a word. The shells that
// sat out a quiet wait are servers from then on, as those that sat out a
// prompt are: when one of two exits later, its turn's end is done at once,
// not ten minutes on for the other.
//
// Why two events for one end. Only the Stop says what is left, but a Stop is
// not yet the end: a Stop hook that blocks (a /goal, a plugin's) sends the
// same turn on, with no turn.start, and the Stop fires again when it is
// really over. turn.complete fires once, right after the last Stop (seen
// live on 2.1.329: plain, blocked, bash-mode and subagent turns), so the
// Stop records and turn.complete decides. An interrupted turn raised neither
// there. A turn an API error ended raises turn.complete with no Stop, and
// only then classic.StopFailure, which names the error (seen live with a
// model that does not exist); it has nothing to add to the verdict, so this
// mod does not hook it, and the pane is where the error is read.
//
// What the rule cannot tell: a monitor that never fires again and a cron
// however far off both hold, so a session that keeps one is never pushed. A
// shell started in a turn that was then interrupted is not known to have
// been there at the next prompt (an interrupted turn has no Stop), so it
// holds for one turn more, until the quiet wait or the next prompt. A `!`
// command is no prompt to the engine (its output starts a turn, with no
// prompt.submit before it; seen live on 2.1.329), so it draws no line
// either: a server holds through its turn as well.
//
// Every decision is a line in the day's log, each led by the session's
// folder and the start of its id, so a push that did or did not arrive can
// be explained afterwards:
//   tail -f ~/.dotfiles/.logs/*_claude_session_done/events.log
//   2026-11-20T02:31:07Z bench 4f1c9a2e stop: not done, background tasks running (shell, monitor), no push
//   2026-11-20T02:38:10Z bench 4f1c9a2e stop: not done, background tasks running (shell), no push; waiting if no turn starts in 600s
//   2026-11-20T02:48:10Z bench 4f1c9a2e quiet: no turn for 600s with background tasks running (shell), taken for waiting
//   2026-11-20T02:48:10Z bench 4f1c9a2e push: unwatched, waiter armed (debounce 600s; pts/1 not focused, input 41s ago)
//   2026-11-20T02:49:15Z bench 4f1c9a2e wait: seen after 65s, no push
//   2026-11-20T02:52:40Z bench 4f1c9a2e prompt: user replied, pending push cancelled
//   2026-11-20T02:53:02Z bench 4f1c9a2e stop: done beside 1 shell(s) from before the last prompt
// Events:
//   stop     not done (background tasks running | wakeups scheduled), and
//            the quiet wait if one started |
//            done (beside N shells from before the last prompt) | refused |
//            ended on an API error, each followed by its push line |
//            FAILED: no Stop before an answer's end, a Stop without
//            background_tasks or session_crons, a reason not known here, a
//            bad CLAUDE_SESSION_QUIET_SECONDS
//   quiet    no turn for N s, taken for waiting | FAILED
//   push     none (not in tmux | no topic file | watched now | session or
//            pane gone) | unwatched, waiter armed | sent | FAILED (no
//            $TMUX_PANE, tmux failing or hung, a bad debounce, ntfy refusing)
//   wait     seen | session or claude's pane gone | FAILED
//   prompt   user replied, pending push cancelled
//   turn     started with no prompt | a task-notification started one |
//            another ended, pending push cancelled
//   session  FAILED (the mark below could not be set)
//   check    mod running | FAILED, the mod is not running (loaded-check.sh's
//            lines, beside this folder: see the mark below)
// A FAILED is a toast too, but under a wait: nobody is there to read one.
//
// Loaded by CLAUDE_CODE_PLUGIN_DIRS in home/.claude/settings.json.
import type { EngineInterface, PromptOrigin, Register, TurnCompleteReason } from 'claude-code';
import { fail, note, seconds, words } from './log';
import { armPush, cancelPush } from './push';

// The prompts that are the person's own, by where the engine says each came
// from: typed at the terminal (or a follow-up to a click there), sent over
// Remote Control, the host's in `claude -p`, a ping from Slack. Every other
// origin is the engine's or another agent's: a task's notification, a
// wakeup, a peer session. Every kind is listed, so that one a newer Claude
// Code adds stops the type check until it is put on a side.
const IS_PERSONS: Record<PromptOrigin['kind'], boolean> = {
  composer: true,
  'auto-continuation': true,
  bridge: true,
  sdk: true,
  'slack-ping': true,
  'task-notification': false,
  'scheduled-trigger': false,
  peer: false,
  'peer-send-message': false,
  'projects-relay': false,
  channel: false,
  coordinator: false,
  observer: false,
  'observer-activity': false,
  plugin: false,
  unclassified: false,
};

type Task = { id: string; type: string };

// What the turn's last Stop said is left to wake the session, each list as
// the Stop gave it: undefined for one it did not send.
type Left = { tasks: readonly Task[] | undefined; wakeups: readonly unknown[] | undefined };

// What the end of a turn of the main loop comes to. null: nothing to decide.
//   waiting   for the person; `how` the turn ended, in the log's and the
//             push's words: "done", "refused", "ended on an API error";
//             `beside` the servers left running, for the log: "" for none
//   working   the session starts its next turn by itself; `on` what, and
//             whether that is shells alone, which may never do so
//   unknown   there is no telling which, and `why`
type Verdict =
  | { is: 'waiting'; how: string; beside: string }
  | { is: 'working'; on: string; isShellsAlone: boolean }
  | { is: 'unknown'; why: string }
  | null;

let left: Left | null = null;
// The shells the last ended turn left, by id, and the servers: the shells
// that were there at the person's last prompt, or sat out a quiet wait.
let lastShells: ReadonlySet<string> = new Set();
let servers: ReadonlySet<string> = new Set();
// Where the prompt that starts the next turn came from; null for none seen.
let startedBy: PromptOrigin['kind'] | null = null;
// The quiet wait of a turn that ended with shells alone holding.
let quiet: { cancel: () => void } | null = null;

const isShell = (t: Task): boolean => t.type === 'shell';

const notDone = (on: string): string => `stop: not done, ${on}, no push`;

// A turn of the main loop started or ended: whatever wait an earlier end
// left, the quiet one here or the push's, is over.
//   settle($, 'prompt: user replied') -> "prompt: user replied, pending push
//   cancelled" in the log if a push was pending; a quiet wait ends unsaid
async function settle($: EngineInterface, why: string): Promise<void> {
  quiet?.cancel();
  quiet = null;
  await cancelPush($, why);
}

// The rule, and the whole of it (the header has why): `said` is what the
// turn's last Stop left, `known` the shells taken for servers.
const verdict = (reason: TurnCompleteReason, said: Left | null, known: ReadonlySet<string>): Verdict => {
  switch (reason) {
    case 'aborted':
      return null;
    // Neither comes with anything to wait for: the model would not answer,
    // or the API would not (retries spent, the context limit), and whatever
    // is still running, claude is stuck until the person looks.
    case 'refusal':
      return { is: 'waiting', how: 'refused', beside: '' };
    case 'error':
      return { is: 'waiting', how: 'ended on an API error', beside: '' };
    case 'answer': {
      // Without the lists there is no telling a session that is done from
      // one that is waiting on its own work, and a guess tells wrongly or
      // never.
      if (said === null) return { is: 'unknown', why: 'the turn ended with no Stop before it' };
      const { tasks, wakeups } = said;
      if (tasks === undefined || wakeups === undefined) {
        const missing = tasks === undefined ? 'background_tasks' : 'session_crons';

        return { is: 'unknown', why: `the Stop input has no ${missing} (update Claude Code: 2.1.329 sends it)` };
      }

      // A turn that leaves a Monitor or a build running ends too ("Monitor
      // re-armed; three samples are left"), and so does one with a /loop's
      // next iteration, a ScheduleWakeup or a cron ahead of it.
      const holding = tasks.filter((t) => !(isShell(t) && known.has(t.id)));
      if (holding.length > 0) {
        return {
          is: 'working',
          on: `background tasks running (${holding.map((t) => t.type).join(', ')})`,
          isShellsAlone: wakeups.length === 0 && holding.every(isShell),
        };
      }
      if (wakeups.length > 0)
        return { is: 'working', on: `${wakeups.length} wakeup(s) scheduled`, isShellsAlone: false };

      // Whatever is left now is a server.
      const beside = tasks.length === 0 ? '' : ` beside ${tasks.length} shell(s) from before the last prompt`;

      return { is: 'waiting', how: 'done', beside };
    }
    default:
      // A Claude Code newer than this mod knows.
      return { is: 'unknown', why: `the turn ended for a reason this mod does not know ("${reason satisfies never}")` };
  }
};

// The quiet wait passed: the shells that held are servers after all, and
// the session is taken for waiting. Nothing may escape: a timer's callback
// has no caller to tell, so the log is where a failure is said.
async function wentQuiet($: EngineInterface, on: string, waited: number): Promise<void> {
  servers = lastShells;

  try {
    await note($, `quiet: no turn for ${waited}s with ${on}, taken for waiting`);
    await armPush($, `went quiet with ${on}`);
  } catch (err) {
    await note($, `quiet: FAILED, ${words(err)}`);
  }
}

// Shells alone hold the push back: start the quiet wait and say so.
async function holdQuiet($: EngineInterface, on: string): Promise<void> {
  let wait: number;
  try {
    wait = seconds('CLAUDE_SESSION_QUIET_SECONDS', await $.env.get('CLAUDE_SESSION_QUIET_SECONDS'), 600);
  } catch (err) {
    return fail($, 'stop', `${words(err)}; ${on}: no push`);
  }

  // A timer cancelled as it fires may still call back: only the wait that
  // is still the pending one acts.
  const timer = $.clock.after(wait * 1000, () => {
    if (quiet !== timer) return;
    quiet = null;
    void wentQuiet($, on, wait);
  });
  quiet = timer;
  await note($, `${notDone(on)}; waiting if no turn starts in ${wait}s`);
}

export const register: Register = (on) => {
  // The mark that this mod is running, for loaded-check.sh beside this
  // folder: a SessionStart hook of settings.json, which Claude Code runs
  // beneath this one, inside next(e). It warns the person where the mark is
  // not this session's id: a claude without this mod pushes nothing, and
  // nothing else says so. The mark is in claude's environment only while
  // those hooks run, so no shell claude starts later carries it.
  on('classic.SessionStart', async ($, e, next) => {
    // A write the engine holds (an organization's settings) resolves, with
    // why: the check beneath will then say the mod is not running, wrongly.
    const { deny } = await $.env.set('SESSION_DONE_MOD_SESSION', e.session_id);
    if (deny !== undefined) {
      await fail(
        $,
        'session',
        `the mark loaded-check.sh goes by could not be set (${deny}), so it warns of a mod that is running`,
      );
    }

    try {
      return await next(e);
    } finally {
      await $.env.set('SESSION_DONE_MOD_SESSION', undefined);
    }
  });

  // The person's prompt draws the line between servers and work: the
  // shells the last turn left were there before it. Nothing is run here, a
  // prompt is not held up.
  on('prompt.submit', (_, e, next) => {
    if (IS_PERSONS[e.origin.kind]) servers = lastShells;
    // Submitted while the session was idle, it starts the next turn.
    if (e.turnId === undefined) startedBy = e.origin.kind;

    return next(e);
  });

  // Not the end yet (the header has why): only what is left is kept.
  on('classic.Stop', (_, e, next) => {
    left = { tasks: e.background_tasks, wakeups: e.session_crons };

    return next(e);
  });

  // The end of a turn, and the one place where its verdict is acted on. A
  // subagent's end is its spawner's business, and the main loop works on.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e);

    const is = verdict(e.reason, left, servers);
    if (left?.tasks !== undefined) lastShells = new Set(left.tasks.filter(isShell).map((t) => t.id));
    left = null;
    if (is === null) return next(e);

    // Each end decides afresh, so a wait still pending from an earlier one
    // goes first (a turn's start has usually cancelled it already).
    await settle($, 'turn: another ended');

    switch (is.is) {
      case 'working':
        await (is.isShellsAlone ? holdQuiet($, is.on) : note($, notDone(is.on)));
        break;
      case 'unknown':
        await fail($, 'stop', `${is.why}, so whether the session is done is unknown: no push`);
        break;
      case 'waiting':
        await note($, `stop: ${is.how}${is.beside}`);
        await armPush($, is.how);
        break;
    }

    return next(e);
  });

  // Any turn of the main loop: the person answered, from whatever channel,
  // or a task's notification or a wakeup started one. That turn's end
  // decides, by its own Stop: what an earlier one left (a turn interrupted
  // after a blocked Stop never came to its end) is not this turn's.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      left = null;

      // Who started it, for the log: by the prompt's origin where one was
      // seen, else by whether there is a prompt at all (one typed over the
      // turn before waited its turn, and was submitted then).
      const by = startedBy;
      startedBy = null;
      const engines = by === null ? 'turn: started with no prompt' : `turn: a ${by} started one`;
      const isPersons = by === null ? e.text !== '' : IS_PERSONS[by];
      await settle($, isPersons ? 'prompt: user replied' : engines);
    }

    return next(e);
  });
};
