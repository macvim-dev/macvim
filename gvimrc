" System gvimrc file for MacVim
"
" Maintainer:	Bjorn Winckler <bjorn.winckler@gmail.com>
" Last Change:	Mon Sep 30 2007
"
" This is a work in progress.  If you feel so inclined, please help me improve
" this file.


" Make sure the '<' and 'C' flags are not included in 'cpoptions', otherwise
" <CR> would not be recognized.  See ":help 'cpoptions'".
let s:cpo_save = &cpo
set cpo&vim


"
" Global default options
"

if !exists("syntax_on")
  syntax on
endif



"
" Extra menus
"


" File menu

aunmenu File.New
aunmenu File.Close
aunmenu File.-SEP4-
aunmenu File.Exit
aunmenu File.Save-Exit

an <silent> 10.290 File.New\ Window             :maca newWindow:<CR>
an  10.295 File.New\ Tab                        :tabnew<CR>
an 10.328 File.-SEP0-                           <Nop>
an <silent> 10.330 File.Close\ Window<Tab>:qa   :confirm qa<CR>
an 10.331 File.Close<Tab>:q                     :confirm q<CR>
"an 10.331 File.Close\ Tab                   :tabclose<CR>

an 20.460 Edit.-SEP4-                       <Nop>
an 20.465.10 Edit.Font.Show\ Fonts          :maca orderFrontFontPanel:<CR>
an 20.465.20 Edit.Font.-SEP5-               <Nop>
an 20.465.30 Edit.Font.Bigger               :maca fontSizeUp:<CR>
an 20.465.40 Edit.Font.Smaller              :maca fontSizeDown:<CR>
an 20.470 Edit.Special\ Characters\.\.\.    :maca orderFrontCharacterPalette:<CR>


" Window menu (should be next to Help so give it a high priority)
aunmenu Window

an <silent> 9900.300 Window.Minimize            :maca performMiniaturize:<CR>
an <silent> 9900.310 Window.Zoom                :maca performZoom:<CR>
an 9900.320 Window.-SEP1-                       <Nop>
" TODO! Grey out if no tabs are visible.
an <silent> 9900.330 Window.Previous\ Tab       :tabprevious<CR>
an <silent> 9900.340 Window.Next\ Tab           :tabnext<CR>
an 9900.350 Window.-SEP2-                       <Nop>
an 9900.360 Window.Enter\ Fullscreen            :set fu<CR>
an 9900.370 Window.Leave\ Fullscreen            :set nofu<CR>
an 9900.380 Window.-SEP3-                       <Nop>
an <silent> 9900.390 Window.Bring\ All\ To\ Front :maca arrangeInFront:<CR>



"
" Toolbar
"
" These items are special ('*' means zero or more arbitrary characters):
"   -space*-        an empty space
"   -flexspace*-    a flexible space
"   -*-             a separator item

" Remove some items so that all items are visible at the default window size.
"aunmenu ToolBar.Undo
"aunmenu ToolBar.Redo
"aunmenu ToolBar.-sep2-
"aunmenu ToolBar.Cut
"aunmenu ToolBar.Copy
"aunmenu ToolBar.Paste
"aunmenu ToolBar.-sep3-
aunmenu ToolBar.Replace
aunmenu ToolBar.FindNext
aunmenu ToolBar.FindPrev
aunmenu ToolBar.-sep5-
aunmenu ToolBar.-sep6-
aunmenu ToolBar.RunCtags
aunmenu ToolBar.TagJump
"aunmenu ToolBar.-sep7-
aunmenu ToolBar.FindHelp

"an 1.295 ToolBar.-flexspace7-   <Nop>



