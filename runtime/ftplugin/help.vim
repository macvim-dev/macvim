" Vim filetype plugin file
" Language:         Vim help file
" Maintainer:       Nikolai Weibull <now@bitwi.se>
" Latest Revision:  2008-07-09

if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

let s:cpo_save = &cpo
set cpo&vim

let b:undo_ftplugin = "setl fo< tw< cole< cocu<"

setlocal formatoptions+=tcroql textwidth=78 cole=2 cocu=nc

if has("gui_macvim")
  " Use swipe gesture to navigate back/forward
  nmap <buffer> <silent> <SwipeLeft>  :po<CR>
  nmap <buffer> <silent> <SwipeRight> :ta<CR>
endif

let &cpo = s:cpo_save
unlet s:cpo_save
