vim.api.nvim_create_augroup("highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = "highlight_yank",
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({ timeout = 500 })
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
    vim.wo.spell = true
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.sh",
  callback = function()
    vim.cmd("!chmod +x %:p")
  end,
})

vim.g.LargeFile = 1024 * 1024 * 1
vim.api.nvim_create_autocmd("BufReadPre", {
  pattern = "*",
  callback = function(input)
    local f = io.open(input.match)
    local size = fsize(f)
    f:close()
    if size > vim.g.LargeFile then
      vim.bo.bufhidden = "unload"
      vim.bo.buftype = "nowrite"
      vim.bo.undolevels = -1
      vim.o.loadplugins = false
      vim.o.lazyredraw = true
      vim.o.swapfile = false
      vim.o.eventignore = "all"
      vim.o.hidden = false
      vim.o.syntax = "off"
      print("Large file")
    end
  end,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.gyp",
  callback = function()
    vim.bo.filetype = "json"
  end,
})
