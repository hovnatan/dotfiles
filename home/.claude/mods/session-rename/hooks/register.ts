// session-rename -- /rename names a session inside the folder its name is in.
//
// A name reads <machine>/<folders...>/<what>, and a /rename changes the last
// part only (the machine here is "mbp"):
//
//   session is                 typed             runs as
//   mbp/backend/bug-441-fix    /rename           /rename mbp/backend/<made up>
//   mbp/bug-441-fix            /rename           /rename mbp/<made up>
//   (no name, or not mbp/...)  /rename           /rename mbp/<made up>
//   any                        /rename foo       /rename mbp/foo
//   any                        /rename mbp/x/y   as typed
//
// A typed name says where it goes itself, so only the machine is put in
// front of it; a made-up one stays in the folder the session is in, which is
// what carries over a /clear: the name is kept, the work under it is new.
//
//   classic.SessionStart      \
//   classic.UserPromptSubmit --(session_title)--> $.state name
//                                                     |
//   /rename --> command.run: folder of name + made-up name --> core's /rename
//                   |                                 |
//                   |           event_log_note.sh: "<id>: 'old' -> 'new'"
//                   v
//       no name to give: "Not renamed: <why>", and no command runs
//
// Why the mod makes the name up itself: core's /rename makes one up and
// applies it in the same step, and in a terminal says nothing a hook can
// read (its answer is `{ ref }`, no text; Claude Code 2.1.328).
//
// What it is made up from: what was said, as text, first words and latest,
// put to the small model in one request. Not a fork of the conversation,
// which the first version used: a session just resumed has nothing to fork
// until a turn ends, so a /rename typed first thing got no name (2026-11-19),
// and a fork reads the whole conversation at the session's own model.
//
// Why the name is remembered, and from two events: `$` has no read of the
// session's name, and these two inputs are all that carry it. The prompt's
// has it at every prompt; the session start's has it before the first one,
// which is where a /rename typed first thing after `claude --resume` finds
// its folder. A name set from elsewhere since the last of them (Remote
// Control) is not known here until the next.
//
// When there is no name to give (nothing said yet, an API error, a reply
// that is not a name, a machine with no name), nothing is renamed and the
// command's answer says why. Core is never left to make the name up: its
// name has no machine and no folder, the next prompt would remember that
// one, and the folder would be gone for every /rename after it. Right after
// a /clear it even names the session for the /clear it has just read,
// "clear-conversation" (2026-11-19).
//
// Loaded by CLAUDE_CODE_PLUGIN_DIRS in home/.claude/settings.json. The
// machine's name is scripts/machine_name.sh's, and each rename is a line in
// ~/.dotfiles/.logs/<day>_claude_session_rename/events.log.

import type { Register } from 'claude-code';
import { atom, read } from 'claude-code';

// Where the name is kept. Written out as a const of this file because the
// engine takes $.state.set's reference only that way (not as current.ref),
// so that what a module writes can be listed without running it.
const NAME_KEPT = { plugin: 'session-rename', key: 'name' } as const;
const current = atom(NAME_KEPT, null);

const ASK =
  'Name the conversation above for a session list: 2 to 5 lowercase words joined ' +
  'by hyphens (fix-login-redirect), about what it is doing. Answer with the name ' +
  'alone: no punctuation, no explanation.';

// How much of the conversation the model is shown: its opening, where the
// work was set, and its latest, where it now is, each text cut short. About
// 3,000 tokens at the most, whatever the conversation's length.
const OPENING = 4;
const LATEST = 24;
const CUT = 400;

// What the model must answer with: fix-login, not "Fix login." or a sentence.
// One word more than ASK asks for is let through: a sixth word is still a
// name, and refusing it would cost a second /rename.
const NAME = /^[a-z0-9]+(-[a-z0-9]+){1,5}$/;

// The end of every answer that made no name up.
const BY_HAND = '/rename <name> sets one.';

