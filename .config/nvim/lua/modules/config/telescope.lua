return function()
  local telescope = safe_require("telescope")
  if not telescope then
    return
  end

  local telescope_previewers = require("telescope.previewers")
  local telescope_actions = require("telescope.actions")

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
      jumplist = { default_text = vim.fn.expand("%:t") .. " ", fname_width = 0.5, show_line = false },
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

  vim.api.nvim_set_keymap(
    "n",
    "<space>f",
    "<cmd>lua require('telescope.builtin').find_files()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>g",
    "<cmd>lua require('telescope.builtin').grep_string()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>G",
    "<cmd>lua require('telescope.builtin').live_grep()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>b",
    "<cmd>lua require('telescope.builtin').buffers()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>h",
    "<cmd>lua require('telescope.builtin').help_tags()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>o",
    "<cmd>lua require('telescope.builtin').oldfiles({cwd_only=true})<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>O",
    "<cmd>lua require('telescope.builtin').oldfiles()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>m",
    "<cmd>lua require('telescope.builtin').marks()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>j",
    "<cmd>lua require('telescope.builtin').jumplist()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>r",
    "<cmd>lua require('telescope.builtin').registers()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>q",
    "<cmd>lua require('telescope.builtin').quickfix()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>k",
    "<cmd>lua require('telescope.builtin').keymaps()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>a",
    "<cmd>lua require('telescope.builtin').diagnostics({bufnr=0})<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>A",
    "<cmd>lua require('telescope.builtin').diagnostics()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>s",
    "<cmd>lua require('telescope.builtin').treesitter()<cr>",
    { noremap = true, silent = true }
  )
  vim.api.nvim_set_keymap(
    "n",
    "<space>p",
    "<cmd>lua require('telescope.builtin').resume()<cr>",
    { noremap = true, silent = true }
  )
end
