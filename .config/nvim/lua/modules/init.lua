local function conf(name)
  return require(string.format("modules.config.%s", name))
end

local plugins = {
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
    run = ":TSUpdate",
    config = conf("nvim-treesitter"),
  },
  { "nvim-treesitter/nvim-treesitter-textobjects" },
  {
    "nvim-treesitter/nvim-treesitter-context",
    config = conf("nvim-treesitter-context"),
  },
  { "mbbill/undotree", config = conf("undotree") },
  { "jpalardy/vim-slime", ft = { "python" }, config = conf("vim-slime") },
  {
    "hanschen/vim-ipython-cell",
    ft = { "python" },
    config = conf("vim-ipython-cell"),
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
  },
  {
    "nvim-telescope/telescope.nvim",
    requires = {
      { "nvim-telescope/telescope-live-grep-args.nvim" },
      { "nvim-telescope/telescope-fzf-native.nvim", run = "make" },
    },
    config = conf("telescope"),
  },
  { "lewis6991/gitsigns.nvim", config = conf("gitsigns") },
  {
    "hrsh7th/nvim-cmp",
    config = conf("nvim-cmp"),
    requires = {
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
  { "neovim/nvim-lspconfig", config = conf("lsp") },
  {
    "npxbr/gruvbox.nvim",
    requires = { "rktjmp/lush.nvim" },
    config = function()
      require("gruvbox").setup({
        transparent_mode = true,
      })
      vim.cmd("colorscheme gruvbox")
    end,
  },
  { "nvim-lua/plenary.nvim" },
  { "TimUntersberger/neogit" },
  {
    "sindrets/diffview.nvim",
    config = function()
      require("diffview").setup()
    end,
    requires = "nvim-lua/plenary.nvim",
  },
  {
    "ggandor/leap.nvim",
    config = function()
      require("leap").set_default_keymaps()
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    config = conf("lualine"),
  },
  {
    "AckslD/nvim-neoclip.lua",
    requires = {
      { "nvim-telescope/telescope.nvim" },
      { "kkharji/sqlite.lua", module = "sqlite" },
    },
    config = conf("neoclip"),
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
    requires = "kevinhwang91/promise-async",
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
}

-- vim.api.nvim_set_keymap("n", "$", "<cmd>lua require'hop'.hint_words()<cr>", {})
local install_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path })
  vim.cmd("packadd packer.nvim")
end

local packer = safe_require("packer")
if packer then
  packer.init({
    compile_path = vim.fn.stdpath("data") .. "/site/plugin/packer_compiled.lua",
    package_root = vim.fn.stdpath("data") .. "/site/pack",
    display = {
      open_fn = function()
        return require("packer.util").float({ border = "rounded" })
      end,
    },
  })

  return packer.startup(function(use)
    use("wbthomason/packer.nvim")
    for _, plugin in ipairs(plugins) do
      use(plugin)
    end
  end)
end
