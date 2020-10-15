let g:polyglot_disabled = ['latex']

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
set smartindent
set showmatch
set ignorecase
set smartcase
set wildignorecase
set ls=2
set title
set ruler
set number
" set relativenumber
set showcmd
set mouse=a
set ttyfast
set nostartofline
" set autowriteall
set autoread
set shortmess=atIc
set modeline
set modelines=3
set whichwrap=b,s,<,>,[,],h,l
" set nowrap
set visualbell t_vb=
set novisualbell
set iskeyword=@,48-57,_,192-255
set isfname-==
set wildmenu
set lazyredraw
set diffopt=vertical,filler,internal,algorithm:histogram,indent-heuristic
set splitbelow
set splitright
set foldmethod=syntax
set foldenable
set foldlevel=99
set viewoptions-=options
set inccommand=nosplit
set cursorline
set wrapscan
set switchbuf=usetab
set listchars=tab:▸\ ,eol:¬
set history=200
if !empty($DISPLAY)
  set clipboard+=unnamedplus
endif
set undofile
set undodir=$HOME/.vimundo
set undolevels=1000
set undoreload=10000
set colorcolumn=80
set nobackup
set nowritebackup
set cmdheight=1
set signcolumn=yes
set conceallevel=1
set nofixendofline

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
nnoremap <S-h> :bprevious<CR>
nnoremap <S-l> :bnext<CR>

call plug#begin('~/.local/share/nvim/site/plugged')
  Plug 'inkarkat/vim-EnhancedJumps'
  Plug 'inkarkat/vim-ingo-library'
  Plug 'sheerun/vim-polyglot'
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
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  Plug 'wellle/tmux-complete.vim'
  Plug 'wellle/targets.vim'
  Plug 'kana/vim-textobj-user'
  Plug 'michaeljsmith/vim-indent-object'
  Plug 'jeetsukumaran/vim-indentwise'
  Plug 'zhimsel/vim-stay'
  Plug 'Konfekt/FastFold'
  Plug 'mbbill/undotree'
  Plug 'ntpeters/vim-better-whitespace'
  Plug 'easymotion/vim-easymotion'
  Plug 'machakann/vim-swap'
  Plug 'jpalardy/vim-slime'
  Plug 'hanschen/vim-ipython-cell'
  Plug 'wsdjeg/vim-fetch'
  Plug 'majutsushi/tagbar'
  Plug 'tmhedberg/SimpylFold'
  Plug 'kshenoy/vim-signature'
  Plug 'tmux-plugins/vim-tmux-focus-events'
  Plug 'airblade/vim-rooter'
  Plug 'puremourning/vimspector'
  Plug 'will133/vim-dirdiff'
call plug#end()

function! ToggleZoom(zoom, direction)
  if exists("t:restore_zoom") && (a:zoom == v:true || t:restore_zoom.win != winnr())
      exec t:restore_zoom.cmd
      unlet t:restore_zoom
  elseif a:zoom
      let t:restore_zoom = { 'win': winnr(), 'cmd': winrestcmd() }
			if a:direction == "vert"
				exec "normal \<C-W>_"
			else
        exec "normal \<C-W>\|"
			endif
  endif
endfunction

augroup restorezoom
    au WinEnter * silent! :call ToggleZoom(v:false, "")
augroup END
nnoremap <silent> <C-w>z :call ToggleZoom(v:true, 'vert')<CR>
nnoremap <silent> <C-w>Z :call ToggleZoom(v:true, 'horiz')<CR>

let g:DirDiffExcludes = "CVS,*.class,*.o,.git,build,.clangd"
let g:DirDiffWindowSize = winheight(0)*2/3

let g:vimspector_install_gadgets = ['debugpy', 'vscode-cpptools', 'CodeLLDB']
sign define vimspectorBP text=o          texthl=WarningMsg
sign define vimspectorBPCond text=o?     texthl=WarningMsg
sign define vimspectorBPDisabled text=o! texthl=LineNr
sign define vimspectorPC text=->        texthl=MatchParen
sign define vimspectorPCBP text=o>       texthl=MatchParen
" let g:vimspector_enable_mappings = 'VISUAL_STUDIO'

