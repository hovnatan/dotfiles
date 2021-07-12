lua require('plugins')
lua require('config')

let g:polyglot_disabled = ['latex']

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
inoremap jk <ESC>

cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'
filetype plugin on
runtime plugins/matchit.vim
syntax on

inoremap <silent><expr> <C-Space> compe#complete()
inoremap <silent><expr> <CR>      compe#confirm('<CR>')
inoremap <silent><expr> <C-e>     compe#close('<C-e>')
inoremap <silent><expr> <C-f>     compe#scroll({ 'delta': +4 })
inoremap <silent><expr> <C-d>     compe#scroll({ 'delta': -4 })

nnoremap <space>f <cmd>Telescope find_files<cr>
nnoremap <space>g <cmd>Telescope live_grep<cr>
nnoremap <space>r <cmd>Telescope grep_string<cr>
nnoremap <space>b <cmd>Telescope buffers<cr>
nnoremap <space>h <cmd>Telescope help_tags<cr>
nnoremap <space>o <cmd>Telescope oldfiles<cr>
nnoremap <space>m <cmd>Telescope marks<cr>
nnoremap <space>q <cmd>Telescope quickfix<cr>
nnoremap <space>k <cmd>Telescope keymaps<cr>

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
let g:strip_whitespace_on_save=0

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


nnoremap <leader>gb :Gblame<CR>
nnoremap <leader>gm :Gstatus<CR><C-w>T
nnoremap <leader>gp :Gpush<CR>

nnoremap <silent> <C-n> :set hlsearch!<CR>

au FocusLost * silent! wa
au BufLeave * silent! wa

au BufNewFile,BufRead *.cu set filetype=cuda
au BufNewFile,BufRead *.cu_inl set filetype=cuda
au BufNewFile,BufRead *.cuh set filetype=cuda


command! MakeTags !ctags -R .
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

function! LightlineGitGutter()
  if !get(g:, 'gitgutter_enabled', 0) || empty(FugitiveHead())
    return ''
  endif
  let [ l:added, l:modified, l:removed ] = GitGutterGetHunkSummary()
  let branch = fugitive#head()

  return printf('%s +%d ~%d -%d', l:branch, l:added, l:modified, l:removed)
endfunction

let g:lightline = {
      \ 'colorscheme': 'gruvbox',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'tpath', 'readonly', 'modified', 'git', 'linter_errors', 'linter_warnings', 'linter_infos', 'linter_hints', 'linter_ok' ] ],
      \   'right':  [[ 'lineinfo'] ] },
      \ 'inactive': {
      \   'left': [ ['tpath', 'readonly', 'modified' ] ],
      \   'right': [ [ 'lineinfo' ],
      \            ]
      \ },
      \ 'component': {
      \   'lineinfo': '%3l(%L):%-2v',
      \ },
      \ 'component_function': {
      \   'tpath': 'GetFilepath_T',
      \   'git': 'LightlineGitGutter'
      \ },
      \ }

let g:lightline.component_expand = {
      \  'linter_hints': 'lightline#lsp#hints',
      \  'linter_infos': 'lightline#lsp#infos',
      \  'linter_warnings': 'lightline#lsp#warnings',
      \  'linter_errors': 'lightline#lsp#errors',
      \  'linter_ok': 'lightline#lsp#ok',
      \ }


filetype plugin indent on

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
                \ setlocal formatlistpat+=\\\|^\\*\\s*
au FileType tex,latex
                \ let b:dispatch = '~/.config/nvim/preview.sh %:p' |
                \ setlocal spell |
                \ setlocal textwidth=80
au FileType json
      \ set conceallevel=0 |
      \ nn <buffer> <F4> :%!python3 -m json.tool<CR>

au FileType python
                \ nnoremap <buffer> <c-c><c-c> :IPythonCellExecuteCellVerbose<CR> |
                \ nnoremap <buffer> <c-c><c-n> :IPythonCellExecuteCellVerboseJump<CR> |
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

if exists('$TMUX')
  autocmd BufEnter,BufNewFile,WinEnter * call system("tmux rename-window \"nvim " . expand("%") . "\"")
endif

if !exists('g:lasttab')
  let g:lasttab = 1
endif
nmap <space>T :exe "tabn ".g:lasttab<CR>
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

let g:python3_host_prog = expand('/usr/bin/python3')

highlight link TSError Normal
