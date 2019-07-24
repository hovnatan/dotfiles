set nocompatible
set hidden
set backspace=indent,eol,start
set t_Co=256
set tabstop=2
set shiftwidth=2
set scrolloff=5
set expandtab
set termguicolors
set autoindent
set smartindent
set cindent
set showmatch
set smartcase
set ignorecase
set ls=2
set title
set ruler
set number
set showcmd
if has('mouse')
  set mouse=a
endif
command! MakeTags !ctags -R .
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
set diffopt+=vertical
set diffopt+=algorithm:patience
set diffopt+=indent-heuristic
set splitbelow
set splitright
set foldmethod=manual
set viewoptions-=options
set inccommand=nosplit
set cursorline
set wrapscan

nnoremap <expr> j (v:count == 0 ? 'gj' : 'j')
nnoremap gj j
nnoremap <expr> k (v:count == 0 ? 'gk' : 'k')
nnoremap gk k
nnoremap gV `[v`]
cnoremap <C-p> <Up>
cnoremap <C-n> <Down>

nnoremap & :&&<CR>
xnoremap & :&&<CR>

let mapleader=","
noremap \ ,
inoremap jk <esc>
set history=200
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'
filetype plugin on
runtime plugins/matchit.vim
syntax on
nnoremap <S-h> gT
nnoremap <S-l> gt
set clipboard+=unnamedplus
set undofile
set undodir=$HOME/.vimundo
set undolevels=1000
set undoreload=10000

let g:undotree_SetFocusWhenToggle = 1

let g:strip_whitespace_on_save = 1
let g:strip_whitespace_confirm = 1
let g:strip_whitelines_at_eof = 1

call plug#begin('~/.local/share/nvim/site/plugged')
  Plug 'sheerun/vim-polyglot'
  Plug 'junegunn/limelight.vim'
  Plug 'junegunn/goyo.vim'
  Plug 'vim-scripts/neat.vim'
  Plug 'lervag/vimtex'
  Plug 'tpope/vim-dispatch'
  Plug 'junegunn/vim-peekaboo'
  Plug 'radenling/vim-dispatch-neovim'
  Plug 'tpope/vim-commentary'
  Plug 'tpope/vim-endwise'
  Plug 'tpope/vim-unimpaired'
  Plug 'tpope/vim-git'
  Plug 'tpope/vim-fugitive'
  Plug 'jreybert/vimagit'
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'
  Plug 'tpope/vim-projectionist'
  Plug 'tpope/vim-vinegar'
  Plug 'tpope/vim-jdaddy'
  Plug 'morhetz/gruvbox'
  Plug 'shinchu/lightline-gruvbox.vim'
  Plug 'itchyny/lightline.vim'
  Plug 'neoclide/coc.nvim', {'do': './install.sh nightly'}
  Plug 'wellle/tmux-complete.vim'
  Plug 'kana/vim-textobj-user'
  Plug 'kana/vim-textobj-lastpat'
  Plug 'nelstrom/vim-visual-star-search'
  Plug 'michaeljsmith/vim-indent-object'
  Plug 'zhimsel/vim-stay'
  Plug 'Konfekt/FastFold'
  Plug 'andymass/vim-matchup'
  Plug 'mbbill/undotree'
  Plug 'ntpeters/vim-better-whitespace'
  Plug 'easymotion/vim-easymotion'
  Plug 'machakann/vim-swap'
  Plug 'jpalardy/vim-slime'
  Plug 'hovnatan/vim-ipython-cell'
  Plug 'majutsushi/tagbar'
call plug#end()

let g:better_whitespace_filetypes_blacklist=['c', 'cpp', 'python', 'markdown']

nnoremap <F5> :UndotreeToggle<cr>
nnoremap <F8> :TagbarToggle<CR>

nmap zuz <Plug>(FastFoldUpdate)
let g:fastfold_savehook = 1
let g:fastfold_fold_command_suffixes =  ['x','X','a','A','o','O','c','C']
let g:fastfold_fold_movement_commands = [']z', '[z', 'zj', 'zk']

let g:slime_target = 'tmux'
" tmux target pane should be the last digit of $TMUX + :
let g:slime_python_ipython = 1

let g:ipython_cell_delimit_cells_by = 'tags'

let g:polyglot_disabled = ['latex']

nmap [g <Plug>(coc-git-prevchunk)
nmap ]g <Plug>(coc-git-nextchunk)
nmap <leader>gi <Plug>(coc-git-chunkinfo)
nmap <leader>gc <Plug>(coc-git-commit)
nnoremap <leader>ga :<C-u>CocCommand git.chunkStage<CR>
nnoremap <leader>gu :<C-u>CocCommand git.chunkUndo<CR>

