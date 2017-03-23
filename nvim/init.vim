if v:version >= 704
    execute pathogen#infect()
endif
  

set nocompatible                  " use vim defaults

"------------------"
" Bugs workarounds "
"------------------"

set backspace=indent,eol,start    " fixes backspace issues

set t_Co=256
"---------------------"
" Gvim configurations "
"---------------------"

if has("gui_running")
    set guifont=Monospace\ 14     " use this font
    set lines=40                  " height = 50 lines
    set columns=120               " width = 100 columns
    "set guioptions-=m             " Remove menu bar
    set guioptions-=T             " Remove toolbar
    "set guioptions-=r             " Remove scrollbar
endif
colorscheme wombat

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

syntax on                         " syntax highlighing
set showmatch                     " highlight matching breckets
set hlsearch                      " highlight searches
set incsearch                     " do incremental searching
set smartcase                    " smart case: change behaviour when capital letter is encountered
set ignorecase                    " ignore case (combined with smart case)


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

" highlight sourcecode lines longer than 100
"au FileType cpp,c,java,pl,php,asp let w:m2=matchadd('ErrorMsg', '\%>100v.\+', -1) 

"------------------------"
" Environment components "
"------------------------"

set ls=2                          " always show status line
set title                         " show title in console title bar
set ruler                         " show the cursor position all the time
set number                        " show line numbers
set numberwidth=5                 " set line numbers column width
set showcmd                       " display incomplete commands
if has('mouse')
  set mouse=a
endif

"---------------------"
" Behavioural section "
"---------------------"

set ttyfast                       " smoother changes
set nostartofline                 " don't jump to first character when paging
set nobackup                      " do not keep a backup file
set autowrite                     " auto saves changes when quitting and swiching buffer
"set nowrap                       " don't wrap lines
set shortmess=atI                 " Abbreviate messages
set modeline                      " last lines in document sets vim mode
set modelines=3                   " number lines checked for modelines
set whichwrap=b,s,h,l,<,>,[,]     " move freely between files

"------------------"
" Turning of bells "
"------------------"

set visualbell t_vb=              " turn off error beep/flash
set novisualbell                  " turn off visual bell

"------------------------"
" Autocmd configurations "
"------------------------"

if has("autocmd")
    " Restore cursor position
    au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif
    
    " Filetypes (au = autocmd)
    au FileType helpfile set nonumber      " no line numbers when viewing help
    au FileType helpfile nnoremap <buffer><cr> <c-]>   " Enter selects subject
    au FileType helpfile nnoremap <buffer><bs> <c-T>   " Backspace to go back
    
    " When using mutt, text width=72
    au FileType mail,tex set textwidth=72
    au FileType cpp,c,java,sh,pl,php,asp  set autoindent
    au FileType cpp,c,java,sh,pl,php,asp  set smartindent
    au FileType cpp,c,java,sh,pl,php,asp  set cindent
    "au BufRead mutt*[0-9] set tw=72
    
    " Automatically chmod +x Shell and Perl scripts
    au BufWritePost   *.sh             !chmod +x %

    " File formats
    au BufNewFile,BufRead  *.pls    set syntax=dosini
    au BufNewFile,BufRead  *.skl    set syntax=skill
    au BufNewFile,BufRead  modprobe.conf    set syntax=modconf
endif


set shortmess=at
set number "show line number
"set cursorline "highlight current line
set wildmenu
set lazyredraw "redraw only when need to
set showmatch           " highlight matching [{()}]
"cnoremap <C-p> <Up>
"cnoremap <C-n> <Down>
" turn off search highlight
" move vertically by visual line
nnoremap j gj
nnoremap k gk
" highlight last inserted text
nnoremap gV `[v`]
let mapleader=","       " leader is comma
inoremap jk <esc>
" toggle gundo
"nnoremap <leader>u :GundoToggle<CR>
nnoremap <leader><space> :nohlsearch<CR>

set history=200
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [B :bfirst<CR>
nnoremap <silent> ]B :blast<CR>

set hidden
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'   " map %% as filepath without filename

filetype plugin on
runtime plugins/matchit.vim

"set makeprg=/home/hkarapet/scripts/fdi_build.csh\ -i\ /home/hkarapet/fdi_build\ -TDBG
"compiler gcc
"set errorformat^=%-G%f:%l:\ warning:%m
"set tags +=/home/hkarapet/fdi_build/ic/fdi/src/fdi/tags
" previous tab
nnoremap <S-h> gT
" next tab
nnoremap <S-l> gt

silent! set clipboard=unnamedplus " map default clipboard to xwindows clipboard

"set runtimepath^=~/.vim/bundle/ctrlp.vim
"eCtrlP settings
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlPMixed'
let g:ctrlp_match_window = 'bottom,order:ttb'
let g:ctrlp_switch_buffer = 0
let g:ctrlp_working_path_mode = 0
let g:ctrlp_max_files = 1000
let g:ctrlp_max_depth = 5
"let g:ctrlp_follow_symlinks = 1
"let g:ctrlp_match_func = { 'match': 'pymatcher#PyMatch' }
"let g:ctrlp_prompt_mappings = {
"    \ 'AcceptSelection("e")': ['<c-t>'],
"    \ 'AcceptSelection("t")': ['<cr>', '<2-LeftMouse>'],
"    \ }
"let g:ctrlp_user_command = 'ag %s -l -f --nocolor --hidden -g ""'

" " allows cursor change in tmux mode
if exists('$TMUX')
    let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
    let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
else
    let &t_SI = "\<Esc>]50;CursorShape=1\x7"
    let &t_EI = "\<Esc>]50;CursorShape=0\x7"
endif

if has('persistent_undo')
    set undofile                " Save undo's after file closes
    set undodir=$HOME/.vimundo " where to save undo histories
    set undolevels=1000         " How many undos
    set undoreload=10000        " number of lines to save for undo
endif

