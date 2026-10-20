-- Loud failures for the Hammerspoon modules: fail() alerts where a thing
-- went wrong and raises; guarded() runs code whose errors would otherwise
-- reach no one (a timer's, a callback's go to the Console only) and alerts
-- one that no fail() has alerted yet. So each error is alerted once:
--
--   local fail, guarded = require("failure").new("picker", log)
--
--   fail("no screen at (700, 500)")
--     -> log "ERROR no screen at (700, 500)", alert "picker: no screen ...",
--        raise "picker: no screen ..." (level 0: no position)
--   guarded(fn, ...)           runs fn(...), returns whether it ran clean
--     fn raised via any module's fail()  -> nothing more (alerted)
--     fn raised anything else            -> alerted as
--                                           "picker: unexpected error: ..."
--
-- One record of the last failure serves every module: an error propagates
-- at once, on Hammerspoon's one thread, so no other fail() can run between
-- one alerting and the guard catching it. Without it, a guard had to ask
-- each module it calls into for that module's last failure.
local M = {}

-- The message the last fail() raised, of whichever module.
M.last = nil

-- Whether `err` (a caught error) was raised by a fail(), and so alerted.
function M.alerted(err)
  return err ~= nil and err == M.last
end

function M.new(name, log)
  local function fail(msg)
    log("ERROR %s", msg)
    local full = name .. ": " .. msg
    M.last = full
    hs.alert.show(full, 4)
    error(full, 0)
  end

  local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not M.alerted(err) then
      pcall(fail, "unexpected error: " .. tostring(err))
    end
    return ok
  end

  return fail, guarded
end

return M
