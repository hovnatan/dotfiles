vim.cmd [[packadd packer.nvim]]


return require('packer').startup(function()
  use {'wbthomason/packer.nvim'}
  -- use {'sheerun/vim-polyglot'}
  use {'tpope/vim-abolish'}
  use {'tpope/vim-dispatch'}
  use {'radenling/vim-dispatch-neovim'}
  use {'tpope/vim-commentary'}
  use {'tpope/vim-unimpaired'}
  use {'tpope/vim-surround'}
  use {'tpope/vim-repeat'}
  use {'tpope/vim-projectionist'}
  use {'tpope/vim-vinegar'}
  use {'tpope/vim-jdaddy',
        ft = {'json'}
      }
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
  use {'jpalardy/vim-slime',
        ft = {'python'}
      }
  use {'hanschen/vim-ipython-cell',
        ft = {'python'}
      }
  use {'wsdjeg/vim-fetch'}
  use {'majutsushi/tagbar'}
  use {'kshenoy/vim-signature'}
  use {'airblade/vim-rooter'}
  use {'will133/vim-dirdiff'}
  use {'nvim-lua/popup.nvim'}
  use {'nvim-telescope/telescope.nvim'}
  use {'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }
  use {'hrsh7th/cmp-nvim-lsp'}
  use {'hrsh7th/cmp-buffer'}
  use {'hrsh7th/cmp-path'}
  use {'hrsh7th/nvim-cmp'}
  use {'hrsh7th/cmp-vsnip'}
  use {'hrsh7th/vim-vsnip'}
  use {'andersevenrud/cmp-tmux'}
  use {'neovim/nvim-lspconfig'}
  use {'lakshayg/vim-bazel',
        ft = {'bzl'}
      }
  use {"npxbr/gruvbox.nvim", requires = {"rktjmp/lush.nvim"}}
  -- use {'gennaro-tedesco/nvim-peekup'}
  -- use {'morhetz/gruvbox'}
  use {'spywhere/lightline-lsp'}
  use {'nvim-lua/plenary.nvim'}
  use {'TimUntersberger/neogit'}
  use {'lewis6991/gitsigns.nvim'}
  use { 'phaazon/hop.nvim', 
    as = 'hop',
    config = function()
       require'hop'.setup { keys = 'etovxqpdygfblzhckisuran' }
    end
  }
end)
