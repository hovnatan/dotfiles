vim.api.nvim_create_augroup("highlight_yank", {clear = true})
vim.api.nvim_create_autocmd("TextYankPost", {
    group = "highlight_yank",
    pattern = "*",
    callback = function() vim.highlight.on_yank({timeout = 150}) end
})
