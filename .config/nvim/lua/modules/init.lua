local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--single-branch",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.runtimepath:prepend(lazypath)

require("lazy").setup({
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      -- add any options here
    },
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      "MunifTanjim/nui.nvim",
      -- OPTIONAL:
      --   `nvim-notify` is only needed, if you want to use the notification view.
      --   If not available, we use `mini` as the fallback
      "rcarriga/nvim-notify",
    },
    config = function()
      require("noice").setup({
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = false, -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = false, -- add a border to hover docs and signature help
        },
      })
    end,
  },
  {
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end,
  },
  { "tpope/vim-unimpaired" },
  { "tpope/vim-surround" },
  { "tpope/vim-repeat" },
  { "tpope/vim-vinegar" },
  {
    "nvim-pack/nvim-spectre",
    cmd = "Spectre",
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      exclude = { filetypes = { "terminal", "telescope", "prompt", "nofile" } },
      indent = { char = "▏" },
      scope = { enabled = false },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("modules/config/nvim-treesitter")
    end,
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    config = function()
      require("modules/config/nvim-treesitter-context")
    end,
  },
  {
    "mbbill/undotree",
    config = function()
      require("modules/config/undotree")
    end,
    cmd = "UndotreeShow",
  },
  {
    "hanschen/vim-ipython-cell",
    config = function()
      require("modules/config/vim-ipython-cell")
    end,
    dependencies = {
      {
        "jpalardy/vim-slime",
        config = function()
          require("modules/config/vim-slime")
        end,
      },
    },
    cmd = "IPythonCellExecuteCellVerbose",
  },
  {
    "chentoast/marks.nvim",
    config = function()
      require("marks").setup({
        builtin_marks = { ".", "'" },
        sign_priority = { lower = 16, upper = 20, builtin = 15, bookmark = 25 },
      })
    end,
  },
  {
    "will133/vim-dirdiff",
    config = function()
      vim.g.DirDiffExcludes = "CVS,*.class,*.o,.git,build,.clangd"
    end,
    cmd = "DirDiff",
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      { "nvim-telescope/telescope-live-grep-args.nvim" },
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
      { "nvim-lua/plenary.nvim" },
    },
    config = function()
      require("modules/config/telescope")
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("modules/config/gitsigns")
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    config = function()
      require("modules/config/nvim-cmp")
    end,
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp" },
      { "hrsh7th/cmp-buffer" },
      { "hrsh7th/cmp-path" },
      { "andersevenrud/cmp-tmux" },
      { "ray-x/cmp-treesitter" },
      -- { "saadparwaiz1/cmp_luasnip" },
      -- {
      --   "L3MON4D3/LuaSnip",
      --   wants = "friendly-snippets",
      --   config = conf("luasnip"),
      -- },
      -- "rafamadriz/friendly-snippets",
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("modules/config/lsp")
    end,
    dependencies = {
      {
        "williamboman/mason.nvim",
        config = function()
          require("mason").setup({ PATH = "append" })
        end,
      },
      {
        "williamboman/mason-lspconfig.nvim",
        config = function()
          require("mason-lspconfig").setup({
            ensure_installed = {
              "pyright",
              "bashls",
              "tsserver",
              "eslint",
              "ruff_lsp",
            },
          })
        end,
      },
      {
        "j-hui/fidget.nvim",
        tag = "legacy",
        config = function()
          require("fidget").setup({})
        end,
      },
      "jose-elias-alvarez/typescript.nvim",
      "folke/neodev.nvim",
    },
  },
  {
    "sainnhe/gruvbox-material",
    config = function()
      vim.g.gruvbox_material_foreground = "original"
      vim.g.gruvbox_material_ui_contrast = "medium"
      vim.cmd("colorscheme gruvbox-material")
    end,
  },
  {
    "TimUntersberger/neogit",
    cmd = "Neogit",
    config = function()
      neogit = require("neogit").setup({})
    end,
  },
  {
    "sindrets/diffview.nvim",
    config = function()
      require("diffview").setup({ use_icons = false })
    end,
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        search = {
          enabled = false,
        },
      },
    },
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "S",
        mode = { "n", "o", "x" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Flash Treesitter Search",
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("modules/config/lualine")
    end,
  },
  {
    "simrat39/symbols-outline.nvim",
    config = function()
      require("symbols-outline").setup({ autofold_depth = 1 })
      vim.keymap.set("n", "<space>o", ":SymbolsOutline<cr>")
    end,
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },
  {
    "AckslD/nvim-neoclip.lua",
    dependencies = {
      { "nvim-telescope/telescope.nvim" },
      { "kkharji/sqlite.lua", module = "sqlite" },
    },
    config = function()
      require("modules/config/neoclip")
    end,
  },
  {
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup({
        -- Configuration here, or leave empty to use defaults
      })
    end,
  },
  {
    "andymass/vim-matchup",
    config = function()
      vim.g.matchup_matchparen_offscreen = { method = "popup" }
      vim.keymap.set("n", "]M", "<Plug>(matchup-]%)")
      vim.keymap.set("n", "[M", "<Plug>(matchup-[%)")
      vim.keymap.set("n", "zM", "<Plug>(matchup-z%)")
      vim.keymap.set("n", "gM", "<Plug>(matchup-g%)")
      vim.keymap.set("x", "aM", "<Plug>(matchup-a%)")
      vim.keymap.set("x", "iM", "<Plug>(matchup-i%)")
      vim.keymap.set("i", "<C-G>M", "<Plug>(matchup-c_g%)")
    end,
    event = "BufRead",
  },
  {
    "axkirillov/easypick.nvim",
    config = function()
      local easypick = require("easypick")

      -- only required for the example to work
      local base_branch = "develop"

      easypick.setup({
        pickers = {
          -- add your custom pickers here
          -- below you can find some examples of what those can look like

          -- list files inside current folder with default previewer
          {
            -- name for your custom picker, that can be invoked using :Easypick <name> (supports tab completion)
            name = "ls",
            -- the command to execute, output has to be a list of plain text entries
            command = "ls",
            -- specify your custom previwer, or use one of the easypick.previewers
            previewer = easypick.previewers.default(),
          },

          -- diff current branch with base_branch and show files that changed with respective diffs in preview
          {
            name = "changed_files",
            command = "git diff --name-only $(git merge-base HEAD " .. base_branch .. " )",
            previewer = easypick.previewers.branch_diff({ base_branch = base_branch }),
          },

          -- list files that have conflicts with diffs in preview
          {
            name = "conflicts",
            command = "git diff --name-only --diff-filter=U --relative",
            previewer = easypick.previewers.file_diff(),
          },
        },
      })
      local easypick = require("easypick")

      -- only required for the example to work
      local base_branch = "develop"

      easypick.setup({
        pickers = {
          -- add your custom pickers here
          -- below you can find some examples of what those can look like

          -- list files inside current folder with default previewer
          {
            -- name for your custom picker, that can be invoked using :Easypick <name> (supports tab completion)
            name = "ls",
            -- the command to execute, output has to be a list of plain text entries
            command = "ls",
            -- specify your custom previwer, or use one of the easypick.previewers
            previewer = easypick.previewers.default(),
          },

          -- diff current branch with base_branch and show files that changed with respective diffs in preview
          {
            name = "changed_files",
            command = "git diff --name-only $(git merge-base HEAD " .. base_branch .. " )",
            previewer = easypick.previewers.branch_diff({ base_branch = base_branch }),
          },

          -- list files that have conflicts with diffs in preview
          {
            name = "conflicts",
            command = "git diff --name-only --diff-filter=U --relative",
            previewer = easypick.previewers.file_diff(),
          },
        },
      })
    end,
  },
}, {
  lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
})
