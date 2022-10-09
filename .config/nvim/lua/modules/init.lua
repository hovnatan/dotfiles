local function conf(name)
  return require(string.format("modules.config.%s", name))
end

local plugins = {
  { "tpope/vim-abolish" },
  {
    "tpope/vim-dispatch",
    conifg = function()
      vim.g.dispatch_no_maps = 1
    end,
  },
  { "radenling/vim-dispatch-neovim" },
  { "tpope/vim-commentary" },
  { "tpope/vim-unimpaired" },
  { "tpope/vim-surround" },
  { "tpope/vim-repeat" },
  { "tpope/vim-projectionist" },
  { "tpope/vim-vinegar" },
  { "tpope/vim-jdaddy", ft = { "json" } },
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
  { "wellle/targets.vim" },
  { "michaeljsmith/vim-indent-object" },
  { "jeetsukumaran/vim-indentwise" },
  { "zhimsel/vim-stay" },
  { "mbbill/undotree", config = conf("undotree") },
  { "jpalardy/vim-slime", ft = { "python" }, config = conf("vim-slime") },
  {
    "hanschen/vim-ipython-cell",
    ft = { "python" },
    config = conf("vim-ipython-cell"),
  },

  { "wsdjeg/vim-fetch" },
  {
    "chentoast/marks.nvim",
    config = function()
      require("marks").setup({})
    end,
  },
  {
    "notjedi/nvim-rooter.lua",
    config = function()
      require("nvim-rooter").setup()
    end,
  },
  {
    "will133/vim-dirdiff",
    config = function()
      vim.g.DirDiffExcludes = "CVS,*.class,*.o,.git,build,.clangd"
    end,
  },
  { "nvim-lua/popup.nvim" },
  { "nvim-telescope/telescope.nvim", config = conf("telescope") },
  { "nvim-telescope/telescope-fzf-native.nvim", run = "make" },
  {
    "liuchengxu/vista.vim",
    config = function()
      vim.g.vista_default_executive = "nvim_lsp"
      vim.g.vista_echo_cursor = 0
    end,
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
  { "lakshayg/vim-bazel", ft = { "bzl" } },
  { "npxbr/gruvbox.nvim", requires = { "rktjmp/lush.nvim" } },
  -- use {'gennaro-tedesco/nvim-peekup'}
  -- use {'morhetz/gruvbox'}
  { "nvim-lua/plenary.nvim" },
  { "TimUntersberger/neogit" },
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
