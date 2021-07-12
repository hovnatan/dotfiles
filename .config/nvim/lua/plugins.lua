vim.cmd [[packadd packer.nvim]]


return require('packer').startup(function()
  use {'wbthomason/packer.nvim'}
  use {'sheerun/vim-polyglot'}
  use {'lervag/vimtex'}
  use {'tpope/vim-abolish'}
  use {'tpope/vim-dispatch'}
  use {'radenling/vim-dispatch-neovim'}
  use {'tpope/vim-commentary'}
  use {'tpope/vim-unimpaired'}
  use {'tpope/vim-git'}
  use {'tpope/vim-fugitive'}
  use {'tommcdo/vim-fubitive'}
  use {'tpope/vim-rhubarb'}
  use {'tpope/vim-surround'}
  use {'tpope/vim-repeat'}
  use {'tpope/vim-projectionist'}
  use {'tpope/vim-vinegar'}
  use {'tpope/vim-jdaddy'}
  use {'airblade/vim-gitgutter'}
  use {'itchyny/lightline.vim'}
  use {'shinchu/lightline-gruvbox.vim'}
  use {'nvim-treesitter/nvim-treesitter',  run = ':TSUpdate'}
  use {'nvim-treesitter/playground'}
  use {'nvim-treesitter/nvim-treesitter-textobjects'}
  use {'wellle/targets.vim'}
  use {'michaeljsmith/vim-indent-object'}
  use {'jeetsukumaran/vim-indentwise'}
  use {'zhimsel/vim-stay'}
  use {'mbbill/undotree'}
  use {'ntpeters/vim-better-whitespace'}
  use {'jpalardy/vim-slime'}
  use {'hanschen/vim-ipython-cell'}
  use {'wsdjeg/vim-fetch'}
  use {'majutsushi/tagbar'}
  use {'kshenoy/vim-signature'}
  use {'airblade/vim-rooter'}
  use {'will133/vim-dirdiff'}
  use {'nvim-lua/popup.nvim'}
  use {'nvim-lua/plenary.nvim'}
  use {'nvim-telescope/telescope.nvim'}
  use {'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }
  use {'hrsh7th/nvim-compe'}
  use {'andersevenrud/compe-tmux'}
  use {'neovim/nvim-lspconfig'}
  use {'lakshayg/vim-bazel'}
  use {"npxbr/gruvbox.nvim", requires = {"rktjmp/lush.nvim"}}
  -- use {'gennaro-tedesco/nvim-peekup'}
  -- use {'morhetz/gruvbox'}
  use {'spywhere/lightline-lsp'}
end)
