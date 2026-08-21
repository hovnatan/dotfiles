-- Shared Chrome mechanism. Policy stays with the callers (app_hotkeys raises
-- an existing profile window, url_dispatcher hands a URL to one); this owns
-- the argv contract and the app lookup so a change to either lands in one
-- place.
local M = {}

M.BUNDLE_ID = "com.google.Chrome"

-- Not hs.application.get(): its miss path falls back to scanning every
-- running app's name and then every window's AX title, blocking Hammerspoon
-- precisely when Chrome is closed and the user is waiting for it.
function M.get()
  return hs.application.applicationsForBundleID(M.BUNDLE_ID)[1]
end

-- `open -n` reaches a running Chrome through a short-lived second instance,
-- which is what makes --profile-directory work on an already-open browser.
-- macOS then activates that instance rather than Chrome, so `raise`
-- re-activates Chrome once the handoff is done (by then Chrome has already
-- brought the profile's window to the front of its own window stack).
function M.launchWithProfile(profileDir, url, raise)
  local args = { "-nb", M.BUNDLE_ID, "--args",
    "--profile-directory=" .. (profileDir or "Default") }
  if url then args[#args + 1] = url end
  local onDone
  if raise then
    onDone = function()
      hs.timer.doAfter(0.2, function()
        local app = M.get()
        if app then app:activate() end
      end)
    end
  end
  hs.task.new("/usr/bin/open", onDone, args):start()
end

return M
