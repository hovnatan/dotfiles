return function()
  local function is_whitespace(line)
    return vim.fn.match(line, [[^\s*$]]) ~= -1
  end

  local function all(tbl, check)
    for _, entry in ipairs(tbl) do
      if not check(entry) then
        return false
      end
    end
    return true
  end
  require("neoclip").setup({
    enable_persistent_history = true,
    filter = function(data)
      return not all(data.event.regcontents, is_whitespace)
    end,
    on_paste = {
      set_reg = true,
    },
    keys = {
      telescope = {
        i = {
          paste = "<c-h>",
          paste_behind = "<c-y>",
        },
        n = {
          select = "<cr>",
          paste = "p",
          paste_behind = "P",
          replay = "q",
          delete = "d",
          custom = {},
        },
      },
    },
  })
  require("telescope").load_extension("neoclip")
  vim.api.nvim_set_keymap("n", "<space>y", "<cmd>Telescope neoclip<cr>", { noremap = true, silent = true })
end
