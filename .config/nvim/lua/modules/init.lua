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
  { "tpope/vim-abolish" },
  { "radenling/vim-dispatch-neovim" },
  { "tpope/vim-commentary" },
  { "tpope/vim-unimpaired" },
  { "tpope/vim-surround" },
  { "tpope/vim-repeat" },
  { "tpope/vim-projectionist" },
  { "tpope/vim-vinegar" },
  { "tpope/vim-jdaddy", ft = { "json" } },
  {
    "nvim-pack/nvim-spectre",
    cmd = "Spectre",
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    config = function()
      require("indent_blankline").setup({
        filetype = {
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "html",
          "css",
          "scss",
          "sass",
          "lua",
          "go",
          "ruby",
          "erb",
          "rust",
          "json",
          "yaml",
          "toml",
          "scheme",
          "python",
        },
        buftype_exclude = { "terminal", "telescope", "prompt", "nofile" },
        show_current_context = false,
        show_current_context_start = false,
        show_trailing_blankline_indent = false,
      })
    end,
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
      require("marks").setup({})
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
  },
  {
    "npxbr/gruvbox.nvim",
    dependencies = { "rktjmp/lush.nvim" },
    config = function()
      require("gruvbox").setup({
        transparent_mode = true,
      })
      vim.cmd("colorscheme gruvbox")
    end,
  },
  { "TimUntersberger/neogit", cmd = "Neogit" },
  {
    "sindrets/diffview.nvim",
    config = function()
      require("diffview").setup({ use_icons = true })
    end,
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  },
  {
    "ggandor/leap.nvim",
    config = function()
      require("leap").set_default_keymaps()
    end,
    event = "BufRead",
  },
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("modules/config/lualine")
    end,
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
    "klen/nvim-config-local",
    config = function()
      require("config-local").setup({
        -- Default configuration (optional)
        config_files = { ".vimrc.lua", ".vimrc" }, -- Config file patterns to load (lua supported)
        hashfile = vim.fn.stdpath("data") .. "/config-local", -- Where the plugin keeps files data
        autocommands_create = true, -- Create autocommands (VimEnter, DirectoryChanged)
        commands_create = true, -- Create commands (ConfigSource, ConfigEdit, ConfigTrust, ConfigIgnore)
        silent = true, -- Disable plugin messages (Config loaded/ignored)
        lookup_parents = true, -- Lookup config files in parent directories
      })
    end,
  },
  {
    "kevinhwang91/nvim-ufo",
    dependencies = "kevinhwang91/promise-async",
    config = function()
      require("ufo").setup({
        provider_selector = function(bufnr, filetype, buftype)
          return { "treesitter", "indent" }
        end,
      })
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
    end,
    event = "BufRead",
  },
}, {})
