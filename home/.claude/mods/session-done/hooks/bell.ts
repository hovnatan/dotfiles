// The bell of a session that is waiting for the person (register.ts decides
// when), and the engine's own, which has to be off for this one to be the
// only one.
//
// The bell goes out by $.ui.notify, so through the person's own notification
// channel (`preferredNotifChannel`), as the engine's did; in tmux that is
// the terminal bell, which home/.config/tmux/ takes from there. The engine's
// other notifications (a permission prompt, a question) are not this mod's
// and ring as before.
import type { EngineInterface } from 'claude-code';
import { fail, note, toast } from './log';

// ring($) -> what became of the bell, in the log's words:
//   'rung via terminal_bell' | 'not sent (disabled)' | 'FAILED, <the error>'
// A channel that sends nothing (notifications disabled, a terminal that has
// none) is the person's setup, as it was for the engine's bell. One that
// fails is a toast too, and never an exception: the push is still to decide.
export async function ring($: EngineInterface): Promise<string> {
  try {
    const sent = await $.ui.notify('Claude is waiting for your input', { title: 'Claude Code' });

    return sent.isSent ? `rung via ${sent.channel}` : `not sent (${sent.reason})`;
  } catch (err) {
    toast($, `the bell could not be rung: ${String(err)}`);

    return `FAILED, ${String(err)}`;
  }
}

// engine-bell-off.sh, beside this folder, sees to the engine's bell and says
// what it found (its header has the setting and what turning it off costs).
// A line at every start, also when there was nothing to do: with the
// engine's bell off, a mod that has stopped loading means no bell at all,
// and this line is what loaded-check.sh (a SessionStart hook of
// settings.json, beside this folder) looks for to say so on screen.
export async function engineBellOff($: EngineInterface): Promise<void> {
  const ran = await $.process.run([`${$.plugin.root}/engine-bell-off.sh`]);
  if (ran.exitCode !== 0) {
    return fail(
      $,
      'session',
      `Claude Code's own idle bell could not be turned off, so it rings beside this one: ${ran.stderr.trim()}`,
    );
  }

  const changed = ran.stdout.trim();
  await note(
    $,
    changed === ''
      ? "session: started, Claude Code's own idle bell is off"
      : `session: started, turned Claude Code's own idle bell off (messageIdleNotifThresholdMs ${changed})`,
  );
}
