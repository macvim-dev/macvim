" Test for MacVim behaviors and regressions

source check.vim
source term_util.vim
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

    call assert_true(exists('##OSAppearanceChanged'), 'Missing autocmd event "OSAppearanceChanged"')

    call assert_true(has('fullscreen'), 'Missing feature "fullscreen"')
    call assert_true(has('gui_macvim'), 'Missing feature "gui_macvim"')
    call assert_true(has('odbeditor'), 'Missing feature "odbeditor"')
    call assert_true(has('touchbar'), 'Missing feature "touchbar"')
    call assert_true(has('transparency'), 'Missing feature "transparency"')
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

" Test that we correctly set the locale to have .UTF-8 if launching from the
" Dock or the $LANG env variable is not set.
func Test_macvim_default_locale_utf8()
    CheckRunVimInTerminal
    if !has('terminal') || !executable('/bin/sh')
        return
    endif
    let buf = term_start('/bin/sh')

    " Wait for shell prompt.
    call WaitForAssert({-> assert_match('[$#] $', term_getline(buf, '.'))})

    " Unset the $LANG environmental variable. This causes Vim to try to set a
    " default one in macOS.
    call term_sendkeys(buf, "unset LANG\<CR>")

    " Run Vim and ask it to output the $LANG variable. It should be
    " automatically created since it doesn't exist.
    call term_sendkeys(buf, v:progpath
        \              . " --clean -X"
        \              . " -c 'echo $LANG'\<CR>")

    " Wait for Vim to come up and show something in the status line.
    let term_rows = term_getsize(buf)[0]
    call term_wait(buf)
    call WaitFor({-> len(term_getline(buf, term_rows)) > 0})

    " Check that the locale actually has .UTF-8 in it. We can't check for
    " "en_US.UTF-8" because we shouldn't assume what locale the tester is
    " using.
    call assert_match('^[a-zA-Z-_]\+\.UTF-8\>', term_getline(buf, term_rows), "Default locale doesn't have UTF-8 encoding set")

    " Cleanly exist from Vim/terminal and clean up.
    call term_sendkeys(buf, ":qall!\<CR>")
    call term_wait(buf)
    call WaitForAssert({-> assert_match('[$#] $', term_getline(buf, '.'))})
    call StopShellInTerminal(buf)
    exe buf . 'bwipe!'
endfunc
