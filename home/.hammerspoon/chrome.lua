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

-- Hand Chrome a command line: start it, or reach the running one.
--   M.open({ profile = "Profile 1" })
--   M.open({ profile = "Profile 1", url = "https://x", raise = true })
--     -> open -nb com.google.Chrome --args --profile-directory=Profile 1 https://x
--
--   profile  profile directory to open in; absent, Chrome picks the one it
--            used last
--   url      page to open, as a tab in the profile's last window; absent,
--            that window comes forward
--   raise    activate Chrome once it has the command line
--
-- `open -n` reaches a running Chrome through a short-lived second instance,
-- which is what makes Chrome's switches work on an already-open browser.
-- macOS then activates that instance rather than Chrome, so `raise`
-- re-activates Chrome once the handoff is done (by then Chrome has already
-- brought the right window to the front of its own window stack).
function M.open(opts)
  local args = { "-nb", M.BUNDLE_ID, "--args" }
  if opts.profile then
    args[#args + 1] = "--profile-directory=" .. opts.profile
  end
  if opts.url then
    args[#args + 1] = opts.url
  end

  local onDone
  if opts.raise then
    onDone = function()
      hs.timer.doAfter(0.2, function()
        local app = M.get()
        if app then
          app:activate()
        end
      end)
    end
  end

  -- An empty environment for open(1), as scripts/macos/open_clean.sh gives
  -- it (history there): `open` hands its own environment to an app it
  -- starts, so a Chrome started here would otherwise carry Hammerspoon's,
  -- which is a shell's whenever Hammerspoon was relaunched from one. With
  -- none passed, launchd fills in what a Dock launch gets. Done in place
  -- rather than through the script, which costs a bash start and a log
  -- directory on every clicked link.
  local task = hs.task.new("/usr/bin/open", onDone, args)
  assert(task:setEnvironment({}), "chrome.open: could not clear open's environment")
  task:start()
end

return M
