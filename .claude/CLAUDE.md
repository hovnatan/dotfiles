# Python guidelines

When working with Python, invoke the relevant /astral:<skill> for uv, ty, and ruff to ensure best practices are followed.

# Use plain ASCII, avoid ambiguous Unicode characters

Default to plain ASCII everywhere -- code, strings, comments, identifiers, commit messages, and prose/Markdown -- unless a non-ASCII character is genuinely required (e.g. a proper noun, a real math symbol, an existing API). Two reasons:
- In prose, fancy typography (especially the em dash) reads as an LLM tell. Prefer plain `-` / `--`.
- In code, many Unicode characters look like ASCII but are not, and linters (e.g. ruff RUF001/RUF002/RUF003) reject them: "String contains ambiguous `×` (MULTIPLICATION SIGN). Did you mean `x`?".

Common offenders and their ASCII replacements:
- `–` `—` (en/em dash) -> `-` or `--`
- `“` `”` `‘` `’` (smart quotes) -> `"` `'`
- `…` (ellipsis) -> `...`
- `×` (multiplication sign) -> `x` or `*`
- `→` (arrow) -> `->`
- `·` (middle dot) -> `.` or `*`
- non-breaking space (U+00A0) -> regular space

# Andrej Karpathy behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

Prefactoring (Section 1) is the deliberate exception: refactoring purely to make the upcoming change easy is allowed, but keep it a separate, self-contained step (ideally its own commit) - not opportunistic cleanup mixed into the feature change.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
