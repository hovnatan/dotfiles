-- ssh_command.interactive: an iTerm2 commandLine in, the command Cmd-T
-- replays in the new tab out (nil plus a reason when it must not guess).
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

-- commandLine -> expected replay; false where the replay must be refused.
local CASES = {
  -- A plain login and its options stay as they are.
  { "ssh vm", "ssh vm" },
  { "ssh -p 2222 user@vm", "ssh -p 2222 user@vm" },
  { "/usr/bin/ssh -A -J jump vm", "/usr/bin/ssh -A -J jump vm" },
  { "ssh ssh://user@vm:2222", "ssh ssh://user@vm:2222" },

  -- A remote command is not run a second time.
  { "ssh -p 2222 user@vm ./deploy.sh", "ssh -p 2222 user@vm" },
  { "ssh vm sudo reboot", "ssh vm" },
  { "ssh -t vm tmux attach", "ssh -t vm" },
  -- rsync's and git's transport ssh: a shell, never their server command.
  { "ssh vm rsync --server -vlogDtpre.iLsfxCIvu . /data", "ssh vm" },

  -- Forwards and no-shell options are dropped.
  { "ssh -N -L 8080:localhost:80 vm", "ssh vm" },
  { "ssh -fNT -R 9000:localhost:9000 vm", "ssh vm" },
  { "ssh -s vm sftp", "ssh vm" },

  -- getopt bundling and an attached argument.
  { "ssh -vp2222 vm", "ssh -v -p 2222 vm" },
  { "ssh -vp 2222 vm", "ssh -v -p 2222 vm" },
  { "ssh -o ServerAliveInterval=30 vm uptime", "ssh -o ServerAliveInterval=30 vm" },
  { "ssh -- vm", "ssh vm" },

  -- A remote command is dropped unread, quotes and all.
  { 'ssh vm "echo $HOME"', "ssh vm" },
  { "ssh vm 'ls'", "ssh vm" },
  { 'ssh -t vm "tmux new -A -s main"', "ssh -t vm" },

  -- A kept word the joined string cannot carry back safely: refused.
  { 'ssh -o "ProxyCommand ssh -W %h:%p jump" vm', false },
  { "ssh -p$((1)) vm", false },
  { "ssh vm;rm", false },
  { '"/opt/my ssh/ssh" vm', false },
  { "ssh -i ~/.ssh/key vm", false },
  { "ssh -o ControlPath=/tmp/ssh-%C vm", false },
  { "ssh", false },
  { "ssh -p", false },
}

local passed, failed = 0, 0
for _, case in ipairs(CASES) do
  local input, want = case[1], case[2]
  local got, why = ssh.interactive(input)
  local ok
  if want then
    ok = got == want
  else
    ok = got == nil and type(why) == "string"
  end
  if ok then
    passed = passed + 1
    log("PASS %-50s -> %s", input, got or ("refused: " .. why))
  else
    failed = failed + 1
    log("FAIL %-50s -> %s (want %s)", input, tostring(got or why), want or "refused")
  end
end

log("%d passed, %d failed", passed, failed)
file:close()
if failed > 0 then
  os.exit(1)
end
