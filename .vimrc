set nocompatible
set backspace=indent,eol,start
set complete-=i
set smarttab
set nrformats-=octal
set ttimeout
set ttimeoutlen=100
set incsearch
nnoremap <silent> <C-L> :nohlsearch<C-R>=has('diff')?'<Bar>diffupdate':''<CR><CR><C-L>
set laststatus=2
set ruler
set wildmenu
set scrolloff=1
set sidescroll=1
set sidescrolloff=2
set display+=lastline
set display+=truncate
set listchars=tab:>\ ,trail:-,extends:>,precedes:<,nbsp:+
set formatoptions+=j
set autoread
set history=1000
set tabpagemax=50
set viminfo^=!
set sessionoptions-=options
set viewoptions-=options

if &t_Co == 8 && $TERM !~# '^Eterm'
  set t_Co=16
endif

set nolangremap
filetype plugin indent on
syntax enable
inoremap <C-U> <C-G>u<C-U>
inoremap <C-W> <C-G>u<C-W>

runtime! macros/matchit.vim
runtime ftplugin/man.vim

let vimDir = '$HOME/.vim'

if stridx(&runtimepath, expand(vimDir)) == -1
  let &runtimepath.=','.vimDir
endif

let &undodir = expand(vimDir . '/undodir')
set undofile

let &t_SI = "\e[6 q"
let &t_EI = "\e[2 q"

augroup myCmds
au!
autocmd VimEnter * silent !echo -ne "\e[2 q"
augroup END
