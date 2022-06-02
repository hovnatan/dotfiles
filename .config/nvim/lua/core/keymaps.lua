vim.g.mapleader = ","

vim.api.nvim_set_keymap("n", "<F9>", ":silent Dispatch!<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "j", "(v:count == 0 ? 'gj' : 'j')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gj", "j", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "k", "(v:count == 0 ? 'gk' : 'k')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gk", "k", { noremap = true, silent = true })

vim.api.nvim_set_keymap("c", "<C-p>", "<Up>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("c", "<C-n>", "<Down>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })
