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

an <silent> 10.290 File.New\ Window             :action newWindow:<CR>
an  10.295 File.New\ Tab                        :tabnew<CR>
an 10.328 File.-SEP0-                           <Nop>
an <silent> 10.330 File.Close\ Window<Tab>:qa   :confirm qa<CR>
an 10.331 File.Close<Tab>:q                     :confirm q<CR>
"an 10.331 File.Close\ Tab                   :tabclose<CR>

an 20.460 Edit.-SEP4-                       <Nop>
an 20.465.10 Edit.Font.Show\ Fonts          :action orderFrontFontPanel:<CR>
an 20.465.20 Edit.Font.-SEP5-               <Nop>
an 20.465.30 Edit.Font.Bigger               :action fontSizeUp:<CR>
an 20.465.40 Edit.Font.Smaller              :action fontSizeDown:<CR>
an 20.470 Edit.Special\ Characters\.\.\.    :action orderFrontCharacterPalette:<CR>


" Window menu (should be next to Help so give it a high priority)
aunmenu Window

an <silent> 9900.300 Window.Minimize          :action performMiniaturize:<CR>
an <silent> 9900.310 Window.Zoom              :action performZoom:<CR>
an 9900.320 Window.-SEP1-                     <Nop>
" TODO! Grey out if no tabs are visible.
an <silent> 9900.330 Window.Previous\ Tab     :tabprevious<CR>
an <silent> 9900.340 Window.Next\ Tab         :tabnext<CR>
an 9900.350 Window.-SEP2-                     <Nop>
an <silent> 9900.360 Window.Bring\ All\ To\ Front :action arrangeInFront:<CR>



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

menukeyequiv File.New\ Window                       <D-n>
menukeyequiv File.New\ Tab                          <D-t>

menukeyequiv File.Open\.\.\.                        <D-o>
menukeyequiv File.Open\ Tab\.\.\.                   <D-T>
menukeyequiv File.Close\ Window                     <D-W>
"menukeyequiv File.Close\ Tab                        <D-w>
menukeyequiv File.Close                             <D-w>
menukeyequiv File.Save                              <D-s>
menukeyequiv File.Save\ As\.\.\.                    <D-S>
menukeyequiv File.Print                             <D-p>

menukeyequiv Edit.Undo                              <D-z>
menukeyequiv Edit.Redo                              <D-Z>
menukeyequiv Edit.Cut                               <D-x>
menukeyequiv Edit.Copy                              <D-c>
menukeyequiv Edit.Paste                             <D-v>
menukeyequiv Edit.Select\ All                       <D-a>
menukeyequiv Edit.Special\ Characters\.\.\.         <D-M-t> 
menukeyequiv Edit.Font.Bigger                       <D-=>
menukeyequiv Edit.Font.Smaller                      <D-->

menukeyequiv Tools.Spelling.To\ Next\ error         <D-;>
menukeyequiv Tools.Spelling.Suggest\ Corrections    <D-:>
menukeyequiv Tools.Make                             <D-b>
menukeyequiv Tools.List\ Errors                     <D-l>
menukeyequiv Tools.List\ Messages                   <D-L>
menukeyequiv Tools.Next\ Error                      <D-C-Right>
menukeyequiv Tools.Previous\ Error                  <D-C-Left>
menukeyequiv Tools.Older\ List                      <D-C-Up>
menukeyequiv Tools.Newer\ List                      <D-C-Down>

menukeyequiv Window.Minimize                        <D-m>
menukeyequiv Window.Previous\ Tab                   <D-{>
menukeyequiv Window.Next\ Tab                       <D-}>


" Restore the previous value of 'cpoptions'.
let &cpo = s:cpo_save
unlet s:cpo_save
