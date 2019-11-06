set nocompatible
set hidden
set backspace=indent,eol,start
set t_Co=256

set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab

set scrolloff=5
set termguicolors
set autoindent
set smartindent
set cindent
set showmatch
set smartcase
set ignorecase
set wildignorecase
set ls=2
set title
set ruler
set number
set showcmd
set mouse=a
set ttyfast
set nostartofline
set nobackup
set autowrite
set shortmess=atIc
set modeline
set modelines=3
set whichwrap=b,s,h,l,<,>,[,]
set visualbell t_vb=
set novisualbell
set iskeyword=@,48-57,_,192-255,-,.
set isfname-==
set wildmenu
set lazyredraw
set showmatch
set diffopt=vertical,filler,internal,algorithm:histogram,indent-heuristic
set splitbelow
set splitright
set foldmethod=syntax
set nofoldenable
set viewoptions-=options
set inccommand=nosplit
set cursorline
set wrapscan
set switchbuf=usetab
set listchars=tab:▸\ ,eol:¬
set history=200
set clipboard+=unnamedplus
set undofile
set undodir=$HOME/.vimundo
set undolevels=1000
set undoreload=10000
set colorcolumn=80
set nobackup
set nowritebackup
set cmdheight=1
set shortmess+=c
set signcolumn=yes:1
set conceallevel=1

nn <F9> :silent Dispatch!<CR>

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
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'
filetype plugin on
runtime plugins/matchit.vim
syntax on
" nnoremap <S-h> gT
" nnoremap <S-l> gt
nnoremap <S-l> :bnext<CR>
nnoremap <S-h> :bprevious<CR>

let g:undotree_SetFocusWhenToggle = 1

let g:better_whitespace_enabled=0
let g:strip_whitelines_at_eof = 1

call plug#begin('~/.local/share/nvim/site/plugged')
  Plug 'kshenoy/vim-signature'
  Plug 'inkarkat/vim-ingo-library'
  Plug 'inkarkat/vim-EnhancedJumps'
  Plug 'sheerun/vim-polyglot'
  Plug 'junegunn/limelight.vim'
  Plug 'junegunn/goyo.vim'
  Plug 'vim-scripts/neat.vim'
  Plug 'lervag/vimtex'
  Plug 'tpope/vim-abolish'
  Plug 'tpope/vim-dispatch'
  Plug 'junegunn/vim-peekaboo'
  Plug 'radenling/vim-dispatch-neovim'
  Plug 'tpope/vim-commentary'
  Plug 'tpope/vim-endwise'
  Plug 'tpope/vim-unimpaired'
  Plug 'tpope/vim-git'
  Plug 'tpope/vim-fugitive'
  Plug 'rbong/vim-flog'
  Plug 'airblade/vim-gitgutter'
  Plug 'tommcdo/vim-fubitive'
  Plug 'tpope/vim-rhubarb'
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'
  Plug 'tpope/vim-projectionist'
  Plug 'tpope/vim-vinegar'
  Plug 'tpope/vim-jdaddy'
  Plug 'morhetz/gruvbox'
  Plug 'shinchu/lightline-gruvbox.vim'
  Plug 'itchyny/lightline.vim'
  " Plug 'bling/vim-bufferline'
  " Plug 'vim-airline/vim-airline'
  " Plug 'vim-airline/vim-airline-themes'
  Plug 'neoclide/coc.nvim', {'do': './install.sh nightly'}
  Plug 'wellle/tmux-complete.vim'
  Plug 'kana/vim-textobj-user'
  " Plug 'nelstrom/vim-visual-star-search'
  Plug 'michaeljsmith/vim-indent-object'
  Plug 'jeetsukumaran/vim-indentwise'
  Plug 'zhimsel/vim-stay' " remember states
  Plug 'Konfekt/FastFold'
  Plug 'andymass/vim-matchup'
  Plug 'mbbill/undotree'
  Plug 'ntpeters/vim-better-whitespace'
  Plug 'easymotion/vim-easymotion'
  Plug 'machakann/vim-swap'
  Plug 'jpalardy/vim-slime'
  Plug 'hovnatan/vim-ipython-cell'
  Plug 'wsdjeg/vim-fetch'
  " Plug 'vim-scripts/repeatable-motions.vim'
call plug#end()

nnoremap <F5> :UndotreeToggle<cr>

nmap zuz <Plug>(FastFoldUpdate)
let g:fastfold_savehook = 1
let g:fastfold_fold_command_suffixes =  ['x','X','a','A','o','O','c','C']
let g:fastfold_fold_movement_commands = [']z', '[z', 'zj', 'zk']

let g:slime_target = 'tmux'
" tmux target pane should be the last digit of $TMUX + :, e.g., 8:. Need
" "default" not "default " as tmux server
let g:slime_python_ipython = 1

let g:ipython_cell_delimit_cells_by = 'tags'

let g:polyglot_disabled = ['latex']

