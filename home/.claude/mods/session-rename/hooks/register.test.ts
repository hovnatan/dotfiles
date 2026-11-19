// What /rename runs as, for each row of the table at the top of register.ts.
// Nothing sits beneath the mod in a test: engine() stands for the machine
// ("mbp"), the conversation, the model's made-up name, and core's /rename,
// and keeps what the mod asked of each.

import type { TestBody } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';

type Engine = { machineFails?: true; made?: string; modelFails?: true; isCleared?: true };

// What was said, as the engine hands it over: text, a tool call, and the
// rows the engine adds in tags, which are no part of what to name.
const SAID = [
  {
    role: 'user' as const,
    content: [
      { type: 'text', text: '<system-reminder>be brief</system-reminder>' },
      { type: 'text', text: 'add a rate limiter to the upload API' },
    ],
  },
  {
    role: 'assistant' as const,
    content: [
      { type: 'text', text: 'On it.' },
      { type: 'tool_use', id: 't1', name: 'Bash', input: { command: 'ls' } },
    ],
  },
  { role: 'user' as const, content: [{ type: 'tool_result', tool_use_id: 't1', content: 'api.py' }] },
];

// The same, right after a /clear: the command's own rows and nothing said.
const CLEARED = [
  {
    role: 'user' as const,
    content: [
      { type: 'text', text: '<command-name>/clear</command-name>' },
      { type: 'text', text: '<local-command-stdout></local-command-stdout>' },
    ],
  },
];

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
const RAN = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false };

// engine(on, {...}) -> { ran, toasts, logged, asked, clock }: the /rename
// arguments that reached core, the toasts shown, the lines handed to the
// event log, the prompts put to the model, and the clock to move (a /clear's
// rename waits on a timer). Scripts are told apart by their last part: the
// mod finds both from its own folder, which is the test's to place.
const engine = (on: Parameters<TestBody>[1], how: Engine = {}) => {
  const ran: string[] = [];
  const toasts: string[] = [];
  const logged: string[] = [];
  const asked: string[] = [];
  const clock = mock.clock(on, { now: 1_000_000 });

  on('session.id', () => ({ value: 's-1' }));
  on('process.run', (_, e) => {
    const script = e.argv[0] ?? '';
    if (script.endsWith('/../../../../scripts/machine_name.sh')) {
      return how.machineFails
        ? { value: { ...RAN, exitCode: 1, stderr: 'machine_name.sh: hostname prints nothing\n' } }
        : { value: { ...RAN, exitCode: 0, stdout: 'mbp\n' } };
    }
    if (!script.endsWith('/../../../../scripts/event_log_note.sh') || e.argv[1] !== 'claude_session_rename') {
      throw new Error(`a process the mod should not run: ${e.argv.join(' ')}`);
    }
    logged.push(e.argv.slice(2).join(' '));

    return { value: { ...RAN, exitCode: 0 } };
  });
  on('session.messages', () => ({ value: how.isCleared ? CLEARED : SAID }));
  on('model.complete', (_, e) => {
    asked.push(`${e.model}: ${e.prompt}`);

    return how.modelFails
      ? { value: { isAnswered: false, reason: 'empty-reply', usage: USAGE } }
      : { value: { isAnswered: true, text: how.made ?? 'upload-rate-limiter\n', usage: USAGE } };
  });
  on('ui.toast', (_, e) => {
    toasts.push(e.text);

    return { value: undefined };
  });
  on('command.run', (_, e) => {
    // Core's /clear: it says nothing, and the name stays as it was.
    if (e.command === 'clear') return {};
    ran.push(e.args);

    return { text: `Session renamed to: ${e.args}` };
  });
  on('classic.UserPromptSubmit', () => ({}));
  on('classic.SessionStart', () => ({}));

  return { ran, toasts, logged, asked, clock };
};

// named($, "mbp/x"): a prompt in a session of that name, which is where the
// mod learns it.
const named = ($: Parameters<TestBody>[0], title: string) =>
  $.classic.UserPromptSubmit({ prompt: 'hi', session_title: title });

// rename($, "foo"): the person typing `/rename foo` at a terminal's prompt.
const rename = ($: Parameters<TestBody>[0], args: string) =>
  $.command.run({
    command: 'rename',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  });

// clear($, clock): the person typing `/clear` there, and the moment after
// it, when the rename the mod left on a timer runs.
const clear = async ($: Parameters<TestBody>[0], clock: ReturnType<typeof mock.clock>) => {
  await $.command.run({
    command: 'clear',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  });
  await clock.advance(1);
};

test('a made-up name stays in the folder the session is in', async ($, on) => {
  const { ran, toasts, logged, asked } = engine(on);

  await named($, 'mbp/backend/bug-441-fix');
  await rename($, '');

  expect(ran).toEqual(['mbp/backend/upload-rate-limiter']);
  // The model reads what was said and nothing the engine added around it.
  expect(asked.length).toBe(1);
  expect(asked[0]).toContain(
    'sonnet: <conversation>\nuser: add a rate limiter to the upload API\n\nassistant: On it.\n</conversation>',
  );
  expect(toasts).toEqual([]);
  expect(logged).toEqual(["s-1: 'mbp/backend/bug-441-fix' -> 'mbp/backend/upload-rate-limiter'"]);
});

test('a second /rename goes by the name the first one gave, with no prompt between', async ($, on) => {
  const { ran } = engine(on);

  await named($, 'mbp/backend/bug-441-fix');
  await rename($, 'mbp/frontend/x');
  await rename($, '');

  expect(ran).toEqual(['mbp/frontend/x', 'mbp/frontend/upload-rate-limiter']);
});

test('a /rename typed first thing after a resume has the name the session started with', async ($, on) => {
  const { ran } = engine(on);

  await $.classic.SessionStart({ source: 'resume', session_title: 'mbp/backend/bug-441-fix' });
  await rename($, '');

  expect(ran).toEqual(['mbp/backend/upload-rate-limiter']);
});

// `claude -n mbp/backend` is how a session starts (the tmux-session skill):
// "backend" is where it lives, not a name to make up over (2026-11-19, when
// hov-8cpu/sdk became hov-8cpu/release-sdk-pauli-path-limit).
test('the part after the machine is the folder, and a made-up name goes under it', async ($, on) => {
  const { ran, logged } = engine(on);

  await $.classic.SessionStart({ source: 'startup', session_title: 'mbp/backend' });
  await rename($, '');
  await rename($, '');

  // The second one replaces the first's name and goes no deeper.
  expect(ran).toEqual(['mbp/backend/upload-rate-limiter', 'mbp/backend/upload-rate-limiter']);
  expect(logged[0]).toBe("s-1: 'mbp/backend' -> 'mbp/backend/upload-rate-limiter'");
});

test("no name, or one that is not this machine's, starts under the machine", async ($, on) => {
  const { ran } = engine(on);

  await rename($, '');
  await named($, 'vm/backend/bug-441-fix');
  await rename($, '');

  expect(ran).toEqual(['mbp/upload-rate-limiter', 'mbp/upload-rate-limiter']);
});

// The other side of "the part after the machine is the folder": the name
// cannot say that this second part was made up, so it is one too.
test('the name made up for a session that had none is its folder from then on', async ($, on) => {
  const { ran } = engine(on);

  await rename($, '');
  await rename($, '');
  await rename($, '');

  expect(ran).toEqual([
    'mbp/upload-rate-limiter',
    'mbp/upload-rate-limiter/upload-rate-limiter',
    'mbp/upload-rate-limiter/upload-rate-limiter',
  ]);
});

test('a typed name gets the machine in front, and no folder', async ($, on) => {
  const { ran } = engine(on);

  await named($, 'mbp/backend/bug-441-fix');
  await rename($, ' foo ');
  await rename($, 'mbp/x/y');

  expect(ran).toEqual(['mbp/foo', 'mbp/x/y']);
});

