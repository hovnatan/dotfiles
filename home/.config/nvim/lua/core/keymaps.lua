vim.g.mapleader = ","

local opts = { noremap = true, silent = true }

vim.keymap.set("n", "j", "(v:count == 0 ? 'gj' : 'j')", { noremap = true, silent = true, expr = true })
vim.keymap.set("n", "gj", "j", opts)
vim.keymap.set("n", "k", "(v:count == 0 ? 'gk' : 'k')", { noremap = true, silent = true, expr = true })
vim.keymap.set("n", "gk", "k", opts)

-- Command line: <C-p>/<C-n> and <Up>/<Down> walk the completion popup while it
-- is open (the <space>f / <space>b pickers in core/picker.lua), and otherwise
-- recall history filtered by what is already typed. Built-in <C-n>/<C-p> would
-- skip that filter, and built-in <Up>/<Down> in the popup climb directories.
for _, k in ipairs({ { "<C-p>", "<Up>" }, { "<C-n>", "<Down>" } }) do
  local key, arrow = k[1], k[2]
  local rhs = function()
    return vim.fn.wildmenumode() == 1 and vim.keycode(key) or vim.keycode(arrow)
  end
  vim.keymap.set("c", key, rhs, { expr = true, replace_keycodes = false })
  vim.keymap.set("c", arrow, rhs, { expr = true, replace_keycodes = false })
end

vim.keymap.set("i", "jk", "<Esc>", opts)
vim.keymap.set("n", ",cl", "<cmd> :let @+=join([@%,  line('.')], ':')<CR>", opts)
vim.keymap.set("n", ",h", "/[^\\d0-\\d127]<CR>", opts)
vim.keymap.set("i", "<C-l>", [[(&spell == 0 ? '' : '<c-g>u<Esc>[s1z=`]a<c-g>u')]], { expr = true })
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
  vim.opt.hlsearch = true
end, {})
vim.keymap.set("n", "#", function()
  vim.fn.execute("normal! #N")
  vim.opt.hlsearch = true
end, {})
vim.keymap.set("n", "<C-n>", function()
  vim.opt.hlsearch = not (vim.opt.hlsearch:get())
end, opts)

vim.cmd([[nnoremap <expr> <space>v '`[' . getregtype()[0] . '`]']])

vim.keymap.set({ "n", "v", "o" }, "H", "^", opts)
vim.keymap.set({ "n", "v", "o" }, "L", "g_", opts)
vim.keymap.set({ "n", "v", "o" }, "M", "%", { remap = true, silent = true })
vim.keymap.set({ "n", "v", "o" }, "]w", "g*", opts)
vim.keymap.set({ "n", "v", "o" }, "[w", "g#", opts)

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
vim.keymap.set("n", "<space>J", ":tabp<cr>")
vim.keymap.set("n", "<space>K", ":tabn<cr>")
vim.keymap.set("n", "<space>Q", ":tabc<cr>")
