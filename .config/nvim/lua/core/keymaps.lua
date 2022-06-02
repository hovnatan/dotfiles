local map = function(mode, key, cmd, opts)
    vim.api.nvim_set_keymap(mode, key, cmd,
                            opts or {noremap = true, silent = true})
end

map("n", "<space>f", "<cmd>lua require('telescope.builtin').find_files()<cr>")
map("n", "<space>g", "<cmd>lua require('telescope.builtin').grep_string()<cr>")
map("n", "<space>G", "<cmd>lua require('telescope.builtin').live_grep()<cr>")
map("n", "<space>b", "<cmd>lua require('telescope.builtin').buffers()<cr>")
map("n", "<space>h", "<cmd>lua require('telescope.builtin').help_tags()<cr>")
map("n", "<space>o",
    "<cmd>lua require('telescope.builtin').oldfiles({cwd_only=true})<cr>")
map("n", "<space>O", "<cmd>lua require('telescope.builtin').oldfiles()<cr>")
map("n", "<space>m", "<cmd>lua require('telescope.builtin').marks()<cr>")
map("n", "<space>r", "<cmd>lua require('telescope.builtin').registers()<cr>")
map("n", "<space>q", "<cmd>lua require('telescope.builtin').quickfix()<cr>")
map("n", "<space>k", "<cmd>lua require('telescope.builtin').keymaps()<cr>")
map("n", "<space>a",
    "<cmd>lua require('telescope.builtin').diagnostics({bufnr=0})<cr>")
map("n", "<space>s",
    "<cmd>lua require('telescope.builtin').lsp_document_symbols()<cr>")
map("n", "<space>p", "<cmd>lua require('telescope.builtin').resume()<cr>")
