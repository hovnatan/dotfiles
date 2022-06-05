vim.api.nvim_create_augroup("highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = "highlight_yank",
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({ timeout = 150 })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "c,cpp,java",
  callback = function()
    vim.bo.commentstring = "// %s"
  end,
})

vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
  pattern = "*",
  callback = function()
    vim.cmd("wa")
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown,text,rst,tex,latex",
  callback = function()
    vim.bo.textwidth = 80
    vim.bo.spell = true
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.sh",
  callback = function()
    vim.cmd("!chmod +x %:p")
  end,
})
