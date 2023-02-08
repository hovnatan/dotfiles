vim.g.ipython_cell_delimit_cells_by = "tags"
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.keymap.set(
      "n",
      "<C-c><C-c>",
      ":IPythonCellExecuteCellVerbose<CR>",
      { noremap = true, silent = true, buffer = true }
    )
    vim.keymap.set(
      "n",
      "<C-c><C-n>",
      ":IPythonCellExecuteCellVerboseJump<CR>",
      { noremap = true, silent = true, buffer = true }
    )
  end,
})