" This is so that HIG Cmd and Option movement mappings can be disabled by
" adding the line
"   let macvim_skip_cmd_opt_movement = 1
" to the user .vimrc
"
if !exists("macvim_skip_cmd_opt_movement")
  no   <D-Left>       <Home>
  no!  <D-Left>       <Home>
  no   <M-Left>       <C-Left>
  no!  <M-Left>       <C-Left>

  no   <D-Right>      <End>
  no!  <D-Right>      <End>
  no   <M-Right>      <C-Right>
  no!  <M-Right>      <C-Right>

  no   <D-Up>         <C-Home>
  ino  <D-Up>         <C-Home>
  map  <M-Up>         {
  imap <M-Up>         <C-o>{

  no   <D-Down>       <C-End>
  ino  <D-Down>       <C-End>
  map  <M-Down>       }
  imap <M-Down>       <C-o>}
endif " !exists("macvim_skip_cmd_opt_movement")


" This is so that the HIG shift movement related settings can be enabled by
" adding the line
"   let macvim_hig_shift_movement = 1
" to the user .vimrc (not .gvimrc!).
"
if exists("macvim_hig_shift_movement")
  " Shift + special movement key (<S-Left>, etc.) and mouse starts insert mode
  set selectmode=mouse,key
  set keymodel=startsel,stopsel

  " HIG related shift + special movement key mappings
  nn   <S-D-Left>     <S-Home>
  vn   <S-D-Left>     <S-Home>
  ino  <S-D-Left>     <S-Home>
  nn   <S-M-Left>     <S-C-Left>
  vn   <S-M-Left>     <S-C-Left>
  ino  <S-M-Left>     <S-C-Left>

  nn   <S-D-Right>    <S-End>
  vn   <S-D-Right>    <S-End>
  ino  <S-D-Right>    <S-End>
  nn   <S-M-Right>    <S-C-Right>
  vn   <S-M-Right>    <S-C-Right>
  ino  <S-M-Right>    <S-C-Right>

  nn   <S-D-Up>       <S-C-Home>
  vn   <S-D-Up>       <S-C-Home>
  ino  <S-D-Up>       <S-C-Home>

  nn   <S-D-Down>     <S-C-End>
  vn   <S-D-Down>     <S-C-End>
  ino  <S-D-Down>     <S-C-End>
endif " exists("macvim_hig_shift_movement")



"
" Menu key equivalents (these should always have the 'D' modifier set)
"

macmenukey File.New\ Window                       <D-n>
macmenukey File.New\ Tab                          <D-t>

macmenukey File.Open\.\.\.                        <D-o>
macmenukey File.Open\ Tab\.\.\.                   <D-T>
macmenukey File.Close\ Window                     <D-W>
"macmenukey File.Close\ Tab                        <D-w>
macmenukey File.Close                             <D-w>
macmenukey File.Save                              <D-s>
macmenukey File.Save\ As\.\.\.                    <D-S>
macmenukey File.Print                             <D-p>

macmenukey Edit.Undo                              <D-z>
macmenukey Edit.Redo                              <D-Z>
macmenukey Edit.Cut                               <D-x>
macmenukey Edit.Copy                              <D-c>
macmenukey Edit.Paste                             <D-v>
macmenukey Edit.Select\ All                       <D-a>
macmenukey Edit.Special\ Characters\.\.\.         <D-M-t> 
macmenukey Edit.Font.Bigger                       <D-=>
macmenukey Edit.Font.Smaller                      <D-->

macmenukey Tools.Spelling.To\ Next\ error         <D-;>
macmenukey Tools.Spelling.Suggest\ Corrections    <D-:>
macmenukey Tools.Make                             <D-b>
macmenukey Tools.List\ Errors                     <D-l>
macmenukey Tools.List\ Messages                   <D-L>
macmenukey Tools.Next\ Error                      <D-C-Right>
macmenukey Tools.Previous\ Error                  <D-C-Left>
macmenukey Tools.Older\ List                      <D-C-Up>
macmenukey Tools.Newer\ List                      <D-C-Down>

macmenukey Window.Minimize                        <D-m>
macmenukey Window.Previous\ Tab                   <D-{>
macmenukey Window.Next\ Tab                       <D-}>
macmenukey Window.Enter\ Fullscreen               <D-Enter>
macmenukey Window.Leave\ Fullscreen               <D-S-Enter>


" Restore the previous value of 'cpoptions'.
let &cpo = s:cpo_save
unlet s:cpo_save