nnoremap <leader>gb :Gblame<CR>
nnoremap <leader>gs :MagitOnly<CR>
nnoremap <leader>gp :! git push<CR>

nnoremap <Esc><Esc> :<C-u>nohlsearch<CR>

let g:coc_global_extensions = [ 'coc-emoji', 'coc-python',
      \ 'coc-prettier', 'coc-json', 'coc-word',
      \ 'coc-vimtex', 'coc-highlight', 'coc-lists',
      \ 'coc-tabnine',
      \ 'coc-git'
      \ ]
call textobj#user#plugin('line', {
\   '-': {
\     'select-a-function': 'CurrentLineA',
\     'select-a': 'al',
\     'select-i-function': 'CurrentLineI',
\     'select-i': 'il',
\   },
\ })

function! CurrentLineA()
  normal! 0
  let head_pos = getpos('.')
  normal! $
  let tail_pos = getpos('.')
  return ['v', head_pos, tail_pos]
endfunction

function! CurrentLineI()
  normal! ^
  let head_pos = getpos('.')
  normal! g_
  let tail_pos = getpos('.')
  let non_blank_char_exists_p = getline('.')[head_pos[2] - 1] !~# '\s'
  return
  \ non_blank_char_exists_p
  \ ? ['v', head_pos, tail_pos]
  \ : 0
endfunction

set colorcolumn=80

set nobackup
set nowritebackup
set cmdheight=1
set shortmess+=c
set signcolumn=yes
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

inoremap <silent><expr> <c-space> coc#refresh()

nmap <silent> [c <Plug>(coc-diagnostic-prev)
nmap <silent> ]c <Plug>(coc-diagnostic-next)

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window
nnoremap <silent> K :call <SID>show_documentation()<CR>

function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction

nmap <leader>rn <Plug>(coc-rename)
xmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>ac  <Plug>(coc-codeaction)
nmap <leader>qf  <Plug>(coc-fix-current)

" Use <tab> for select selections ranges, needs server support, like: coc-tsserver, coc-python
nmap <silent> <TAB> <Plug>(coc-range-select)
xmap <silent> <TAB> <Plug>(coc-range-select)
xmap <silent> <S-TAB> <Plug>(coc-range-select-backword)

command! -nargs=? Fold :call CocAction('fold', <f-args>)


let g:lightline = {
      \ 'colorscheme': 'gruvbox',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'cocstatus', 'readonly', 'absolutepath', 'modified' ] ]
      \ },
      \ 'component_function': {
      \   'cocstatus': 'coc#status'
      \ },
      \ }

nnoremap <silent> <space>a  :<C-u>CocList diagnostics<cr>
nnoremap <silent> <space>c  :<C-u>CocList commands<cr>
nnoremap <silent> <space>o  :<C-u>CocList outline<cr>
nnoremap <silent> <space>h  :<C-u>CocList mru<cr>
nnoremap <silent> <space>b  :<C-u>CocList buffers<cr>
nnoremap <silent> <space>f  :<C-u>CocList files<cr>
nnoremap <silent> <leader>gf  :<C-u>CocList gfiles<cr>
nnoremap <silent> <space>l  :<C-u>CocList <cr>
nnoremap <silent> <space>s  :<C-u>CocList -I symbols<cr>
nnoremap <silent> <space>g  :<C-u>CocList grep<cr>
nnoremap <silent> <space>j  :<C-u>CocNext<CR>
nnoremap <silent> <space>k  :<C-u>CocPrev<CR>
nnoremap <silent> <space>p  :<C-u>CocListResume<CR>

nnoremap <expr><C-f> coc#util#has_float() ? coc#util#float_scroll(1) : "\<C-f>"
nnoremap <expr><C-b> coc#util#has_float() ? coc#util#float_scroll(0) : "\<C-b>"

nnoremap <silent> <space>w  :exe 'CocList -I --normal --input='.expand('<cword>').' words'<CR>

vnoremap <leader>g :<C-u>call <SID>GrepFromSelected(visualmode())<CR>
nnoremap <leader>g :<C-u>set operatorfunc=<SID>GrepFromSelected<CR>g@

function! s:GrepFromSelected(type)
  let saved_unnamed_register = @@
  if a:type ==# 'v'
    normal! `<v`>y
  elseif a:type ==# 'char'
    normal! `[v`]y
  else
    return
  endif
  let word = substitute(@@, '\n$', '', 'g')
  let word = escape(word, '| ')
  let @@ = saved_unnamed_register
  execute 'CocList grep '.word
endfunction

filetype plugin indent on

