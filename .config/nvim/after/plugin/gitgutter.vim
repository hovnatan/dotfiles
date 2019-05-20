" Disable real time gitgutter updates
autocmd! gitgutter CursorHold,CursorHoldI

" Update gitgutter on write
autocmd BufWritePost * GitGutter
