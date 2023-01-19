vim.g.mapleader = ","

vim.api.nvim_set_keymap("n", "<F9>", ":silent Dispatch!<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "j", "(v:count == 0 ? 'gj' : 'j')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gj", "j", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "k", "(v:count == 0 ? 'gk' : 'k')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gk", "k", { noremap = true, silent = true })

vim.api.nvim_set_keymap("c", "<C-p>", "<Up>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("c", "<C-n>", "<Down>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-n>", "<cmd> :set hlsearch! <CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", ",cl", "<cmd> :let @+=join([@%,  line('.')], ':')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", ",h", "/[^\\d0-\\d127]<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-l>", "<c-g>u<Esc>[s1z=`]a<c-g>u", { noremap = true, silent = true }) -- correct the spelling
vim.api.nvim_set_keymap("n", "<S-Tab>", ":bnext<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<space><space>", "<C-^>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", "<C-d>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-k>", "<C-u>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-w>j", ":wincmd h<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-w>k", ":wincmd l<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-w>h", ":wincmd j<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-w>l", ":wincmd k<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "*", "", {
  callback = function()
    vim.fn.execute("normal! *N")
    vim.fn.execute("set hlsearch")
  end,
})
vim.api.nvim_set_keymap("n", "#", "", {
  callback = function()
    vim.fn.execute("normal! #N")
    vim.fn.execute("set hlsearch")
  end,
})
vim.cmd([[nnoremap <expr> <space>v '`[' . strpart(getregtype(), 0, 1) . '`]']])
vim.api.nvim_set_keymap(
  "n",
  "<leader>tc",
  ':call system("tmux load-buffer -", @0)<cr>',
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "n",
  "<leader>tp",
  ':let @0 = system("tmux save-buffer -")<cr>"0p<cr>g;',
  { noremap = true, silent = true }
)
