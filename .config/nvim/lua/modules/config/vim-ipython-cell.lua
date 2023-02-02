vim.g.ipython_cell_delimit_cells_by = "tags"
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.api.nvim_buf_set_keymap(
      0,
      "n",
      "<C-c><C-c>",
      ":IPythonCellExecuteCellVerbose<CR>",
      { noremap = true, silent = true }
    )
    vim.api.nvim_buf_set_keymap(
      0,
      "n",
      "<C-c><C-n>",
      ":IPythonCellExecuteCellVerboseJump<CR>",
      { noremap = true, silent = true }
    )
  end,
})