// folderOf("mbp/backend/bug-441", "mbp") -> "mbp/backend/"
// folderOf("mbp/bug-441", "mbp")         -> "mbp/"
// folderOf("bug-441" | null, "mbp")      -> "mbp/"   (not this machine's: start over)
const folderOf = (name: string | null, machine: string): string =>
  name?.startsWith(`${machine}/`) ? name.slice(0, name.lastIndexOf('/') + 1) : `${machine}/`;

// said(messages) -> ["user: fix the login redirect", "assistant: Found it: ..."]
// Text alone: no tool calls or results, and none of what the engine adds in
// tags (<system-reminder>, a slash command's <command-name> rows). A long
// conversation is its first OPENING lines, "[...]", and its last LATEST.
const said = (
  messages: readonly { role: string; content: readonly { type: string; [k: string]: unknown }[] }[],
): string[] => {
  const lines = messages.flatMap((m) =>
    m.content.flatMap((b) => {
      const text = b.type === 'text' && typeof b.text === 'string' ? b.text.trim() : '';

      return text === '' || text.startsWith('<') ? [] : [`${m.role}: ${text.slice(0, CUT)}`];
    }),
  );

  return lines.length <= OPENING + LATEST ? lines : [...lines.slice(0, OPENING), '[...]', ...lines.slice(-LATEST)];
};

export const register: Register = (on) => {
  // The prompt's runs at every prompt of every session, so it is one write
  // to the engine's memory and nothing else: no process, no file.
  // SessionStart's source: startup (claude -n <name>), resume, clear, compact, fork.
  on('classic.SessionStart', async ($, e, next) => {
    await $.state.set(NAME_KEPT, e.session_title ?? null);
    return next(e);
  });

  on('classic.UserPromptSubmit', async ($, e, next) => {
    await $.state.set(NAME_KEPT, e.session_title ?? null);
    return next(e);
  });

  on('command.run', { command: 'rename' }, async ($, e, next) => {
    // The one way out with no name to give: no command runs beneath, and
    // this is the command's answer, for the person alone.
    const kept = (why: string) => ({ text: `Not renamed: ${why}`, isTextDisplayOnly: true as const });

    // The mod is home/.claude/mods/session-rename/ of the repo, wherever the
    // repo is: its scripts are four folders up.
    const scripts = `${$.plugin.root}/../../../../scripts`;
    const asked = await $.process.run([`${scripts}/machine_name.sh`]);
    if (asked.exitCode !== 0) return kept(`no machine name to put in front. ${asked.stderr.trim()}`);
    const machine = asked.stdout.trim();
    const old = await read($, current);

    let name = e.args.trim();
    if (name === '') {
      const lines = said(await $.session.messages({ as: 'api' }));
      if (lines.length === 0) return kept(`nothing said yet to name. ${BY_HAND}`);

      const made = await $.model.complete({
        model: 'haiku',
        prompt: `<conversation>\n${lines.join('\n\n')}\n</conversation>\n\n${ASK}`,
        maxTokens: 40,
      });
      if (!made.isAnswered) return kept(`no name from the model (${made.reason}). ${BY_HAND}`);

      const what = made.text.trim();
      if (!NAME.test(what)) return kept(`the model's answer is not a name ("${what.slice(0, 40)}"). ${BY_HAND}`);

      name = folderOf(old, machine) + what;
    } else if (!name.startsWith(`${machine}/`)) {
      name = `${machine}/${name}`;
    }

    const done = await next({ ...e, args: name });
    await $.state.set(NAME_KEPT, name);

    // The log is the repo's rule for what acts by itself (AGENTS.md); a log
    // that cannot be written is said, and the rename stands.
    const line = `${await $.session.id()}: '${old ?? ''}' -> '${name}'`;
    const logged = await $.process.run([`${scripts}/event_log_note.sh`, 'claude_session_rename', line]);
    if (logged.exitCode !== 0) {
      $.ui.toast(`the rename is not in the log: ${logged.stderr.trim()}`);
    }

    return done;
  });
};