let g:gruvbox_contrast_light = 'medium'
let g:gruvbox_contrast_dark = 'medium'
" let g:gruvbox_color_column = 'dark0'
let g:gruvbox_hls_cursor = 'red'
colorscheme gruvbox
let &background=readfile(expand("~/.my_colors"))[0]

let g:tex_flavor='latex'
let g:vimtex_view_method='zathura'
let g:vimtex_quickfix_mode=0
set conceallevel=1
let g:tex_conceal='abdmg'

set spelllang=en_us
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
for d in glob('~/.config/nvim/spell/*.add', 1, 1)
    if filereadable(d) && (!filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl'))
        exec 'mkspell! ' . fnameescape(d)
    endif
endfor

au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

if &background == "light"
 hi CocInfoSign guifg=#b57614
 hi CocWarningSign guifg=#b57614
 else

endif

au FileType markdown,mkd,md,text
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell
au FileType tex,latex
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell
au FileType json
      \ set conceallevel=0
au FileType cpp
                \ set iskeyword-=. |
                \ set iskeyword-=-
au FileType python
                \ set iskeyword-=. |
                \ set iskeyword-=- |
                \ nnoremap <buffer> <F6> :IPythonCellExecuteCell<CR> |
                \ inoremap <buffer> <F6> <C-o>:IPythonCellExecuteCell<CR> |
                \ nnoremap <buffer> <F7> :IPythonCellExecuteCellJump<CR> |
                \ inoremap <buffer> <F7> <C-o>:IPythonCellExecuteCellJump<CR>

au BufWritePost *.sh silent! !chmod +x %:p

aug i3config_ft_detection
  au!
  au BufNewFile,BufRead ~/.config/i3/config set filetype=i3config
aug end

let g:netrw_banner    = 0
let g:netrw_winsize   = 20
let g:netrw_liststyle = 3
let g:netrw_altv      = 1
let g:netrw_cursor    = 1
let g:netrw_browsex_viewer="xdg-open"
autocmd FileType netrw setl bufhidden=delete

tnoremap <Esc> <C-\><C-n>
tnoremap <C-v><Esc> <Esc>

nnoremap <leader>t <C-W>T<CR>
nnoremap <C-W>t :tab split<CR>

inoremap ;1 <c-o>ma
inoremap ;2 <c-o>mb
inoremap ;3 <c-o>mc
inoremap ;4 <c-o>md

nnoremap <S-Tab> :bnext<cr>
nnoremap <space><space> <c-^>

set updatetime=300
autocmd CursorHold * silent call CocActionAsync('highlight')

" # Function to permanently delete views created by 'mkview'
function! MyDeleteView()
    let path = fnamemodify(bufname('%'),':p')
    " vim's odd =~ escaping for /
    let path = substitute(path, '=', '==', 'g')
    if empty($HOME)
    else
        let path = substitute(path, '^'.$HOME, '\~', '')
    endif
    let path = substitute(path, '/', '=+', 'g') . '='
    " view directory
    let path = &viewdir.'/'.path
    call delete(path)
    echo "Deleted: ".path
endfunction

" # Command Delview (and it's abbreviation 'delview')
command Delview call MyDeleteView()
" Lower-case user commands: http://vim.wikia.com/wiki/Replace_a_builtin_command_using_cabbrev
cabbrev delview <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'Delview' : 'delview')<CR>

function! s:DiffWithSaved()
  let filetype=&ft
  diffthis
  vnew | r # | normal! 1Gdd
  diffthis
  exe "setlocal bt=nofile bh=wipe nobl noswf ro ft=" . filetype
endfunction
com! DiffSaved call s:DiffWithSaved()

command! TT :vs | terminal
augroup TerminalStuff
  autocmd TermOpen * setlocal nonumber norelativenumber signcolumn=no | startinsert
augroup END

" file is large from 10mb
let g:LargeFile = 1024 * 1024 * 100
augroup LargeFile
  au!
  autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > g:LargeFile || f == -2 | call LargeFile() | endif
augroup END

function! LargeFile()
 " save memory when other file is viewed
 setlocal bufhidden=unload
 " is read-only (write with :w new_filename)
 setlocal buftype=nowrite
 " no undo possible
 setlocal undolevels=-1
 " display message
 set noloadplugins

 set lazyredraw
 set noswapfile
 set eventignore=all
 set nohidden
 set syntax=off
 autocmd VimEnter *  echo "The file is larger than " . (g:LargeFile / 1024 / 1024) . " MB, so some options are changed (see .vimrc for details)."
endfunction

" call CocAction('toggleSource', 'tmuxcomplete')
if exists('$TMUX')
  autocmd BufEnter,BufNewFile,WinEnter * call system("tmux rename-window \"nvim " . expand("%") . "\"")
endif
