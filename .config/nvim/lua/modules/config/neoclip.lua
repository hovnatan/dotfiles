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
    content_spec_column = true,
    default_register = "+",
    history = 10000,
    filter = function(data)
      whitespace = not all(data.event.regcontents, is_whitespace)
      if not whitespace then
        return false
      end
      local count = 0
      for _, entry in ipairs(data.event.regcontents) do
        if count > 0 then
          return true
        end
        if string.len(entry) > 1 then
          return true
        end
        count = count + 1
      end
      return false
    end,
    on_paste = {
      set_reg = true,
    },
    keys = {
      telescope = {
        i = {
          paste = "<cr>",
          select = "<c-s>",
        },
      },
    },
  })
  require("telescope").load_extension("neoclip")
  vim.api.nvim_set_keymap("n", "<space>y", "<cmd>Telescope neoclip<cr>", { noremap = true, silent = true })
end
