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
syntax on
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
set splitbelow
set splitright
nnoremap j gj
nnoremap gj j
nnoremap k gk
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
nnoremap <S-h> gT
nnoremap <S-l> gt
set clipboard+=unnamedplus
set undofile                
set undodir=$HOME/.vimundo  
set undolevels=1000         
set undoreload=10000        
call plug#begin('~/.local/share/nvim/site/plugged')
  Plug 'sheerun/vim-polyglot'
  Plug 'junegunn/fzf'
  Plug 'junegunn/fzf.vim'
  Plug 'vim-scripts/neat.vim'
  " Plug 'lervag/vimtex'
  Plug 'tpope/vim-dispatch'
  Plug 'radenling/vim-dispatch-neovim'
  Plug 'tpope/vim-commentary'
  Plug 'tpope/vim-endwise'
  Plug 'tpope/vim-unimpaired'
  Plug 'tpope/vim-git'
  Plug 'tpope/vim-fugitive'
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'
  Plug 'tpope/vim-projectionist'
  Plug 'tpope/vim-vinegar'
  Plug 'morhetz/gruvbox'
  Plug 'shinchu/lightline-gruvbox.vim'
  Plug 'itchyny/lightline.vim'
  Plug 'neoclide/coc.nvim', {'do': './install.sh nightly'}
  Plug 'wellle/tmux-complete.vim'
  Plug 'easymotion/vim-easymotion'
  Plug 'kana/vim-textobj-user'
  Plug 'kana/vim-textobj-lastpat'
  Plug 'bronson/vim-visual-star-search'
  Plug 'google/vim-searchindex'
  Plug 'svermeulen/vim-cutlass'
  Plug 'svermeulen/vim-yoink'
  Plug 'svermeulen/vim-subversive'
call plug#end()

let g:coc_global_extensions = [ 'coc-emoji', 'coc-python', 'coc-prettier', 'coc-json', 'coc-word' ] 
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

" Remap keys for gotos
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

nmap <leader>crn <Plug>(coc-rename)
vmap <leader>cfs  <Plug>(coc-format-selected)
nmap <leader>cfs  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

vmap <leader>ca  <Plug>(coc-codeaction-selected)
nmap <leader>ca  <Plug>(coc-codeaction-selected)
nmap <leader>cac  <Plug>(coc-codeaction)
nmap <leader>cqf  <Plug>(coc-fix-current)
command! -nargs=0 Format :call CocAction('format')
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
nnoremap <silent> <space>e  :<C-u>CocList extensions<cr>
nnoremap <silent> <space>c  :<C-u>CocList commands<cr>
nnoremap <silent> <space>o  :<C-u>CocList outline<cr>
nnoremap <silent> <space>s  :<C-u>CocList -I symbols<cr>
nnoremap <silent> <space>j  :<C-u>CocNext<CR>
nnoremap <silent> <space>k  :<C-u>CocPrev<CR>
nnoremap <silent> <space>p  :<C-u>CocListResume<CR>

filetype plugin indent on

let g:gruvbox_contrast_light = 'medium'
let g:gruvbox_contrast_dark = 'medium'
" let g:gruvbox_color_column = 'dark0'
let g:gruvbox_hls_cursor = 'red'
colorscheme gruvbox
set background=light
" set background=dark

let g:tex_flavor='latex'
let g:vimtex_view_method='zathura'
let g:vimtex_quickfix_mode=0
set conceallevel=1
let g:tex_conceal='abdmg'

nmap <Leader>b :Buffers<CR>
nmap <Leader>f :GFiles<CR>
nmap <Leader>F :Files<CR>
nmap <Leader>h :History<CR>
nnoremap <silent> <Leader>rg :Rg <C-R><C-W><CR>
nmap <Leader>a :Rg<Space>

let g:fzf_buffers_jump = 1

function! s:build_quickfix_list(lines)
  call setqflist(map(copy(a:lines), '{ "filename": v:val }'))
  copen
  cc
endfunction

let g:fzf_action = {
  \ 'ctrl-q': function('s:build_quickfix_list'),
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

let g:fzf_layout = { 'down': '~40%' }

" Customize fzf colors to match your color scheme
let g:fzf_colors =
\ { 'fg':      ['fg', 'Normal'],
  \ 'bg':      ['bg', 'Normal'],
  \ 'hl':      ['fg', 'Comment'],
  \ 'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
  \ 'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
  \ 'hl+':     ['fg', 'Statement'],
  \ 'info':    ['fg', 'PreProc'],
  \ 'border':  ['fg', 'Ignore'],
  \ 'prompt':  ['fg', 'Conditional'],
  \ 'pointer': ['fg', 'Exception'],
  \ 'marker':  ['fg', 'Keyword'],
  \ 'spinner': ['fg', 'Label'],
  \ 'header':  ['fg', 'Comment'] }

set spelllang=en_us
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
for d in glob('~/.config/nvim/spell/*.add', 1, 1)
    if filereadable(d) && (!filereadable(d . '.spl') || getftime(d) > getftime(d . '.spl'))
        exec 'mkspell! ' . fnameescape(d)
    endif
endfor

au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

hi CocInfoSign guifg=#b57614
hi CocWarningSign guifg=#b57614

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
au FileType python
                \ set iskeyword-=.
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

noremap <leader>t :tab split<CR>

nnoremap gm m
nnoremap m d
xnoremap m d

nnoremap mm dd
nnoremap M D
nmap <c-n> <plug>(YoinkPostPasteSwapBack)
nmap <c-p> <plug>(YoinkPostPasteSwapForward)

nmap p <plug>(YoinkPaste_p)
nmap P <plug>(YoinkPaste_P)
let g:yoinkIncludeDeleteOperations=1

nmap s <plug>(SubversiveSubstitute)
nmap ss <plug>(SubversiveSubstituteLine)
nmap S <plug>(SubversiveSubstituteToEndOfLine)
