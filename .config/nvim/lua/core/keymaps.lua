vim.g.mapleader = ","

vim.api.nvim_set_keymap("n", "<F9>", ":silent Dispatch!<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "j", "(v:count == 0 ? 'gj' : 'j')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gj", "j", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "k", "(v:count == 0 ? 'gk' : 'k')", { noremap = true, silent = true, expr = true })
vim.api.nvim_set_keymap("n", "gk", "k", { noremap = true, silent = true })

vim.api.nvim_set_keymap("c", "<C-p>", "<Up>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("c", "<C-n>", "<Down>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })

vim.cmd([[
nmap ,cl :let @+=join([@%,  line(".")], ':')<CR>
nmap ,h /[^\d0-\d127]<CR>
nnoremap <silent> <C-n> :set hlsearch!<CR>

inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u

nnoremap <leader>T <C-w>T<CR>
nnoremap <leader>t :tab split<CR>

nnoremap <S-Tab> :bnext<cr>
nnoremap <space><space> <C-^>

nnoremap <C-j> <C-d>
nnoremap <C-k> <C-u>
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
nnoremap <silent> <C-w>j :wincmd h<CR>
nnoremap <silent> <C-w>k :wincmd l<CR>
nnoremap <silent> <C-w>h :wincmd j<CR>
nnoremap <silent> <C-w>l :wincmd k<CR>
]])
