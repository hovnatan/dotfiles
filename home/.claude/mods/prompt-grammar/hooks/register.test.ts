// What prompt-grammar does with a prompt, case by case. Nothing sits beneath
// the mod in a test: engine() stands for the model, the event log, the
// terminal's width and the clock the check waits on.

import type { TestBody } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';

type Engine = { answer?: string; modelFails?: true; isNarrow?: true };

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
const RAN = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false };
const TWO_SLIPS = JSON.stringify([
  { wrong: 'would it better', fixed: 'would it be better', why: 'missing "be"' },
  { wrong: 'with fix', fixed: 'with the fix', why: 'missing article' },
]);
const PROMPT = 'would it better to push the branch with fix?';

const PANE = {
  plugin: 'prompt-grammar',
  component: 'Pane',
  requestId: 'grammar',
  surface: 'terminal',
  props: {
    title: 'Grammar',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const;

const engine = (on: Parameters<TestBody>[1], how: Engine = {}) => {
  const asked: { model: string; system: string; prompt: string }[] = [];
  const toasts: string[] = [];
  const logged: string[] = [];
  const opened: string[] = [];
  const clock = mock.clock(on, { now: 1_000_000 });

  on('session.id', () => ({ value: '4f1c9a2e-0000' }));
  on('session.cwd', () => ({ value: '/work/backend' }));
  on('session.start', (_, e) => ({ cwd: e.cwd }));
  on('command.register', () => ({ value: { command: 'grammar' } }));
  on('prompt.submit', (_, e) => ({ text: e.text }));
  on('process.run', (_, e) => {
    const script = e.argv[0] ?? '';
    if (!script.endsWith('/../../../../scripts/event_log_note.sh') || e.argv[1] !== 'claude_prompt_grammar') {
      throw new Error(`a process the mod should not run: ${e.argv.join(' ')}`);
    }
    logged.push(e.argv.slice(2).join(' '));

    return { value: { ...RAN, exitCode: 0 } };
  });
  on('model.complete', (_, e) => {
    asked.push({ model: e.model, system: e.system ?? '', prompt: e.prompt });

    return how.modelFails
      ? { value: { isAnswered: false, reason: 'empty-reply', usage: USAGE } }
      : { value: { isAnswered: true, text: how.answer ?? '[]', usage: USAGE } };
  });
  on('ui.toast', (_, e) => {
    toasts.push(e.text);

    return { value: undefined };
  });
  on('ui.open', (_, e) => {
    opened.push(e.id);

    return {
      value: how.isNarrow ? { isPlaced: false, reason: 'unasked under 144 columns (120 now)' } : { isPlaced: true },
    };
  });

  return { asked, toasts, logged, opened, clock };
};

type Kind = 'composer' | 'bridge' | 'sdk' | 'task-notification';

// typed($, clock, "..."): the prompt entered, then the moment after it, when
// the check the mod left on a timer has run.
const typed = async (
  $: Parameters<TestBody>[0],
  clock: ReturnType<typeof mock.clock>,
  text: string,
  kind: Kind = 'composer',
) => {
  const entered = await $.prompt.submit({ text, wait: false, origin: { kind } });
  await clock.advance(1);

  return entered;
};

// The pane as drawn, a line per Text, top to bottom.
const pane = async ($: Parameters<TestBody>[0]): Promise<string> => {
  const ui = await $.ui.mount(PANE);
  const texts = (await ui.findAll({ type: 'Text' })).map((one) => one.text ?? '');
  await ui.unmount();

  return texts.join('\n');
};

test('slips are listed in the pane, logged, and the pane opens', async ($, on) => {
  const { asked, logged, opened, toasts, clock } = engine(on, { answer: TWO_SLIPS });

  expect(await typed($, clock, PROMPT)).toEqual({ text: PROMPT });

  expect(asked).toHaveLength(1);
  expect(asked[0]?.model).toBe('sonnet');
  expect(asked[0]?.prompt).toBe(`<message>\n${PROMPT}\n</message>`);
  expect(asked[0]?.system).toContain('JSON array');
  expect(opened).toEqual(['grammar']);
  expect(toasts).toEqual([]);
  expect(logged).toEqual([
    'backend 4f1c9a2e 2 slips: "would it better" -> "would it be better" (missing "be"); "with fix" -> "with the fix" (missing article)',
  ]);

  const drawn = await pane($);
  expect(drawn).toContain(PROMPT);
  expect(drawn).toContain('- would it better');
  expect(drawn).toContain('+ would it be better');
  expect(drawn).toContain('(missing article)');
});

test('the prompt enters before its check is asked for', async ($, on) => {
  const { asked, clock } = engine(on, { answer: TWO_SLIPS });

  await $.prompt.submit({ text: PROMPT, wait: false, origin: { kind: 'composer' } });
  expect(asked).toHaveLength(0);
  expect(await pane($)).toContain('checking');

  await clock.advance(1);
  expect(asked).toHaveLength(1);
});

test('a clean prompt says so and opens nothing', async ($, on) => {
  const { logged, opened, clock } = engine(on);

  await typed($, clock, 'can you run the tests again?');

  expect(opened).toEqual([]);
  expect(logged).toEqual(['backend 4f1c9a2e clean']);
  expect(await pane($)).toContain('no slips');
});

test('the newest prompt is drawn first', async ($, on) => {
  const { clock } = engine(on);

  await typed($, clock, 'can you run the tests again?');
  await typed($, clock, 'and what is the status now?');

  const drawn = await pane($);
  expect(drawn.indexOf('and what is the status now?')).toBeLessThan(drawn.indexOf('can you run the tests again?'));
});

test('what I did not type, or is too short to hold grammar, is not checked', async ($, on) => {
  const { asked, clock } = engine(on, { answer: TWO_SLIPS });

  await typed($, clock, PROMPT, 'sdk');
  await typed($, clock, PROMPT, 'task-notification');
  await typed($, clock, 'commit and push');
  await $.prompt.submit({
    text: '/review would it better to merge?',
    wait: false,
    origin: { kind: 'composer' },
    command: { name: 'review', args: 'would it better to merge?' },
  });
  await clock.advance(1);

  expect(asked).toHaveLength(0);
  expect(await pane($)).toBe('No prompt checked yet.');
});

test('a prompt sent over Remote Control is checked', async ($, on) => {
  const { asked, clock } = engine(on);

  await typed($, clock, PROMPT, 'bridge');

  expect(asked).toHaveLength(1);
});

test('no answer from the model is a failed check, said on screen and in the log', async ($, on) => {
  const { logged, opened, toasts, clock } = engine(on, { modelFails: true });

  await typed($, clock, PROMPT);

  expect(opened).toEqual([]);
  expect(logged).toEqual(['backend 4f1c9a2e FAILED, no answer from the model (empty-reply)']);
  expect(toasts).toEqual(['prompt not checked: no answer from the model (empty-reply)']);
  expect(await pane($)).toContain('not checked: no answer from the model (empty-reply)');
});

test('an answer that is not the list asked for fails the check, and is not read as clean', async ($, on) => {
  const { logged, clock } = engine(on, { answer: '{"wrong":"with fix"}' });

  await typed($, clock, PROMPT);

  expect(logged).toEqual(['backend 4f1c9a2e FAILED, the model\'s answer is not a list: {"wrong":"with fix"}']);
});

test('where the pane is not drawn, the first slip is a toast', async ($, on) => {
  const { toasts, clock } = engine(on, { answer: TWO_SLIPS, isNarrow: true });

  await typed($, clock, PROMPT);

  expect(toasts).toEqual([
    '"would it better" -> "would it be better" (missing "be"), and 1 more. /grammar lists them.',
  ]);
});

test('/grammar opens the pane', async ($, on) => {
  const { opened } = engine(on);

  await $.session.start({ cwd: '/work/backend', surface: 'terminal', isInteractive: true });
  const ran = await $.command.run({
    command: 'grammar',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  });

  expect(opened).toEqual(['grammar']);
  expect(ran).toEqual({ text: 'Grammar pane opened.', isTextDisplayOnly: true });
});

test('a long prompt, most of it a paste, is sent as its two ends', async ($, on) => {
  const { asked, clock } = engine(on);
  const long = `why does this fail? ${'x'.repeat(5000)} is it the limit?`;

  await typed($, clock, long);

  const sent = asked[0]?.prompt ?? '';
  expect(sent).toContain('why does this fail?');
  expect(sent).toContain('\n[...]\n');
  expect(sent).toContain('is it the limit?');
  expect(sent.length).toBeLessThan(2100);
});
