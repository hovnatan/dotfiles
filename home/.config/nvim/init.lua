-- Plugin-free on purpose: the lazy.nvim setup (lua/modules/, ~48 plugins)
-- was dropped when this config was restored from git history (3456c4f4^);
-- lines that only existed for a plugin went with it.
require("core.utils")
require("core.options")
require("core.keymaps")
require("core.autocmd")
