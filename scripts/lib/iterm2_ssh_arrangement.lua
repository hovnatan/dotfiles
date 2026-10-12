-- The logic behind scripts/iterm2_ssh_arrangement.sh: save the tabs of
-- iTerm2's windows as the commands that bring each back, and restore them
-- into new windows. A tab saved here can be reopened after iTerm2 lost it:
-- a reboot, a Cmd-Q, or an upgrade without session restoration.
--
--   save [<name>]                 every window (<name> defaults to "all")
--   save <name> <title prefix>    the one window whose title starts so
--     iTerm2 (osascript) --> per window: its title template, and one record
--                            per tab: panes, jobName, commandLine, title,
--                            path
--       |
--       v  plan(): what each tab is
--     ssh, title "[<session>]" -> remote tmux; which socket holds <session>
--                                 is asked of the host (one ssh per host)
--                                 -> ssh -t <login> tmux -L claude attach -t =<session>
--     ssh, any other title     -> ssh <login>
--     anything else            -> cd '<path>' (a local tab; its program is
--                                 not rerun)
--       |
--       v
--     ~/.local/state/iterm2_ssh_arrangements/<name>.txt: plain text, to
--     read or edit by hand; a "window: <title template>" line per window,
--     then one command per tab, in tab order (render / parse_file)
--
--   restore [<name>]
--     the file --> a new window per "window:" block, a tab per line, each
--                  line typed into the tab's shell (as Cmd-T does), so
--                  exiting ssh leaves a local shell; then every window's
--                  title template is set (iterm2_set_window_titles.py: only
--                  the Python API can set it)
--
-- <login> is ssh_command.lua's replay of the tab's ssh command line (Cmd-T's
-- parser): the options and destination, never a remote command or forward.
-- The "[<session>]" title is ~/.tmux.conf's set-titles-string for an iTerm2
-- client. A session lives on the default socket or on claude_tmux_run.sh's
-- "claude" one, and the title does not say which, hence the lookup.
--
-- Loaded with no arguments (the test) it returns its functions; run with
-- arguments it is the script. Lines typed into a tab are for fish, the
-- shell of the default profile.
local M = {}

local SOCKETS = { "claude", "default" }

