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

vim.cmd([[
let s:savedCpo = &cpo
set cpo&vim

function! s:VStarsearch_searchCWord()
	let wordStr = expand("<cword>")
	if strlen(wordStr) == 0
		echohl ErrorMsg
		echo 'E348: No string under cursor'
		echohl NONE
		return
	endif

	if wordStr[0] =~ '\<'
		let @/ = '\<' . wordStr . '\>'
	else
		let @/ = wordStr
	endif

	let savedUnnamed = @"
	let savedS = @s
	normal! "syiw
	if wordStr != @s
		normal! w
	endif
	let @s = savedS
	let @" = savedUnnamed
endfunction

" https://github.com/bronson/vim-visual-star-search/
function! s:VStarsearch_searchVWord()
	let savedUnnamed = @"
	let savedS = @s
	normal! gv"sy
	let @/ = '\V' . substitute(escape(@s, '\'), '\n', '\\n', 'g')
	let @s = savedS
	let @" = savedUnnamed
endfunction

nnoremap <silent> * :call <SID>VStarsearch_searchCWord()<CR>:set hls<CR>
vnoremap <silent> * :<C-u>call <SID>VStarsearch_searchVWord()<CR>:set hls<CR>
nmap <silent> # *
vmap <silent> # *

noremap <expr> n 'Nn'[v:searchforward]
noremap <expr> N 'nN'[v:searchforward]

let &cpo = s:savedCpo
]])
