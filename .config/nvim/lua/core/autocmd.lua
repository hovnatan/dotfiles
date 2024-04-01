vim.api.nvim_create_augroup("highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = "highlight_yank",
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({ timeout = 250 })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "c,cpp,java",
  callback = function()
    vim.bo.commentstring = "// %s"
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.api.nvim_buf_del_keymap(0, "n", "]M")
    vim.api.nvim_buf_del_keymap(0, "x", "]M")
    vim.api.nvim_buf_del_keymap(0, "n", "[M")
    vim.api.nvim_buf_del_keymap(0, "x", "[M")
  end,
})

vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
  pattern = "*",
  callback = function()
    vim.cmd("wa")
  end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  pattern = "*",
  callback = function()
    vim.cmd("checktime")
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "NeogitCommitMessage,gitcommit,markdown,text,rst,tex,latex",
  callback = function(input)
    if string.match(input.file, 'requirements.*txt') ~= null then
      return
    end
    vim.bo.textwidth = 80
    vim.opt_local.spell = true
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

vim.api.nvim_create_autocmd({ "BufReadPost" }, {
  pattern = { "*" },
  callback = function()
    local ft = vim.opt_local.filetype:get()
    -- don't apply to git messages
    if ft:match("commit") or ft:match("rebase") then
      return
    end
    -- get position of last saved edit
    local markpos = vim.api.nvim_buf_get_mark(0, '"')
    local line = markpos[1]
    local col = markpos[2]
    -- if in range, go there
    if (line > 1) and (line <= vim.api.nvim_buf_line_count(0)) then
      vim.api.nvim_win_set_cursor(0, { line, col })
    end
  end,
})
