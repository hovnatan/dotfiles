vim.g.do_filetype_lua = 1
vim.g.did_load_filetypes = 0

vim.opt.compatible = false
vim.opt.hidden = true
vim.opt.backspace = "indent,eol,start"
-- vim.opt.t_Co = 256
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.scrolloff = 500
vim.opt.termguicolors = true
vim.opt.smartindent = true
vim.opt.showmatch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.wildignorecase = true
vim.opt.ls = 2
vim.opt.title = true
vim.opt.ruler = true
vim.opt.number = true
vim.opt.showcmd = true
vim.opt.mouse = "a"
vim.opt.ttyfast = true
vim.opt.startofline = false
vim.opt.autoread = true
vim.opt.shortmess = "atIc"
vim.opt.modeline = true
vim.opt.modelines = 3
vim.opt.whichwrap = "b,s,<,>,[,],h,l"
vim.opt.wrap = false
vim.opt.visualbell = false
vim.opt.iskeyword = "@,48-57,_,192-255"
vim.opt.isfname = vim.opt.isfname - "="
vim.opt.matchpairs = vim.opt.matchpairs + "<:>"
vim.opt.wildmenu = true
vim.opt.lazyredraw = true
vim.opt.diffopt = "vertical,filler,internal,algorithm:histogram,indent-heuristic"
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.viewoptions = vim.opt.viewoptions - "options"
vim.opt.inccommand = "nosplit"
vim.opt.cursorline = true
vim.opt.wrapscan = true
vim.opt.switchbuf = "usetab"
vim.opt.listchars = "tab:▸\\ ,eol:¬"
vim.opt.history = 200
vim.opt.undofile = true
vim.opt.undodir = vim.fn.expand("~/.vimundo")
vim.opt.undolevels = 1000
vim.opt.undoreload = 10000
vim.opt.colorcolumn = "80"
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.cmdheight = 1
vim.opt.signcolumn = "yes:1"
vim.opt.conceallevel = 0
vim.opt.fixendofline = false
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = [[nvim_treesitter#foldexpr()]]
vim.opt.completeopt = "menuone,noselect"

local file = io.open(os.getenv("HOME") .. "/.my_colors", "r")
vim.o.background = file:read("*a")
file:close()
vim.cmd("colorscheme gruvbox")

vim.g.python3_host_prog = "python3"

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
