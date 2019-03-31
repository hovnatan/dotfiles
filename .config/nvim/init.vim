set nocompatible                  " use vim defaults

set backspace=indent,eol,start    " fixes backspace issues

set t_Co=256

"----------------------"
" Tabs->spaces section "
"----------------------"

set tabstop=2                     " numbers of spaces of tab character
set shiftwidth=2                  " numbers of spaces to (auto)indent
set scrolloff=5                   " keep lines when scrolling
set expandtab                     " tabs are converted to spaces, use only when required

"---------------------"
" Indentation section "
"---------------------"

set autoindent                    " always set autoindenting on
set smartindent                   " smart indent
set cindent                       " cindent

"---------------------------------"
" Highlighting, searching section "
"---------------------------------"

syntax on
set showmatch
set hlsearch
set incsearch
set smartcase
set ignorecase


"hi Search       ctermbg=darkyellow ctermfg=NONE    " change search hl color
"hi MatchParen   ctermbg=darkgreen ctermfg=NONE       " change matching parentheses color
"
"hi LineNr       ctermbg=NONE ctermfg=darkgray  " change line numbers color
"
"hi StatusLine   ctermbg=NONE ctermfg=darkgray  " change status line color
"hi StatusLineNC ctermbg=NONE ctermfg=darkgray  " change non activestatus line color
"
"hi VertSplit    ctermbg=NONE ctermfg=darkgray  " change vertical split line color 
"
"hi Folded       ctermbg=NONE ctermfg=darkblue  " change folded line color
"hi FoldColumn   ctermbg=NONE ctermfg=darkblue  " change folded column color

"------------------------"
" Environment components "
"------------------------"

set ls=2                          " always show status line
set title                         " show title in console title bar
set ruler                         " show the cursor position all the time
set number                        " show line numbers
set relativenumber
set numberwidth=5                 " set line numbers column width
set showcmd                       " display incomplete commands
if has('mouse')
  set mouse=a
endif

"---------------------"
" Behavioral section "
"---------------------"

set ttyfast                       " smoother changes
set nostartofline                 " don't jump to first character when paging
set nobackup                      " do not keep a backup file
set autowrite                     " auto saves changes when quitting and swiching buffer
set shortmess=atI                 " Abbreviate messages
set modeline                      " last lines in document sets vim mode
set modelines=3                   " number lines checked for modelines
set whichwrap=b,s,h,l,<,>,[,]     " move freely between files

"------------------"
" Turning of bells "
"------------------"

set visualbell t_vb=              " turn off error beep/flash
set novisualbell                  " turn off visual bell

" Restore cursor position
au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

au FileType markdown,mkd,md
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p'
au FileType tex,latex
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p'
au BufWritePost *.sh silent! !chmod +x %:p

" headless dispatch
nn <F9> :silent Dispatch!<CR>


set shortmess=at
set number "show line number
set wildmenu
set lazyredraw "redraw only when need to
set showmatch           " highlight matching [{()}]
nnoremap j gj
nnoremap k gk
" highlight last inserted text
nnoremap gV `[v`]
let mapleader=","       " leader is comma
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
  Plug 'fgrsnau/ncm-otherbuf'
  Plug 'fgrsnau/ncm2-aspell'
  Plug 'wellle/tmux-complete.vim'
call plug#end()

autocmd BufEnter * call ncm2#enable_for_buffer()

set completeopt=noinsert,menuone,noselect
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

let g:airline_theme = 'gruvbox'

filetype plugin indent on

let g:gruvbox_contrast_dark = 'hard'
let g:gruvbox_color_column = 'dark0'
let g:gruvbox_hls_cursor = 'red'

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

setlocal spell
set spelllang=en_us
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
for d in glob('~/.config/nvim/spell/*.add', 1, 1)
    if filereadable(d) && (!filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl'))
        exec 'mkspell! ' . fnameescape(d)
    endif
endfor

