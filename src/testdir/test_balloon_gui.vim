" Tests for 'ballooneval' in the GUI.

source check.vim
CheckGui
CheckFeature balloon_eval

if !has('gui_macvim') " See https://github.com/macvim-dev/macvim/issues/902

func Test_balloon_show_gui()
  let msg = 'this this this this'
  call balloon_show(msg)
  call assert_equal(msg, balloon_gettext())
  sleep 10m
  call balloon_show('')

  let msg = 'that that'
  eval msg->balloon_show()
  call assert_equal(msg, balloon_gettext())
  sleep 10m
  call balloon_show('')
endfunc

endif " !has('gui_macvim')