let g:rooter_patterns = ['.git']
let g:rooter_silent_chdir = 1

let g:SignatureMap = {
  \ 'Leader'             :  "m",
  \ 'PlaceNextMark'      :  "m,",
  \ 'ToggleMarkAtLine'   :  "m.",
  \ 'PurgeMarksAtLine'   :  "m-",
  \ 'DeleteMark'         :  "dm",
  \ 'PurgeMarks'         :  "m<Space>",
  \ 'PurgeMarkers'       :  "m<BS>",
  \ 'GotoNextLineAlpha'  :  "",
  \ 'GotoPrevLineAlpha'  :  "",
  \ 'GotoNextSpotAlpha'  :  "",
  \ 'GotoPrevSpotAlpha'  :  "",
  \ 'GotoNextLineByPos'  :  "",
  \ 'GotoPrevLineByPos'  :  "",
  \ 'GotoNextSpotByPos'  :  "",
  \ 'GotoPrevSpotByPos'  :  "",
  \ 'GotoNextMarker'     :  "",
  \ 'GotoPrevMarker'     :  "",
  \ 'GotoNextMarkerAny'  :  "",
  \ 'GotoPrevMarkerAny'  :  "",
  \ 'ListBufferMarks'    :  "m/",
  \ 'ListBufferMarkers'  :  "m?"
  \ }


nnoremap <F8> :TagbarToggle<CR>
nnoremap <F5> :UndotreeToggle<cr>
let g:undotree_SetFocusWhenToggle = 1
let g:undotree_WindowLayout = 2

let g:better_whitespace_filetypes_blacklist=['git', 'diff', 'gitcommit', 'unite', 'qf', 'help']
let g:better_whitespace_enabled=0
let g:strip_whitespace_on_save=1

nmap zuz <Plug>(FastFoldUpdate)
let g:fastfold_savehook = 1
let g:fastfold_fold_command_suffixes =  ['x','X','a','A','o','O','c','C']
let g:fastfold_fold_movement_commands = [']z', '[z', 'zj', 'zk']

let g:slime_no_mappings = 1
xmap <c-c><c-c> <Plug>SlimeRegionSend
nmap <c-c>v     <Plug>SlimeConfig
let g:slime_target = 'tmux'
" tmux target pane should be the last digit of $TMUX + :, e.g., 8:. Need
" "default" not "default " as tmux server
let g:slime_python_ipython = 1
let g:slime_default_config = {"socket_name": "default", "target_pane": "{last}"}
let g:slime_dont_ask_default = 1

let g:ipython_cell_delimit_cells_by = 'tags'


nmap [g <Plug>(coc-git-prevchunk)
nmap ]g <Plug>(coc-git-nextchunk)
nmap <leader>gi <Plug>(coc-git-chunkinfo)
nmap <leader>gc <Plug>(coc-git-commit)
nnoremap <leader>ga :<C-u>CocCommand git.chunkStage<CR>
nnoremap <leader>gu :<C-u>CocCommand git.chunkUndo<CR>

nnoremap <leader>gb :Gblame<CR>
nnoremap <leader>gm :Gstatus<CR><C-w>T
nnoremap <leader>gp :Gpush<CR>

nnoremap <Esc><Esc> :<C-u>let v:hlsearch=!v:hlsearch<CR>

