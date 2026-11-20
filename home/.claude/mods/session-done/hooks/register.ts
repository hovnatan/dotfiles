// session-done -- tell the person when a session is waiting for them, and
// only then: its turn ended with no background task running and no wakeup
// scheduled, so nothing but the person will start the next one. Two things
// follow from that one rule, and only from it:
//
//   the bell (bell.ts)   at once, through the person's notification channel
//   the push (push.ts)   to ntfy.sh, if nobody looks at claude's tmux pane
//                        for ten minutes
//
// Why a mod rings the bell. Claude Code's own idle bell (its `idle_prompt`
// notification) rings 60 s after every turn end, and holds back only for
// background agents and workflows. A turn that ended on a Monitor's event,
// or with a shell still running in the background, rang it too: once per
// event, for work that was not done (43 times in a day in one session,
// 2026-11-19). No hook can veto that bell, so it is turned off whole
// (engine-bell-off.sh, at each session's start) and rung from here. Its
// minute is gone with it: the engine waited to see whether the person was
// still there, and a bell for somebody who is there costs less than a
// minute's wait for somebody who is not.
//
//   classic.Stop ----> remember what is left: background tasks, wakeups
//
//   turn.complete (main loop), by its reason:
//     answer ---> anything left? --yes--> working: no bell, no push. The
//                    | no                 task's notification or the wakeup
//     refusal -------+                    starts a turn, and its end decides
//     error ---------+
//     aborted        |    (nothing: whoever pressed Escape is at the keyboard)
//                    v
//          waiting for the person
//             |-- the bell, at once
//             '-- the push's wait (the diagram in push.ts)
//
//   turn.start (main loop) ----> a pending push is cancelled
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
// What "left" cannot tell: a background shell that never exits (a dev
// server) and a cron however far off both count, so a session that keeps
// one neither rings nor pushes.
//
// The rule was the push's alone until 2026-11-20 (the ntfy-stop mod), and
// narrower: it read background tasks off the Stop and nothing else. Hence
// one mod for both, and bell and push with no say in when.
//
// Every decision is a line in the day's log, each led by the session's
// folder and the start of its id, so a bell or a push that did or did not
// arrive can be explained afterwards:
//   tail -f ~/.dotfiles/.logs/*_claude_session_done/events.log
//   2026-11-20T02:31:07Z bench 4f1c9a2e stop: not done, background tasks running (shell, monitor), no bell, no push
//   2026-11-20T02:44:51Z bench 4f1c9a2e stop: done, bell rung via terminal_bell
//   2026-11-20T02:44:51Z bench 4f1c9a2e push: unwatched, waiter armed (debounce 600s; pts/1 not focused, input 41s ago)
//   2026-11-20T02:45:56Z bench 4f1c9a2e wait: seen after 65s, no push
// Events:
//   session  started (engine's own bell off | turned off) | FAILED
//   stop     not done (background tasks running | wakeups scheduled) |
//            done | refused | ended on an API error, each with what became
//            of the bell (rung | not sent | FAILED) |
//            FAILED: no Stop before an answer's end, a Stop without
//            background_tasks or session_crons, a reason not known here
//   push     none (not in tmux | no topic file | watched now | session or
//            pane gone) | unwatched, waiter armed | sent | FAILED (no
//            $TMUX_PANE, tmux failing or hung, a bad debounce, ntfy refusing)
//   wait     seen | session or claude's pane gone | FAILED
//   prompt   user replied, pending push cancelled
//   turn     started with no prompt | another ended, pending push cancelled
// A FAILED is a toast too, but under a wait: nobody is there to read one.
//
// Loaded by CLAUDE_CODE_PLUGIN_DIRS in home/.claude/settings.json.
import type { Register, TurnCompleteReason } from 'claude-code';
import { engineBellOff, ring } from './bell';
import { fail, note } from './log';
import { armPush, cancelPush } from './push';

// What the turn's last Stop said is left to wake the session, each list as
// the Stop gave it: undefined for one it did not send.
type Left = { tasks: readonly { type: string }[] | undefined; wakeups: readonly unknown[] | undefined };

// What the end of a turn of the main loop comes to. null: nothing to decide.
//   waiting   for the person; `how` the turn ended, in the log's and the
//             push's words: "done", "refused", "ended on an API error"
//   working   the session starts its next turn by itself; `on` what
//   unknown   there is no telling which, and `why`
type Verdict = { is: 'waiting'; how: string } | { is: 'working'; on: string } | { is: 'unknown'; why: string } | null;

let left: Left | null = null;

// The rule, and the whole of it: `said` is what the turn's last Stop left.
const verdict = (reason: TurnCompleteReason, said: Left | null): Verdict => {
  switch (reason) {
    case 'aborted':
      return null;
    // Neither comes with anything to wait for: the model would not answer,
    // or the API would not (retries spent, the context limit), and whatever
    // is still running, claude is stuck until the person looks.
    case 'refusal':
      return { is: 'waiting', how: 'refused' };
    case 'error':
      return { is: 'waiting', how: 'ended on an API error' };
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

      // A turn that leaves a Monitor or a background task running ends too
      // ("Monitor re-armed; three samples are left"), and so does one with
      // a /loop's next iteration, a ScheduleWakeup or a cron ahead of it.
      if (tasks.length > 0) {
        return { is: 'working', on: `background tasks running (${tasks.map((t) => t.type).join(', ')})` };
      }
      if (wakeups.length > 0) return { is: 'working', on: `${wakeups.length} wakeup(s) scheduled` };

      return { is: 'waiting', how: 'done' };
    }
    default:
      // A Claude Code newer than this mod knows.
      return { is: 'unknown', why: `the turn ended for a reason this mod does not know ("${reason satisfies never}")` };
  }
};

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    await engineBellOff($);

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

    const is = verdict(e.reason, left);
    left = null;
    if (is === null) return next(e);

    // Each end decides afresh, so a wait still pending from an earlier one
    // goes first (a turn's start has usually cancelled it already).
    await cancelPush($, 'turn: another ended');

    switch (is.is) {
      case 'working':
        await note($, `stop: not done, ${is.on}, no bell, no push`);
        break;
      case 'unknown':
        await fail($, 'stop', `${is.why}, so whether the session is done is unknown: no bell, no push`);
        break;
      // The bell first: it is the one wanted now, and the push's question
      // to tmux can take its time.
      case 'waiting':
        await note($, `stop: ${is.how}, bell ${await ring($)}`);
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
      await cancelPush($, e.text === '' ? 'turn: started with no prompt' : 'prompt: user replied');
    }

    return next(e);
  });
};
