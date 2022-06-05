return function()
  vim.cmd([==[
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
  let branch = get(b:, 'gitsigns_head', '')
  let status = get(b:, 'gitsigns_status', '')
  if !(status == '')
    return branch . ' ' .  status
  else
    return branch
  endif
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


      ]==])
end