-- A word fish reads back as exactly itself (ssh_command.lua's SAFE).
local PLAIN = "^[%w@%.,_:/=+%-]+$"

-- Fields of a tab record, records, a window's template from its records,
-- and windows, as osascript prints them: control characters no title or
-- command line carries.
local FS, RS, GS, WS = "\31", "\30", "\29", "\28"

-- osascript output -> list of tabs. Every field is required: a missing one
-- means iTerm2 renamed or dropped the variable.
--   "1\31ssh\31ssh vm\31[backend]\31/Users/me\30" ->
--   { { panes = 1, job = "ssh", commandLine = "ssh vm", title = "[backend]", path = "/Users/me" } }
function M.parse_facts(text)
  local tabs = {}
  for record in text:gmatch("([^" .. RS .. "]*)" .. RS) do
    local f = {}
    for field in (record .. FS):gmatch("([^" .. FS .. "]*)" .. FS) do
      f[#f + 1] = field
    end
    if #f ~= 5 then
      error(string.format("tab %d: %d fields from iTerm2, want 5: %q", #tabs + 1, #f, record))
    end
    tabs[#tabs + 1] = { panes = tonumber(f[1]), job = f[2], commandLine = f[3], title = f[4], path = f[5] }
  end
  if #tabs == 0 then
    error("iTerm2 reported no tabs: " .. string.format("%q", text))
  end
  return tabs
end

-- osascript output -> list of windows, each { template =, tabs = }.
--   "<template>\29<tab records>\28<template>\29<tab records>"
function M.parse_windows(text)
  local windows = {}
  for chunk in (text .. WS):gmatch("([^" .. WS .. "]*)" .. WS) do
    local template, facts = chunk:match("^([^" .. GS .. "]*)" .. GS .. "(.*)$")
    if not template then
      error(string.format("window %d from iTerm2 has no title separator: %q", #windows + 1, chunk))
    end
    windows[#windows + 1] = { template = template, tabs = M.parse_facts(facts) }
  end
  return windows
end

-- Saved windows ({ template =, lines = }) -> the file's text.
function M.render(name, savedAt, windows)
  local out = {
    string.format("# iTerm2 ssh arrangement %q, saved %s; restore with:", name, savedAt),
    "#   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh restore " .. name,
    "# Each window: its title template (Window > Edit Window Title takes it",
    "# as is), then one command per tab.",
  }
  for _, w in ipairs(windows) do
    out[#out + 1] = ""
    out[#out + 1] = ("window: " .. w.template):gsub(" $", "")
    for _, line in ipairs(w.lines) do
      out[#out + 1] = line
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- The file's text -> its windows. A command before the first "window:" line
-- or a window with no tabs is an error: a hand edit gone wrong.
--   "window: x\nssh vm\n" -> { { template = "x", lines = { "ssh vm" } } }
function M.parse_file(text)
  local windows = {}
  local n = 0
  for line in text:gmatch("([^\n]*)\n?") do
    n = n + 1
    local template = line:match("^window: ?(.*)$")
    if template then
      windows[#windows + 1] = { template = template, lines = {}, at = n }
    elseif line ~= "" and not line:match("^#") then
      if #windows == 0 then
        error(string.format("line %d is a command before any \"window:\" line: %s", n, line))
      end
      table.insert(windows[#windows].lines, line)
    end
  end
  if #windows == 0 then
    error("no \"window:\" line")
  end
  for i, w in ipairs(windows) do
    if #w.lines == 0 then
      error(string.format("window %d (line %d) has no tabs", i, w.at))
    end
    w.at = nil
  end
  return windows
end

-- A tab title -> the remote tmux session it shows, or nil. retitle.sh may
-- leave a trailing space on it.
--   "[api/docs]" -> "api/docs";  "[ai-agent] " -> "ai-agent";  "fish:~" -> nil
function M.tmux_session(title)
  return title:match("^%[(.+)%] ?$")
end

-- A login with -t (a tty for tmux), unless it already has one.
--   "ssh -p 2222 vm" -> "ssh -t -p 2222 vm"
function M.with_tty(login)
  if (" " .. login .. " "):find(" -t ", 1, true) then
    return login
  end
  local program, rest = login:match("^(%S+) (.+)$")
  return program .. " -t " .. rest
end

-- The line that reattaches <session> on <socket>.
--   ("ssh vm", "claude", "ai-agent") -> "ssh -t vm tmux -L claude attach -t =ai-agent"
--   ("ssh vm", "default", "main")    -> "ssh -t vm tmux attach -t =main"
-- "=" makes the target exact: "bench" must not attach "api/docs".
function M.attach_line(login, socket, session)
  if not session:match(PLAIN) then
    error(string.format("tmux session %q has characters that would need quoting; rename it", session))
  end
  local tmux = socket == "default" and "tmux" or ("tmux -L " .. socket)
  return string.format("%s %s attach -t =%s", M.with_tty(login), tmux, session)
end

-- A path quoted for fish: inside '...' only \ and ' are special.
function M.fish_quote(s)
  return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

-- What a tab is, before any remote lookup.
--   { kind = "tmux", login = "ssh vm", session = "backend" }
--   { kind = "ssh", login = "ssh vm" }
--   { kind = "local", line = "cd '/Users/me'" }
-- A split tab or an ssh line ssh_command.lua will not re-parse is an error:
-- saving it as something else would restore the wrong thing.
function M.plan(tab, index, ssh)
  if tab.panes ~= 1 then
    error(string.format("tab %d has %s panes; only one-pane tabs can be saved", index, tostring(tab.panes)))
  end
  if tab.job ~= "ssh" then
    if tab.path == "" then
      error(string.format("tab %d: iTerm2 reports no directory for it", index))
    end
    return { kind = "local", line = "cd " .. M.fish_quote(tab.path) }
  end
  local login, why = ssh.interactive(tab.commandLine)
  if not login then
    error(string.format("tab %d: ssh command line cannot be replayed: %s", index, why))
  end
  local session = M.tmux_session(tab.title)
  if session then
    return { kind = "tmux", login = login, session = session }
  end
  return { kind = "ssh", login = login }
end

-- `tmux ls` output of every socket on a host -> { [session] = { sockets } }.
--   "claude ai-agent\ndefault main\n" -> { ["ai-agent"] = { "claude" }, main = { "default" } }
-- Lines of any other shape ("no server running on ...") are what a socket
-- with no server prints; they are kept only for the error below.
function M.parse_sessions(text)
  local found = {}
  for line in text:gmatch("[^\n]+") do
    local socket, session = line:match("^(%S+) (.+)$")
    for _, known in ipairs(SOCKETS) do
      if socket == known then
        found[session] = found[session] or {}
        table.insert(found[session], socket)
      end
    end
  end
  return found
end

-- The command that lists every socket's sessions on the host of <login>.
-- Single quotes read the same in a remote sh and a remote fish.
function M.list_sessions_command(login)
  local parts = {}
  for _, socket in ipairs(SOCKETS) do
    local tmux = socket == "default" and "tmux" or ("tmux -L " .. socket)
    parts[#parts + 1] = string.format("%s ls -F '%s #{session_name}'", tmux, socket)
  end
  return login .. " " .. M.sh_quote(table.concat(parts, "; ")) .. " </dev/null 2>&1"
end

-- A word quoted for the local /bin/sh that io.popen runs.
function M.sh_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Plans -> the lines of the saved file. lookup(login) returns that host's
-- parse_sessions table and the raw output (for the error).
function M.lines(plans, lookup)
  local out = {}
  for i, p in ipairs(plans) do
    if p.kind == "local" then
      out[i] = p.line
    elseif p.kind == "ssh" then
      out[i] = p.login
    else
      local found, raw = lookup(p.login)
      local sockets = found[p.session]
      if not sockets then
        error(string.format(
          "tab %d: tmux session %q is on no socket (%s) of `%s`; its tmux ls said:\n%s",
          i, p.session, table.concat(SOCKETS, ", "), p.login, raw))
      end
      if #sockets > 1 then
        error(string.format("tab %d: tmux session %q is on sockets %s of `%s`; rename one",
          i, p.session, table.concat(sockets, " and "), p.login))
      end
      out[i] = M.attach_line(p.login, sockets[1], p.session)
    end
  end
  return out
end

if select("#", ...) == 0 then
  return M
end

-- The script ----------------------------------------------------------------

local repo, logPath, command, name, windowPrefix = ...
local logFile = assert(io.open(logPath, "a"))
logFile:setvbuf("line")
local function log(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. string.format(fmt, ...)
  logFile:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end
local function die(msg)
  log("ERROR: %s", msg)
  os.exit(1)
end

local USAGE = "usage: iterm2_ssh_arrangement.sh save [<name> [<window title prefix>]] | restore [<name>]"
name = name or "all"
if not (command == "save" or command == "restore") or (command == "restore" and windowPrefix) then
  die(USAGE)
end
if not name:match("^[%w._-]+$") then
  die(string.format("name %q: use letters, digits, '.', '_', '-'", name))
end
local dir = os.getenv("HOME") .. "/.local/state/iterm2_ssh_arrangements"
local file = dir .. "/" .. name .. ".txt"

-- Runs a command, returns its output; a non-zero exit is fatal.
local function run(cmd, what)
  local p = assert(io.popen(cmd))
  local out = p:read("a")
  local ok, _, code = p:close()
  if not ok then
    die(string.format("%s exited %s:\n%s", what, tostring(code), out))
  end
  return out
end

-- Every window front to back, or the one whose title starts with argv[0]:
-- per window its title template, \x1d, then its tabs, one record each, in
-- tab order; windows joined by \x1c. jobName and commandLine are the local
-- foreground job, ssh for an ssh tab whatever runs on the far side. The
-- template is the raw titleOverrideFormat
-- ("ai-agent \\(currentTab.currentSession.name)"), not the title it
-- renders; empty when the window has none.
local READ_WINDOWS = [[
function run(argv) {
  const it = Application("iTerm2");
  let windows = it.windows();
  if (argv.length) {
    windows = windows.filter((x) => x.name().startsWith(argv[0]));
    if (windows.length !== 1) {
      throw new Error(windows.length + " windows have a title starting with " + JSON.stringify(argv[0])
        + "; titles: " + JSON.stringify(it.windows().map((x) => x.name())));
    }
  }
  if (!windows.length) throw new Error("iTerm2 has no window");
  return windows.map((w) => {
    const template = w.currentTab().currentSession().variable({ named: "tab.window.titleOverrideFormat" }) || "";
    return template + "\x1d" + w.tabs().map((t) => {
      const s = t.sessions();
      const v = (n) => s[0].variable({ named: n });
      return [s.length, v("jobName"), v("commandLine"), s[0].name(), v("path")].join("\x1f") + "\x1e";
    }).join("");
  }).join("\x1c");
}
]]

-- A new window with a tab per argument, each argument typed into its shell.
-- Prints the id of the first tab's session, which names the window to the
-- Python API.
local OPEN_WINDOW = [[
function run(argv) {
  const it = Application("iTerm2");
  const w = it.createWindowWithDefaultProfile();
  const first = w.currentTab().currentSession();
  argv.forEach((line, i) => {
    const t = i === 0 ? w.currentTab() : w.createTabWithDefaultProfile();
    t.currentSession().write({ text: line });
  });
  return first.id();
}
]]


if command == "save" then
  local ssh = assert(loadfile(repo .. "/home/.hammerspoon/ssh_command.lua"))()
  local which = windowPrefix and string.format("the window titled %q...", windowPrefix) or "every window"
  local out = run("osascript -l JavaScript -e " .. M.sh_quote(READ_WINDOWS)
    .. (windowPrefix and (" " .. M.sh_quote(windowPrefix)) or "") .. " 2>&1", "reading " .. which)
  local ok, windows = pcall(M.parse_windows, (out:gsub("\n$", "")))
  if not ok then
    die(windows)
  end
  log("save %s: %d windows (%s)", name, #windows, which)

  -- One lookup per host, however many tabs of however many windows show a
  -- tmux session on it.
  local cache = {}
  local function lookup(login)
    if not cache[login] then
      log("asking `%s` which tmux sockets hold which sessions", login)
      -- tmux ls exits 1 for a socket with no server; that is an empty
      -- socket, so the exit code is not checked, only the sessions found.
      local p = assert(io.popen(M.list_sessions_command(login)))
      local raw = p:read("a")
      p:close()
      cache[login] = { M.parse_sessions(raw), raw }
    end
    return table.unpack(cache[login])
  end

  -- Any tab that cannot be saved fails the whole save, naming its window:
  -- a file missing a window would restore less than was there, silently.
  local saved = {}
  for wi, w in ipairs(windows) do
    local okw, lines = pcall(function()
      local plans = {}
      for i, tab in ipairs(w.tabs) do
        plans[i] = M.plan(tab, i, ssh)
      end
      return M.lines(plans, lookup)
    end)
    if not okw then
      die(string.format("window %d (title template %q): %s", wi, w.template, lines))
    end
    saved[wi] = { template = w.template, lines = lines }
    log("window %d: %d tabs, title template %q", wi, #lines, w.template)
    for i, line in ipairs(lines) do
      log("  tab %d: %s", i, line)
    end
  end

  -- Written beside its final name and renamed into place, so a failed save
  -- never leaves half a file where a good one was.
  run("mkdir -p " .. M.sh_quote(dir), "making " .. dir)
  local tmp = file .. ".tmp"
  local f = assert(io.open(tmp, "w"))
  f:write(M.render(name, os.date("!%Y-%m-%dT%H:%M:%SZ"), saved))
  assert(f:close())
  assert(os.rename(tmp, file))
  log("saved %s", file)
else
  local f = io.open(file)
  if not f then
    local saved = run("ls " .. M.sh_quote(dir) .. " 2>/dev/null || true", "listing " .. dir):gsub("%.txt\n", " ")
    die(string.format("no arrangement %q: %s does not exist; saved ones: %s", name, file,
      saved == "" and "(none)" or saved))
  end
  local text = f:read("a")
  f:close()
  local ok, windows = pcall(M.parse_file, text)
  if not ok then
    die(file .. ": " .. windows)
  end

  -- Last window first: each new window comes to the front, so the one saved
  -- frontmost ends up frontmost again. Titles wait until every window is
  -- open, so a failure there loses no tab.
  local titles = {}
  for wi = #windows, 1, -1 do
    local w = windows[wi]
    local args = {}
    for i, line in ipairs(w.lines) do
      args[i] = M.sh_quote(line)
      log("window %d tab %d: %s", wi, i, line)
    end
    local session = run("osascript -l JavaScript -e " .. M.sh_quote(OPEN_WINDOW) .. " " .. table.concat(args, " "),
      string.format("opening window %d in iTerm2", wi)):gsub("\n$", "")
    log("window %d restored (session %s)", wi, session)
    if w.template ~= "" then
      titles[#titles + 1] = M.sh_quote(session) .. " " .. M.sh_quote(w.template)
    end
  end
  if #titles > 0 then
    log("setting %d window titles through the Python API (iTerm2 may ask to allow it)", #titles)
    -- uv reads the script's pinned iterm2 from its inline metadata.
    io.stdout:write(run(string.format("uv run --quiet --script %s %s 2>&1",
      M.sh_quote(repo .. "/scripts/lib/iterm2_set_window_titles.py"), table.concat(titles, " ")),
      "setting window titles (Settings > General > Magic > Enable Python API must be on)"))
  end
  log("restored %s: %d windows", name, #windows)
end