// The four ways of having no name to give: nothing is renamed, nothing is
// logged, and the command's answer says why.
test('with no name from the model, nothing is renamed and the answer says why', async ($, on) => {
  const { ran, toasts, logged } = engine(on, { modelFails: true });

  await named($, 'mbp/backend/bug-441-fix');
  const answer = await rename($, '');

  expect(answer.text).toBe('Not renamed: no name from the model (empty-reply). /rename <name> sets one.');
  expect(ran).toEqual([]);
  expect(toasts).toEqual([]);
  expect(logged).toEqual([]);
});

test('with nothing said yet, nothing is renamed and the model is not asked', async ($, on) => {
  const { ran, asked } = engine(on, { isCleared: true });

  await $.classic.SessionStart({ source: 'clear', session_title: 'mbp/backend/bug-441-fix' });
  const answer = await rename($, '');

  expect(answer.text).toBe('Not renamed: nothing said yet to name. /rename <name> sets one.');
  expect(ran).toEqual([]);
  expect(asked).toEqual([]);
});

test('an answer that is not a name is not used', async ($, on) => {
  const { ran } = engine(on, { made: 'Sure! How about "Upload limiter"?' });

  const answer = await rename($, '');

  expect(answer.text).toBe(
    'Not renamed: the model\'s answer is not a name ("Sure! How about "Upload limiter"?"). /rename <name> sets one.',
  );
  expect(ran).toEqual([]);
});

test('with no machine name, not even a typed name is used', async ($, on) => {
  const { ran } = engine(on, { machineFails: true });

  const answer = await rename($, 'foo');

  expect(answer.text).toBe('Not renamed: no machine name to put in front. machine_name.sh: hostname prints nothing');
  expect(ran).toEqual([]);
});

test('a /rename after one that gave no name still knows the folder', async ($, on) => {
  const { ran } = engine(on, { isCleared: true });

  await named($, 'mbp/backend/bug-441-fix');
  await rename($, '');
  await rename($, 'mbp/backend/by-hand');

  expect(ran).toEqual(['mbp/backend/by-hand']);
});

// The second table at the top of register.ts.
test('a /clear leaves the folder of the name, and the next /rename goes under it', async ($, on) => {
  const { ran, logged, clock } = engine(on);

  await named($, 'mbp/backend/bug-441-fix');
  await clear($, clock);
  await rename($, '');

  expect(ran).toEqual(['mbp/backend', 'mbp/backend/upload-rate-limiter']);
  // One line a rename: the /clear's own, which the mod's /rename hook never
  // sees and so does not log a second time, then the made-up one.
  expect(logged).toEqual([
    "s-1: 'mbp/backend/bug-441-fix' -> 'mbp/backend' (/clear)",
    "s-1: 'mbp/backend' -> 'mbp/backend/upload-rate-limiter'",
  ]);
});

test('a /clear cuts one part, the last, however deep the name is', async ($, on) => {
  const { ran, clock } = engine(on);

  await named($, 'mbp/a/b/c');
  await clear($, clock);

  expect(ran).toEqual(['mbp/a/b']);
});

test("a /clear of a name with no part to drop, of no name, or of another machine's renames nothing", async ($, on) => {
  const { ran, logged, toasts, clock } = engine(on);

  await clear($, clock);
  await named($, 'mbp/backend');
  await clear($, clock);
  await named($, 'vm/backend/bug-441-fix');
  await clear($, clock);

  expect(ran).toEqual([]);
  expect(logged).toEqual([]);
  expect(toasts).toEqual([]);
});

test('with no machine name, a /clear keeps the name and a toast says why', async ($, on) => {
  const { ran, toasts, clock } = engine(on, { machineFails: true });

  await named($, 'mbp/backend/bug-441-fix');
  await clear($, clock);

  expect(ran).toEqual([]);
  expect(toasts).toEqual([
    'the session keeps its name, mbp/backend/bug-441-fix: no machine name to read it by. machine_name.sh: hostname prints nothing',
  ]);
});
