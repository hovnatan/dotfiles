// Snapshot of iTerm2's sessions for iterm2_bell_banners.lua, printed as JSON.
// Run in its own osascript process (JavaScript for Automation) so the Apple
// Events, about 35ms per bellCount read, never block Hammerspoon. By hand:
//   osascript -l JavaScript ~/.hammerspoon/iterm2_sessions.js
// ->
//   {"frontmost": true, "current": "<id of the focused session>",
//    "sessions": [{"tabNumber": 1, "sessionId": "...", "sessionName": "fish:~",
//                  "bells": 4, "visible": true}, ...]}
// or {"gone": true} if iTerm2 quit while it was being taken.
//
// tabNumber is the tab's position in its window, the "#<n>" of a bell
// banner. bells is the session's bellCount (unset until its first bell, so
// 0). visible: the session's tab is the one on screen in the front window.
const iterm = Application("iTerm2");

// Which sessions sit where, per window: its id and its session ids as a
// nested array ([tab][pane], one Apple Event).
function layout() {
  return iterm.windows().map((w) => ({ window: w, id: w.id(), tabs: w.tabs.sessions.id() }));
}

// A layout as a string to compare.
function key(windows) {
  return JSON.stringify(windows.map((w) => [w.id, w.tabs]));
}

function read(windows) {
  const front = windows.length ? iterm.currentWindow() : null;
  const frontId = front ? front.id() : null;

  // Names come back like the ids, one Apple Event per window; bellCount is
  // a command, so it costs one per session.
  const sessions = [];
  for (const { window, id, tabs: ids } of windows) {
    const shown = id === frontId ? new Set(window.currentTab().sessions.id()) : new Set();
    const names = window.tabs.sessions.name();
    const tabs = window.tabs();
    ids.forEach((tabIds, i) => {
      tabIds.forEach((sessionId, j) => {
        const bells = tabs[i].sessions[j].variable({ named: "bellCount" });
        sessions.push({
          tabNumber: i + 1,
          sessionId,
          sessionName: names[i][j],
          bells: Number(bells || 0),
          visible: shown.has(sessionId),
        });
      });
    });
  }

  return {
    frontmost: iterm.frontmost(),
    current: front ? front.currentSession().id() : "",
    sessions,
  };
}

// Whether the layout is still `before`; not if it cannot even be read.
function steady(before) {
  try {
    return before !== undefined && key(layout()) === key(before);
  } catch (e) {
    return false;
  }
}

// The reads above are separate Apple Events joined by position, so a tab
// that opens, closes or moves between two of them either breaks one
// ("Invalid index. (-1719)", "Can't get object. (-1728)"; 5 of 47 snapshots
// while tabs opened and closed) or, worse, hands a session the bell count of
// its neighbour. Neither can have happened if the layout is the same after
// as before, so only such a snapshot is printed; otherwise another is taken
// after PAUSE, up to ATTEMPTS in all: about 5s at the 0.7s an attempt takes
// with 8 sessions in 3 windows, well within the caller's 60s.
//
//   attempt 1: a tab closes mid-read -> "Invalid index"  -> layout changed
//   attempt 2, 0.3s later: layout the same after as before -> printed
//
// An error with the layout unchanged is a real one and is thrown at once.
// One that keeps the layout from being read at all (no Automation
// permission, -1743) cannot be told from a change and is thrown with the
// last attempt.
const ATTEMPTS = 5;
const PAUSE = 0.3; // seconds

function run() {
  let last;
  for (let i = 1; i <= ATTEMPTS; i++) {
    if (i > 1) {
      delay(PAUSE);
    }
    if (!iterm.running()) {
      return JSON.stringify({ gone: true });
    }
    let before;
    try {
      before = layout();
      const result = read(before);
      if (steady(before)) {
        return JSON.stringify(result);
      }
      last = "its tabs changed";
    } catch (e) {
      if (steady(before)) {
        throw e;
      }
      last = `${e.message} (${e.errorNumber})`;
    }
  }
  throw new Error(`no snapshot of iTerm2 in ${ATTEMPTS} attempts, its tabs kept changing; the last one: ${last}`);
}
