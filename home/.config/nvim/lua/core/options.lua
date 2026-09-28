vim.g.loaded_2html_plugin = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_gzip = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_spellfile_plugin = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_zipPlugin = 1

vim.opt.compatible = false
vim.opt.hidden = true
vim.opt.backspace = "indent,eol,start"
-- vim.opt.t_Co = 256
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.scrolloff = 5
vim.opt.smartindent = true
vim.opt.showmatch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.wildignorecase = true
vim.opt.showbreak = "↪ "
vim.opt.ls = 2
vim.opt.title = true
-- Over ssh the title leads with the machine, as the fish and zsh titles do
-- ("(<host>) vim"): nvim's own title replaced theirs, so a remote nvim tab
-- read like a local one. The rest is nvim's default titlestring:
--   "(hov-8cpu) options.lua (~/.dotfiles/home/.config/nvim/lua/core) - NVIM"
-- Host is the hostname up to its first dot; fish's fish_prompt_host override
-- is a fish-only variable nvim cannot see. Inside tmux this only names the
-- pane, since tmux's set-titles-string (with its own host prefix) wins.
if vim.env.SSH_CONNECTION then
  local host = vim.fn.hostname():gsub("%..*", "")
  vim.opt.titlestring = "(" .. host .. ') %t%( %M%)%( (%{expand("%:~:h")})%)%a - NVIM'
end
vim.opt.ruler = true
vim.opt.number = true
vim.opt.showcmd = true
vim.opt.mouse = ""
vim.opt.ttyfast = true
vim.opt.startofline = false
vim.opt.autoread = true
vim.opt.shortmess = "atIF"
vim.opt.modeline = true
vim.opt.modelines = 3
vim.opt.whichwrap = "b,s,<,>,[,],h,l"
-- Soft wrap on: long lines break at a word boundary (linebreak), not
-- mid-word, and continuation rows keep the line's indent (breakindent).
-- ,uw turns it off for the current window (core/plugins.lua).
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.visualbell = false
vim.opt.iskeyword = "@,48-57,_,192-255"
vim.opt.isfname = vim.opt.isfname - "="
vim.opt.matchpairs = vim.opt.matchpairs + "<:>"
vim.opt.wildmenu = true
vim.opt.lazyredraw = false
vim.opt.diffopt = "vertical,filler,internal,algorithm:histogram,indent-heuristic"
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.foldcolumn = "0"
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
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
vim.opt.colorcolumn = "88"
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.cmdheight = 1
vim.opt.signcolumn = "yes:1"
vim.opt.conceallevel = 0
vim.opt.fixendofline = true
vim.opt.completeopt = "menuone,noselect"
vim.opt.timeoutlen = 1000

-- ~/.my_colors (light|dark) is optional machine state that scripts/cw.sh
-- writes; without it Neovim detects the background from the terminal.
local file = io.open(vim.fn.expand("~/.my_colors"), "r")
if file then
  vim.o.background = vim.trim(file:read("*a"))
  file:close()
end

vim.g.python3_host_prog = "python3"

vim.o.spelllang = "en_us"
-- zg adds to the hunspell personal word list in ~/.dotfiles-private, linked
-- here by scripts/setup_user_symlinks.sh, so nvim and hunspell (Claude Code's
-- spellcheck) share one list. Plain words only: nvim cannot read hunspell's
-- "word/dog" affix hints, and hunspell cannot read zw's "word/!". Without the
-- clone, zg starts a local file here, which the installer flags once the
-- clone arrives.
vim.o.spellfile = vim.fn.stdpath("data") .. "/spell/en.utf-8.add"

-- nvim reads only the compiled .spl and rebuilds it on zg alone, so words
-- arriving any other way (a dotup pull, a hunspell save, a fresh machine)
-- would stay flagged. Rebuild at startup when the list is newer: two stats,
-- and a few ms of mkspell for ~100 words.
local add_stat = vim.uv.fs_stat(vim.o.spellfile)
if add_stat then
  local spl_stat = vim.uv.fs_stat(vim.o.spellfile .. ".spl")
  if not spl_stat or spl_stat.mtime.sec <= add_stat.mtime.sec then
    vim.cmd("silent mkspell! " .. vim.fn.fnameescape(vim.o.spellfile))
  end
end
vim.opt.spelloptions = "camel"

vim.o.clipboard = "unnamedplus"

vim.opt.exrc = true

-- Command-line completion in a popup menu, matched fuzzily. The first <Tab>
-- already inserts the top match (:neo<Tab> -> :Neogit) and further <Tab>s
-- cycle; lastused lists the most recent buffer first for :b. (Moved here
-- from the plugin-free core/picker.lua when snacks' picker took over
-- <space>f / <space>b.)
vim.o.wildmode = "full:lastused"
vim.o.wildoptions = "pum,fuzzy"
