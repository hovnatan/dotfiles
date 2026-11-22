// What prompt-grammar does with a prompt, case by case. Nothing sits beneath
// the mod in a test: engine() stands for the model, the event log, the pane
// and the clock the check waits on.

import type { TestBody } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';

type Engine = { answer?: string; outputTokens?: number; modelFails?: true; modelRefused?: true };

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
const RAN = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false };
const TWO_SLIPS = JSON.stringify([
  {
    wrong: 'would it better',
    fixed: 'would it be better',
    why: 'missing "be"',
    explain: 'An adjective such as "better" needs the verb "be" in front of it.',
    examples: ['Would it be faster to rebase?', 'It would be easier to start over.'],
  },
  {
    wrong: 'with fix',
    fixed: 'with the fix',
    why: 'missing article',
    explain: 'A single countable thing that both of us know takes "the".',
    examples: ['Push the branch.', 'Open the file.'],
  },
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
  const closed: string[] = [];
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

    if (how.modelRefused) return { deny: 'the model opus is not allowed here' };
    const usage = { ...USAGE, output_tokens: how.outputTokens ?? 0 };

    return how.modelFails
      ? { value: { isAnswered: false, reason: 'empty-reply', usage } }
      : { value: { isAnswered: true, text: how.answer ?? '[]', usage } };
  });
  on('ui.toast', (_, e) => {
    toasts.push(e.text);

    return { value: undefined };
  });
  on('ui.open', (_, e) => {
    opened.push(e.id);

    return { value: { isPlaced: true } };
  });
  on('ui.panes', () => ({
    value: opened
      .filter((id) => !closed.includes(id))
      .map((id) => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })),
  }));
  on('ui.close', (_, e) => {
    closed.push(e.id);

    return { value: undefined };
  });

  return { asked, toasts, logged, opened, closed, clock };
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

test('slips are a toast, logged, and listed in the pane once it is asked for', async ($, on) => {
  const { asked, logged, opened, toasts, clock } = engine(on, { answer: TWO_SLIPS });

  expect(await typed($, clock, PROMPT)).toEqual({ text: PROMPT });

  expect(asked).toHaveLength(1);
  expect(asked[0]?.model).toBe('opus');
  expect(asked[0]?.prompt).toBe(`<message>\n${PROMPT}\n</message>`);
  expect(asked[0]?.system).toContain('JSON array');
  expect(opened).toEqual([]);
  expect(toasts).toEqual([
    '"would it better" -> "would it be better" (missing "be"); "with fix" -> "with the fix" (missing article)',
  ]);
  expect(logged).toEqual([
    'backend 4f1c9a2e 2 slips: "would it better" -> "would it be better" (missing "be"); "with fix" -> "with the fix" (missing article)',
  ]);

  const drawn = await pane($);
  expect(drawn).toContain(PROMPT);
  expect(drawn).toContain('- would it better');
  expect(drawn).toContain('+ would it be better');
  expect(drawn).toContain('(missing article)');
  expect(drawn).toContain('An adjective such as "better" needs the verb "be" in front of it.');
  expect(drawn).toContain('e.g. Would it be faster to rebase?');
  expect(drawn).toContain('e.g. Open the file.');
});

test('the prompt enters before its check is asked for', async ($, on) => {
  const { asked, clock } = engine(on, { answer: TWO_SLIPS });

  await $.prompt.submit({ text: PROMPT, wait: false, origin: { kind: 'composer' } });
  expect(asked).toHaveLength(0);
  expect(await pane($)).toContain('checking');

  await clock.advance(1);
  expect(asked).toHaveLength(1);
});

test('a clean prompt is logged and left out of the pane', async ($, on) => {
  const { logged, clock } = engine(on);

  await typed($, clock, 'can you run the tests again?');

  expect(logged).toEqual(['backend 4f1c9a2e clean']);
  expect(await pane($)).toBe('No slips yet.');
});

test('the newest prompt is drawn first', async ($, on) => {
  const { clock } = engine(on, { answer: TWO_SLIPS });

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
  expect(await pane($)).toBe('No slips yet.');
});

