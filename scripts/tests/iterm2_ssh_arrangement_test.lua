-- iterm2_ssh_arrangement.lua: iTerm2 tab records in, saved lines (or the
-- error that refuses the save) out. The host's tmux ls is faked.
local repo = assert(arg[1], "pass the repo path")
local file = assert(io.open(assert(arg[2], "pass the event log path"), "a"))
file:setvbuf("line")
local function log(fmt, ...)
  local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. string.format(fmt, ...)
  file:write(line, "\n")
  io.stdout:write(line, "\n")
  io.stdout:flush()
end

local ssh = assert(loadfile(repo .. "/home/.hammerspoon/ssh_command.lua"))()
local M = assert(loadfile(repo .. "/scripts/lib/iterm2_ssh_arrangement.lua"))()

local FS, RS = "\31", "\30"
local function record(panes, job, commandLine, title, path)
  return table.concat({ panes, job, commandLine, title, path }, FS) .. RS
end

-- What `tmux ls` on each socket of each host prints.
local HOSTS = {
  ["ssh vm"] = "claude ai-agent\nclaude api/docs\ndefault main\n"
    .. "error connecting to /tmp/tmux-1000/x (No such file or directory)\n",
  ["ssh -p 2222 user@box"] = "no server running on /tmp/tmux-1000/claude\ndefault main\n",
  ["ssh twin"] = "claude dup\ndefault dup\n",
  ["ssh -t vm"] = "default main\n",
}
local function lookup(login)
  local raw = assert(HOSTS[login], "no fake host " .. login)
  return M.parse_sessions(raw), raw
end

local function save(text)
  local plans = {}
  for i, tab in ipairs(M.parse_facts(text)) do
    plans[i] = M.plan(tab, i, ssh)
  end
  return M.lines(plans, lookup)
end

-- facts -> expected lines; a string where the save must fail, naming it.
local CASES = {
  {
    "ssh tabs: tmux on either socket, a plain login, options kept",
    record(1, "ssh", "ssh vm", "[ai-agent]", "/Users/me")
      .. record(1, "ssh", "ssh vm", "fish:~/d/ai-agent", "/Users/me")
      .. record(1, "ssh", "ssh vm", "[api/docs] ", "/Users/me")
      .. record(1, "ssh", "ssh -p 2222 user@box ./deploy.sh", "[main]", "/Users/me"),
    {
      "ssh -t vm tmux -L claude attach -t =ai-agent",
      "ssh vm",
      "ssh -t vm tmux -L claude attach -t =api/docs",
      "ssh -t -p 2222 user@box tmux attach -t =main",
    },
  },
  {
    "a local tab reopens in its directory, quoted for fish",
    record(1, "nvim", "nvim .", "nvim", "/Users/me/it's here"),
    { [[cd '/Users/me/it\'s here']] },
  },
  {
    "-t already given is not doubled",
    record(1, "ssh", "ssh -t vm", "[main]", "/"),
    { "ssh -t vm tmux attach -t =main" },
  },
  { "split tab", record(2, "fish", "fish", "fish", "/"), "2 panes" },
  {
    "session on no socket",
    record(1, "ssh", "ssh vm", "[gone]", "/"),
    "on no socket",
  },
  {
    "session on two sockets",
    record(1, "ssh", "ssh twin", "[dup]", "/"),
    "sockets claude and default",
  },
  {
    "ssh line Cmd-T would refuse",
    record(1, "ssh", 'ssh -o "ProxyCommand x" vm', "fish", "/"),
    "cannot be replayed",
  },
  { "a field missing", "1" .. FS .. "ssh" .. RS, "fields from iTerm2" },
}

local passed, failed = 0, 0
local function check(ok, what, detail)
  if ok then
    passed = passed + 1
    log("PASS %s", what)
  else
    failed = failed + 1
    log("FAIL %s: %s", what, detail)
  end
end

for _, case in ipairs(CASES) do
  local what, facts, want = case[1], case[2], case[3]
  local ok, got = pcall(save, facts)
  if type(want) == "table" then
    local same = ok and #got == #want
    for i = 1, #want do
      same = same and got[i] == want[i]
    end
    check(same, what, ok and table.concat(got, " | ") or tostring(got))
  else
    check(
      not ok and tostring(got):find(want, 1, true) ~= nil,
      what,
      ok and ("saved " .. table.concat(got, " | ")) or tostring(got)
    )
  end
end

-- Windows from osascript: one per \28-separated chunk, template first.
do
  local text = "a \\(x)"
    .. "\29"
    .. record(1, "ssh", "ssh vm", "fish", "/")
    .. "\28"
    .. "\29"
    .. record(1, "fish", "fish", "fish", "/tmp")
    .. record(1, "ssh", "ssh vm", "[main]", "/")
  local ok, w = pcall(M.parse_windows, text)
  check(
    ok and #w == 2 and w[1].template == "a \\(x)" and #w[1].tabs == 1 and w[2].template == "" and #w[2].tabs == 2,
    "two windows split from osascript",
    tostring(w)
  )
  local okBad, err = pcall(M.parse_windows, record(1, "ssh", "ssh vm", "fish", "/"))
  check(not okBad and tostring(err):find("no title separator", 1, true), "a window without its template", tostring(err))
end

-- The file round-trips, comments and blank lines aside.
do
  local windows = {
    { template = "ai-agent \\(currentTab.currentSession.name)", lines = { "ssh -t vm tmux attach -t =x", "ssh vm" } },
    { template = "", lines = { "cd '/tmp'" } },
  }
  local text = M.render("all", "2026-10-12T00:00:00Z", windows)
  local ok, back = pcall(M.parse_file, text)
  local same = ok and #back == 2
  for i = 1, 2 do
    same = same and back[i].template == windows[i].template and #back[i].lines == #windows[i].lines
    for j = 1, #windows[i].lines do
      same = same and back[i].lines[j] == windows[i].lines[j]
    end
  end
  check(same, "file round trip", text)
  check(text:find("\nwindow:\n", 1, true) ~= nil, "an empty template leaves no trailing space", text)
end

-- Hand edits that would restore the wrong thing are refused.
for _, case in ipairs({
  { "a command before any window", "# c\nssh vm\nwindow: x\nssh vm\n", "before any" },
  { "a window with no tabs", "window: x\n\nwindow: y\nssh vm\n", "window 1 (line 1) has no tabs" },
  { "no window at all", "# only comments\n", 'no "window:" line' },
}) do
  local ok, err = pcall(M.parse_file, case[2])
  check(not ok and tostring(err):find(case[3], 1, true), case[1], ok and "accepted" or tostring(err))
end

-- The lookup's remote command reads the same in a remote sh and fish.
check(
  M.list_sessions_command("ssh vm")
    == [[ssh vm 'tmux -L claude ls -F '\''claude #{session_name}'\''; tmux ls -F '\''default #{session_name}'\''' </dev/null 2>&1]],
  "remote tmux ls command",
  M.list_sessions_command("ssh vm")
)

log("%d passed, %d failed", passed, failed)
file:close()
if failed > 0 then
  os.exit(1)
end
