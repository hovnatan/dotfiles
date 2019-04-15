set backspace=indent,eol,start    " fixes backspace issues
set t_Co=256
set tabstop=2
set shiftwidth=2
set scrolloff=5
set expandtab
set autoindent
set smartindent
set cindent
syntax on
set showmatch
set hlsearch
set incsearch
set smartcase
set ignorecase
set ls=2
set title
set ruler
set number
set relativenumber
set numberwidth=5
set showcmd
if has('mouse')
  set mouse=a
endif
set ttyfast
set nostartofline
set nobackup
set autowrite
set shortmess=atI
set modeline
set modelines=3
set whichwrap=b,s,h,l,<,>,[,]
set visualbell t_vb=
set novisualbell
set iskeyword=@,48-57,_,192-255,-,.
nn <F9> :silent Dispatch!<CR>
set shortmess=at
set wildmenu
set lazyredraw
set showmatch
nnoremap j gj
nnoremap k gk
nnoremap gV `[v`]
let mapleader=","
inoremap jk <esc>
nnoremap <leader><space> :nohlsearch<CR>
set history=200
set hidden
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'   " map %% as filepath without filename
filetype plugin on
runtime plugins/matchit.vim
nnoremap <S-h> gT
nnoremap <S-l> gt
silent! set clipboard=unnamedplus
set undofile                
set undodir=$HOME/.vimundo  
set undolevels=1000         
set undoreload=10000        
call plug#begin('~/.local/share/nvim/site/plugged')
  Plug 'junegunn/fzf.vim'
  Plug 'vim-scripts/neat.vim'
  " Plug 'lervag/vimtex'
  " Plug 'sirver/ultisnips'
  Plug 'tpope/vim-dispatch'
  Plug 'morhetz/gruvbox'
  Plug 'vim-airline/vim-airline'
  Plug 'ncm2/ncm2'
  Plug 'roxma/nvim-yarp'
  Plug 'ncm2/ncm2-bufword'
  Plug 'ncm2/ncm2-path'
  Plug 'ncm2/ncm2-tmux'
  Plug 'fgrsnau/ncm-otherbuf'
  Plug 'fgrsnau/ncm2-aspell'
"  Plug 'autozimu/LanguageClient-neovim'
"  Plug 'neoclide/coc.nvim', {'do': { -> coc#util#install()}}
call plug#end()

autocmd BufEnter * call ncm2#enable_for_buffer()

set completeopt=noinsert,menuone,noselect
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

let g:airline_theme = 'gruvbox'

filetype plugin indent on

let g:gruvbox_contrast_light = 'medium'
let g:gruvbox_contrast_dark = 'medium'
" let g:gruvbox_color_column = 'dark0'
let g:gruvbox_hls_cursor = 'red'
colorscheme gruvbox
set background=light
" set background=dark

let g:UltiSnipsExpandTrigger = '<tab>'
let g:UltiSnipsJumpForwardTrigger = '<tab>'
let g:UltiSnipsJumpBackwardTrigger = '<s-tab>'

let g:tex_flavor='latex'
let g:vimtex_view_method='zathura'
let g:vimtex_quickfix_mode=0
set conceallevel=1
let g:tex_conceal='abdmg'


nnoremap <silent> <c-p> :Files <CR>

tnoremap <Esc> <C-\><C-n>
au TermOpen * setlocal listchars= nonumber norelativenumber
au TermOpen * startinsert
au BufEnter,BufWinEnter,WinEnter term://* startinsert
au BufLeave term://* stopinsert

set spelllang=en_us
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
for d in glob('~/.config/nvim/spell/*.add', 1, 1)
    if filereadable(d) && (!filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl'))
        exec 'mkspell! ' . fnameescape(d)
    endif
endfor

au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

au FileType markdown,mkd,md
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell
au FileType tex,latex
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell
au FileType json
      \ set conceallevel=0
au FileType cpp
                \ set iskeyword-=.
au BufWritePost *.sh silent! !chmod +x %:p
