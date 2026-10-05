-- The interactive-login part of an ssh command line, for iterm2_keys.lua's
-- Cmd-T: a second shell on the machine a tab is ssh'd into, and nothing
-- else the first command did. Pure Lua, no hs.*, so
-- scripts/tests/ssh_command_test.lua runs it in CI.
--
--   iTerm2 commandLine -> words -> options / destination / remote command
--                                    |          |            |
--                                    |          kept         dropped
--                                    kept, minus DROP
--
-- E.g.
--   ssh vm                          -> ssh vm
--   ssh -p 2222 user@vm ./deploy.sh -> ssh -p 2222 user@vm   (not run twice)
--   ssh -N -L 8080:localhost:80 vm  -> ssh vm                (no second tunnel)
--   ssh -t vm tmux attach           -> ssh -t vm             (a plain shell)
--   ssh vm "tmux new -s main"       -> ssh vm                (a quote, but dropped)
--   ssh -o "ProxyCommand x" vm      -> nil: a kept word is quoted, not ours
--                                      to re-parse
local M = {}

-- OpenSSH's options that take an argument (ssh(1), getopt string in ssh.c).
local TAKES_ARG = {}
for c in ("BbcDEeFIiJLlmOoPpQRSWw"):gmatch(".") do
  TAKES_ARG[c] = true
end

-- Options of the first command that the new tab must not repeat: forwards
-- (L R D W: a second bind fails with "Address already in use"), and those
-- that make it no interactive shell (N no command, f background, T no tty,
-- n no stdin, s subsystem, G/V/Q print and exit, O control-master command).
local DROP = {}
for c in ("LRDWNfTnsGVQO"):gmatch(".") do
  DROP[c] = true
end

-- A word that fish reads back as exactly itself: no quotes, spaces, `$`,
-- `;`, globs, `~`, `%`. iTerm2 joins argv with spaces and double-quotes an
-- argument with a space, so a kept word outside this set is one whose real
-- boundaries or meaning the joined string has lost. Words of the remote
-- command are dropped unread, so they may hold anything.
local SAFE = "^[%w@%.,_:/=+%-]+$"

-- commandLine -> the replay command, or nil and why it cannot be one.
function M.interactive(commandLine)
  local words = {}
  for word in commandLine:gmatch("%S+") do
    words[#words + 1] = word
  end
  local function plain(word)
    return word:match(SAFE)
  end
  if not (words[1] and plain(words[1])) then
    return nil, "program " .. string.format("%q", tostring(words[1])) .. " is not plain"
  end

  local out = { words[1] }
  local i = 2
  while i <= #words do
    local word = words[i]
    if word == "--" then
      i = i + 1
      break
    end
    if word:sub(1, 1) ~= "-" or #word == 1 then
      break
    end
    if not plain(word) then
      return nil, "option " .. string.format("%q", word) .. " is not plain"
    end

    -- One word may bundle flags and end in an option with its argument
    -- (getopt): -vp2222, -vp 2222. Each is re-emitted on its own.
    local j = 2
    while j <= #word do
      local c = word:sub(j, j)
      local arg
      if TAKES_ARG[c] then
        arg = word:sub(j + 1)
        if arg == "" then
          i = i + 1
          arg = words[i]
          if not arg then
            return nil, "-" .. c .. " has no argument"
          end
          if not plain(arg) then
            return nil, "-" .. c .. " argument " .. string.format("%q", arg) .. " is not plain"
          end
        end
        j = #word
      end
      if not DROP[c] then
        out[#out + 1] = "-" .. c
        out[#out + 1] = arg
      end
      j = j + 1
    end
    i = i + 1
  end

  local destination = words[i]
  if not destination then
    return nil, "no destination"
  end
  if not plain(destination) then
    return nil, "destination " .. string.format("%q", destination) .. " is not plain"
  end
  out[#out + 1] = destination
  return table.concat(out, " ")
end

return M