let g:coc_global_extensions = [ 'coc-marketplace', 'coc-python',
      \ 'coc-json', 'coc-word',
      \ 'coc-vimtex', 'coc-lists',
      \ 'coc-git', 'coc-css', 'coc-html', 'coc-tsserver'
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

nmap <silent> [w <Plug>(coc-diagnostic-prev)
nmap <silent> ]w <Plug>(coc-diagnostic-next)

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
    call CocActionAsync('doHover')
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

au FocusLost * silent! wa
au BufLeave * silent! wa

au BufNewFile,BufRead *.cu set filetype=cuda
au BufNewFile,BufRead *.cu_inl set filetype=cuda
au BufNewFile,BufRead *.cuh set filetype=cuda

xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>ac  <Plug>(coc-codeaction)
nmap <leader>qf  <Plug>(coc-fix-current)


command! -nargs=? Fold :call CocAction('fold', <f-args>)

command! MakeTags !ptags
command! Nw noa w

function! GetFilepath_T()
  " from https://github.com/Lokaltog/vim-powerline/blob/09c0cea859a2e0989eea740655b35976d951a84e/autoload/Powerline/Functions.vim
	let dirsep = has('win32') && ! &shellslash ? '\' : '/'
	let filepath = expand('%:p:~')

  let fpath = split(filepath, dirsep)
  let len_p = len(fpath)
  if len_p > 2
    let fpath_shortparts = map(fpath[0:-3], 'v:val[0]')
    let ret = extend(fpath_shortparts, [fpath[-2], fpath[-1]])
    let ret = join(ret, dirsep)
    if filepath[0] == dirsep
      let ret = dirsep . ret
    endif
  else
    let ret = filepath
  endif
	return ret
endfunction

function! CocDiagnostic() abort
  let info = get(b:, 'coc_diagnostic_info', {})
  if empty(info) | return '' | endif
  let msgs = []
  if get(info, 'error', 0)
    call add(msgs, 'E' . info['error'])
  endif
  if get(info, 'warning', 0)
    call add(msgs, 'W' . info['warning'])
  endif
  return join(msgs, ' ')
endfunction

function! GitMessTruncated() abort
  return substitute(FugitiveStatusline()[5:-3], "(", ":", "")
endfunction

let g:lightline = {
      \ 'colorscheme': 'gruvbox',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'tpath', 'readonly', 'modified', 'cocdiag'] ],
      \   'right': [ [ 'lineinfo' ],
      \              [ 'git']
      \            ]
      \ },
      \ 'inactive': {
      \   'left': [ ['tpath', 'readonly', 'modified', 'cocdiag' ] ],
      \   'right': [ [ 'lineinfo' ],
      \            ]
      \ },
      \ 'component': {
      \   'lineinfo': '%3l(%L):%-2v'
      \ },
      \ 'component_function': {
      \   'cocdiag': 'CocDiagnostic',
      \   'tpath': 'GetFilepath_T',
      \   'git': 'GitMessTruncated'
      \ },
      \ }

nnoremap <silent> <space>a  :<C-u>CocList diagnostics<cr>
nnoremap <silent> <space>c  :<C-u>CocList commands<cr>
nnoremap <silent> <space>o  :<C-u>CocList outline<cr>
nnoremap <silent> <space>h  :<C-u>CocList --no-sort mru<cr>
nnoremap <silent> <space>b  :<C-u>CocList buffers<cr>
nnoremap <silent> <space>f  :<C-u>CocList gfiles<cr>
nnoremap <silent> <space>gp :<C-u>CocList commits<cr>
nnoremap <silent> <space>gb :<C-u>CocList bcommits<cr>
nnoremap <silent> <space>d  :<C-u>CocList files<cr>
nnoremap <silent> <space>l  :<C-u>CocList <cr>
nnoremap <silent> <space>m  :<C-u>CocList marks<cr>
nnoremap <silent> <space>s  :<C-u>CocList -I symbols<cr>
nnoremap <silent> <space>w  :<C-u>CocList -I grep -w<cr>
nnoremap <silent> <space>r  :<C-u>CocList -I grep<cr>
nnoremap <silent> <space>j  :<C-u>CocNext<cr>
nnoremap <silent> <space>k  :<C-u>CocPrev<cr>
nnoremap <silent> <space>p  :<C-u>CocListResume<cr>

