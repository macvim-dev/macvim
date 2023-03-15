" Test for MacVim behaviors and regressions

source check.vim
CheckFeature gui_macvim

" Tests for basic existence of commands and options to make sure no
" regressions have accidentally removed them
func Test_macvim_options_commands_exist()
    " MacVim-specific options
    call assert_true(exists('+antialias'), 'Missing option "antialias"')
    call assert_true(exists('+blurradius'), 'Missing option "blurradius"')
    call assert_true(exists('+fullscreen'), 'Missing option "fullscreen"')
    call assert_true(exists('+fuoptions'), 'Missing option "fuoptions"')
    call assert_true(exists('+macligatures'), 'Missing option "macligatures"')
    call assert_true(exists('+macmeta'), 'Missing option "macmeta"')
    call assert_true(exists('+macthinstrokes'), 'Missing option "macthinstrokes"')
    call assert_true(exists('+transparency'), 'Missing option "transparency"')

    " Other GUI options we care about
    call assert_true(exists('+toolbariconsize'), 'Missing option "toolbariconsize"')

    call assert_true(exists(':macaction'), 'Missing command "macaction"')
    call assert_true(exists(':macmenu'), 'Missing command "macmenu"')

    call assert_true(exists('*showdefinition'), 'Missing function "showdefinition"')

    call assert_true(exists('##OSAppearanceChanged'), 'Missing autocmd event "OSAppearanceChanged"')

    call assert_true(has('fullscreen'), 'Missing feature "fullscreen"')
    call assert_true(has('gui_macvim'), 'Missing feature "gui_macvim"')
    call assert_true(has('odbeditor'), 'Missing feature "odbeditor"')
    call assert_true(has('touchbar'), 'Missing feature "touchbar"')
    call assert_true(has('transparency'), 'Missing feature "transparency"')

    " Vim system-specific features that we expect to be on in macOS
    call assert_true(has('clipboard'), 'Missing feature "clipboard"')
    call assert_true(has('sound'), 'Missing feature "sound"')
    call assert_true(has('terminal'), 'Missing feature "terminal"')
    call assert_true(has('xim'), 'Missing feature "xim"')
endfunc

" Test that Cmd-key and touch pad mappings are working (this doesn't actually
" test that the full mapping work properly as it's difficult to inject keys in
" Vimscript)
func Test_macvim_mappings()
    let g:marker_value=0

    nnoremap <D-1> :let g:marker_value=100<CR>
    call feedkeys("\<D-1>", "xt")
    call assert_equal(100, g:marker_value)

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

" Test that setting invalid values with properly throw invalid argument errors
func Test_macvim_invalid_options()
    call assert_fails("let &blur=-1", 'E474:')
    call assert_fails("let &transparency=-1", 'E474:')
    call assert_fails("let &transparency=101", 'E474:')

    call assert_fails("let &fuoptions='abcdef'", 'E474:')
endfunc
