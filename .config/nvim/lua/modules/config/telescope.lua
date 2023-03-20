local telescope = require("telescope")

local telescope_actions = require("telescope.actions")
local telescope_builtin = require("telescope.builtin")
local telescope_sorters = require("telescope.sorters")

telescope.setup({
  defaults = {
    prompt_prefix = " ",
    selection_caret = "➜ ",
    scroll_strategy = "limit",
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = { mirror = false, preview_cutoff = 0 },
      vertical = { mirror = false, preview_cutoff = 0 },
      height = 0.95,
      width = 0.95,
    },
    file_sorter = telescope_sorters.get_fuzzy_file,
    generic_sorter = telescope_sorters.get_generic_fuzzy_sorter,
    set_env = { ["COLORTERM"] = "truecolor" }, -- default = nil,
    tiebreak = function(current_entry, existing_entry, prompt)
      return false
    end,
    path_display = { truncate },
    mappings = {
      i = {
        ["<esc>"] = telescope_actions.close,
        ["<C-j>"] = telescope_actions.cycle_history_next,
        ["<C-k>"] = telescope_actions.cycle_history_prev,
      },
    },
    cache_picker = {
      num_pickers = 10,
    },
  },
  pickers = {
    buffers = {
      sort_mru = true,
      previewer = false,
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
    live_grep_args = {
      auto_quoting = false,
    },
  },
})
telescope.load_extension("fzf")
telescope.load_extension("live_grep_args")
telescope.load_extension("enhanced_find_files")

vim.keymap.set("n", "<space>f", function()
  return telescope.extensions.enhanced_find_files.enhanced_find_files({ cwd_only = true })
end, { noremap = true, silent = true })
vim.keymap.set("n", "<space>g", telescope.extensions.live_grep_args.live_grep_args, { noremap = true, silent = true })
vim.keymap.set("n", "<space>G", telescope_builtin.grep_string, { noremap = true, silent = true })
vim.keymap.set("n", "<space>b", telescope_builtin.buffers, { noremap = true, silent = true })
vim.keymap.set("n", "<space>h", telescope_builtin.help_tags, { noremap = true, silent = true })
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
vim.keymap.set("n", "<space>[", telescope_builtin.pickers, { noremap = true, silent = true })
