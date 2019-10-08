" Test for MacVim behaviors and regressions

source check.vim
CheckFeature gui_macvim

" Tests for basic existence of commands and options to make sure no
" regressions have accidentally removed them
func Test_macvim_options_commands()
    call assert_true(exists('+antialias'), 'Missing option "antialias"')
    call assert_true(exists('+blurradius'), 'Missing option "blurradius"')
    call assert_true(exists('+fullscreen'), 'Missing option "fullscreen"')
    call assert_true(exists('+fuoptions'), 'Missing option "fuoptions"')
    call assert_true(exists('+macligatures'), 'Missing option "macligatures"')
    call assert_true(exists('+macmeta'), 'Missing option "macmeta"')
    call assert_true(exists('+macthinstrokes'), 'Missing option "macthinstrokes"')
    call assert_true(exists('+toolbariconsize'), 'Missing option "toolbariconsize"')
    call assert_true(exists('+transparency'), 'Missing option "transparency"')

    call assert_true(exists(':macaction'), 'Missing command "macaction"')
    call assert_true(exists(':macmenu'), 'Missing command "macmenu"')
endfunc

" Test that Cmd-key and touch pad mappings are working (this doesn't actually
" test that the full mapping work properly as it's difficult to inject keys in
" Vimscript)
func Test_macvim_mappings()
    let g:marker_value=0

    nnoremap <D-1> :let g:marker_value=1<CR>
    call feedkeys("\<D-1>", "xt")
    call assert_equal(1, g:marker_value)

    nnoremap <SwipeLeft> :let g:marker_value=1<CR>
    call feedkeys("\<SwipeLeft>", "xt")
    call assert_equal(1, g:marker_value)
    nnoremap <SwipeRight> :let g:marker_value=2<CR>
    call feedkeys("\<SwipeRight>", "xt")
    call assert_equal(2, g:marker_value)
    nnoremap <SwipeUp> :let g:marker_value=3<CR>
    call feedkeys("\<SwipeUp>", "xt")
    call assert_equal(3, g:marker_value)
    nnoremap <SwipeDown> :let g:marker_value=4<CR>
    call feedkeys("\<SwipeDown>", "xt")
    call assert_equal(4, g:marker_value)
    nnoremap <ForceClick> :let g:marker_value=5<CR>
    call feedkeys("\<ForceClick>", "xt")
    call assert_equal(5, g:marker_value)
endfunc
