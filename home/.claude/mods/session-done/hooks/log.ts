// The mod's way to the day's event log and to the person's screen, for the
// three files beside it.
//
// In the files register.ts imports, whatever takes `$` is a function
// declaration, never an arrow in a const: the engine follows `$` past an
// import into those alone, and refuses to load the module otherwise.
import type { EngineInterface } from 'claude-code';

// The repo's scripts, from this mod's folder (home/.claude/mods/session-done/):
// four folders up.
export function script($: EngineInterface, name: string): string {
  return `${$.plugin.root}/../../../../scripts/${name}`;
}

// On screen, for long enough to be read, and saying whose words these are.
export function toast($: EngineInterface, text: string): void {
  $.ui.toast(`session-done: ${text}`, { timeoutMs: 15000 });
}

// note($, 'push: none, watched now'): that line in the day's log, led by the
// session's folder and the start of its id:
//   2026-11-20T02:44:51Z bench 4f1c9a2e push: none, watched now
// A log that cannot be written, or kept in bounds, is a toast: the one thing
// left to say it with.
export async function note($: EngineInterface, event: string): Promise<void> {
  const cwd = await $.session.cwd();
  const who = `${cwd.slice(cwd.lastIndexOf('/') + 1)} ${(await $.session.id()).slice(0, 8)}`;
  const logged = await $.process.run([script($, 'event_log_note.sh'), 'claude_session_done', who, event]);
  if (logged.exitCode !== 0) toast($, `${logged.stderr.trim()} (at "${event}")`);
}

// Something the mod cannot do or judge: said in the log and on screen.
//   fail($, 'push', '$TMUX is set but ...') -> "push: FAILED, $TMUX is set but ..."
export async function fail($: EngineInterface, event: string, what: string): Promise<void> {
  await note($, `${event}: FAILED, ${what}`);
  toast($, what);
}
