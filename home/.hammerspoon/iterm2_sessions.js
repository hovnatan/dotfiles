// Snapshot of iTerm2's sessions for iterm2_bell_banners.lua, printed as JSON.
// Run in its own osascript process (JavaScript for Automation) so the Apple
// Events, about 35ms per bellCount read, never block Hammerspoon. By hand:
//   osascript -l JavaScript ~/.hammerspoon/iterm2_sessions.js
// ->
//   {"frontmost": true, "current": "<id of the focused session>",
//    "sessions": [{"tabNumber": 1, "sessionId": "...", "sessionName": "fish:~",
//                  "bells": 4, "visible": true}, ...]}
//
// tabNumber is the tab's position in its window, the "#<n>" of a bell
// banner. bells is the session's bellCount (unset until its first bell, so
// 0). visible: the session's tab is the one on screen in the front window.
const iterm = Application("iTerm2");
const windows = iterm.windows();
const front = windows.length ? iterm.currentWindow() : null;
const frontId = front ? front.id() : null;

// Ids and names come back per window as one nested array each ([tab][pane]),
// one Apple Event apiece; bellCount is a command, so it costs one per session.
const sessions = [];
for (const w of windows) {
  const shown = w.id() === frontId ? new Set(w.currentTab().sessions.id()) : new Set();
  const ids = w.tabs.sessions.id();
  const names = w.tabs.sessions.name();
  const tabs = w.tabs();
  ids.forEach((tabIds, i) => {
    tabIds.forEach((id, j) => {
      const bells = tabs[i].sessions[j].variable({ named: "bellCount" });
      sessions.push({
        tabNumber: i + 1,
        sessionId: id,
        sessionName: names[i][j],
        bells: Number(bells || 0),
        visible: shown.has(id),
      });
    });
  });
}

JSON.stringify({
  frontmost: iterm.frontmost(),
  current: front ? front.currentSession().id() : "",
  sessions,
});