let g:gitgutter_map_keys = 0
nmap [g <Plug>(GitGutterPrevHunk)
nmap ]g <Plug>(GitGutterNextHunk)
nmap <leader>gi <Plug>(GitGutterPreviewHunk)
nmap <leader>ga <Plug>(GitGutterStageHunk)
nmap <leader>gu <Plug>(GitGutterUndoHunk)

nnoremap <leader>gb :Gblame<CR>
nnoremap <leader>gm :Gstatus<CR><C-w>T
nnoremap <leader>gp :Gpush<CR>

nnoremap <Esc><Esc> :<C-u>set hlsearch!<CR>

let g:coc_global_extensions = [ 'coc-emoji', 'coc-python',
      \ 'coc-prettier', 'coc-json', 'coc-word',
      \ 'coc-vimtex', 'coc-highlight', 'coc-lists'
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
nmap <leader>x  <Plug>(coc-cursors-operator)

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


command! -nargs=? Fold :call CocAction('fold', <f-args>)

command! MakeTags !ptags
command! Nw noa w

" let g:airline#extensions#tabline#enabled = 1
" let g:airline_powerline_fonts = 1
" let g:airline_theme='gruvbox'
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
nnoremap <silent> <space>f  :<C-u>CocList gfiles<cr>
nnoremap <silent> <space>d  :<C-u>CocList files<cr>
nnoremap <silent> <space>l  :<C-u>CocList <cr>
nnoremap <silent> <space>m  :<C-u>CocList marks<cr>
nnoremap <silent> <space>s  :<C-u>CocList -I symbols<cr>
nnoremap <silent> <space>r  :<C-u>CocList grep<cr>
nnoremap <silent> <space>j  :<C-u>CocNext<CR>
nnoremap <silent> <space>k  :<C-u>CocPrev<CR>
nnoremap <silent> <space>p  :<C-u>CocListResume<CR>

nnoremap <expr><C-f> coc#util#has_float() ? coc#util#float_scroll(1) : "\<C-f>"
nnoremap <expr><C-b> coc#util#has_float() ? coc#util#float_scroll(0) : "\<C-b>"

nnoremap <silent> <space>w  :exe 'CocList -I --normal --input='.expand('<cword>').' words'<CR>

vnoremap <leader>rg :<C-u>call <SID>GrepFromSelected(visualmode())<CR>
nnoremap <leader>rg :<C-u>set operatorfunc=<SID>GrepFromSelected<CR>g@

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
                \ inoremap <buffer> <F7> <C-o>:IPythonCellExecuteCellJump<CR> |
                \ setlocal foldenable |
                \ setlocal foldmethod=indent
autocmd FileType git 
      \ setlocal foldenable


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

nnoremap <leader>T <C-w>T<CR>
nnoremap <leader>t :tab split<CR>

let g:dispatch_no_maps = 1
imap ;; <C-o>m.

nnoremap <S-Tab> :bnext<cr>
nnoremap <space><space> <c-^>

" map <C-j> <Plug>RepeatMotionUp
" map <Down> <Plug>RepeatMotionDown
" map <Right> <Plug>RepeatMotionRight
" map <Left> <Plug>RepeatMotionLeft

map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l

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

nmap g<C-o>      <Plug>EnhancedJumpsOlder
nmap g<C-i>      <Plug>EnhancedJumpsNewer
nmap <C-o>       <Plug>EnhancedJumpsLocalOlder
nmap <C-i>       <Plug>EnhancedJumpsLocalNewer

if !exists('g:lasttab')
  let g:lasttab = 1
endif
nmap <space>t :exe "tabn ".g:lasttab<CR>
au TabLeave * let g:lasttab = tabpagenr()

nnoremap <expr> gp '`[' . strpart(getregtype(), 0, 1) . '`]'


" from https://www.vim.org/scripts/script.php?script_id=4335
let s:savedCpo = &cpo
set cpo&vim

function! s:VStarsearch_searchCWord()
	let wordStr = expand("<cword>")
	if strlen(wordStr) == 0
		echohl ErrorMsg
		echo 'E348: No string under cursor'
		echohl NONE
		return
	endif

	if wordStr[0] =~ '\<'
		let @/ = '\<' . wordStr . '\>'
	else
		let @/ = wordStr
	endif

	let savedUnnamed = @"
	let savedS = @s
	normal! "syiw
	if wordStr != @s
		normal! w
	endif
	let @s = savedS
	let @" = savedUnnamed
endfunction

" https://github.com/bronson/vim-visual-star-search/
function! s:VStarsearch_searchVWord()
	let savedUnnamed = @"
	let savedS = @s
	normal! gv"sy
	let @/ = '\V' . substitute(escape(@s, '\'), '\n', '\\n', 'g')
	let @s = savedS
	let @" = savedUnnamed
endfunction

nnoremap <silent> * :call <SID>VStarsearch_searchCWord()<CR>:set hls<CR>
vnoremap <silent> * :<C-u>call <SID>VStarsearch_searchVWord()<CR>:set hls<CR>
nmap <silent> # *
vmap <silent> # *

let &cpo = s:savedCpo
" autocmd BufReadPost fugitive://* set bufhidden=delete
