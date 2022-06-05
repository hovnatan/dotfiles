require("core.utils")
require("modules")
require("core.options")
require("core.keymaps")
require("core.autocmd")

local file = io.open(os.getenv("HOME") .. "/.my_colors", "r")
vim.o.background = file:read("*a")
vim.cmd("colorscheme gruvbox")

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
  vim.lsp.diagnostic.on_publish_diagnostics,
  { virtual_text = false }
)
vim.o.clipboard = "unnamed"

vim.g.python3_host_prog = "/opt/homebrew/bin/python3"

vim.g.netrw_banner = 0
vim.g.netrw_winsize = 20
vim.g.netrw_altv = 1
vim.g.netrw_cursor = 1
vim.g.netrw_browsex_viewer = "open"
vim.g.netrw_fastbrowse = 0
vim.g.netrw_altfile = 1
vim.g.netrw_liststyle = 1
vim.g.netrw_maxfilenamelen = 50

vim.o.spelllang = en_us
vim.o.spellfile = "~/Dropbox/scripts/nvim/spell/en.utf-8.add"

vim.cmd([==[

" file is large from 10mb
let g:LargeFile = 1024 * 1024 * 100
augroup LargeFile
  au!
  autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > g:LargeFile || f == -2 | call LargeFile() | endif
augroup END

function! LargeFile()
 " save memory when other file is viewed
 setlocal bufhidden=unload
 " is read-only (write with :w new_filename)
 setlocal buftype=nowrite
 " no undo possible
 setlocal undolevels=-1
 " display message
 set noloadplugins

 set lazyredraw
 set noswapfile
 set eventignore=all
 set nohidden
 set syntax=off
 autocmd VimEnter *  echo "The file is larger than " . (g:LargeFile / 1024 / 1024) . " MB, so some options are changed (see .vimrc for details)."
endfunction

]==])
