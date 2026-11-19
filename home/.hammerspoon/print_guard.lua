-- print() that a killed `hs` client cannot break. Loaded once hs.ipc is
-- (init.lua), whose print it wraps:
--
--   print(...) --> guarded --> hs.ipc's print --> the Console
--                    |               '--> each `hs` connected without -q:
--                    |                    remote:sendMessage(the line)
--                    '-- first: unregister the clients whose port is gone
--
-- hs.ipc echoes every Console line to the connected clients. One killed
-- before it said goodbye (kill -9, a timeout, a closed terminal) stays
-- registered until hs.ipc's own sweep, which runs every 60 s. Until then
-- print() raises in whichever module logs next:
--
--   1st print     sendMessage raises "ipc port is no longer valid (early)"
--                 and leaves the client marked as being printed to
--   every later   hs.ipc sees the mark and warns through hs.logger, which
--                 prints, which sees the mark, ...: "stack overflow"
--
-- Seen 2026-11-17 in eye_breaks.lua, whose timer stops on an error, and
-- 2026-11-18 in ghostty_snapshots.lua. Reproduced on Hammerspoon 1.1.1
-- (2026-11-19), where the last line printed "false ... (early)", then
-- "false ... stack overflow", and "true" from the sweep on:
--
--   sleep 300 | hs -n &          a client that stays; then kill -9 the hs
--   hs -q -c 'return pcall(_G.print, "probe")' </dev/null
--
-- The mark is hs.ipc's guard against a print inside a print; nothing clears
-- it when the send raises, and the sweep does not either.
local ipc = require("hs.ipc")
local hooked = print

-- What hs.ipc's sweep does, at every print instead of once a minute, and
-- the mark with it. Clients are registered only while an `hs` runs, so the
-- table walked here is empty nearly always.
local function dropDeadClients()
  for id, client in pairs(ipc.__registeredCLIInstances) do
    local remote = client._cli.remote
    if not remote or not remote:isValid() then
      if remote then
        remote:delete()
      end
      ipc.__registeredCLIInstances[id] = nil
      ipc.insidePrintInstances[id] = nil
    end
  end
end

local function guarded(...)
  dropDeadClients()
  local ok, err = pcall(hooked, ...)
  if ok then
    return
  end

  -- A send that failed all the same: a port gone between the check above
  -- and the send, or a reason not seen yet. The error stands, as itself,
  -- here and at each later print that fails the same way; with the marks
  -- left on, every later print would be a stack overflow instead, even
  -- once the client had gone.
  for id in pairs(ipc.insidePrintInstances) do
    ipc.insidePrintInstances[id] = nil
  end
  error(err, 0)
end

print = guarded -- luacheck: ignore

return { print = guarded }
