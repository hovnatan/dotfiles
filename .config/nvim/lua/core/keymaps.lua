vim.g.mapleader = ","

local opts = { noremap = true, silent = true }

vim.keymap.set("n", "<F9>", ":silent Dispatch!<CR>", opts)

vim.keymap.set("n", "j", "(v:count == 0 ? 'gj' : 'j')", { noremap = true, silent = true, expr = true })
vim.keymap.set("n", "gj", "j", opts)
vim.keymap.set("n", "k", "(v:count == 0 ? 'gk' : 'k')", { noremap = true, silent = true, expr = true })
vim.keymap.set("n", "gk", "k", opts)

vim.keymap.set("c", "<C-p>", "<Up>", opts)
vim.keymap.set("c", "<C-n>", "<Down>", opts)

vim.keymap.set("i", "jk", "<Esc>", opts)
vim.keymap.set("n", "<C-n>", "<cmd> :set hlsearch! <CR>", opts)
vim.keymap.set("n", ",cl", "<cmd> :let @+=join([@%,  line('.')], ':')<CR>", opts)
vim.keymap.set("n", ",h", "/[^\\d0-\\d127]<CR>", opts)
vim.keymap.set("n", "<C-l>", "<c-g>u<Esc>[s1z=`]a<c-g>u", opts) -- correct the spelling
vim.keymap.set("n", "<S-Tab>", ":bnext<CR>", opts)
vim.keymap.set("n", "<space><space>", "<C-^>", opts)
vim.keymap.set("n", "<C-j>", "<C-d>", opts)
vim.keymap.set("n", "<C-k>", "<C-u>", opts)
vim.keymap.set("n", "<C-h>", "<C-w>h", opts)
vim.keymap.set("n", "<C-l>", "<C-w>l", opts)
vim.keymap.set("n", "<C-w>j", ":wincmd h<CR>", opts)
vim.keymap.set("n", "<C-w>k", ":wincmd l<CR>", opts)
vim.keymap.set("n", "<C-w>h", ":wincmd j<CR>", opts)
vim.keymap.set("n", "<C-w>l", ":wincmd k<CR>", opts)

vim.keymap.set("n", "*", function()
  vim.fn.execute("normal! *N")
  vim.fn.execute("set hlsearch")
end, {})
vim.keymap.set("n", "#", function()
  vim.fn.execute("normal! #N")
  vim.fn.execute("set hlsearch")
end, {})

vim.cmd([[nnoremap <expr> <space>v '`[' . strpart(getregtype(), 0, 1) . '`]']])

vim.keymap.set({ "n", "v", "o" }, "H", "^")
vim.keymap.set({ "n", "v", "o" }, "L", "g_")
vim.keymap.set({ "n", "v", "o" }, "M", "%", { remap = true })
vim.keymap.set({ "n", "v", "o" }, "]w", "g*")
vim.keymap.set({ "n", "v", "o" }, "[w", "g#")

vim.keymap.set("n", "q", "<Nop>")
vim.keymap.set("n", "gq", "q")

vim.keymap.set("i", "<C-a>", "<C-o>^")
vim.keymap.set("c", "<C-a>", "<HOME>")
vim.keymap.set("!", "<C-b>", "<Left>")
vim.keymap.set("!", "<C-e>", "<END>")
vim.keymap.set("!", "<C-f>", "<Right>")
vim.keymap.set("!", "<C-v>", "<C-r>*")
vim.keymap.set("!", "<C-k>", '<C-o>"_d$')
vim.keymap.set("!", "<M-f>", "<S-Right>")
vim.keymap.set("!", "<M-b>", "<S-Left>")
vim.keymap.set("i", "<S-Tab>", "<BS>")
vim.keymap.set("n", "<space>j", ":bp<cr>")
vim.keymap.set("n", "<space>k", ":bn<cr>")
vim.keymap.set("n", "<space>J", ":tabp<cr>")
vim.keymap.set("n", "<space>K", ":tabn<cr>")
vim.keymap.set("n", "<space>q", ":tabc<cr>")
