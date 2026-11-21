// What prompt-grammar keeps for the session: the prompts it checked, oldest
// first, each with what the check came to (none yet while it runs).
export type Slip = { wrong: string; fixed: string; why: string };

export type Outcome = { status: 'clean' } | { status: 'slips'; slips: Slip[] } | { status: 'failed'; why: string };

export type Check = { id: number; prompt: string; outcome?: Outcome };

declare module 'claude-code' {
  interface PluginState {
    'prompt-grammar': { checks: Shaped<Check[]> };
  }
}
