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
  { "itchyny/lightline.vim", config = conf("lightline") },
  { "shinchu/lightline-gruvbox.vim" },
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
    "kshenoy/vim-signature",
    config = function()
      vim.g.SignatureMap = {
        Leader = "m",
        PlaceNextMark = "m,",
        ToggleMarkAtLine = "m.",
        PurgeMarksAtLine = "m-",
        DeleteMark = "dm",
        PurgeMarks = "m<Space>",
        PurgeMarkers = "m<BS>",
        GotoNextLineAlpha = "",
        GotoPrevLineAlpha = "",
        GotoNextSpotAlpha = "",
        GotoPrevSpotAlpha = "",
        GotoNextLineByPos = "",
        GotoPrevLineByPos = "",
        GotoNextSpotByPos = "",
        GotoPrevSpotByPos = "",
        GotoNextMarker = "",
        GotoPrevMarker = "",
        GotoNextMarkerAny = "",
        GotoPrevMarkerAny = "",
        ListBufferMarks = "m/",
        ListBufferMarkers = "m?",
      }
    end,
  },
  {
    "airblade/vim-rooter",
    config = function()
      vim.g.rooter_patterns = { ".git" }
      vim.g.rooter_silent_chdir = 1
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
  { "hrsh7th/cmp-nvim-lsp" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-path" },
  {
    "hrsh7th/nvim-cmp",
    config = conf("nvim-cmp"),
    requires = {
      { "hrsh7th/cmp-vsnip" },
      { "hrsh7th/vim-vsnip" },
      { "hrsh7th/vim-vsnip-integ" },
      { "rafamadriz/friendly-snippets" },
      { "andersevenrud/cmp-tmux" },
    },
  },
  { "neovim/nvim-lspconfig", config = conf("lsp") },
  { "lakshayg/vim-bazel", ft = { "bzl" } },
  { "npxbr/gruvbox.nvim", requires = { "rktjmp/lush.nvim" } },
  -- use {'gennaro-tedesco/nvim-peekup'}
  -- use {'morhetz/gruvbox'}
  { "spywhere/lightline-lsp" },
  { "nvim-lua/plenary.nvim" },
  { "TimUntersberger/neogit" },
  {
    "phaazon/hop.nvim",
    as = "hop",
    config = function()
      require("hop").setup({ keys = "etovxqpdygfblzhckisuran" })
      vim.api.nvim_set_keymap("n", "$", "<cmd>lua require'hop'.hint_words()<cr>", { noremap = true, silent = true })
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