test('a prompt sent over Remote Control is checked', async ($, on) => {
  const { asked, clock } = engine(on);

  await typed($, clock, PROMPT, 'bridge');

  expect(asked).toHaveLength(1);
});

test('no answer from the model is a failed check, said on screen and in the log', async ($, on) => {
  const { logged, toasts, clock } = engine(on, { modelFails: true });

  await typed($, clock, PROMPT);

  expect(logged).toEqual(['backend 4f1c9a2e FAILED, no answer from the model (empty-reply)']);
  expect(toasts).toEqual(['prompt not checked: no answer from the model (empty-reply)']);
  expect(await pane($)).toContain('not checked: no answer from the model (empty-reply)');
});

test('an answer that is not the list asked for fails the check, and is not read as clean', async ($, on) => {
  const { logged, clock } = engine(on, { answer: '{"wrong":"with fix"}' });

  await typed($, clock, PROMPT);

  expect(logged).toEqual([
    `backend 4f1c9a2e unread answer: ${JSON.stringify('{"wrong":"with fix"}')}`,
    'backend 4f1c9a2e FAILED, the model\'s answer is not a list: {"wrong":"with fix"}',
  ]);
});

test('a call the engine refuses is a failed check, in the pane and the log', async ($, on) => {
  const { logged, toasts, clock } = engine(on, { modelRefused: true });

  await typed($, clock, PROMPT);

  const why = 'prompt-grammar: $.model.complete: the model opus is not allowed here';
  expect(logged).toEqual([`backend 4f1c9a2e FAILED, ${why}`]);
  expect(toasts).toEqual([`prompt not checked: ${why}`]);
  expect(await pane($)).toContain(`not checked: ${why}`);
});

test('an answer cut at the token cap says so', async ($, on) => {
  const { logged, clock } = engine(on, { answer: '[{"wrong":"with fix","fixed":"with the', outputTokens: 4000 });

  await typed($, clock, PROMPT);

  expect(logged.at(-1)).toBe("backend 4f1c9a2e FAILED, the model's answer was cut at 4000 tokens");
});

test('a slip without its explanation fails the check', async ($, on) => {
  const { logged, clock } = engine(on, {
    answer: '[{"wrong":"with fix","fixed":"with the fix","why":"missing article"}]',
  });

  await typed($, clock, PROMPT);

  expect(logged.at(-1)).toContain(
    "FAILED, an entry of the model's answer is not { wrong, fixed, why, explain, examples }",
  );
});

test('a list taken back and written again fails the check, and the log keeps the answer', async ($, on) => {
  const answer = `${TWO_SLIPS}\n\nWait, the second is no slip.\n\n[]`;
  const { logged, toasts, clock } = engine(on, { answer });

  await typed($, clock, PROMPT);

  expect(toasts).toHaveLength(1);
  expect(toasts[0]).toContain("prompt not checked: the model's answer is not JSON (");
  expect(logged).toHaveLength(2);
  expect(logged[0]).toBe(`backend 4f1c9a2e unread answer: ${JSON.stringify(answer)}`);
  expect(logged[1]).toContain("FAILED, the model's answer is not JSON (");
});

test('/grammar opens the pane, and closes it when it is shown', async ($, on) => {
  const { opened, closed } = engine(on);
  const grammar = () =>
    $.command.run({
      command: 'grammar',
      args: '',
      origin: { kind: 'composer' },
      presentation: { isFullscreen: false, columns: 80 },
    });

  await $.session.start({ cwd: '/work/backend', surface: 'terminal', isInteractive: true });

  expect(await grammar()).toEqual({ text: 'Grammar pane opened.', isTextDisplayOnly: true });
  expect(opened).toEqual(['grammar']);
  expect(closed).toEqual([]);

  expect(await grammar()).toEqual({ text: 'Grammar pane closed.', isTextDisplayOnly: true });
  expect(opened).toEqual(['grammar']);
  expect(closed).toEqual(['grammar']);
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
