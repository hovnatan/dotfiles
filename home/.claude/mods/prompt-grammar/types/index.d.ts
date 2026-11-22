// What prompt-grammar keeps for the session: the prompts whose check found
// slips or failed, oldest first, and the ones still being checked (no outcome
// yet). A prompt checked clean is dropped.
// why: the rule's name, for the toast and the log; explain and examples: the
// rule spelled out, for the pane.
export type Slip = { wrong: string; fixed: string; why: string; explain: string; examples: string[] };

export type Outcome = { status: 'clean' } | { status: 'slips'; slips: Slip[] } | { status: 'failed'; why: string };

export type Check = { id: number; prompt: string; outcome?: Exclude<Outcome, { status: 'clean' }> };

declare module 'claude-code' {
  interface PluginState {
    'prompt-grammar': { checks: Shaped<Check[]> };
  }
}
