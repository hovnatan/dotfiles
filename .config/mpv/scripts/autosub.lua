-- default keybinding: b
-- add the following to your input.conf to change the default keybinding:
-- keyname script_binding auto_load_subs
local utils = require 'mp.utils'

function load_sub_fn()
  path = mp.get_property("path")
  t = { args = { "download_subtitles.py", path } }

  mp.osd_message("Searching subtitle")
  res = utils.subprocess(t)
  if res.error == nil then
    mp.osd_message("Subtitle download succeeded")
  else
    mp.osd_message("Subtitle download failed: ")
  end
end

mp.add_key_binding("b", "auto_load_subs", load_sub_fn)
