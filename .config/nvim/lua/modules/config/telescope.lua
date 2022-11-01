return function()
  local telescope = safe_require("telescope")
  if not telescope then
    return
  end

  local telescope_previewers = require("telescope.previewers")
  local telescope_actions = require("telescope.actions")
  local telescope_builtin = require("telescope.builtin")

  telescope.setup({
    defaults = {
      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
      },
      prompt_prefix = "> ",
      selection_caret = "> ",
      entry_prefix = "  ",
      initial_mode = "insert",
      selection_strategy = "reset",
      sorting_strategy = "descending",
      scroll_strategy = "limit",
      layout_strategy = "vertical",
      layout_config = {
        horizontal = { mirror = false, preview_cutoff = 0 },
        vertical = { mirror = false, preview_cutoff = 0 },
        height = 0.95,
        width = 0.95,
      },
      file_sorter = require("telescope.sorters").get_fuzzy_file,
      file_ignore_patterns = {},
      generic_sorter = require("telescope.sorters").get_generic_fuzzy_sorter,
      winblend = 0,
      border = {},
      borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      color_devicons = true,
      use_less = true,
      set_env = { ["COLORTERM"] = "truecolor" }, -- default = nil,
      file_previewer = telescope_previewers.vim_buffer_cat.new,
      grep_previewer = telescope_previewers.vim_buffer_vimgrep.new,
      qflist_previewer = telescope_previewers.vim_buffer_qflist.new,
      tiebreak = function(current_entry, existing_entry, prompt)
        return false
      end,
      -- Developer configurations: Not meant for general override
      buffer_previewer_maker = telescope_previewers.buffer_previewer_maker,
      path_display = { "truncate" },
      mappings = {
        i = {
          ["<esc>"] = telescope_actions.close,
        },
      },
    },
    pickers = {
      -- Your special builtin config goes in here
      buffers = {
        sort_mru = true,
        previewer = false,
        mappings = {
          i = {
            ["<c-d>"] = telescope_actions.delete_buffer,
            -- or right hand side can also be a the name of the action as string
            ["<c-d>"] = "delete_buffer",
          },
          n = { ["<c-d>"] = telescope_actions.delete_buffer },
        },
      },
      find_files = { previewer = false },
      oldfiles = { previewer = false },
      jumplist = { fname_width = 0.5, show_line = false },
      treesitter = { default_text = "function " },
    },
    extensions = {
      fzf = {
        fuzzy = true, -- false will only do exact matching
        override_generic_sorter = true, -- override the generic sorter
        override_file_sorter = true, -- override the file sorter
        case_mode = "smart_case", -- or "ignore_case" or "respect_case"
        -- the default case_mode is "smart_case"
      },
    },
  })
  telescope.load_extension("fzf")

  vim.keymap.set("n", "<space>f", telescope_builtin.find_files, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>g", telescope_builtin.grep_string, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>G", telescope_builtin.live_grep, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>b", telescope_builtin.buffers, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>h", telescope_builtin.help_tags, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>o", function()
    return telescope_builtin.oldfiles({ cwd_only = true })
  end, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>O", telescope_builtin.oldfiles, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>m", telescope_builtin.marks, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>j", function()
    return telescope_builtin.jumplist({ default_text = vim.fn.expand("%:t") .. " " })
  end, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>r", telescope_builtin.registers, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>k", telescope_builtin.keymaps, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>a", function()
    return telescope_builtin.diagnostics({ bufnr = 0 })
  end, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>A", telescope_builtin.diagnostics, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>s", telescope_builtin.treesitter, { noremap = true, silent = true })
  vim.keymap.set("n", "<space>p", telescope_builtin.resume, { noremap = true, silent = true })
end
