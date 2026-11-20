-- Phone notifications through ntfy.sh, for the Hammerspoon modules.
--
--   require("ntfy").push("Eye break over", "The 10m break has ended.", function(sent, detail) ... end)
--     -> POST https://ntfy.sh/<topic>, header Title; then done(true, "sent"),
--        or done(false, <why not>) for the caller to log
--
-- The topic is the one home/.claude/mods/session-done/ pushes to, so one
-- subscription on the phone covers both. It is read from a file that stays
-- outside this repo: a topic name is a capability (who knows it can
-- subscribe), and this repo is public. The file is the private repo's, one
-- per machine (~/.dotfiles-private/machines/<name>/home/.config/claude-ntfy/,
-- linked by the installer). The topic is never passed to `done` either,
-- which callers log.
local M = {}

local TOPIC_FILE = os.getenv("HOME") .. "/.config/claude-ntfy/topic"
local URL = "https://ntfy.sh/"

-- The topic, or nil on a machine with no topic file: the private repo is
-- optional, and so is a topic in it; a machine without is not at fault. A file that is there
-- and empty is.
local function topic()
  local file = io.open(TOPIC_FILE)
  if not file then
    return nil
  end
  local name = file:read("l")
  file:close()
  if not name or name == "" then
    error("ntfy: " .. TOPIC_FILE .. " is empty; put the ntfy.sh topic name in it, or delete it")
  end
  return name
end

-- Send `message` under `title`. Returns at once; done(sent, detail) is
-- called when ntfy.sh has answered, or straight away with no topic.
function M.push(title, message, done)
  local name = topic()
  if not name then
    done(false, "no topic file (" .. TOPIC_FILE .. "): notifications are not set up on this machine")
    return
  end
  hs.http.asyncPost(URL .. name, message, { Title = title }, function(status, body)
    if status == 200 then
      done(true, "sent")
    else
      -- A negative status is no answer at all (offline), and its text may
      -- quote the URL, which ends in the topic.
      local why = tostring(body):gsub(name, "<topic>", 1)
      done(false, string.format("ntfy.sh answered %s: %s", tostring(status), why))
    end
  end)
end

return M
