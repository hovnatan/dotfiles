require("core.utils")
require("modules")
require("core.options")
require("core.keymaps")
require("core.autocmd")

local file = io.open(os.getenv("HOME") .. "/.my_colors", "r")
vim.o.background = file:read("*a")
vim.cmd([[colorscheme gruvbox]])

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
  vim.lsp.diagnostic.on_publish_diagnostics,
  { virtual_text = false }
)
vim.o.clipboard = "unnamed"
