set nocompatible
set backspace=indent,eol,start
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
set smartcase
set ignorecase
set ls=2
set title
set ruler
set number
set relativenumber
set numberwidth=5
" set termguicolors
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
nnoremap j gj
nnoremap k gk
nnoremap gV `[v`]
let mapleader=","
inoremap jk <esc>
set history=200
set hidden
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'   " map %% as filepath without filename
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
  " Plug 'sirver/ultisnips'
  Plug 'tpope/vim-dispatch'
  Plug 'tpope/vim-commentary'
  Plug 'tpope/vim-endwise'
  Plug 'morhetz/gruvbox'
  Plug 'shinchu/lightline-gruvbox.vim'
  Plug 'itchyny/lightline.vim'
  Plug 'neoclide/coc.nvim', {'do': { -> coc#util#install()}}
  Plug 'wellle/tmux-complete.vim'
  Plug 'haya14busa/incsearch.vim'
  Plug 'haya14busa/incsearch-fuzzy.vim'
  Plug 'haya14busa/incsearch-easymotion.vim'
  Plug 'easymotion/vim-easymotion'
call plug#end()

set colorcolumn=80
set hidden

map /  <Plug>(incsearch-forward)
map ?  <Plug>(incsearch-backward)
map g/ <Plug>(incsearch-stay)
map z/ <Plug>(incsearch-fuzzy-/)
map z? <Plug>(incsearch-fuzzy-?)
map zg/ <Plug>(incsearch-fuzzy-stay)
set hlsearch
map n  <Plug>(incsearch-nohl-n)
map N  <Plug>(incsearch-nohl-N)
map *  <Plug>(incsearch-nohl-*)
map #  <Plug>(incsearch-nohl-#)
map g* <Plug>(incsearch-nohl-g*)
map g# <Plug>(incsearch-nohl-g#)
let g:incsearch#auto_nohlsearch = 1 " auto unhighlight after searching
let g:incsearch#consistent_n_direction = 1
nnoremap <leader><space> :nohlsearch<CR>

function! s:config_easyfuzzymotion(...) abort
  return extend(copy({
  \   'converters': [incsearch#config#fuzzy#converter()],
  \   'modules': [incsearch#config#easymotion#module()],
  \   'keymap': {"\<CR>": '<Over>(easymotion)'},
  \   'is_expr': 0,
  \   'is_stay': 1
  \ }), get(a:, 1, {}))
endfunction

noremap <silent><expr> <Space>/ incsearch#go(<SID>config_easyfuzzymotion())

set hidden
set nobackup
set nowritebackup
set cmdheight=2
set updatetime=300
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

autocmd CursorHold * silent call CocActionAsync('highlight')

nmap <leader>rn <Plug>(coc-rename)
vmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

vmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>ac  <Plug>(coc-codeaction)
nmap <leader>qf  <Plug>(coc-fix-current)
command! -nargs=0 Format :call CocAction('format')
command! -nargs=? Fold :call     CocAction('fold', <f-args>)


let g:lightline = {
      \ 'colorscheme': 'gruvbox',
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'cocstatus', 'readonly', 'filename', 'modified' ] ]
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

let g:UltiSnipsExpandTrigger = '<tab>'
let g:UltiSnipsJumpForwardTrigger = '<tab>'
let g:UltiSnipsJumpBackwardTrigger = '<s-tab>'

let g:tex_flavor='latex'
let g:vimtex_view_method='zathura'
let g:vimtex_quickfix_mode=0
set conceallevel=1
let g:tex_conceal='abdmg'

nmap <Leader>b :Buffers<CR>
nmap <Leader>f :GFiles<CR>
nmap <Leader>F :Files<CR>
nmap <Leader>a :Rg<Space>

let g:fzf_buffers_jump = 1

let g:fzf_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

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