nnoremap <expr><C-f> coc#util#has_float() ? coc#util#float_scroll(1) : "\<C-f>"
nnoremap <expr><C-b> coc#util#has_float() ? coc#util#float_scroll(0) : "\<C-b>"

" grep word under cursor
command! -nargs=+ -complete=custom,s:GrepArgs Rg exe 'CocList grep '.<q-args>

function! s:GrepArgs(...)
  let list = ['-S', '-smartcase', '-i', '-ignorecase', '-w', '-word',
        \ '-e', '-regex', '-u', '-skip-vcs-ignores', '-t', '-extension']
  return join(list, "\n")
endfunction

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
  execute 'CocList grep -w '.word
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
set spellfile=~/Dropbox/scripts/nvim/spell/en.utf-8.add
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
" for d in glob('~/Dropbox/scripts/nvim/spell/*.add', 1, 1)
"     if filereadable(d) && (!filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl'))
"         exec 'mkspell! ' . fnameescape(d)
"     endif
" endfor

au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

au FileType markdown,text,rst
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell |
                \ setlocal textwidth=80 |
                \ setlocal formatlistpat+=\\\|^\\*\\s* |
                \ let b:strip_whitespace_on_save=0
au FileType tex,latex
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell |
                \ setlocal textwidth=80
au FileType json
      \ set conceallevel=0 |
      \ nn <buffer> <F4> :%!python3 -m json.tool<CR>

au FileType python
                \ nnoremap <buffer> <c-c><c-c> :IPythonCellExecuteCell<CR> |
                \ nnoremap <buffer> <c-c><c-n> :IPythonCellExecuteCellJump<CR> |
                \ Abolish -buffer true True |
                \ Abolish -buffer false False

au FileType cpp
      \ setlocal cindent

au BufWritePost *.sh silent! !chmod +x %:p

aug i3config_ft_detection
  au!
  au BufNewFile,BufRead ~/.config/i3/config set filetype=i3config
aug end

let g:netrw_banner    = 0
let g:netrw_winsize   = 20
let g:netrw_altv      = 1
let g:netrw_cursor    = 1
let g:netrw_browsex_viewer="xdg-open"
let g:netrw_fastbrowse = 0
let g:netrw_altfile = 1

tnoremap <Esc> <C-\><C-n>
tnoremap <C-v><Esc> <Esc>

nnoremap <leader>T <C-w>T<CR>
nnoremap <leader>t :tab split<CR>

let g:dispatch_no_maps = 1
imap ;; <C-o>m.

nnoremap <S-Tab> :bnext<cr>
nnoremap <space><space> <C-^>

nnoremap <C-j> <C-d>
nnoremap <C-k> <C-u>
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
nnoremap <silent> <C-w>j :wincmd h<CR>
nnoremap <silent> <C-w>k :wincmd l<CR>
nnoremap <silent> <C-w>h :wincmd j<CR>
nnoremap <silent> <C-w>l :wincmd k<CR>

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

if !exists('g:lasttab')
  let g:lasttab = 1
endif
nmap <space>t :exe "tabn ".g:lasttab<CR>
au TabLeave * let g:lasttab = tabpagenr()

nnoremap <expr> <space>v '`[' . strpart(getregtype(), 0, 1) . '`]'


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

noremap <expr> n 'Nn'[v:searchforward]
noremap <expr> N 'nN'[v:searchforward]

let &cpo = s:savedCpo
" autocmd BufReadPost fugitive://* set bufhidden=delete
nnoremap <leader>cd :cd %:p:h<CR>:pwd<CR>

" au VimEnter * let g:volatile_ftypes += ['git']
"
" to find out origin of a mapping use e.g., :verbose map <C-x>

" copy relative filepath and the current line number to clipboard
nmap ,cl :let @+=join([@%,  line(".")], ':')<CR>
nmap ,h /[^\d0-\d127]<CR>
