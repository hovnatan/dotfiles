-- Highlight every non-ASCII character (em dash, smart quote, NBSP, ...) on a
-- red background, so stray typography stands out in files meant to be plain
-- ASCII. File buffers only (buftype ""): pickers, the explorer and terminals
-- keep their icons clean, and a big or minified file (filetype "bigfile",
-- snacks bigfile in plugins.lua) is never scanned. On by default;
-- plugins.lua maps the ,ua toggle.
--
--   redraw --> on_win: enabled, buftype "", not bigfile? --no--> skip window
--                           | yes
--              on_line, per visible line: each run of bytes >= 0x80
--              (one UTF-8 char or several: an em dash is 3 bytes) gets an
--              ephemeral extmark, redrawn every time, so nothing is stored
--
-- Deciding at draw time, not with per-window matches kept up to date by
-- autocmds, means no event can be missed: a buffer whose buftype is set
-- after it is shown (terminals) is right on the next redraw. DiffDelete is
-- used directly, so a :colorscheme reload needs no group to be rebuilt.

local M = {}

local ns = vim.api.nvim_create_namespace("non_ascii")
local enabled = true

vim.api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, buf)
    local bo = vim.bo[buf]
    return enabled and bo.buftype == "" and bo.filetype ~= "bigfile"
  end,
  on_line = function(_, _, buf, row)
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
    local s, e = line:find("[\128-\255]+")
    while s do
      vim.api.nvim_buf_set_extmark(buf, ns, row, s - 1, {
        end_col = e,
        hl_group = "DiffDelete",
        ephemeral = true,
      })
      s, e = line:find("[\128-\255]+", e + 1)
    end
  end,
})

function M.enabled()
  return enabled
end

function M.set(state)
  enabled = state
  vim.cmd("redraw!")
end

return M
