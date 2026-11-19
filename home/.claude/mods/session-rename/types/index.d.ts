// What session-rename keeps for the session: the name the session went by
// when the mod last heard it, or null before it has.
declare module 'claude-code' {
  interface PluginState {
    'session-rename': { name: string | null };
  }
}
